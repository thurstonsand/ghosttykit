# Install

Status: skeleton.

The primary macOS install path will be Homebrew. The formula should install:

- `gty`
- `ghosttykitd`
- a `brew services` user service for `ghosttykitd`

Remote hosts should receive `gty` through the normal `gty ssh` bootstrap/upgrade flow where practical.
