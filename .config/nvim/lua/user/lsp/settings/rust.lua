function Toggle_inlay_hints()
    local hints = _G.RUSTTOOLSINLAY or OPTS.inlay_hints
    if hints == true then
        -- require('rust-tools').inlay_hints.disable()
        vim.cmd("RustDisableInlayHints")
    else
        vim.cmd("RustEnableInlayHints")
    -- require('rust-tools').inlay_hints.enable()
    end
    _G.RUSTTOOLSINLAY = not _G.RUSTTOOLSINLAY
end


local ra_settings = {
      ["rust-analyzer"] = {
        diagnostics = { enabled = true, disabled = {"inactive-code"} },
			  procMacro = {
			  		enable = true,
			  	attributes = {
			  		enable = true,
			  	}
			  },
			  checkOnSave = {
			  	command = "clippy",
           extraArgs={"--target-dir", "/var/tmp/rust-analyzer-check"}
			  },
			  -- cargo = {
			  -- 	loadOutDirsFromCheck = true,
			  -- },
        imports = { prefix = "crate" },
        inlay_hints = { lifetimeElisionHints = { enable = "skip_trivial" }, },
      }
}

local generic_opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}


local extension_path = vim.env.HOME .. '/.vscode/extensions/vadimcn.vscode-lldb-1.6.7/'
local codelldb_path = extension_path .. 'adapter/codelldb'
local liblldb_path = extension_path .. 'lldb/lib/liblldb.so'

OPTS = {
  tools = { -- rust-tools options
        -- Automatically set inlay hints (type hints)
        autoSetHints = false,
        -- Whether to show hover actions inside the hover window
        -- This overrides the default hover handler
		-- how to execute terminal commands
		-- options right now: termopen / quickfix
		executor = require("rust-tools/executors").termopen,

        runnables = {
            -- whether to use telescope for selection menu or not
            use_telescope = true
            -- rest of the opts are forwarded to telescope
        },
        -- on_initialized = ra_callback,
        reload_workspace_from_cargo_toml = true,
        debuggables = {
            -- whether to use telescope for selection menu or not
            use_telescope = true
            -- rest of the opts are forwarded to telescope
        },

        -- These apply to the default RustSetInlayHints command
        inlay_hints = {
            -- Only show inlay hints for the current line
            only_current_line = false,

            -- Event which triggers a refersh of the inlay hints.
            -- You can make this "CursorMoved" or "CursorMoved,CursorMovedI" but
            -- not that this may cause  higher CPU usage.
            -- This option is only respected when only_current_line and
            -- autoSetHints both are true.
            only_current_line_autocmd = "CursorHold",

            -- wheter to show parameter hints with the inlay hints or not
            show_parameter_hints = false,

            -- prefix for parameter hints
            parameter_hints_prefix = "", -- <- ",

            -- prefix for all the other hints (type, chaining)
            other_hints_prefix = "=> ",

            -- whether to align to the length of the longest line in the file
            max_len_align = true,

            -- padding from the left if max_len_align is true
            max_len_align_padding = 4,

            -- whether to align to the extreme right or not
            right_align = false,

            -- padding from the right if right_align is true
            right_align_padding = 8,

            -- The color of the hints
            highlight = "SpecialComment",
        },

        hover_actions = {
            -- the border that is used for the hover window
            -- see vim.api.nvim_open_win()
            border = {
                {"╭", "FloatBorder"}, {"─", "FloatBorder"},
                {"╮", "FloatBorder"}, {"│", "FloatBorder"},
                {"╯", "FloatBorder"}, {"─", "FloatBorder"},
                {"╰", "FloatBorder"}, {"│", "FloatBorder"}
            },

            -- whether the hover action window gets automatically focused
            auto_focus = false
        },

        -- settings for showing the crate graph based on graphviz and the dot
        -- command
        crate_graph = {
            -- Backend used for displaying the graph
            -- see: https://graphviz.org/docs/outputs/
            -- default: x11
            backend = "x11",
            -- where to store the output, nil for no output stored (relative
            -- path from pwd)
            -- default: nil
            output = nil,
            -- true for all crates.io and external crates, false only the local
            -- crates
            -- default: true
            full = true,
        }
  },
	server = {
        commands = ra_commands,
        settings = ra_settings,
	      standalone = false,
        capabilities = generic_opts.capabilities,
        config = generic_opts.config,
        on_attach = generic_opts.on_attach,
	},

    -- debugging stuff
    dap = {
        adapter = {
            type = 'executable',
            command = 'lldb-vscode',
            name = "rt_lldb"
        }
    }
}

-- local _ = require('null-ls')

require('crates').setup {
    date_format = "%d-%m-%Y",
    null_ls = {
        enabled = true,
        name = "crates.nvim",
    },
}


return OPTS
