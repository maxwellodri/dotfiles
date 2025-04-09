local fonts = {"FiraCode Nerd Font Mono,Noto Color Emoji"}

vim.g.gui_font_default_size = 9
vim.g.gui_font_size = vim.g.gui_font_default_size
vim.g.gui_font_face = fonts[math.random(1, #fonts)] --# symbol is len operator


RefreshGuiFont = function()
  vim.opt.guifont = string.format("%s:h%s",vim.g.gui_font_face, vim.g.gui_font_size)
end

RandomiseGuiFont = function()
  vim.opt.guifont = string.format("%s:h%s",fonts[math.random(1, #fonts)], vim.g.gui_font_size)
end

ResizeGuiFont = function(delta)
  vim.g.gui_font_size = vim.g.gui_font_size + delta
  RefreshGuiFont()
end

ResetGuiFont = function ()
  vim.g.gui_font_size = vim.g.gui_font_default_size
  RefreshGuiFont()
end

-- Call function on startup to set default value
ResetGuiFont()

-- Keymaps
local opts = { noremap = true, silent = true }
vim.keymap.set('n', "<leader>fU", function() ResizeGuiFont(1)  end, opts)
vim.keymap.set('n', "<leader>fu", function() ResizeGuiFont(-1) end, opts)
