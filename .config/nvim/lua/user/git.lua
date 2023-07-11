function GitDiffSwitch()
  local output = vim.fn.systemlist('git status --porcelain')  -- Get the current Git status
  local current_file = vim.fn.expand('%')  -- Get the current file name
  local modified = false
  local staged = false

  -- Check if the current file has been modified or staged
  for _, line in ipairs(output) do
    if line:sub(1, 2) == 'M ' and line:sub(3) == current_file then
      modified = true
    elseif line:sub(1, 2) == 'M ' and line:sub(3) ~= current_file then
      -- Another file has been modified, so we can't do the switch
      print('Error: Another file has been modified')
      return
    elseif line:sub(1, 2) == 'A ' or line:sub(1, 2) == 'M ' then
      staged = true
    end
  end

  -- If the current file has not been modified, we can't do the switch
  if not modified then
    print('Error: Current file has not been modified')
    return
  end

  -- Get the Git hash of the previous commit
  local git_hash = vim.fn.system('git rev-parse HEAD^'):gsub('%s+', '')

  -- Load the contents of the file from the previous commit
  local previous_contents = vim.fn.system('git show ' .. git_hash .. ':' .. current_file)

  -- Load the contents of the current file
  local current_contents = vim.fn.join(vim.fn.readfile(current_file), '\n')

  -- Switch the buffer to the previous commit's version of the file
  vim.fn.bufload(vim.fn.bufnr('%'), { bufnr = vim.fn.bufnr(), force = true })
  vim.fn.bufsetname(current_file .. ' (previous)')

  -- Write the current file's contents to a temporary file
  local temp_file = os.tmpname()
  local file = io.open(temp_file, 'w')
  file:write(current_contents)
  file:close()

  -- Load the contents of the current file from the temporary file
  vim.cmd('edit ' .. temp_file)
  vim.fn.bufsetname(current_file)

  -- Remove the temporary file
  os.remove(temp_file)

  -- If the file was staged, stage it again
  if staged then
    vim.fn.system('git add ' .. current_file)
  end
end

function GitSwitch()
  -- get the name of the current file
  local current_file = vim.fn.expand('%:p')

  -- check if the file exists in git repository
  local git_root = vim.fn.system('git rev-parse --show-toplevel'):gsub('\n', '')
  local git_file = current_file:gsub(git_root, '')
  if git_file == current_file then
    print('Error: Current file is not in a Git repository')
    return
  end

  -- get the SHA of the last commit that modified the file
  local last_commit_sha = vim.fn.system('git log --pretty=format:"%h" -n 1 -- ' .. git_file):gsub('\n', '')
  if last_commit_sha == '' then
    print('Error: File does not exist in the last commit')
    return
  end

  -- get the diff status of the file
  local diff_status = vim.fn.system('git diff --name-status ' .. current_file):gsub('\n', '')
  if diff_status == '' then
    print('Error: Current file has not been modified')
    return
  end

  -- get the name of the staged file
  local staged_file = vim.fn.system('git diff --name-only --cached'):gsub('\n', '')
  if staged_file == '' then
    staged_file = nil
  end

  -- switch to the previous commit
  vim.fn.execute('e ' .. git_root .. '/' .. git_file .. '@' .. last_commit_sha)

  -- switch to the staged file if it exists and is different from the current file
  if staged_file ~= nil and vim.fn.bufname() ~= staged_file then
    vim.fn.execute('e ' .. git_root .. '/' .. staged_file)
  end
end

function GitPreviousCommitToggle()
  local bufnr = vim.fn.bufnr()  -- get the buffer number of the current buffer
  local filepath = vim.fn.expand('%:p')  -- get the absolute path of the current file

  -- check if the file exists in the git repository
  local cmd = string.format('git ls-files --error-unmatch %s > /dev/null 2>&1', filepath)
  local status = os.execute(cmd)
  if status ~= 0 then
    print('Error: file does not exist in git repository')
    return
  end

  -- check if the current file is in a clean state
  cmd = string.format('git diff --quiet --exit-code %s > /dev/null 2>&1', filepath)
  status = os.execute(cmd)
  if status == 0 then
    print('Error: current file is unchanged')
    return
  end

  -- get the SHA-1 hash of the previous commit of the current file
  cmd = string.format('git rev-list --max-count=1 HEAD -- %s', filepath)
  local handle = io.popen(cmd)
  local output = handle:read('*a')
  handle:close()
  local prev_commit = output:gsub('%s', '')

  -- switch to the previous commit or the current file
  if vim.bo[bufnr].modified then
    OpenFileFromLastCommit()
  else
    cmd = string.format('git show %s:%s', prev_commit, filepath)
    vim.cmd(string.format('edit! %s', cmd))
  end
end

function OpenFileFromLastCommit()
  -- check if file has changes
  if vim.fn.system("git show HEAD~1 " .. vim.fn.expand("%")) == 1 then
    print("File has unsaved changes. Please save or discard changes before opening the file from the last commit.")
    return
  end
  -- get the commit hash for the last version of the file
  local commit_hash = vim.fn.system("git rev-list -n 1 HEAD -- " .. vim.fn.expand("%"))
  -- open the file from the commit
  vim.cmd(":edit " .. commit_hash .. ":" .. vim.fn.expand("%"))
end

-- vim.api.nvim_set_keymap('n', '<C-g>', ':w<CR>:lua GitPreviousCommitToggle()<CR>', { noremap = true, silent = true })
