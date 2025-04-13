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
        color = { fg = 'white', bg = '#223355', gui = 'bold' },
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
              return spinner_chars[1]
            end
          end
          return ""
        end,
        color = function(section)
          if section and section.value and string.find(section.value, "✓") then
            return { fg = "#00FF00" } -- Green for checkmark (fixed the missing # in your code)
          else
            --return { fg = "#D4B95E" } -- Soft amber/gold for spinner
            return { fg = "#00FF00" } -- Green for checkmark (fixed the missing # in your code)
          end
        end,
        ignore_lsp = {'null-ls'},
      },
      'encoding',
      'fileformat',
      'filetype'
    },
    lualine_y = {'progress'},
    lualine_z = {'location', 'branch'}
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {'location'},
    lualine_y = {},
    lualine_z = {}
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
