-- minimal runtime for the WorktreeReview headless spec: only the repo's nvim
-- lua tree, no user config / plugins.
local src = debug.getinfo(1, 'S').source:sub(2)
local repo = vim.fs.normalize((src:gsub('[^/]+$', '')) .. '../')
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;' .. package.path
return repo
