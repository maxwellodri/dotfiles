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
    Plug 'tpope/vim-surround' "adds s vim adjevtive
    Plug 'tpope/vim-eunuch' "unix commands
    Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
    Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
    Plug 'nvim-lua/plenary.nvim' "library of functions, used by other modules
    Plug 'MunifTanjim/nui.nvim' "ui component library
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
    Plug 'nvim-treesitter/nvim-treesitter-context'
    Plug 'sheerun/vim-polyglot' "AIO bundle
    Plug 'tikhomirov/vim-glsl'
    Plug 'JuliaEditorSupport/julia-vim'
    Plug 'kevinoid/vim-jsonc'
    Plug 'lervag/vimtex'
    Plug 'ron-rs/ron.vim'
    Plug 'leafgarland/typescript-vim'
    Plug 'raimon49/requirements.txt.vim' "requirement.txt support
    Plug 'DingDean/wgsl.vim' 
    Plug 'chrisbra/csv.vim'
    Plug 'mechatroner/rainbow_csv'
    Plug 'elkowar/yuck.vim'
    Plug 'habamax/vim-godot'
    " ============ "
    " Rust Support "
    " ============ "
    "Plug 'rust-lang/rust.vim'
    "Plug 'arzg/vim-rust-syntax-ext'
    Plug 'saecki/crates.nvim'
    "Plug 'simrat39/rust-tools.nvim'
    Plug 'mrcjkb/rustaceanvim', { 'tag': '^5'}
    " =================
    " LSP / cmp / LuaSnip
    " =================
    Plug 'williamboman/mason.nvim'
    Plug 'williamboman/mason-lspconfig.nvim'
    Plug 'jose-elias-alvarez/null-ls.nvim'
    Plug 'neovim/nvim-lspconfig' 
    Plug 'hrsh7th/nvim-cmp'
    Plug 'hrsh7th/cmp-buffer'
    Plug 'hrsh7th/cmp-path'
    Plug 'hrsh7th/cmp-cmdline'
    Plug 'hrsh7th/cmp-nvim-lsp'
    Plug 'saadparwaiz1/cmp_luasnip' 
    Plug 'hrsh7th/cmp-nvim-lua'
    Plug 'hrsh7th/cmp-nvim-lsp-document-symbol'
    Plug 'L3MON4D3/LuaSnip' "snippet engine
    Plug 'rafamadriz/friendly-snippets' "a bunch of snippets to use
    Plug 'mfussenegger/nvim-dap'
    Plug 'rcarriga/nvim-dap-ui'
    Plug 'theHamsta/nvim-dap-virtual-text'

    Plug 'onsails/lspkind.nvim'
    "" ====
    "" C#
    "" ====
    Plug 'Hoffs/omnisharp-extended-lsp.nvim'
    "" ====
    "" Git
    "" ====
    Plug 'tpope/vim-fugitive'
    Plug 'kdheepak/lazygit.nvim'
    " ======
    " Search / File Finding / Navigation
    " ======
    Plug 'PeterRincker/vim-searchlight'
    "Plug 'preservim/nerdtree'
    " Plug 'pseewald/vim-anyfold'
    " Plug 'arecarn/vim-fold-cycle'
    Plug 'nvim-telescope/telescope.nvim'
    Plug 'nvim-telescope/telescope-ui-select.nvim'
    Plug 'kyazdani42/nvim-tree.lua' "library of functions, used by other modules
    Plug 'stsewd/gx-extended.vim' "requires gx from vim-markdown (contained in vim-polyglot) to be disabled
    Plug 'stevearc/oil.nvim'
    " ==============
    " Visual / Appearance
    " ==============
    Plug 'kien/rainbow_parentheses.vim' 
    Plug 'machakann/vim-highlightedyank' "highlight on yank
    Plug 'feline-nvim/feline.nvim' "status bar - airline replacement
    Plug 'Yggdroot/indentLine'
    " ===============
    " Color Schemes 
    " ===============
    Plug 'tomasiser/vim-code-dark'
    Plug 'tomasr/molokai'
    Plug 'morhetz/gruvbox'
    "Plug 'ellisonleao/gruvbox.nvim'
    Plug 'RRethy/nvim-base16'
    Plug 'ghifarit53/tokyonight-vim' 
    Plug 'savq/melange'
    Plug 'ajmwagar/vim-deus' 
    Plug 'sainnhe/edge'
    Plug 'jnurmine/Zenburn'
    Plug 'arzg/vim-colors-xcode'
    Plug 'ChristianChiarulli/nvcode-color-schemes.vim'
    "Plug 'pineapplegiant/spaceduck'
    " ===============
    " NoteTaking & Vim Wiki
    " ===============
    Plug 'vimwiki/vimwiki'
    " ===============
    " Perf
    " ===============
    Plug 'lewis6991/impatient.nvim'
    "Plug 'nathom/filetype.nvim'
    Plug 'tweekmonster/startuptime.vim'
    "
    call plug#end()
    source ~/.vimrc "vimrc is effectively a plugin lmao
    nnoremap <silent><leader>V :w<CR>:so $MYVIMRC<CR>:PlugInstall<CR>

" To try out:
" https://github.com/folke/trouble.nvim
"https://github.com/Lommix/godot.nvim -> nvr
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

    let g:did_load_filetypes = 0
    let g:do_filetype_lua = 0

" Colorscheme
    "nnoremap <leader>hi :echo synIDattr(synIDtrans(synID(line("."), col("."), 1)), "fg")<CR>
    "":echo synIDattr(synID(line("."), col("."), 1), "name")<CR>

" Statusline
    "set statusline=
    "set cmdheight=2 " space below the statusline
    "set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\ 
    "set statusline+=%{FugitiveStatusline()}
    "set showtabline=1
" Treeitter
" Treeitter Context
" Telescope
    nnoremap <leader>fo <cmd>Telescope find_files find_command=rg,--ignore,--hidden,--files prompt_prefix=🔍🥺<CR>
    nnoremap <leader>fh <cmd>Telescope find_files find_command=rg,--hidden=true,--files prompt_prefix=🔍🥺<CR>
    nnoremap <leader>ff :tabnew<CR>:Telescope find_files find_command=rg,--ignore,--hidden,--files prompt_prefix=🔍🥺<CR>
    nnoremap <leader>fv :vsplit<CR>:Telescope find_files find_command=rg,--ignore,--hidden,--files prompt_prefix=🔍🥺<CR>
    nnoremap <leader>fs <cmd>Telescope lsp_document_symbols find_command=rg,--ignore,--hidden,--files prompt_prefix=🔍🥺<CR>
    nnoremap <leader>rg <cmd>Telescope live_grep prompt_prefix=🔍🤔<CR>
    nnoremap <leader>rs <cmd>Telescope lsp_workspace_symbols prompt_prefix=🔍👹<CR>
    nnoremap gr <cmd>Telescope lsp_references prompt_prefix=😠<CR>
    nnoremap <leader>rv :vsplit<CR>:<cmd>Telescope live_grep prompt_prefix=🔍🤔<CR>
 " Oil


" Git
   let g:lazygit_floating_window_winblend = 0 " transparency of floating window
   let g:lazygit_floating_window_scaling_factor = 0.9 " scaling factor for floating window
   let g:lazygit_floating_window_border_chars = ['╭', '╮', '╰', '╯'] " customize lazygit popup window corner characters
   let g:lazygit_floating_window_use_plenary = 0 " use plenary.nvim to manage floating window if available
   let g:lazygit_use_neovim_remote = 1 " fallback to 0 if neovim-remote is not installed
   nnoremap <silent> <leader>gg :LazyGit<CR>
" impatient
" Yank Highlighting
  let g:highlightedyank_highlight_duration = 650
" Lastplace
  let g:lastplace_ignore = "gitcommit,gitrebase,svn,hgcommit"

" Markdown Options
    autocmd Filetype markdown set conceallevel=2
" Lua Options
    autocmd Filetype lua set softtabstop=2
    autocmd Filetype lua set tabstop=2
    autocmd Filetype lua set shiftwidth=2
" CSV Options
    autocmd BufWritePre *.csv RainbowAlign

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
    autocmd BufWritePre *.py lua vim.lsp.buf.format()
"C#
    autocmd BufWritePre *.cs lua vim.lsp.buf.format()

" Mutt Options
    au BufRead /tmp/mutt-* set tw=72
" VimWiki Options
    "unmap <leader>ww
    "unmap <leader>wt
    "unmap <leader>ws
    "unmap <leader>wd
    "unmap <leader>wr
    nnoremap <leader>wo <Plug>VimwikiIndex
" LSP / cmp / luasnip/null-ls
  set completeopt=menu,menuone,noselect,preview
  nnoremap <leader><C-m> :Mason<CR>

" Godot Options
    "autocmd FileType gdscript nnoremap <F5> <Esc>:w<CR>:GodotRun<CR>
    "autocmd BufWritePre gdscript :%s/\s\+$//e
    lua vim.g.godot_executable = '/bin/godot-mono-bin'

    autocmd Filetype gdscript nnoremap <leader>fo <cmd>Telescope find_files find_command=rg,--ignore,--files prompt_prefix=🔍🥺<CR>
    function! RebuildAndRestart()
       let l:current_dir = getcwd()
       execute 'cd' fnameescape(system('git rev-parse --show-toplevel'))
       if system('cargo build --manifest-path ./rust/Cargo.toml') != 0
          echo "Build failed. Exiting."
          execute 'cd' fnameescape(l:current_dir)
          return
       endif
       !pkill -f godot-mono
       !mykaelium &
       windo if &filetype == 'gdscript' | execute 'LspRestart' | endif
       execute 'cd' fnameescape(l:current_dir)
    endfunction
    autocmd FileType rust,gdscript command! RebuildAndRestart :call RebuildAndRestart()
    nnoremap <leader>bb :RebuildAndRestart<CR>
" Rust Options
    function! GetSrcDir(...) abort
        if a:0 == 0
            let l:dir_curr = expand('%:p:h')
        else
            let l:dir_curr = a:1
        endif
    
        let l:dir_last = ""
    
        while l:dir_last != l:dir_curr
            if isdirectory(l:dir_curr . '/src') || filereadable(l:dir_curr . '/src')
                return l:dir_curr . '/src'
            else
                let l:dir_last = l:dir_curr
                let l:dir_curr = fnamemodify(l:dir_curr, ':h')
            endif
        endwhile
        return ""
    endfunction
    
    function! CdSrcDir()
      let g:src_dir = GetSrcDir()
      if strlen(g:src_dir)
        execute 'cd' fnameescape(g:src_dir)
        echo 'Changed to src/'
      endif
    endfunction

    function! CdParent()
      let g:parent_dir = expand('%:h:p')
      if strlen(g:parent_dir)
        execute 'cd' fnameescape(g:parent_dir)
        echo 'Changed to parent'
      endif
    endfunction
    
    autocmd Filetype rust nnoremap <leader>ds :call CdSrcDir()<CR>
    autocmd Filetype rust nnoremap <leader>dS :call CdParent()<CR>
" terminal:
    command! Sterm silent execute '!nohup st -d' expand('%:p:h') '> /dev/null 2>&1 &'
    nnoremap <S-CR> :Sterm<CR>
" vim
    command! Vimrc silent lcd ~/.config/nvim/ | edit init.vim
" Navigation & Splits
    nnoremap <silent><leader>dr :Gcd<CR>:echo "Changed to git root dir"<CR>
    nnoremap <silent_leader>dh :cd<CR>:echo "Changed to home dir"<CR>
    nnoremap <silent><leader>bn :bn<CR>
    nnoremap <silent><leader>bp :bp<CR>
    nnoremap <silent><leader>bl :bl<CR>
    nnoremap <silent><leader>bf :bf<CR>
    nnoremap <silent><leader>bd :bd<CR>
    nnoremap <silent><C-k> 10k
    nnoremap <silent><C-j> 10j
    nnoremap <silent><C-h> 10h
    nnoremap <silent><C-l> 10l

    vnoremap <silent><C-k> 10k
    vnoremap <silent><C-j> 10j
    vnoremap <silent><C-h> 10h
    vnoremap <silent><C-l> 10l
    nnoremap <silent><C-Left> <C-w>10>
    nnoremap <silent><C-Right> <C-w>10<
    nnoremap <silent><C-Down> <C-w>10-
    nnoremap <silent><C-Up> <C-w>10+
    "TODO add buffer hotkeys with leader i.e. <leader>
" Font
" Neovide
"
   set mouse=
   let g:neovide_cursor_vfx_mode = "wireframe"
   let g:neovide_cursor_animation_length=0.035
   let g:neovide_cursor_trail_length=0.01

   let g:neovide_scroll_animation_length = 0.3
   let g:neovide_cursor_unfocused_outline_width=0.125
    if exists("g:neovide")
        set titlestring="%F Neovide"
    endif
" indentLine
    let g:indentLine_enabled = 0
    let g:indentLine_char_list = ['|', '¦', '┆', '┊']
    let g:indentLine_defaultGroup = 'SpecialKey'
    let g:indentLine_color_gui = '#e91e63'
    autocmd Filetype rust let g:indentLine_enabled = 1
" keybinds & utils
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
"
"

"TODO unset shift L and shift H
"
nnoremap <C-z> :stop<CR>
inoremap <C-z> <Esc>:stop<CR>
lua << EOF
function _G.ReloadVimConfig()
    vim.cmd('source $MYVIMRC')
    -- Clear the Lua module cache
    for name, _ in pairs(package.loaded) do
        if name:match('^user') then
            package.loaded[name] = nil
        end
    end
    print("Reloaded vimrc and Lua configuration")
end
EOF

nnoremap <silent><leader>v :w<CR>:lua ReloadVimConfig()<CR>
lua require('user.init')
