if vim.g.loaded_ghosttykit_nvim then
  return
end
vim.g.loaded_ghosttykit_nvim = true

vim.api.nvim_create_user_command("GhosttyKit", function(opts)
  local subcommand = opts.fargs[1]
  if subcommand == "doctor" then
    vim.cmd("checkhealth ghosttykit")
    return
  end
  vim.notify("Unknown GhosttyKit command: " .. tostring(subcommand), vim.log.levels.ERROR, { title = "ghosttykit" })
end, {
  nargs = "+",
  complete = function(arg_lead)
    return vim.tbl_filter(function(item)
      return item:find(arg_lead, 1, true) == 1
    end, { "doctor" })
  end,
})
