# GhosttyKit Neovim plugin

`ghosttykit.nvim` lets Neovim navigation keys move between Neovim windows and Ghostty splits as one workspace.

## Installation

Install GhosttyKit first. The Neovim plugin talks to the `ghosttykitd` daemon through the Lua SDK.

Stable channel:

```sh
brew install thurstonsand/ghosttykit/ghosttykit
open -a Ghostty
brew services start thurstonsand/ghosttykit/ghosttykit
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
brew install thurstonsand/ghosttykit/ghosttykit-nightly
brew services start thurstonsand/ghosttykit/ghosttykit-nightly
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

Add this fragment to your Ghostty config. It makes `Ctrl-h/j/k/l` move between Ghostty splits in shells, while passing those keys through to Neovim when `ghosttykit.nvim` activates the `nvim` key table.

```ghostty
# ctrl-hjkl navigates Ghostty splits unless this surface is in the nvim key table
keybind = ctrl+h=goto_split:left
keybind = ctrl+j=goto_split:down
keybind = ctrl+k=goto_split:up
keybind = ctrl+l=goto_split:right
keybind = nvim/
keybind = nvim/ctrl+h=text:\x08
keybind = nvim/ctrl+j=text:\x0a
keybind = nvim/ctrl+k=text:\x0b
keybind = nvim/ctrl+l=text:\x0c
```

The key table must be named `nvim`. GhosttyKit does not edit your Ghostty config automatically.

## Options

```lua
{
  "thurstonsand/ghosttykit.nvim",
  version = "*", -- use branch = "main" with ghosttykit-nightly
  opts = {
    focused = true,
    key_table = "nvim",
    float_win_behavior = "previous",
    notify_errors = false,
  },
}
```

- `focused`: Activate Ghostty key table while Neovim is focused. Default: `true`.
- `key_table`: Ghostty key table to activate while Neovim is focused. Default: `"nvim"`.
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

The health check reports Ghostty or bridge context and runs the GhosttyKit `doctor` protocol request.
