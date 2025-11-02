vim.api.nvim_create_augroup('FixPolyglot', { clear = true })
vim.api.nvim_create_autocmd('FileType', {
    group = 'FixPolyglot',
    pattern = 'markdown',
    callback = function()
        vim.opt_local.softtabstop = 2
        vim.opt_local.tabstop = 4
        vim.opt_local.shiftwidth = 4
    end,
})
require('render-markdown').setup({})

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
        links = true,
        lists = true,
        maps = true,
        paths = true,
        tables = true,
        cmp = true,
    },
    filetypes = {md = true, rmd = true, markdown = true},
    create_dirs = true,
    perspective = {
        priority = 'first',
        fallback = 'current',
        root_tell = false,
        nvim_wd_heel = false,
        update = false
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
        name_is_source = true,
        conceal = false,
        context = 0,
        implicit_extension = nil,
        transform_implicit = false,
        transform_explicit = function(text)
            text = text:gsub(" ", "-")
            text = text:lower()
            --text = os.date('%Y-%m-%d_')..text
            return(text)
        end,
        create_on_follow_failure = true
    },
    new_file_template = {
        use_template = true,
        placeholders = {
            before = {
                title = "link_title",
                date = "os_date"
            },
            after = {}
        },
        template = "{{ title }}"
    },
    to_do = {
        symbols = {' ', '-', 'X'},
        update_parents = true,
        not_started = ' ',
        in_progress = '-',
        complete = 'X'
    },
    foldtext = {
        object_count = true,
        object_count_icons = 'emoji',
        object_count_opts = function()
            return require('mkdnflow').foldtext.default_count_opts()
        end,
        line_count = true,
        line_percentage = true,
        word_count = false,
        title_transformer = nil,
        separator = ' · ',
        fill_chars = {
            left_edge = '⢾',
            right_edge = '⡷',
            left_inside = ' ⣹',
            right_inside = '⣏ ',
            middle = '⣿',
        },
    },
    tables = {
        trim_whitespace = true,
        format_on_move = true,
        auto_extend_rows = false,
        auto_extend_cols = false,
        style = {
            cell_padding = 1,
            separator_padding = 1,
            outer_pipes = true,
            mimic_alignment = true
        }
    },
    yaml = {
        bib = { override = false }
    },
     mappings  = {
        MkdnEnter = {{'n', 'v'}, '<CR>'},
    --     MkdnTab = {'i', '<Tab>'},
    --     MkdnSTab = {'i', '<S-Tab>'},
    --     MkdnNextLink = {'n', '<Tab>'},
    --     MkdnPrevLink = {'n', '<S-Tab>'},
    --     MkdnNextHeading = {'n', ']]'},
    --     MkdnPrevHeading = {'n', '[['},
    --     MkdnGoBack = {'n', '<BS>'},
    --     MkdnGoForward = {'n', '<Del>'},
    --     MkdnCreateLink = false, -- see MkdnEnter
    --     MkdnCreateLinkFromClipboard = false,
           MkdnFollowLink = {'n', '<CR>'}, -- see MkdnEnter
    --     MkdnDestroyLink = {'n', '<M-CR>'},
    --     MkdnTagSpan = {'v', '<M-CR>'},
    --     MkdnMoveSource = {'n', '<F2>'},
    --     MkdnYankAnchorLink = {'n', 'yaa'},
    --     MkdnYankFileAnchorLink = {'n', 'yfa'},
    --     MkdnIncreaseHeading = {'n', '+'},
    --     MkdnDecreaseHeading = {'n', '-'},
    --     MkdnToggleToDo = {{'n', 'v'}, '<C-Space>'},
           MkdnNewListItemBelowInsert = {'n', 'o'},
        MkdnNewListItemAboveInsert = false, -- {'n', 'O'},
           --MkdnExtendList = {'i', '<CR>'},
    --     MkdnUpdateNumbering = {'n', '<leader>nn'},
    --     MkdnTableNextCell = {'i', '<Tab>'},
    --     MkdnTablePrevCell = {'i', '<S-Tab>'},
    --     MkdnTableNextRow = false,
    --     MkdnTablePrevRow = {'i', '<M-CR>'},
    --     MkdnTableNewRowBelow = {'n', '<leader>ir'},
    --     MkdnTableNewRowAbove = {'n', '<leader>iR'},
    --     MkdnTableNewColAfter = {'n', '<leader>ic'},
    --     MkdnTableNewColBefore = {'n', '<leader>iC'},
    --     MkdnFoldSection = {'n', '<leader>f'},
    --     MkdnUnfoldSection = {'n', '<leader>F'}
    }
})

