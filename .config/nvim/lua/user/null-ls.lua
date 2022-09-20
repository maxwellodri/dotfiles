local null = {}


null.setup = function()
  require("null-ls").setup({
      sources = {
          require("null-ls").builtins.formatting.stylua,
          require("null-ls").builtins.diagnostics.eslint,
          -- require("null-ls").builtins.completion.spell, -- annoying spelling variations!
      },
  })
end
return null
