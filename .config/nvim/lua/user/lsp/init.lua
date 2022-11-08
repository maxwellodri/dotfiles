require("user.lsp.handlers").setup()
local opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}

local lspconfig = require'lspconfig'
local rust_opts = require("user.lsp.settings.rust")

require("mason-lspconfig").setup_handlers({
  function (server_name)
    require("lspconfig")[server_name].setup {
      on_attach = opts.on_attach,
      capabilities = opts.capabilities,
      config = opts.config,
          }
      end,
      ["rust_analyzer"] = function ()
        require('rust-tools').setup(rust_opts)
      end,
      ["sumneko_lua"] = function ()
          lspconfig.sumneko_lua.setup {
            on_attach = opts.on_attach,
            capabilities = opts.capabilities,
            config = opts.config,
              settings = {
                  Lua = {
                      diagnostics = {
                          globals = { "vim" }
                      },
	   	            workspace = {
	   	            	library = {
	   	            		[vim.fn.expand("$VIMRUNTIME/lua")] = true,
	   	            		[vim.fn.stdpath("config") .. "/lua"] = true,
	   	            	},
	   	            },
                 },
             }
          }
      end,

      -- ["jsonls"] = function ()
  	  -- 	local jsonls = require("user.lsp.settings.jsonls")
  	  -- 	-- opts = vim.tbl_deep_extend("force", rust_analyzer_opts, opts)
 	    -- -- opts = vim.tbl_deep_extend("force", rust_tools_opts, opts)
  	  -- 	 -- vim.tbl_deep_extend("force", rust_analyzer_opts, lspconfig.rust_analyzer.setup)
      --    lspconfig.jsonls.setup {
      --       on_attach = opts.on_attach,
      --       capabilities = opts.capabilities,
      --       config = opts.config,
      --       setup = jsonls.setup,
      --       settings = jsonls.settings,
      --    }

      -- end,
})
-- lsp_installer.on_server_ready(function(server)
-- 
-- 	 if server.name == "jsonls" then
-- 	 	local jsonls_opts = require("user.lsp.settings.jsonls")
-- 	 	opts = vim.tbl_deep_extend("force", jsonls_opts, opts)
-- 	 end
-- 
-- 	 if server.name == "sumneko_lua" then
-- 	 	local sumneko_opts = require("user.lsp.settings.sumneko_lua")
-- 	 	opts = vim.tbl_deep_extend("force", sumneko_opts, opts)
-- 	 end
-- 
-- 	 if server.name == "rust_analyzer" then
-- 	 	local rust_analyzer_opts = require("user.lsp.settings.rust_analyzer")
-- 	 	opts = vim.tbl_deep_extend("force", rust_analyzer_opts, opts)
-- 	 end
-- 
-- 	 if server.name == "pyright" then
-- 	 	local pyright_opts = require("user.lsp.settings.pyright")
-- 	 	opts = vim.tbl_deep_extend("force", pyright_opts, opts)
-- 	 end
-- 
--   if server.name == "tsserver" then
--     client.server_capabilities.documentFormatting = false
--   end
-- 
-- 	-- This setup() function is exactly the same as lspconfig's setup function.
-- 	-- Refer to https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
-- 	server:setup(opts)
-- end)
