-- Project-local Neovim override (sourced via 'exrc' because vim.o.exrc is set in
-- lua/user/init.lua). Only affects this repository.
--
-- Patch <leader>rg so Telescope live_grep also searches hidden (dot)files, while
-- still skipping gitignored files. ripgrep respects .gitignore by default, so
-- adding --hidden is enough to cover "tracked + untracked + hidden, minus
-- gitignored". The --glob '!.git' prunes the .git internals so only real files
-- (tracked or untracked) are searched. Only this mapping is touched; the global
-- telescope vimgrep_arguments are left unchanged.

local ok, builtin = pcall(require, "telescope.builtin")
if not ok then
  return
end

local grep_args = {
  "rg",
  "--color=never",
  "--no-heading",
  "--with-filename",
  "--line-number",
  "--column",
  "--smart-case",
  "--hidden",        -- include dotfiles
  "--glob", "!.git", -- prune git internals (keeps only tracked/untracked files)
}

vim.keymap.set("n", "<leader>rg", function()
  builtin.live_grep({
    prompt_prefix = "🔍🤔",
    vimgrep_arguments = grep_args,
  })
end, { desc = "live_grep (hidden, gitignore-aware)" })
