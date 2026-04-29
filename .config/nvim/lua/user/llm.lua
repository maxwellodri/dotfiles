local M = {}

local function review_plan()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 then return end

  local plans_dir = git_root .. '/.opencode/plans'
  if vim.fn.isdirectory(plans_dir) ~= 1 then return end

  local sorted = vim.fn.glob(plans_dir .. '/*', false, true)
  if #sorted == 0 then return end
  table.sort(sorted, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)

  local display_names = {}
  for _, f in ipairs(sorted) do
    table.insert(display_names, vim.fn.fnamemodify(f, ':t'))
  end

  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Review Plan',
      finder = require('telescope.finders').new_table({
        results = display_names,
        entry_maker = function(name)
          return {
            value = name,
            display = name,
            ordinal = name,
            path = plans_dir .. '/' .. name,
          }
        end,
      }),
      sorter = require('telescope.config').values.generic_sorter({}),
      attach_mappings = function(_, map)
        map('i', '<CR>', function(prompt_bufnr)
          local entry = require('telescope.actions.state').get_selected_entry()
          require('telescope.actions').close(prompt_bufnr)
          if not entry then return end
          M.render_plan(entry.path)
        end)
        return true
      end,
    })
    :find()
end

function M.render_plan(filepath)
  local lines = vim.fn.readfile(filepath)
  if not lines or #lines == 0 then return end

  local tasks_start = nil
  local progress_start = nil
  for i, line in ipairs(lines) do
    if line:match('^# Tasks') and not tasks_start then
      tasks_start = i
    elseif line:match('^# Progress') and not progress_start then
      progress_start = i
    end
  end
  if not tasks_start then return end

  local context_lines = {}
  for i = 2, tasks_start - 1 do
    table.insert(context_lines, lines[i])
  end

  local json_lines = {}
  local json_end = progress_start and (progress_start - 1) or #lines
  for i = tasks_start + 1, json_end do
    table.insert(json_lines, lines[i])
  end

  local json_str = table.concat(json_lines, '\n')
  local tasks = vim.json.decode(json_str) or {}

  local filename = vim.fn.fnamemodify(filepath, ':t')
  local buf_lines = {}

  table.insert(buf_lines, '# Plan: ' .. filename)
  for _, line in ipairs(context_lines) do
    table.insert(buf_lines, line)
  end
  table.insert(buf_lines, '')
  table.insert(buf_lines, '---')
  table.insert(buf_lines, '')
  table.insert(buf_lines, '## Tasks')
  table.insert(buf_lines, '')
  for _, task in ipairs(tasks) do
    local label = task.task or 'Untitled'
    if task.completed then
      label = label .. '  [Completed]'
    end
    table.insert(buf_lines, label)
    if task.steps then
      for _, step in ipairs(task.steps) do
        table.insert(buf_lines, '- ' .. step)
      end
    end
    table.insert(buf_lines, '')
  end

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
  vim.api.nvim_buf_set_name(buf, 'Plan Review: ' .. filename)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.cmd('split')
  vim.api.nvim_win_set_buf(0, buf)
end

function M.setup()
  vim.api.nvim_create_user_command('Review', review_plan, {})
end

return M
