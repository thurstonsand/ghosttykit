local M = {}

local mappings = {
  { key = "<Plug>(GhosttyKitNavigateLeft)", direction = "left", desc = "GhosttyKit navigate left" },
  { key = "<Plug>(GhosttyKitNavigateDown)", direction = "down", desc = "GhosttyKit navigate down" },
  { key = "<Plug>(GhosttyKitNavigateUp)", direction = "up", desc = "GhosttyKit navigate up" },
  { key = "<Plug>(GhosttyKitNavigateRight)", direction = "right", desc = "GhosttyKit navigate right" },
}

local function navigate(direction)
  return function()
    require("ghosttykit.nvim").navigate(direction)
  end
end

function M.setup_plug_mappings()
  for _, mapping in ipairs(mappings) do
    vim.keymap.set("n", mapping.key, navigate(mapping.direction), { desc = mapping.desc })
  end
end

return M
