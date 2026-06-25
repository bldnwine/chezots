vim.opt.rtp:prepend("/home/bldnwine/.local/share/nvim/site")
-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Disable cursorline
vim.opt.cursorline = false

-- Load Aether colorscheme (after plugins load)
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local aether = vim.fn.expand("~/.config/aether/theme/neovim.lua")
    if vim.fn.filereadable(aether) == 1 then
      vim.cmd("source " .. aether)
    end
  end,
  once = true,
})
