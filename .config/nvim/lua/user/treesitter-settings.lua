local status_ok, configs = pcall(require, "nvim-treesitter.configs")
if not status_ok then
    return
end

configs.setup {
    ensure_installed = {"rust", "python", "bash", "toml"},
    sync_install = false,
    ignore_install = { "" },
    highlight = {
        enable=true,
        disable = { "" }, -- list of langs that will be disabled
        additional_vim_regex_highligting = true,
    },
    indent = { enable = true, disable = { "yaml" } },
}
