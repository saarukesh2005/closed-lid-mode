import Foundation

/// Reads `pmset` output.
///
/// Worth knowing: the `disablesleep` setting does NOT appear in
/// `pmset -g custom` at all - only in plain `pmset -g`, as `SleepDisabled`.
/// An early version of this app read the wrong command, always found nothing,
/// and therefore always believed the mode was off.
public enum PmsetParser {

    /// Parses `pmset -g`. Absent key means off.
    public static func sleepDisabled(inPmsetOutput output: String) -> Bool {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("SleepDisabled") else { continue }
            // "	SleepDisabled		1"  -> last whitespace-separated field
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let value = fields.last {
                return value == "1"
            }
        }
        return false
    }

    public struct Battery: Equatable, Sendable {
        public let percent: Int?
        public let onBattery: Bool
        public init(percent: Int?, onBattery: Bool) {
            self.percent = percent
            self.onBattery = onBattery
        }
    }

    /// Parses `pmset -g batt`, e.g.
    ///
    ///     Now drawing from 'Battery Power'
    ///      -InternalBattery-0 (id=123)	91%; discharging; 17:28 remaining present: true
    public static func battery(inBattOutput output: String) -> Battery {
        // "AC Power" is the reliable signal; a Mac with no battery reports it too.
        let onBattery = output.contains("'Battery Power'")

        var percent: Int?
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: #"\d{1,3}%"#, options: .regularExpression) else { continue }
            let digits = line[range].dropLast()   // strip "%"
            if let value = Int(digits), (0...100).contains(value) {
                percent = value
                break
            }
        }
        return Battery(percent: percent, onBattery: onBattery)
    }
}
