return {
  {
    "bjarneo/ash.nvim",
    name = "ash",
  },
  { "Shatur/neovim-ayu" },
  { "luisiacc/gruvbox-baby", name = "gruvbox-baby" },
  {
    "neanias/everforest-nvim",
    main = "everforest", -- This tells LazyVim to use require("everforest").setup(opts)
    opts = {
      background = "soft",
    },
    { "rebelot/kanagawa.nvim", name = "kanagawa" },
  },

  {

    "LazyVim/LazyVim",
    opts = {
      -- colorscheme = "ayu-dark",
      --  colorscheme = "ash",
      -- colorscheme = "gruvbox-baby",
      colorscheme = function() end,
      -- colorscheme = "kanagawa-wave",
    },
  },
}
