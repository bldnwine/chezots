return {
    {
        "bjarneo/aether.nvim",
        branch = "v2",
        name = "aether",
        priority = 1000,
        opts = {
            transparent = true,
            colors = {
                bg = "#202027",
                bg_dark = "#202027",
                bg_highlight = "NONE",
                fg = "#f4ea9c",
                fg_dark = "#f4ea9c",
                comment = "#a59c88",
                red = "#b27575",
                orange = "#d5aeae",
                yellow = "#bdbd89",
                green = "#80b780",
                cyan = "#7cb6b6",
                blue = "#9393c3",
                purple = "#ae6fae",
                magenta = "#c482c4",
            },
        },
        config = function(_, opts)
            require("aether").setup(opts)
            vim.cmd.colorscheme("aether")
            require("aether.hotreload").setup()
        end,
    },
    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "aether",
        },
    },
}
