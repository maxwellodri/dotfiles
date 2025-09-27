local opts = { noremap = true, silent = true }
vim.keymap.set({'n', 'i'}, "<C-_>", function() vim.cmd("resize -1") end, opts)
vim.keymap.set({'n', 'i'}, "<C-+>", function() vim.cmd("resize +1") end, opts)
vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "godot.log",
    callback = function()
        -- Map C-<leader> to run the rsync command when godot.log is open
        vim.api.nvim_buf_set_keymap(0, "n", "<leader><leader>g", ":lua SyncGodotLog()<CR>:edit!<CR>", { noremap = true, silent = true })
    end
})

function SyncGodotLog()
    local script_path = vim.fn.expand("$bin/poll_log.sh")
    local scratch_file = vim.fn.expand("~/.cache/godot.log.scratch")

    -- Run the shell script
    vim.fn.system(script_path)

    -- Check if the scratch file is not empty
    if vim.fn.getfsize(scratch_file) > 0 then
        -- Move to the end of the file and read the content of the scratch file
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("G$:w<CR>", true, false, true), "n", false)

        -- Schedule the read command after moving to the end of the file
        vim.schedule(function ()
            vim.cmd("read " .. scratch_file)
            vim.cmd("write")
        end)
    else
        print("None")
    end
end
local function find_files_from_git_root()
    local cwd = vim.fn.getcwd()
    if vim.fn.FugitiveGitDir() ~= '' then
        cwd = vim.fn.fnamemodify(vim.fn.FugitiveGitDir(), ':h')
    end
    require('telescope.builtin').find_files({
        find_command = {'rg', '--ignore', '--hidden', '--files'},
        prompt_prefix = '🔍🥺',
        cwd = cwd
    })
end
vim.keymap.set('n', '<leader>fo', find_files_from_git_root)
