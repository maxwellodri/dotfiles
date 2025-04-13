local null = {}

local null_ls = require("null-ls")
null.setup = function()
  require("null-ls").setup({
      sources = {
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.formatting.stylua,
        require("none-ls.diagnostics.eslint"),
          -- require("null-ls").builtins.completion.spell, -- annoying spelling variations!
      },
  })
end
return null
