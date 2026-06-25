return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = {
              analysis = {
                exclude = { "**/.venv", "**/venv", "**/node_modules", "**/__pycache__" },
              },
            },
          },
        },
      },
    },
  },
}
