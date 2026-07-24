local opts = { noremap = true, silent = true }
vim.keymap.set({'n', 'i'}, "<C-_>", function() vim.cmd("resize -1") end, opts)
vim.keymap.set({'n', 'i'}, "<C-+>", function() vim.cmd("resize +1") end, opts)
vim.api.nvim_create_autocmd("BufEnter", {
    pattern = "godot.log",
    callback = function()
        vim.api.nvim_buf_set_keymap(0, "n", "<leader><leader>g", ":lua SyncGodotLog()<CR>:edit!<CR>", { noremap = true, silent = true })
    end
})

function SyncGodotLog()
    local script_path = vim.fn.expand("$bin/poll_log.sh")
    local scratch_file = vim.fn.expand("~/.cache/godot.log.scratch")

    vim.fn.system(script_path)

    if vim.fn.getfsize(scratch_file) > 0 then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("G$:w<CR>", true, false, true), "n", false)

        vim.schedule(function ()
            vim.cmd("read " .. scratch_file)
            vim.cmd("write")
        end)
    else
        print("None")
    end
end

local telescope_settings = require("user.telescope-settings")

vim.keymap.set('n', '<leader>fo', function()
    require('telescope.builtin').find_files(telescope_settings.find_files_opts())
end)
vim.keymap.set('n', '<leader>fg', function()
    require('telescope.builtin').find_files(telescope_settings.git_dirty_files_opts())
end)
vim.keymap.set('n', '<leader>ff', function()
    vim.cmd('tabnew')
    require('telescope.builtin').find_files(telescope_settings.find_files_opts())
end)
vim.keymap.set('n', '<leader>fb', require('telescope.builtin').buffers, { desc = 'Telescope buffers' })
