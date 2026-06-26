# @thurstonsand/pi-paste

Paste your Mac clipboard into a remote Pi session.

`@thurstonsand/pi-paste` adds an `alt+v` shortcut and a `/paste` command to Pi. When Pi is running over `gty ssh`, it reaches back through the GhosttyKit bridge with the GhosttyKit TypeScript SDK, reads the clipboard from your local Mac, and inserts it into the remote prompt editor.

That means you can copy something on your Mac and paste it into a coding agent running on another machine. Text is inserted directly. Files, screenshots, PDFs, and Finder copies are written on the remote host and inserted as `@file` references so Pi can read them.

## Install

Install and start GhosttyKit on your Mac. See the root [GhosttyKit README](../../README.md#install) for the full install flow.

```sh
brew install thurstonsand/ghosttykit/ghosttykit
open -a Ghostty
brew services start thurstonsand/ghosttykit/ghosttykit
gty doctor
```

Install the Pi package:

```sh
pi install npm:@thurstonsand/pi-paste
```

Start the remote session with GhosttyKit's SSH wrapper:

```sh
gty ssh your-host
```

Inside Pi, press `alt+v` or run `/paste`.

Use matching nightlies if you want to track the latest changes:

```sh
brew install thurstonsand/ghosttykit/ghosttykit-nightly
brew services start thurstonsand/ghosttykit/ghosttykit-nightly
pi install npm:@thurstonsand/pi-paste@nightly
```

## Settings

Optional global Pi settings:

```json
{
  "paste": {
    "shortcut": "alt+v",
    "outputDir": "/tmp/pi-paste-file"
  }
}
```

- `shortcut`: Pi shortcut to bind. Defaults to `alt+v`.
- `outputDir`: where file paste content is written on the machine running Pi. Defaults to `/tmp/pi-paste-file`.

Paste failures are shown as Pi notifications.

## Development

From this repository:

```sh
pi -e ./pi/pi-paste
```

Run the package checks before publishing changes:

```sh
cd pi/pi-paste
npm run check
```
