vim.api.nvim_create_augroup('MarkdownSettings', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
    group = 'MarkdownSettings',
    pattern = 'markdown',
    callback = function()
        vim.opt_local.softtabstop = 2
        vim.opt_local.tabstop = 2
        vim.opt_local.shiftwidth = 2
        vim.api.nvim_set_hl(0, 'markdownError', { link = 'Normal' })
    end,
})
require('render-markdown').setup({
    heading = {
        position = 'inline',  -- or 'right'
    },
})

vim.api.nvim_set_hl(0, 'RenderMarkdownH1', { link = 'GruvboxGreenBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH1Bg', { link = 'GruvboxGreenBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH2', { link = 'GruvboxPurpleBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH2Bg', { link = 'GruvboxPurpleBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH3', { link = 'GruvboxAquaBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH3Bg', { link = 'GruvboxAquaBold'})
vim.api.nvim_set_hl(0, 'RenderMarkdownH4', { link = 'GruvboxBlueBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH4Bg', { link = 'GruvboxBlueBold'})

vim.api.nvim_set_hl(0, 'RenderMarkdownH5', { link = 'GruvboxYellowBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH5Bg', { link = 'GruvboxYellowBold'})

vim.api.nvim_set_hl(0, 'RenderMarkdownH6', { link = 'GruvboxOrangeBold' })
vim.api.nvim_set_hl(0, 'RenderMarkdownH6Bg', { link = 'GruvboxOrangeBold'})

vim.keymap.set('n', '<leader>vw', function()
    local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('%s+$', '')
    local notes_path
    if vim.v.shell_error == 0 and vim.fn.filereadable(git_root .. '/notes/index.md') == 1 then
        notes_path = git_root .. '/notes/index.md'
    elseif vim.fn.filereadable(vim.fn.expand('~/Documents/notes/index.md')) == 1 then
        notes_path = vim.fn.expand('~/Documents/notes/index.md')
    else
        print('Notes file not found')
        return
    end
    -- If already editing this file, do nothing
    if vim.fn.expand('%:p') == notes_path then
        return
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(notes_path))
end, { desc = 'Open notes index' })

require('mkdnflow').setup({
    modules = {
        bib = true,
        buffers = true,
        conceal = true,
        cursor = true,
        folds = true,
        foldtext = true,
        links = true,
        lists = true,
        maps = true,
        paths = true,
        tables = true,
        templates = true,
        to_do = true,
        yaml = false,
        cmp = true,
        notebook = true,
    },
    -- OLD: filetypes = {md = true, rmd = true, markdown = true}
    filetypes = { markdown = true, rmd = true },
    create_dirs = true,
    -- RENAMED: perspective → path_resolution
    path_resolution = {
        primary = 'first',       -- was perspective.priority
        fallback = 'current',    -- was perspective.fallback
        root_marker = false,     -- was perspective.root_tell
        sync_cwd = false,        -- was perspective.nvim_wd_heel
        update_on_navigate = false,  -- was perspective.update
    },
    wrap = false,
    bib = {
        default_path = nil,
        find_in_root = true
    },
    silent = false,
    cursor = {
        jump_patterns = nil
    },
    links = {
        style = 'markdown',
        compact = false,            -- RENAMED from name_is_source (inverted: true → false)
        conceal = false,
        search_range = 0,           -- RENAMED from context
        implicit_extension = nil,
        transform_on_follow = false,    -- RENAMED from transform_implicit
        transform_on_create = function(text)  -- RENAMED from transform_explicit
            text = text:gsub(" ", "-")
            text = text:lower()
            return text
        end,
        auto_create = true,         -- RENAMED from create_on_follow_failure
    },
    new_file_template = {
        enabled = true,  -- RENAMED from use_template
        placeholders = {  -- FLATTENED (was nested before/after)
            title = "link_title",
            date = "os_date",
        },
        template = "{{ title }}"
    },
    -- RESTRUCTURED: to_do now uses statuses dict + status_order
    to_do = {
        highlight = false,
        statuses = {
            not_started = { marker = ' ' },
            in_progress = { marker = '-' },
            complete = { marker = 'X' },
        },
        status_order = { 'not_started', 'in_progress', 'complete' },
        status_propagation = {
            up = true,    -- was update_parents = true
            down = true,  -- NEW
        },
        sort = {
            on_status_change = false,
            recursive = false,
            cursor_behavior = { track = true },
        },
    },
    foldtext = {
        object_count = true,
        object_count_icon_set = 'emoji',  -- RENAMED from object_count_icons
        object_count_opts = function()
            return require('mkdnflow').foldtext.default_count_opts()
        end,
        line_count = true,
        line_percentage = true,
        word_count = false,
        title_transformer = function()
            return function(text) return text end
        end,
        fill_chars = {
            left_edge = '⢾⣿⣿',
            right_edge = '⣿⣿⡷',
            item_separator = ' · ',       -- was separator (top-level)
            section_separator = ' ⣹⣿⣏ ',
            left_inside = ' ⣹',
            right_inside = '⣏ ',
            middle = '⣿',
            -- OLD (single-char, uncomment to restore):
            -- left_edge = '⢾',
            -- right_edge = '⡷',
        },
    },
    tables = {
        type = 'pipe',
        trim_whitespace = true,
        format_on_move = true,
        auto_extend_rows = false,
        auto_extend_cols = false,
        style = {
            cell_padding = 1,
            separator_padding = 1,
            outer_pipes = true,
            apply_alignment = true  -- RENAMED from mimic_alignment
        }
    },
    yaml = {
        bib = { override = false }
    },
    mappings = {
        MkdnEnter = {{'n', 'v'}, '<CR>'},
        MkdnFollowLink = {'n', '<CR>'},
        MkdnNewListItemBelowInsert = {'n', 'o'},
        MkdnNewListItemAboveInsert = false,
    }
})

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

vim.keymap.set('n', 'O', function()
    SmartNewItemDeeper()
    vim.cmd.startinsert()
end, { buffer = true, desc = 'Mkdn: deeper item above' })
