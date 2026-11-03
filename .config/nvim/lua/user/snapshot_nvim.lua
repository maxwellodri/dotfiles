-- Per-directory nvim session files, consumed by tmux snapshot restore:
-- a restored pane relaunches bare `nvim` at the pane's saved cwd, and this
-- module makes that nvim reopen what was open there last time. Files live
-- next to the tmux snapshots under ~/.local/state/tmux/nvim/<sha256(cwd)>.vim.
-- Only active under $TMUX: plain terminal nvim never saves or restores, and
-- nvim launched with file arguments (qz project windows) is never hijacked.
--
-- Saving is event-driven, not quit-driven: reboots and tmux kill-server
-- never run VimLeavePre, so the file must already be current. Buffer/
-- window/tab/cwd changes schedule a debounced mksession; VimLeavePre still
-- fires a final save for clean exits.
local store = (vim.env.XDG_STATE_HOME or vim.fn.expand("~") .. "/.local/state") .. "/tmux/nvim"
local session = store .. "/" .. vim.fn.sha256(vim.fn.getcwd()) .. ".vim"

vim.o.sessionoptions = "blank,buffers,curdir,folds,tabpages,winsize"

local group = vim.api.nvim_create_augroup("user-snapshot-nvim", { clear = true })

local function save()
	vim.fn.mkdir(store, "p")
	vim.cmd("silent mksession! " .. vim.fn.fnameescape(session))
end

local pending = false
local function schedule_save()
	if pending then
		return
	end
	pending = true
	vim.defer_fn(function()
		pending = false
		-- this_session is intentionally not checked here: sourcing a
		-- session sets it, and post-restore edits must still autosave
		if vim.fn.argc() > 0 or not vim.env.TMUX then
			return
		end
		save()
	end, 500)
end

vim.api.nvim_create_autocmd({
	"BufAdd",
	"BufDelete",
	"BufEnter",
	"BufWritePost",
	"FileWritePost",
	"WinNew",
	"WinClosed",
	"TabNew",
	"TabClosed",
	"DirChanged",
}, {
	group = group,
	callback = schedule_save,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	callback = function()
		if not vim.env.TMUX or vim.fn.argc() > 0 then
			return
		end
		save()
	end,
})

vim.api.nvim_create_autocmd("VimEnter", {
	group = group,
	callback = function()
		-- v:this_session empty: not already loaded via -S or another session
		if not vim.env.TMUX or vim.v.this_session ~= "" or vim.fn.argc() > 0 then
			return
		end
		if vim.fn.filereadable(session) == 1 then
			vim.cmd("silent! source " .. vim.fn.fnameescape(session))
		end
	end,
})
