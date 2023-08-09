require("user.lsp.handlers").setup()
local opts = {
    on_attach = require("user.lsp.handlers").on_attach,
    capabilities = require("user.lsp.handlers").capabilities,
    config = require("user.lsp.handlers").config,
}

local lspconfig = require'lspconfig'
local rust_opts = require("user.lsp.settings.rust")

local port = os.getenv('GDScript_Port') or '6005'
local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', port)

require'lspconfig'.gdscript.setup({
			{ cmd = godot_cmd, on_attach = opts.on_attach, config = opts.config, capabilities = opts.capabilities, flags = { debounce_text_changes = 150, }}
})



local handlers = {
    -- The first entry (without a key) will be the default handler
    -- and will be called for each installed server that doesn't have
    -- a dedicated handler.
    function (server_name) -- default handler (optional)
        require("lspconfig")[server_name].setup { on_attach = opts.on_attach, capabilities = opts.capabilities, config = opts.config }
    end,
    -- Next, you can provide targeted overrides for specific servers.
    ["rust_analyzer"] = function ()
      require("rust-tools").setup(rust_opts)
    end,
    ["omnisharp"] = function ()
        local csharp_opts = require("user.lsp.settings.csharp")
        lspconfig.omnisharp.organizeImportsOnFormat = true
        lspconfig.omnisharp.dotnet = { inlayHints = { enableInlayHintsForParameters = true } }
        lspconfig.omnisharp.setup(csharp_opts)
    end,
		["pyright"] = function()
			lspconfig.pyright.setup(opts)
			-- vim.diagnostic.config({ virtual_text = false })
		end,


		-- ["gdtoolkit"] = function()
		-- local port = os.getenv('GDScript_Port') or '6005'
		-- local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', port)
		-- lspconfig["gdtoolkit"].setup {
		-- 	{ cmd = godot_cmd, on_attach = opts.on_attach, flags = { debounce_text_changes = 150, }}
		-- }
		-- end,

}

require("mason-lspconfig").setup({ handlers = handlers })

