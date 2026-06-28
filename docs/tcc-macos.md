# macOS Automation Permissions

Status: stable Homebrew releases use the bundled identity.

`ghosttykitd` controls Ghostty through macOS Apple Events. Homebrew service packaging must prove that the daemon can request, retain, and diagnose Automation/TCC permissions when launched through `brew services`.

Release builds package `ghosttykitd` inside `GhosttyKitD.app`, a background-only app bundle with `NSAppleEventsUsageDescription` and the stable bundle identifier `dev.ghosttykit.ghosttykitd`. The bundle and daemon are signed with the Apple Events hardened-runtime entitlement. Homebrew launches the daemon from inside that bundle so macOS TCC records Automation access against the bundle identity instead of a versioned Cellar executable path.

On startup, the daemon performs a harmless Ghostty Apple Events preflight when Ghostty is already running. This is meant to make the first `brew services start thurstonsand/ghosttykit/ghosttykit-nightly` trigger the normal macOS Automation prompt instead of deferring the failure until the first layout command. After that first bundled authorization, Homebrew upgrades should retain access as long as the bundle identifier and signing requirement stay stable.

First-run flow:

```sh
open -a Ghostty
brew services start thurstonsand/ghosttykit/ghosttykit-nightly
gty doctor
```

`gty doctor` proves the socket and service are reachable, then asks the daemon to rerun a harmless Ghostty Apple Events check and reports whether Automation is confirmed, failed, or could not be checked because Ghostty is not running.

If macOS denies Automation access, `gty doctor` reports a failed Automation check. Check the daemon log at `$(brew --prefix)/var/log/ghosttykitd.log`.

For manual reset during packaging tests:

```sh
tccutil reset AppleEvents dev.ghosttykit.ghosttykitd
brew services restart thurstonsand/ghosttykit/ghosttykit-nightly
```
