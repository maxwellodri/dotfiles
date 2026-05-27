local M = {}

M.extra_find_paths = {}

M.find_files_opts = function()
  local cwd = vim.fn.getcwd()
  local ignore_git_root = { "~/.config/nvim" }
  local should_ignore_git_root = false
  for _, dir in ipairs(ignore_git_root) do
    local expanded_dir = vim.fn.resolve(vim.fn.expand(dir))
    if cwd == expanded_dir then
      should_ignore_git_root = true
      break
    end
  end
  if not should_ignore_git_root then
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    if vim.v.shell_error == 0 then
      cwd = git_root
    end
  end

  local find_opts = {
    hidden = true,
    file_ignore_patterns = { "^%.git/" },
    prompt_prefix = '🔍🥺',
    cwd = cwd,
  }

  local extra = M.extra_find_paths
  if #extra > 0 and vim.fn.executable("fd") == 1 then
    local base = "fd --hidden --type f --exclude .git"
    local cmd = "{ " .. base .. "; " .. table.concat(extra, "; ") .. "; } | sort -u"
    find_opts.find_command = { "bash", "-c", cmd }
  end

  return find_opts
end

require("telescope").setup {
  defaults = {
    preview = {
      hide_on_startup = false,
      treesitter = true
    }
  },
  pickers = {
    find_files = {
      preview = {
        hide_on_startup = true,
        treesitter = false,
      }
    }
  },
  extensions = {
    ["ui-select"] = {
      require("telescope.themes").get_cursor {
        codeactions = { theme = require("telescope.themes").get_cursor,},
      }
    }
  }
}

return M
