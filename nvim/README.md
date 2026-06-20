# GhosttyKit Neovim plugin

`ghosttykit.nvim` lets Neovim navigation keys move between Neovim windows and Ghostty splits as one workspace.

## Installation

Load the plugin at startup. It coordinates focus state with Ghostty, so lazy loading is not recommended.

With lazy.nvim:

```lua
{
  "thurstonsand/ghosttykit.nvim",
  version = "*",
  opts = {},
}
```

The bundled lazy.nvim spec maps CTRL-h, CTRL-j, CTRL-k, and CTRL-l through lazy.nvim `keys`.

With other plugin managers, load the plugin at startup, configure it, and bind the provided `<Plug>` mappings:

```lua
require("ghosttykit.nvim").setup({})

vim.keymap.set("n", "<C-h>", "<Plug>(GhosttyKitNavigateLeft)")
vim.keymap.set("n", "<C-j>", "<Plug>(GhosttyKitNavigateDown)")
vim.keymap.set("n", "<C-k>", "<Plug>(GhosttyKitNavigateUp)")
vim.keymap.set("n", "<C-l>", "<Plug>(GhosttyKitNavigateRight)")
```

## Options

```lua
{
  "thurstonsand/ghosttykit.nvim",
  version = "*",
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
