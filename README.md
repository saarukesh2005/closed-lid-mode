<img src="docs/icon.png" width="120" align="right" alt="Closed-Lid Mode icon">

# Closed-Lid Mode

[![Build](https://github.com/saarukesh2005/closed-lid-mode/actions/workflows/build.yml/badge.svg)](https://github.com/saarukesh2005/closed-lid-mode/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/saarukesh2005/closed-lid-mode)](https://github.com/saarukesh2005/closed-lid-mode/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A macOS menu bar switch for using an external monitor with the laptop lid
shut **while running on battery**.

```
🟢 LID ON     lid can stay shut, external monitor keeps working
🔴 LID OFF    normal Apple behaviour: lid shut on battery = sleep
```

## The problem

Apple only allows clamshell mode (lid closed, external display active) when
the Mac is **plugged in**. On battery, closing the lid puts it to sleep and
the external monitor goes dark. There is no setting for this anywhere in
System Settings.

macOS does have a hidden power setting that lifts the restriction, but it is
undocumented, system-wide, survives reboots, and is easy to leave switched on
by accident — which quietly stops your Mac ever sleeping. This app makes the
state permanently visible in the menu bar and one click away.

## Install

### Option A — download the app

Grab **ClosedLidMode-1.0.0.dmg** from the
[latest release](https://github.com/saarukesh2005/closed-lid-mode/releases/latest),
open it, and drag **Closed-Lid Mode** into Applications.

The first launch will be blocked. **This is expected** — see below.

### Option B — build it yourself (no warnings)

Needs the Xcode Command Line Tools (`xcode-select --install`). Nothing else.

```bash
git clone https://github.com/saarukesh2005/closed-lid-mode.git
cd closed-lid-mode
./build.sh --install
```

An app you compile yourself is never quarantined, so it just opens. If you
are comfortable in a terminal, this is the smoother path.

Run the tests with `./build.sh --test`.

Either way, look for a red or green dot in your menu bar afterwards.

To start it automatically: System Settings → General → **Login Items &
Extensions** → *Open at Login* → **+** → Closed-Lid Mode.

## About that Gatekeeper warning

If you download the release, macOS will refuse to open it:

> "Closed-Lid Mode" can't be opened because Apple cannot check it for
> malicious software.

**Why:** Apple only waives that for apps signed with a Developer ID
certificate and notarised through Apple's service. That requires the Apple
Developer Program, which costs 99 USD a year. This app is free and
ad-hoc signed instead, so it gets the warning. Verified with
`spctl -a -t exec`: **rejected**, `Signature=adhoc`, `TeamIdentifier=not set`.

Nothing is wrong with the app; macOS simply has no paid identity to check it
against. You should be sceptical of that claim from any stranger on the
internet, which is exactly why **Option B exists** — build it from source and
read the single 230-line file first. It is short on purpose.

To open the downloaded version anyway, pick one:

**From System Settings** — try to open the app, let it be blocked, then go to
System Settings → **Privacy & Security**, scroll down, and click
**Open Anyway** next to the message about Closed-Lid Mode. On macOS 15 and
later this is the only click-through route; right-click → Open no longer
works for unsigned apps.

**From Terminal** — strip the download quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Closed-Lid Mode.app"
```

## Using it

Click the indicator for a menu with the state spelled out and one button to
flip it.

```
🟢 LID ON     on, and nothing to worry about
⚠️ LID ON     on, but the monitor is unplugged or you are on battery
🔴 LID OFF    normal Apple behaviour
```

### It switches itself off

The setting is system-wide and survives reboots, so it is very easy to leave
on, walk away, and have the Mac sit awake in a bag draining. That is not a
hypothetical - it is what prompted this feature.

So the app watches, and by default turns the mode off by itself when:

- the external monitor is unplugged, or
- the battery drops to 20% while on battery

Both are switchable in **Switch off automatically**.

Acting unattended needs administrator rights, and there is nobody to approve
a password prompt while you are away. So the app asks once for permission to
switch *off* without a prompt - a single narrow rule that grants exactly
`pmset -a disablesleep 0`. Turning the mode **on** still requires
authentication, which means the worst that rule can do is make your Mac more
willing to sleep. Grant or revoke it from the same menu.

Without that permission nothing is lost - the app just warns loudly with
**⚠️ LID ON** instead of acting.

### Touch ID

**Unlock with Touch ID** in the menu switches on Touch ID for `sudo`, so the
app asks for your fingerprint instead of your password. One macOS
authentication prompt and it is done - no Terminal, no commands to paste.

It writes Apple's own `sudo_local` file, which exists so the setting survives
macOS updates, and the same menu item turns it off again. Everything that
asks for your password in Terminal will accept your fingerprint too.

### Start at login

**Start at login** in the menu, via Apple's `SMAppService`. No hand-written
LaunchAgent, and it shows up in System Settings → Login Items like any other
app.

### Copy diagnostics

Puts the app version, macOS version, mode state, monitor, lid, battery and
every permission setting on the clipboard. Useful when something looks wrong.

## What it actually changes

One undocumented `pmset` setting, nothing else:

```bash
sudo pmset -a disablesleep 1    # ON
sudo pmset -a disablesleep 0    # OFF
```

The app detects the current state by parsing `SleepDisabled` out of
`pmset -g`, re-reads it every 5 seconds so the display stays truthful, and
verifies the value after writing it — if macOS refuses, you get told rather
than a silent lie.

## Things to know before using it

- **It is system-wide, not battery-only.** `pmset` accepts a `-b` (battery)
  flag, but the value is stored once under `SystemPowerSettings` and applies
  on AC too. While ON, the Mac will not sleep on *any* power source. Shut the
  lid and put it in a bag like that and it keeps running.
- **It survives restarts.** The value is written to
  `/Library/Preferences/com.apple.PowerManagement.plist`. A reboot does not
  clear it.
- **Quitting the app does not turn it off.** The app warns you if you try.
- You need an external keyboard and mouse to use the Mac lid-shut.
- Fanless Macs (MacBook Air) trap heat with the lid shut. Heavy sustained work
  in clamshell will run warm and may throttle.
- Display sleep is untouched — the screen still blanks when idle, and a
  keypress wakes it.
- `disablesleep` is not in the `pmset` manual. It works, but Apple does not
  document it, so a future macOS release could change its behaviour.

## Notes for anyone hacking on this

Findings that cost real debugging time, written down so they do not have to be
rediscovered:

**`disablesleep` never appears in `pmset -g custom`.** Only in plain
`pmset -g`, as `SleepDisabled`. An early version read the per-power-source
list, always found nothing, and therefore always believed the mode was off.

**An `NSStatusItem` can be completely invisible while reporting itself as
present and correctly sized.** Two separate causes, both hit here:

- `button.attributedTitle` with an attributed string that names no
  `.foregroundColor` defaults to **black**, which is unreadable on a dark menu
  bar.
- An SF Symbol passed through `withSymbolConfiguration(_:)` can lose its
  template flag, so macOS stops tinting it and it renders dark-on-dark.

Fixing both was still not enough to be confident, so the shipped version uses
**no image at all** and a colour emoji in the plain `button.title`. Emoji are
colour bitmaps, immune to tinting and appearance changes, so the indicator
cannot silently disappear again.

**The accessibility API reports menu bar items at negative y.** On a
single-external-display setup these came back at y ≈ −58. That is normal —
Control Center's visible icons report the same — and is not evidence of being
off-screen. Compare against a known-visible item before chasing it.

**Other apps can mask whether this setting works.** Electron apps (and
anything calling `IOPMAssertionCreate`) hold a `NoIdleSleepAssertion` while
running, and that alone can keep clamshell alive on battery with this mode
**off**. So "it worked on battery" is not proof. Check with:

```bash
pmset -g assertions
```

## Project layout

```
Sources/ClosedLidModeCore/   parsing and decisions - no AppKit, all tested
Sources/ClosedLidMode/       the app: menu bar, actions, privileged setup
Sources/ClosedLidModeTests/  the test suite
tools/make-icon.swift        draws AppIcon.icns with Core Graphics
build.sh                     build / test / install / package
```

The tests are a plain executable run with `swift run ClosedLidModeTests`,
not XCTest and not Swift Testing. Both of those ship with full Xcode rather
than the Command Line Tools, so a contributor with only the CLT installed
could not run them at all. A test nobody can run is worth nothing.

## Licence

MIT — see [LICENSE](LICENSE).
