local status_ok, configs = pcall(require, "nvim-treesitter.configs")
if not status_ok then
    return
end

configs.setup {
    ensure_installed = {"rust", "python", "bash", "toml", "nix"},
    sync_install = false,
    ignore_install = { "" },
    highlight = {
        enable = { "markdown", "markdown_inline" },
        additional_vim_regex_highlighting = false,
        -- disable = { "markdown" },
    },
    indent = { enable = true, disable = { "yaml", "markdown", "markdown_inline" } },
}

vim.keymap.set("n", "<leader>gS", function()
    local result = {}
    -- Get word and line info
    local cursor_word = vim.fn.expand('<cword>')
    local cursor_line = vim.api.nvim_get_current_line()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    
    -- Get treesitter captures
    local captures = vim.treesitter.get_captures_at_pos(
        vim.api.nvim_get_current_buf(),
        cursor_pos[1] - 1,
        cursor_pos[2]
    )

    -- Get LSP semantic tokens
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
    
    -- Check if we have semantic tokens capability
    local has_semantic = false
    for _, client in ipairs(clients) do
        if client.server_capabilities.semanticTokensProvider then
            has_semantic = true
            break
        end
    end

    -- Get semantic token information if available
    local token_info = ""
    if has_semantic then
        local token_type, token_modifiers = vim.lsp.semantic_tokens.get_at_pos()
        if token_type then
            -- Debug print to see the table structure
            vim.print("Token type table:", vim.inspect(token_type))
            
            -- Properly unpack the token type
            local type_str
            if type(token_type) == "table" then
                -- Get the token type string from the table
                type_str = token_type.type or vim.inspect(token_type)
            else
                type_str = tostring(token_type)
            end
            
            token_info = string.format([[

LSP Semantic Tokens:
Type: %s
Modifiers: %s
Raw token data: %s]], 
                type_str,
                vim.inspect(token_modifiers or {}),
                vim.inspect(token_type)  -- Include raw data for debugging
            )
        end
    else
        token_info = "\nLSP Semantic Tokens: Not available"
    end
    
    -- Format output
    local info_str = string.format([[
Syntax Information:
Word: %s
Line: %s
Position: row %d, col %d
Filetype: %s
Syntax group: %s
Treesitter captures:
%s%s
]], 
        cursor_word,
        cursor_line,
        cursor_pos[1],
        cursor_pos[2],
        vim.bo.filetype,
        vim.fn.synIDattr(vim.fn.synID(cursor_pos[1], cursor_pos[2]+1, 1), "name"),
        vim.inspect(captures),
        token_info
    )
    
    vim.fn.setreg('+', info_str)
    print("Syntax information copied to clipboard!")
end)
