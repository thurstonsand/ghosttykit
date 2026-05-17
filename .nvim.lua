vim.opt.autoread = true

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("ghosttykit_checktime", { clear = true }),
  callback = function()
    if vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})

vim.lsp.config("gopls", {
  settings = {
    gopls = {
      buildFlags = { "-tags=integration" },
    },
  },
})
