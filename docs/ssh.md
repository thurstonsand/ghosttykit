# SSH Bridge

Status: skeleton.

`gty ssh` uses OpenSSH Unix-socket reverse forwarding to expose a daemon-owned local bridge socket to a remote `gty` process.

Default behavior is soft failure: if bootstrap, forwarding, or bridge setup fails, `gty ssh` warns and continues as plain SSH. `--require-bridge` makes bridge setup failure fatal for tests and debugging.

Remote commands discover the bridge through `GTY_SOCK`.
