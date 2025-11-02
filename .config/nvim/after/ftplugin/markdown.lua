vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 2
vim.opt_local.softtabstop = 2
vim.opt_local.expandtab = true
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.opt_local.softtabstop = 2
  end,
})
vim.keymap.set({ "i" }, "<Tab>", "<C-t>", { expr = false, buffer = true, silent = true })
vim.cmd("filetype indent on")
vim.cmd("runtime! indent/markdown.vim")
function SmartNewItemDeeper()
    local ok, lists = pcall(require, 'mkdnflow.lists')
    if not ok then return end

    local cur  = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()

    -- figure out what kind of list we are in
    local list_type = lists.hasListType(line)
    if not list_type then return end          -- not on a list item

    local sw = vim.bo.shiftwidth
    local old_indent = line:match('^%s*') or ''
    local new_indent = old_indent .. (' '):rep(sw)   -- one level deeper

    -- ask mkdnflow for the *marker* only (bullet / number)
    local marker = line:match(lists.patterns[list_type].marker)
    if not marker then return end

    -- build the empty item
    local new_line = new_indent .. marker:gsub('%s+$', '') .. '  '

    -- insert below current line        
    vim.api.nvim_buf_set_lines(0, cur[1], cur[1], false, { new_line })

    -- place cursor after the marker
    vim.api.nvim_win_set_cursor(0, { cur[1] + 1, #new_line })
end

-- insert-mode: <S-CR>  (terminal must send it, e.g. kitty, wezterm, alacritty)
vim.keymap.set('i', '<S-CR>', SmartNewItemDeeper, { buffer = true, desc = 'Mkdn: deeper item below' })

-- normal-mode: O  (shadows native O, but we keep its behaviour)
vim.keymap.set('n', 'O', function()
    SmartNewItemDeeper()
    vim.cmd.startinsert()
end, { buffer = true, desc = 'Mkdn: deeper item above' })
