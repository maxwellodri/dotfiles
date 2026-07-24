vim.lsp.config('rust_analyzer', {
  settings = {
    ['rust-analyzer'] = {
      lru = { capacity = 4096 },
      procMacro = {
        ignored = {
          serde_derive = { "Serialize", "Deserialize" },
          bevy_ecs_macros = { "Component", "Bundle", "Event", "Resource" },
          -- bevy_reflect_derive = { "Reflect", "FromReflect", "TypePath" },
        },
      },
    },
  },
})

local ts = require("user.telescope-settings")
ts.extra_find_paths = {
  "fd --type f -e wgsl . assets/",
  "fd --hidden --type f --no-ignore-vcs . notes/",
  "fd --hidden --type f --no-ignore-vcs . .opencode/ --exclude bun.lock --exclude node_modules --exclude package.json --exclude .gitignore",
}

-- GitSplit: never diff anything under notes/
vim.g.GitSplitIgnore = { "./notes/" }
