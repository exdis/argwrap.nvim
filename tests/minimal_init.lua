vim.opt.rtp = {}

local cwd = vim.fn.getcwd()

vim.opt.rtp:append(cwd)

vim.opt.rtp:append(cwd .. "/deps/plenary.nvim")

vim.cmd("runtime! plugin/plenary.vim")
vim.cmd("filetype off")
vim.cmd("syntax off")
