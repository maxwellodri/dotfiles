vim.opt.title = true

local request = 0

-- Git runs in the background: a blocking system call makes Nvim hide the cursor.
local function refresh_title()
  request = request + 1
  local current = request
  local opts = { text = true, stderr = true }
  vim.system({ "git", "rev-parse", "--show-toplevel" }, opts, function(out)
    vim.schedule(function()
      if current ~= request then
        return
      end
      local name
      if out.code == 0 and out.stdout ~= "" then
        name = vim.fn.fnamemodify((out.stdout:gsub("\n", "")), ":t")
      else
        name = vim.fn.expand("%:t")
      end
      vim.opt.titlestring = "vim " .. name
    end)
  end)
end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
  callback = refresh_title,
})
