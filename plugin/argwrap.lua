if vim.g.loaded_argwrap then
  return
end
vim.g.loaded_argwrap = true

vim.api.nvim_create_user_command("ArgWrapToggle", function()
  require("argwrap").toggle()
end, { desc = "Toggle argument wrapping" })
