local M = {}
M.settings = {
    ui = {
        -- Whether to automatically check for new versions when opening the :Mason window.
        check_outdated_packages_on_open = true,

        -- The border to use for the UI window. Accepts same border values as |nvim_open_win()|.
        border = "none",

        icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
        },

        keymaps = {
            -- Keymap to expand a package
            toggle_package_expand = "<CR>",
            -- Keymap to install the package under the current cursor position
            install_package = "i",
            -- Keymap to reinstall/update the package under the current cursor position
            update_package = "u",
            -- Keymap to check for new version for the package under the current cursor position
            check_package_version = "c",
            -- Keymap to update all installed packages
            update_all_packages = "U",
            -- Keymap to check which installed packages are outdated
            check_outdated_packages = "C",
            -- Keymap to uninstall a package
            uninstall_package = "X",
            -- Keymap to cancel a package installation
            cancel_installation = "<C-c>",
            -- Keymap to apply language filter
            apply_language_filter = "<C-f>",
        },
    },

    -- The directory in which to install packages.
    install_root_dir = vim.fn.stdpath("data").."mason",

    pip = {
        -- These args will be added to `pip install` calls. Note that setting extra args might impact intended behavior
        -- and is not recommended.
        --
        -- Example: { "--proxy", "https://proxyserver" }
        install_args = {},
    },

    -- Controls to which degree logs are written to the log file. It's useful to set this to vim.log.levels.DEBUG when
    -- debugging issues with package installations.
    log_level = vim.log.levels.DEBUG,

    -- Limit for the maximum amount of packages to be installed at the same time. Once this limit is reached, any further
    -- packages that are requested to be installed will be put in a queue.
    max_concurrent_installers = 4,

    github = {
        -- The template URL to use when downloading assets from GitHub.
        -- The placeholders are the following (in order):
        -- 1. The repository (e.g. "rust-lang/rust-analyzer")
        -- 2. The release version (e.g. "v0.3.0")
        -- 3. The asset name (e.g. "rust-analyzer-v0.3.0-x86_64-unknown-linux-gnu.tar.gz")
        download_url_template = "https://github.com/%s/releases/download/%s/%s",
    },
}

M.ensure_installed_servers = {"vimls", "pyright", "bashls", "rust_analyzer" }
M.automatic_enable_exclude_servers = { "rust_analyzer" }
M.get_auto_enable_servers = function ()
    -- Diff  of ensure_installed_servers - automatic_enable_exclude_servers
    local autoenableservers = {}
    for _, server in ipairs(M.ensure_installed_servers) do
        local should_include = true
        for _, excluded in ipairs(M.automatic_enable_exclude_servers) do
            if server == excluded then
                should_include = false
                break
            end
        end
        if should_include then
            table.insert(autoenableservers, server)
        end
    end
    return autoenableservers
end
M.setup = function()
    require("mason").setup(M.settings)
    require("mason-lspconfig").setup({
        ensure_installed =  M.ensure_installed_servers,
        automatic_enable = { exclude =  M.automatic_enable_exclude_servers },
    })

end
return M
