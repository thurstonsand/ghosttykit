# GhosttyKit Neovim plugin

`ghosttykit.nvim` lets Neovim navigation keys move between Neovim windows and Ghostty splits as one workspace.

## Installation

Install GhosttyKit first. The Neovim plugin talks to the `ghosttykitd` daemon through the Lua SDK.

Stable channel:

```sh
brew install thurstonsand/tap/ghosttykit
open -a Ghostty
brew services start thurstonsand/tap/ghosttykit
gty doctor
```

With lazy.nvim:

```lua
{
  "thurstonsand/ghosttykit.nvim",
  version = "*",
  opts = {},
}
```

Nightly channel. Pair `ghosttykit-nightly` with the plugin mirror's `main` branch:

```sh
brew install thurstonsand/tap/ghosttykit-nightly
brew services start thurstonsand/tap/ghosttykit-nightly
```

```lua
{
  "thurstonsand/ghosttykit.nvim",
  branch = "main",
  opts = {},
}
```

See the root [GhosttyKit README](../README.md#install) for the full install flow and Automation permission details.

Load the plugin at startup. It coordinates focus state with Ghostty, so lazy loading is not recommended.

The bundled lazy.nvim spec maps CTRL-h, CTRL-j, CTRL-k, and CTRL-l through lazy.nvim `keys`.

With other plugin managers, load the plugin at startup, configure it, and bind the provided `<Plug>` mappings:

```lua
require("ghosttykit.nvim").setup({})

vim.keymap.set("n", "<C-h>", "<Plug>(GhosttyKitNavigateLeft)")
vim.keymap.set("n", "<C-j>", "<Plug>(GhosttyKitNavigateDown)")
vim.keymap.set("n", "<C-k>", "<Plug>(GhosttyKitNavigateUp)")
vim.keymap.set("n", "<C-l>", "<Plug>(GhosttyKitNavigateRight)")
```

## Ghostty key table

Add this fragment to your Ghostty config. It makes `Ctrl-h/j/k/l` move between Ghostty splits in shells, while passing those keys through to whatever inner layer claims them — Neovim, or a remote Herdr session under `gty herdr attach`.

```ghostty
# ctrl-hjkl navigates Ghostty splits unless an inner layer owns this surface
keybind = ctrl+h=goto_split:left
keybind = ctrl+j=goto_split:down
keybind = ctrl+k=goto_split:up
keybind = ctrl+l=goto_split:right
keybind = bypass/
keybind = bypass/ctrl+h=text:\x08
keybind = bypass/ctrl+j=text:\x0a
keybind = bypass/ctrl+k=text:\x0b
keybind = bypass/ctrl+l=text:\x0c
```

The key table must be named `bypass`. GhosttyKit does not edit your Ghostty config automatically.

## Inside Herdr

When Neovim runs in a [Herdr](https://herdr.dev) pane, the plugin detects `HERDR_ENV=1` and changes two things.

At a Neovim window edge it asks Herdr to move instead of calling GhosttyKit, talking to `$HERDR_SOCKET_PATH` directly over Herdr's socket protocol. Herdr focuses a neighboring pane when the pane has one, and otherwise signals the outer Ghostty layer for `gty herdr attach` to act on. The requests are asynchronous, so the keypress never waits on the remote host, and a failed request is reported rather than silently retried against Ghostty. Internal window movement is unchanged.

It also stops managing the Ghostty key table. `gty herdr attach` holds that table for the whole Herdr session; if Neovim released it on exit or suspend, the surrounding Herdr panes would stop receiving navigation keys. The `<Plug>` mappings are installed as usual.

This needs no configuration: Herdr sets `HERDR_ENV`, `HERDR_SOCKET_PATH`, and `HERDR_PANE_ID` in every pane. See [`docs/ssh.md`](../docs/ssh.md#herdr-attach) for the attach command and the Herdr keybindings it expects.

## Options

```lua
{
  "thurstonsand/ghosttykit.nvim",
  version = "*", -- use branch = "main" with ghosttykit-nightly
  opts = {
    key_table = "bypass",
    float_win_behavior = "previous",
    notify_errors = false,
  },
}
```

- `key_table`: Ghostty key table to activate while Neovim is focused. Default: `"bypass"`.
- `float_win_behavior`: Floating window navigation. `"previous"` returns to the previous normal window. `"mux"` sends navigation to Ghostty instead. Default: `"previous"`.
- `notify_errors`: Show daemon errors with `vim.notify()`. Navigation failures are quiet by default. Default: `false`.

## Mappings

lazy.nvim users can customize mappings through their plugin spec `keys`:

```lua
{
  "thurstonsand/ghosttykit.nvim",
  keys = {
    { "<C-h>", false },
    { "<C-l>", false },
    { "<A-h>", function() require("ghosttykit.nvim").navigate("left") end,
      desc = "GhosttyKit navigate left" },
    { "<A-l>", function() require("ghosttykit.nvim").navigate("right") end,
      desc = "GhosttyKit navigate right" },
  },
  opts = {},
}
```

Other plugin managers can map the provided `<Plug>` mappings:

```lua
vim.keymap.set("n", "<C-h>", "<Plug>(GhosttyKitNavigateLeft)")
vim.keymap.set("n", "<C-j>", "<Plug>(GhosttyKitNavigateDown)")
vim.keymap.set("n", "<C-k>", "<Plug>(GhosttyKitNavigateUp)")
vim.keymap.set("n", "<C-l>", "<Plug>(GhosttyKitNavigateRight)")
```

## Health

Run:

```vim
:checkhealth ghosttykit
```

The health check reports Ghostty or bridge context, the Herdr socket and pane it would navigate through when Neovim runs in a Herdr pane, and runs the GhosttyKit `doctor` protocol request.
