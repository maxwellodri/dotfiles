local generic_opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}

local pid = vim.fn.getpid()
-- local omnisharp_path = "/home/maxwell/.local/share/nvimmason/packages/omnisharp/libexec/OmniSharp.dll"
local omnisharp_path = "/home/maxwell/.local/share/nvimmason/packages/omnisharp/omnisharp"
return {
  handlers = {
    ["textDocument/definition"] = require('omnisharp_extended').handler,
  },
  on_attach = generic_opts.on_attach,
  config = generic_opts.config,
  capabilities = generic_opts.capabilities,
  -- find OmniSharp.dll path via fd -H OmniSharp.dll
  -- make sure to use fully expanded path
  -- cmd = { "dotnet", omnisharp_path},
  cmd = { omnisharp_path, '--languageserver' , '--hostPID', tostring(pid) },

  -- Enables support for reading code style, naming convention and analyzer
  -- settings from .editorconfig.
  enable_editorconfig_support = true,

  -- If true, MSBuild project system will only load projects for files that
  -- were opened in the editor. This setting is useful for big C# codebases
  -- and allows for faster initialization of code navigation features only
  -- for projects that are relevant to code that is being edited. With this
  -- setting enabled OmniSharp may load fewer projects and may thus display
  -- incomplete reference lists for symbols.
  enable_ms_build_load_projects_on_demand = false,

  -- Enables support for roslyn analyzers, code fixes and rulesets.
  enable_roslyn_analyzers = true,

  -- Specifies whether 'using' directives should be grouped and sorted during
  -- document formatting.
  organize_imports_on_format = true,

  -- Enables support for showing unimported types and unimported extension
  -- methods in completion lists. When committed, the appropriate using
  -- directive will be added at the top of the current file. This option can
  -- have a negative impact on initial completion responsiveness,
  -- particularly for the first few completion sessions after opening a
  -- solution.
  enable_import_completion = true,

  -- Specifies whether to include preview versions of the .NET SDK when
  -- determining which version to use for project loading.
  sdk_include_prereleases = true,

  -- Only run analyzers against open files when 'enableRoslynAnalyzers' is
  -- true
  analyze_open_documents_only = false,
  inlayHints = { enableInlayHintsForTypes = true },
  csharp = {
    inlayHints = { enableInlayHintsForTypes = true }
  },

}
