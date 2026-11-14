import Foundation
import ClosedLidModeCore

// Fixtures are real output captured from a MacBook Air M4, not invented
// strings - a parsing bug here caused a visible failure once already.

let realPmsetOutput = """
System-wide power settings:
Currently in use:
 standby              1
 Sleep On Power Button 1
 hibernatefile        /var/vm/sleepimage
 powernap             1
 SleepDisabled\t\t1
 disksleep            10
 sleep                1 (sleep prevented by Claude, powerd)
 hibernatemode        3
 displaysleep         10
"""

T.suite("pmset -g : SleepDisabled") {
    T.expect(PmsetParser.sleepDisabled(inPmsetOutput: realPmsetOutput),
             "reads SleepDisabled 1 as on")

    let off = realPmsetOutput.replacingOccurrences(of: "SleepDisabled\t\t1",
                                                   with: "SleepDisabled\t\t0")
    T.expect(!PmsetParser.sleepDisabled(inPmsetOutput: off),
             "reads SleepDisabled 0 as off")

    T.expect(!PmsetParser.sleepDisabled(inPmsetOutput: " sleep 1\n displaysleep 10"),
             "an absent key means off, not a crash")

    T.expect(!PmsetParser.sleepDisabled(inPmsetOutput: ""),
             "empty output means off")

    for line in [" SleepDisabled 1", " SleepDisabled    1", "\tSleepDisabled\t\t1"] {
        T.expect(PmsetParser.sleepDisabled(inPmsetOutput: line),
                 "tolerates whitespace: \(line.debugDescription)")
    }

    // pmset -g custom never contains the key. Reading that command was the
    // original bug, so it is pinned here.
    let customOutput = """
    Battery Power:
     displaysleep         10
     sleep                1
    AC Power:
     displaysleep         10
     sleep                1
    """
    T.expect(!PmsetParser.sleepDisabled(inPmsetOutput: customOutput),
             "pmset -g custom output yields off (the key is never there)")
}

T.suite("pmset -g batt : battery") {
    let discharging = """
    Now drawing from 'Battery Power'
     -InternalBattery-0 (id=35324003)\t91%; discharging; 17:28 remaining present: true
    """
    T.equal(PmsetParser.battery(inBattOutput: discharging).percent, 91, "reads 91%")
    T.expect(PmsetParser.battery(inBattOutput: discharging).onBattery, "knows it is on battery")

    let onAC = """
    Now drawing from 'AC Power'
     -InternalBattery-0 (id=22282339)\t59%; charging; 2:21 remaining present: true
    """
    T.equal(PmsetParser.battery(inBattOutput: onAC).percent, 59, "reads 59%")
    T.expect(!PmsetParser.battery(inBattOutput: onAC).onBattery, "knows it is on mains")

    let full = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t100%; charged; 0:00 remaining"
    T.equal(PmsetParser.battery(inBattOutput: full).percent, 100, "handles a full battery")

    let noPercent = PmsetParser.battery(inBattOutput: "Now drawing from 'AC Power'")
    T.equal(noPercent.percent, nil, "returns nil rather than guessing")

    let empty = PmsetParser.battery(inBattOutput: "")
    T.equal(empty.percent, nil, "survives empty output")
    T.expect(!empty.onBattery, "empty output is not treated as on battery")
}

// The reason this project exists in its current form: the mode was found ON,
// on battery, with no monitor attached, quietly stopping the Mac from sleeping.
T.suite("auto-off policy") {
    let defaults = AutoOffSettings.default

    let modeOff = PowerState(modeIsOn: false, externalDisplayConnected: false,
                             onBattery: true, batteryPercent: 5)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: modeOff, settings: defaults), nil,
            "does nothing when the mode is already off")

    let unplugged = PowerState(modeIsOn: true, externalDisplayConnected: false,
                               onBattery: true, batteryPercent: 91)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: unplugged, settings: defaults),
            .monitorDisconnected,
            "switches off when the monitor is unplugged")

    let atDesk = PowerState(modeIsOn: true, externalDisplayConnected: true,
                            onBattery: false, batteryPercent: 80)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: atDesk, settings: defaults), nil,
            "leaves it alone at the desk, plugged in")

    let lowBattery = PowerState(modeIsOn: true, externalDisplayConnected: true,
                                onBattery: true, batteryPercent: 15)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: lowBattery, settings: defaults),
            .batteryBelow(20),
            "switches off below the battery threshold")

    let lowButCharging = PowerState(modeIsOn: true, externalDisplayConnected: true,
                                    onBattery: false, batteryPercent: 15)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: lowButCharging, settings: defaults), nil,
            "ignores a low battery that is charging")

    let exactly20 = PowerState(modeIsOn: true, externalDisplayConnected: true,
                               onBattery: true, batteryPercent: 20)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: exactly20, settings: defaults),
            .batteryBelow(20),
            "the threshold is inclusive")

    var noBatteryRule = AutoOffSettings.default
    noBatteryRule.batteryThreshold = nil
    T.equal(AutoOffPolicy.reasonToTurnOff(state: lowBattery, settings: noBatteryRule), nil,
            "a disabled threshold never fires")

    var noMonitorRule = AutoOffSettings.default
    noMonitorRule.whenMonitorDisconnected = false
    T.equal(AutoOffPolicy.reasonToTurnOff(state: unplugged, settings: noMonitorRule), nil,
            "a disabled monitor rule never fires")

    let unknownBattery = PowerState(modeIsOn: true, externalDisplayConnected: true,
                                    onBattery: true, batteryPercent: nil)
    T.equal(AutoOffPolicy.reasonToTurnOff(state: unknownBattery, settings: defaults), nil,
            "an unreadable battery does not trigger a switch off")
}

T.suite("risk warnings") {
    var passive = AutoOffSettings.default
    passive.whenMonitorDisconnected = false
    passive.batteryThreshold = nil

    let unplugged = PowerState(modeIsOn: true, externalDisplayConnected: false,
                               onBattery: true, batteryPercent: 91)
    T.equal(AutoOffPolicy.warning(state: unplugged, settings: passive, canActUnattended: true), .onWithoutMonitor,
            "warns when on with no monitor and auto-off is disabled")

    T.equal(AutoOffPolicy.warning(state: unplugged, settings: .default, canActUnattended: true), nil,
            "stays quiet when auto-off will handle it")

    let onBatteryAtDesk = PowerState(modeIsOn: true, externalDisplayConnected: true,
                                     onBattery: true, batteryPercent: 90)
    T.equal(AutoOffPolicy.warning(state: onBatteryAtDesk, settings: passive, canActUnattended: true), .onAndDischarging,
            "warns when on and discharging")

    let safe = PowerState(modeIsOn: true, externalDisplayConnected: true,
                          onBattery: false, batteryPercent: 90)
    T.equal(AutoOffPolicy.warning(state: safe, settings: passive, canActUnattended: true), nil,
            "no warning at the desk on mains")

    let off = PowerState(modeIsOn: false, externalDisplayConnected: false,
                         onBattery: true, batteryPercent: 5)
    T.equal(AutoOffPolicy.warning(state: off, settings: passive, canActUnattended: true), nil,
            "no warning when the mode is off")
}

// The exact state the Mac was found in: mode ON, no monitor, on battery,
// and NO permission to switch off unattended. The app must not look calm.
T.suite("regression: cannot act, must warn") {
    let stuck = PowerState(modeIsOn: true, externalDisplayConnected: false,
                           onBattery: true, batteryPercent: 91)
    T.equal(AutoOffPolicy.warning(state: stuck, settings: .default, canActUnattended: false),
            .couldNotSwitchOff(.monitorDisconnected),
            "warns when auto-off wanted to fire but was not allowed to")

    T.equal(AutoOffPolicy.warning(state: stuck, settings: .default, canActUnattended: true),
            nil,
            "stays quiet when it genuinely can act")

    let lowAndStuck = PowerState(modeIsOn: true, externalDisplayConnected: true,
                                 onBattery: true, batteryPercent: 9)
    T.equal(AutoOffPolicy.warning(state: lowAndStuck, settings: .default, canActUnattended: false),
            .couldNotSwitchOff(.batteryBelow(20)),
            "same for the battery rule")
}

T.report()
