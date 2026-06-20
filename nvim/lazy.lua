return {
  "thurstonsand/ghosttykit.nvim",
  main = "ghosttykit.nvim",
  build = false,
  lazy = false,
  dependencies = {
    { "thurstonsand/ghosttykit.lua", name = "ghosttykit", build = false },
  },
  keys = {
    {
      "<C-h>",
      function()
        require("ghosttykit.nvim").navigate("left")
      end,
      desc = "GhosttyKit navigate left",
    },
    {
      "<C-j>",
      function()
        require("ghosttykit.nvim").navigate("down")
      end,
      desc = "GhosttyKit navigate down",
    },
    {
      "<C-k>",
      function()
        require("ghosttykit.nvim").navigate("up")
      end,
      desc = "GhosttyKit navigate up",
    },
    {
      "<C-l>",
      function()
        require("ghosttykit.nvim").navigate("right")
      end,
      desc = "GhosttyKit navigate right",
    },
  },
  opts = {},
}
