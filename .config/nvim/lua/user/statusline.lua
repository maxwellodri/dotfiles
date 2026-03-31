local C = require('user.colorscheme').colors

local git_diff_cache = {
  result = nil,
  timestamp = 0,
  cache_ttl = 5,
}

vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShell", "FocusGained" }, {
  callback = function()
    git_diff_cache.timestamp = 0
  end,
})

local function git_diff_stat()
  local now = os.time()
  if git_diff_cache.result and (now - git_diff_cache.timestamp) < git_diff_cache.cache_ttl then
    return git_diff_cache.result
  end

  local git_dir = vim.fn.system("git rev-parse --git-dir 2>/dev/null"):gsub("\n", "")
  if git_dir == "" then
    git_diff_cache.result = nil
    git_diff_cache.timestamp = now
    return nil
  end

  local stat = vim.fn.system("git diff --shortstat 2>/dev/null"):gsub("\n", "")
  local files, lines = 0, 0

  if stat ~= "" then
    local f = stat:match("(%d+) files? changed")
    if f then files = tonumber(f) end
    local ins = stat:match("(%d+) insertion")
    local dels = stat:match("(%d+) deletion")
    lines = (ins and tonumber(ins) or 0) + (dels and tonumber(dels) or 0)
  end

  git_diff_cache.result = { lines = lines, files = files }
  git_diff_cache.timestamp = now
  return git_diff_cache.result
end

local function git_diff_component()
  local diff = git_diff_stat()
  if diff == nil then return "" end
  return string.format(" %d edits across %d files", diff.lines, diff.files)
end

local function git_diff_color()
  local diff = git_diff_stat()
  if diff == nil then return nil end
  if diff.files >= 5 or diff.lines >= 50 then
    return { fg = C.faded_red, gui = "bold" }
  end
  return nil
end

require('lualine').setup {
  options = {
    icons_enabled = true,
    theme = 'gruvbox',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
    disabled_filetypes = {
      statusline = {},
      winbar = {},
    },
    ignore_focus = {},
    always_divide_middle = true,
    globalstatus = false,
    refresh = {
      statusline = 100,
      tabline = 100,
      winbar = 100,
    }
  },
  sections = {
    lualine_a = {
      {
        'mode',
        fmt = function(str)
          return str
        end,
        color = { gui = 'bold' },
      }
    },
    lualine_b = {},
    lualine_c = {
      {
        'filename',
        color = { fg = C.white, bg = C.dark_navy, gui = 'bold' },
        separator = { left = ' ', right = ' ' },
      }
    },
    lualine_x = {
      'diagnostics',
      {
        'lsp_status',
        icon = '',
        symbols = {
          spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'},
          done = '✓',
          separator = ' ',
        },
        fmt = function(str)
          if str and str ~= "" then
            if string.find(str, "✓") then
              return "✓" -- LSP is done
            else
              -- Extract the spinner character from the original string
              local spinner_chars = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'}
              for _, char in ipairs(spinner_chars) do
                if string.find(str, char) then
                  return char
                end
              end
              -- If no spinner character is found, return the first one as fallback
              return "~"
            end
          end
          return ""
        end,
        color = function(section)
          if section and section.value and string.find(section.value, "✓") then
            return { fg = C.bright_green } -- Green for checkmark (fixed the missing # in your code)
          else
            --return { fg = "#D4B95E" } -- Soft amber/gold for spinner
            return { fg = C.bright_green } -- Green for checkmark (fixed the missing # in your code)
          end
        end,
      },
      'encoding',
      'fileformat',
      'filetype'
    },
    lualine_y = {'progress'},
    lualine_z = {
      'location',
      {
        git_diff_component,
        icon = '',
        color = git_diff_color,
      },
      'branch'
    }
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {
      'diagnostics',
      {
        'lsp_status',
        icon = '',
        symbols = {
          spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'},
          done = '✓',
          separator = ' ',
        },
        fmt = function(str)
          if str and str ~= "" then
            if string.find(str, "✓") then
              return "✓"
            else
              local spinner_chars = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'}
              for _, char in ipairs(spinner_chars) do
                if string.find(str, char) then
                  return char
                end
              end
              return "~"
            end
          end
          return ""
        end,
        color = function(section)
          if section and section.value and string.find(section.value, "✓") then
            return { fg = C.bright_green }
          else
            return { fg = C.bright_green }
          end
        end,
      },
      'encoding',
      'fileformat',
      'filetype'
    },
    lualine_y = {'progress'},
    lualine_z = {
      'location',
      {
        git_diff_component,
        icon = '',
        color = git_diff_color,
      },
      'branch'
    }
  },
  -- Configuring winbar (equivalent to your components_top)
  winbar = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {},
    lualine_x = {},
    lualine_y = {},
    lualine_z = {}
  },
  inactive_winbar = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {},
    lualine_x = {},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {},
  extensions = {}
}
