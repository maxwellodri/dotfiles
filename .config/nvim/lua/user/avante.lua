-- TODO: disable tools except: read file, write_to_file, str_replace, glob, bash, create_file
require('avante').setup({
  provider = "zai",
  providers = {
    ["zai"] = {
      __inherited_from = "openai",
      endpoint = "https://api.z.ai/api/coding/paas/v4",
      model = "glm-5.1",
      api_key_name = "cmd:pass zai_nvim_api_key",
    },
  },
  disabled_tools = {
    "git_diff", "git_commit",
    "copy_path", "move_path", "delete_path",
    "create_dir",
    "grep", "ls",
    "insert",
    "run_python",
    "read_todos", "write_todos",
    "get_diagnostics",
    "read_file_toplevel_symbols", "read_definitions",
    "web_search",
  },
  mode = "agentic",
  selection = {
    enabled = false,
    hint_display = false,
  },
  behaviour = {
    auto_apply_diff_after_generation = false,
    auto_suggestions = false,
    auto_set_highlight_group = true,
    auto_set_keymaps = true,
    support_paste_from_clipboard = true,
    minimize_diff = true,
    enable_token_counting = true,
    auto_add_current_file = true,
    auto_approve_tool_permissions = true,
  },
  windows = {
    position = "right",
    width = 40,
    sidebar_header = {
      enabled = true,
      align = "center",
      rounded = true,
    },
    input = {
      prefix = "> ",
      height = 8,
    },
    edit = {
      border = "rounded",
      start_insert = true,
    },
    ask = {
      floating = false,
      start_insert = true,
      border = "rounded",
      focus_on_apply = "ours",
    },
  },
  diff = {
    autojump = true,
  },
  highlights = {
    diff = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  mappings = {
    diff = {
      ours = "co",
      theirs = "ct",
      all_theirs = "ca",
      both = "cb",
      cursor = "cc",
      next = "]x",
      prev = "[x",
    },
    suggestion = {
      accept = "<M-l>",
      next = "<M-]>",
      prev = "<M-[>",
      dismiss = "<C-]>",
    },
    jump = {
      next = "]]",
      prev = "[[",
    },
    submit = {
      normal = "<CR>",
      insert = "<C-s>",
    },
    cancel = {
      normal = { "<C-c>", "<Esc>", "q" },
      insert = { "<C-c>" },
    },
    sidebar = {
      apply_all = "A",
      apply_cursor = "a",
      retry_user_request = "r",
      edit_user_request = "e",
      switch_windows = "<Tab>",
      reverse_switch_windows = "<S-Tab>",
      remove_file = "d",
      add_file = "@",
      close = { "<Esc>", "q" },
    },
  },
})
