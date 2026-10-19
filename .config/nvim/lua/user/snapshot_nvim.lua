-- Per-directory nvim session files, consumed by tmux snapshot restore:
-- a restored pane relaunches bare `nvim` at the pane's saved cwd, and this
-- module makes that nvim reopen what was open there last time. Files live
-- next to the tmux snapshots under ~/.local/state/tmux/nvim/<sha256(cwd)>.vim.
-- Only active under $TMUX: plain terminal nvim never saves or restores, and
-- nvim launched with file arguments (qz project windows) is never hijacked.
local store = (vim.env.XDG_STATE_HOME or vim.fn.expand("~") .. "/.local/state") .. "/tmux/nvim"
local session = store .. "/" .. vim.fn.sha256(vim.fn.getcwd()) .. ".vim"

vim.o.sessionoptions = "blank,buffers,curdir,folds,tabpages,winsize"

local group = vim.api.nvim_create_augroup("user-snapshot-nvim", { clear = true })

vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
        if not vim.env.TMUX then
            return
        end
        vim.fn.mkdir(store, "p")
        vim.cmd("mksession! " .. vim.fn.fnameescape(session))
    end,
})

vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
        -- v:this_session empty: not already loaded via -S or another session
        if not vim.env.TMUX or vim.v.this_session ~= "" or vim.fn.argc() > 0 then
            return
        end
        if vim.fn.filereadable(session) == 1 then
            vim.cmd("silent! source " .. vim.fn.fnameescape(session))
        end
    end,
})
