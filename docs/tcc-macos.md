# macOS Automation Permissions

Status: in progress.

`ghosttykitd` controls Ghostty through macOS Apple Events. Homebrew service packaging must prove that the daemon can request, retain, and diagnose Automation/TCC permissions when launched through `brew services`.

Release builds embed an Info.plist with `NSAppleEventsUsageDescription` and sign `ghosttykitd` with the Apple Events hardened-runtime entitlement. On startup, the daemon performs a harmless Ghostty Apple Events preflight when Ghostty is already running. This is meant to make the first `brew services start ghosttykit/local/ghosttykit` trigger the normal macOS Automation prompt instead of deferring the failure until the first layout command.

First-run flow:

```sh
brew services start ghosttykit/local/ghosttykit
gty doctor
```

`gty doctor` proves the socket and service are reachable, then asks the daemon to rerun a harmless Ghostty Apple Events check and reports whether Automation is confirmed, failed, or could not be checked because Ghostty is not running.

If macOS denies Automation access, `gty doctor` reports a failed Automation check. Check the daemon log at `$(brew --prefix)/var/log/ghosttykitd.log`.

For manual reset during packaging tests:

```sh
tccutil reset AppleEvents dev.ghosttykit.ghosttykitd
brew services restart ghosttykit/local/ghosttykit
```
