return {
commands = {
	RustOpenDocs = {
	      function()
	        vim.lsp.buf_request(vim.api.nvim_get_current_buf(), 'experimental/externalDocs', vim.lsp.util.make_position_params(), function(err, url)
	          if err then
	            error(tostring(err))
	          else
	            vim.fn['netrw#BrowseX'](url, 0)
	          end
	        end)
	      end,
	      description = 'Open documentation for the symbol under the cursor in default browser',
	    },
	},
  settings = {
      ["rust-analyzer"] = {
				procMacro = {
					enable = true,
				attributes = {
					enable = true,
				}
			},
			checkOnSave = {
				command = "clippy",
			},
			cargo = {
				loadOutDirsFromCheck = true,
			},
    }
	}
}
