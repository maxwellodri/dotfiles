set runtimepath^=~/.vim runtimepath+=~/.vim/after
runtime! expand('$HOME') + '/.config/nvim/plugin'
let &packpath=&runtimepath
" Autoinstall VimPlug
    let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
    if empty(glob(data_dir . '/autoload/plug.vim'))
                   silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
                   autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
    endif

" Plugins
    call plug#begin(data_dir . '/plugins')
    "TODO
    "Plug 'jistr/vim-nerdtree-tabs'
    "Plug 'tpope/vim-commentary'
    "Plug 'vim-airline/vim-airline'
    "Plug 'vim-airline/vim-airline-themes'
    "Plug 'airblade/vim-gitgutter'
    "Plug 'vim-scripts/grep.vim'
    "Plug 'vim-scripts/CSApprox'
    "Plug 'Raimondi/delimitMate'
    "Plug 'majutsushi/tagbar'
    "Plug 'Yggdroot/indentLine'
    "Plug 'editor-bootstrap/vim-bootstrap-updater'
    "Plug 'tpope/vim-rhubarb' " required by fugitive to :Gbrowse
    "Plug 'preservim/tagbar'        "requires ctags  to be installed
    " ==============
    " Miscellaneous
    " ==============
    Plug 'tpope/vim-sensible'
    Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
    Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
    Plug 'nvim-lua/plenary.nvim' "library of functions, used by other modules
    Plug 'kyazdani42/nvim-web-devicons' "library of icons
    " =================
    " Language Support
    " =================
    function! TSCustomInstall(info) 
        " info is a dictionary with 3 fields
        " - name:   name of the plugin
        " - status: 'installed', 'updated', or 'unchanged'
        " - force:  set on PlugInstall! or PlugUpdate!
        if a:info.status == 'installed'
            TSInstall rust python toml
        endif
        if a:info.status == 'updated'
            TSUpdate
        endif
    endfunction
    Plug 'nvim-treesitter/nvim-treesitter', {'do': function('TSCustomInstall') }
    Plug 'sheerun/vim-polyglot' "AIO bundle
    Plug 'rust-lang/rust.vim'
    Plug 'tikhomirov/vim-glsl'
    Plug 'JuliaEditorSupport/julia-vim'
    Plug 'kevinoid/vim-jsonc'
    Plug 'lervag/vimtex'
    Plug 'ron-rs/ron.vim'
    Plug 'leafgarland/typescript-vim'
    Plug 'raimon49/requirements.txt.vim' "requirement.txt support
    Plug 'simrat39/rust-tools.nvim'
    " =================
    " LSP / cmp / LuaSnip
    " =================
    Plug 'neovim/nvim-lspconfig' 
    Plug 'hrsh7th/nvim-cmp'
    Plug 'hrsh7th/cmp-buffer'
    Plug 'hrsh7th/cmp-path'
    Plug 'hrsh7th/cmp-cmdline'
    Plug 'hrsh7th/cmp-nvim-lsp'
    Plug 'williamboman/nvim-lsp-installer'
    Plug 'saadparwaiz1/cmp_luasnip' 
    Plug 'hrsh7th/cmp-nvim-lua'
    Plug 'L3MON4D3/LuaSnip' "snippet engine
    Plug 'rafamadriz/friendly-snippets' "a bunch of snippets to use
    " Plug 'filipdutescu/renamer.nvim', { 'branch': 'master' }
    Plug 'mfussenegger/nvim-dap'
    "" ====
    "" Git
    "" ====
    Plug 'tpope/vim-fugitive'
    " ======
    " Search / File Finding
    " ======
    Plug 'PeterRincker/vim-searchlight'
    Plug 'preservim/nerdtree'
    Plug 'pseewald/vim-anyfold'
    Plug 'arecarn/vim-fold-cycle'
    Plug 'nvim-telescope/telescope.nvim'
    Plug 'kyazdani42/nvim-tree.lua' "library of functions, used by other modules
    " ==============
    " Visual / Appearance
    " ==============
    Plug 'kien/rainbow_parentheses.vim' 
    Plug 'machakann/vim-highlightedyank' "highlight on yank
    Plug 'vim-airline/vim-airline'
    Plug 'vim-airline/vim-airline-themes'
    " ===============
    " Color Schemes 
    " ===============
    Plug 'tomasiser/vim-code-dark'
    Plug 'tomasr/molokai'
    Plug 'morhetz/gruvbox'
    Plug 'ghifarit53/tokyonight-vim' 
    Plug 'ajmwagar/vim-deus' 
    Plug 'sainnhe/edge'
    Plug 'jnurmine/Zenburn'
    "Plug 'pineapplegiant/spaceduck'
    " ===============
    " NoteTaking & Vim Wiki
    " ===============
    Plug 'vimwiki/vimwiki'
    "
    call plug#end()
    source ~/.vimrc "vimrc is effectively a plugin lmao
    nnoremap <silent><leader>V :w<CR>:so $MYVIMRC<CR>:PlugInstall<CR>
" Rainbow Parentheses
   let g:rbpt_colorpairs = [
    \ ['brown',       'RoyalBlue3'],
    \ ['Darkblue',    'SeaGreen3'],
    \ ['darkgray',    'DarkOrchid3'],
    \ ['darkgreen',   'firebrick3'],
    \ ['darkcyan',    'RoyalBlue3'],
    \ ['darkred',     'SeaGreen3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['brown',       'firebrick3'],
    \ ['gray',        'RoyalBlue3'],
    \ ['black',       'SeaGreen3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['Darkblue',    'firebrick3'],
    \ ['darkgreen',   'RoyalBlue3'],
    \ ['darkcyan',    'SeaGreen3'],
    \ ['darkred',     'DarkOrchid3'],
    \ ['red',         'firebrick3'],
    \ ]
    au VimEnter * RainbowParenthesesToggle
    au Syntax * RainbowParenthesesLoadRound
    au Syntax * RainbowParenthesesLoadSquare
    au Syntax * RainbowParenthesesLoadBraces

" Colorscheme
    let g:gruvbox_italic=1
    let g:gruvbox_bold=1
    let g:gruvbox_underline=1
    let g:gruvbox_termcolors=256
    let g:gruvbox_contrast_dark='medium'
    let g:gruvbox_contrast_light='hard'
    colorscheme gruvbox

" Statusline
    "" TODO
    set statusline=
    set cmdheight=2 " space below the statusline
    "set statusline+=%{FugitiveStatusline()}
    ""set laststatus=2
    "set statusline+=%#function#\ %l "color theming
    "set statusline+=%f "add file name to statusline %t
    ""set laststatus=2
    ""set statusline=
    "set statusline+=%1*\ %f\ %*
    "set statusline+=%= "LHS/RHS  divider
    "set statusline+=%2*\ %{FugitiveStatusline()}
    "set statusline+=%2*\ %l/%L "Line current/Linemax
    "set statusline+=%2*\ %m "is modified
    "set statusline+=%2*\ %r "is readonly
    "set statusline+=%3*\ ‹‹
    "set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
    "set statusline+=%3*\ ::
    "set statusline+=%3*\ %n
    "set statusline+=%3*\ ››\ %*
    set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\ 
    set statusline+=%{FugitiveStatusline()}
" Airline 
    let g:airline#extensions#tabline#enabled = 1
    let g:airline#extensions#tabline#left_sep = ''
    let g:airline#extensions#tabline#left_alt_sep = ''
    let g:airline#extensions#tabline#right_sep = ''
    let g:airline#extensions#tabline#right_alt_sep = ''
    
    " enable powerline fonts
    let g:airline_powerline_fonts = 1
    let g:airline_left_sep = ''
    let g:airline_right_sep = ''
    
    " Switch to your current theme
    let g:airline_theme = 'gruvbox'
    let g:airline#extensions#tabline#formatter = 'unique_tail_improved'
    let g:airline#extensions#tabline#fnamemod = '%F'
    
    
    " show tabs when there are at least 2
    set showtabline=1
        
" Treeitter
    lua require('user.treesitter-settings')
" Telescope
    lua require('user.telescope-settings')
    nnoremap <leader>ff <cmd>Telescope find_files find_command=rg,--ignore,--hidden,--files prompt_prefix=🔍🥺<CR>
    nnoremap <leader>fg <cmd>Telescope live_grep prompt_prefix=🔍🤔<CR>

" AnyFold + Fold Cylce
    "autocmd Filetype Telescope* call AnyFoldTelescope else call AnyFoldActivate
    augroup vim_anyfold
        autocmd!
        autocmd Filetype vim AnyFoldActivate
        autocmd Filetype vim set foldlevel=0
    augroup END
    hi Folded term=underline
    autocmd Filetype cpp set foldignore=#/
    "let g:anyfold_identify_comments=2
    autocmd User anyfoldLoaded normal zv

    let g:fold_cycle_default_mapping = 0 "disable default mappings
    
    " Won't close when max fold is opened
    let g:fold_cycle_toggle_max_open  = 1
    " Won't open when max fold is closed
    let g:fold_cycle_toggle_max_close = 1

" Nerdtree
   map <silent><C-a> :NERDTreeToggle<CR>
   let g:NERDTreeWinSize=70
   let g:NERDTreeChDirMode=2
   let g:NERDTreeIgnore=['\.rbc$', '\~$', '\.pyc$', '\.db$', '\.sqlite$', '__pycache__']
   let g:NERDTreeSortOrder=['^__\.py$', '\/$', '*', '\.swp$', '\.bak$', '\~$']
   let g:NERDTreeShowBookmarks=1
   let g:nerdtree_tabs_focus_on_files=1
   let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
   let g:NERDTreeWinPos = "right"
   "autocmd VimEnter * NERDTree | wincmd p
   autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif "Exit Vim if NERDTree is the only window remaining in the only tab.
   autocmd BufWritePost * silent! NERDTreeRefreshRoot 
" NvimTree
    "let g:nvim_tree_quit_on_open = 1 "0 by default, closes the tree when you open a file
    "let g:nvim_tree_indent_markers = 1 "0 by default, this option shows indent markers when folders are open
    "let g:nvim_tree_git_hl = 1 "0 by default, will enable file highlight for git attributes (can be used without the icons).
    "let g:nvim_tree_highlight_opened_files = 1 "0 by default, will enable folder and file icon highlight for opened files/directories.
    "let g:nvim_tree_root_folder_modifier = ':~' "This is the default. See :help filename-modifiers for more options
    "let g:nvim_tree_add_trailing = 1 "0 by default, append a trailing slash to folder names
    "let g:nvim_tree_group_empty = 1 " 0 by default, compact folders that only contain a single folder into one node in the file tree
    "let g:nvim_tree_disable_window_picker = 1 "0 by default, will disable the window picker.
    "let g:nvim_tree_icon_padding = ' ' "one space by default, used for rendering the space between the icon and the filename. Use with caution, it could break rendering if you set an empty string depending on your font.
    "let g:nvim_tree_symlink_arrow = ' >> ' " defaults to ' ➛ '. used as a separator between symlinks' source and target.
    "let g:nvim_tree_respect_buf_cwd = 1 "0 by default, will change cwd of nvim-tree to that of new buffer's when opening nvim-tree.
    "let g:nvim_tree_create_in_closed_folder = 0 "1 by default, When creating files, sets the path of a file when cursor is on a closed folder to the parent folder when 0, and inside the folder when 1.
    "let g:nvim_tree_refresh_wait = 500 "1000 by default, control how often the tree can be refreshed, 1000 means the tree can be refresh once per 1000ms.
    "let g:nvim_tree_window_picker_exclude = {
    "    \   'filetype': [
    "    \     'notify',
    "    \     'packer',
    "    \     'qf'
    "    \   ],
    "    \   'buftype': [
    "    \     'terminal'
    "    \   ]
    "    \ }
    "" Dictionary of buffer option names mapped to a list of option values that
    "" indicates to the window picker that the buffer's window should not be
    "" selectable.
    "let g:nvim_tree_special_files = { 'README.md': 1, 'Makefile': 1, 'MAKEFILE': 1 } " List of filenames that gets highlighted with NvimTreeSpecialFile
    "let g:nvim_tree_show_icons = {
    "    \ 'git': 1,
    "    \ 'folders': 0,
    "    \ 'files': 0,
    "    \ 'folder_arrows': 0,
    "    \ }
    ""If 0, do not show the icons for one of 'git' 'folder' and 'files'
    ""1 by default, notice that if 'files' is 1, it will only display
    ""if nvim-web-devicons is installed and on your runtimepath.
    ""if folder is 1, you can also tell folder_arrows 1 to show small arrows next to the folder icons.
    ""but this will not work when you set indent_markers (because of UI conflict)
    "
    "" default will show icon by default if no icon is provided
    "" default shows no icon by default
    "let g:nvim_tree_icons = {
    "    \ 'default': '',
    "    \ 'symlink': '',
    "    \ 'git': {
    "    \   'unstaged': "✗",
    "    \   'staged': "✓",
    "    \   'unmerged': "",
    "    \   'renamed': "➜",
    "    \   'untracked': "★",
    "    \   'deleted': "",
    "    \   'ignored': "◌"
    "    \   },
    "    \ 'folder': {
    "    \   'arrow_open': "",
    "    \   'arrow_closed': "",
    "    \   'default': "",
    "    \   'open': "",
    "    \   'empty': "",
    "    \   'empty_open': "",
    "    \   'symlink': "",
    "    \   'symlink_open': "",
    "    \   }
    "    \ }
    "
    "nnoremap <C-a> :NvimTreeToggle<CR>
    "nnoremap <leader>ar :NvimTreeRefresh<CR>
    "nnoremap <leader>an :NvimTreeFindFile<CR>
    "" NvimTreeOpen, NvimTreeClose, NvimTreeFocus, NvimTreeFindFileToggle, and NvimTreeResize are also available if you need them
    "
    "" a list of groups can be found at `:help nvim_tree_highlight`
    "highlight NvimTreeFolderIcon guibg=blue
    "lua require('nvimtree-settings')
" Fugitive
   "" noremap <Leader>ga :Gwrite<CR>
   "" noremap <Leader>gc :Gcommit<CR>
   "" noremap <Leader>gsh :Gpush<CR>
   "" noremap <Leader>gll :Gpull<CR>
   "" noremap <Leader>gs :Gstatus<CR>
   "" noremap <Leader>gb :Gblame<CR>
   "" noremap <Leader>gd :Gvdiff<CR>
   "" noremap <Leader>gr :Gremove<CR>
   "Plugin has beeb updated -> fixme 

" Yank Highlighting
   let g:highlightedyank_highlight_duration = 700
" Lastplace
    let g:lastplace_ignore = "gitcommit,gitrebase,svn,hgcommit"

" LSP / cmp / luasnip
    set completeopt=menu,menuone,noselect
    lua require('user.cmp')
    lua require('user.lsp')

" renamer.nvim
    "lua require('user.renamer')
    "nnoremap <silent> <leader>rn <cmd>lua require('renamer').rename()<cr>
    "vnoremap <silent> <leader>rn <cmd>lua require('renamer').rename()<cr>
    "hi default link RenamerNormal Normal
    "hi default link RenamerBorder RenamerNormal
    "hi default link RenamerTitle Identifier
" rust_tools.nvim
    lua require("user.rust_tools")
" Markdown Options
    autocmd Filetype markdown set conceallevel=2
" Lua Options
    autocmd Filetype lua set softtabstop=2
    autocmd Filetype lua set tabstop=2
    autocmd Filetype lua set shiftwidth=2

" Python Options
    autocmd Filetype python set tabstop=4 
    autocmd Filetype python set softtabstop=4
    autocmd Filetype python set shiftwidth=4
    autocmd Filetype python set textwidth=79 "pep conformance 🤔
    autocmd Filetype python set autoindent 
    autocmd Filetype python set expandtab
    autocmd Filetype python set fileformat=unix 
    "add #type: ignore to EOL to ignore type warnings for pyright:
    autocmd Filetype python map <silent>,ignore $a #type: ignore<Esc> 
    "lua require'lspconfig'.pyright.setup{on_attach=require'nvim-cmp'.on_attach}
    "lua cmd = { "pyright-langserver", "--stdio" } filetypes = { "python" } root_dir = function(startpath) return M.search_ancestors(startpath, matcher) end settings = { python = {analysis = {autoSearchPaths = true, diagnosticMode = "workspace", useLibraryCodeForTypes = true}}} single_file_support = true

" Mutt Options
    au BufRead /tmp/mutt-* set tw=72
" VimWiki Options
    "emp
" Rust Options
    autocmd BufWritePre *.rs lua vim.lsp.buf.formatting_sync(nil, 1000)
"end
"autocmd Filetype rust map <silent><leader><leader> :w<CR>:!rustfmt %<CR>:!cargo check<CR>
"nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo "use <leader>,<CMD> 
"nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
"" ========================
"" Tagba
"" ========================
"nmap <C-s> :TagbarToggle<CR>
"let g:tagbar_autoclose = 1
"let g:tagbar_autofocus = 1
""let g:tagbar_left = 1
"let g_tagbar_width = 15
