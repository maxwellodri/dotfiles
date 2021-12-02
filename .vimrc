"
"        _                    
" __   _(_)_ __ ___  _ __ ___ 
" \ \ / / | '_ ` _ \| '__/ __|
"  \ V /| | | | | | | | | (__ 
"   \_/ |_|_| |_| |_|_|  \___|
"                             

filetype on
set termguicolors
let s:plug = '~/.vim/plugged' "Plugins:
call plug#begin()

"TODO
"Plug 'scrooloose/nerdtree'
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
" =================
" Language Support
" =================
Plug 'sheerun/vim-polyglot' "AIO bundle
Plug 'rust-lang/rust.vim'
Plug 'tikhomirov/vim-glsl'
Plug 'JuliaEditorSupport/julia-vim'
Plug 'kevinoid/vim-jsonc'
Plug 'lervag/vimtex'
Plug 'ron-rs/ron.vim'
Plug 'leafgarland/typescript-vim'
Plug 'raimon49/requirements.txt.vim' "requirement.txt support
" ====
" Git
" ====
Plug 'tpope/vim-fugitive'
" ======
" Search / File Finding
" ======
Plug 'PeterRincker/vim-searchlight'
Plug 'preservim/nerdtree'
" ==============
" Miscellaneous
" ==============
Plug 'tpope/vim-sensible'
Plug 'machakann/vim-highlightedyank' "highlight on yank
Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
" =========
" Snippets
" =========
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
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
"
call plug#end()

" =============
" 
" Basic Options 
"
" =============
color gruvbox
filetype on
"set termguicolors
set title
set titlestring=%F "necessary to be able to 'toggle' configs in sxhkd
if exists('$SHELL')
    set shell=$SHELL
else
    set shell=/bin/sh
endif
filetype plugin indent on
syntax on
"set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
set statusline+=%{FugitiveStatusline()}
set sessionoptions-=options
set tabstop=4
set softtabstop=2
set expandtab
set smarttab
set autoindent
set path+=** ""recursive subdirectory search
set wildmenu
set wildmode=longest,list,full
set encoding=utf-8
syntax enable
set clipboard=unnamedplus
set number
set nocompatible
set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
set hidden
let mapleader =" "
"toggle spellchecker:
map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
"reload vimrc:
map <silent><leader>v :so $MYVIMRC<CR> 
nnoremap <leader>b :ls<CR>
"generic compile script:
nnoremap <leader>c :!compile %<CR>

" Search mappings: Going to the next one in a search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv
"Abbreviations
cnoreabbrev W! w!
cnoreabbrev Q! q!
cnoreabbrev Qall! qall!
cnoreabbrev Wq wq
cnoreabbrev Wa wa
cnoreabbrev wQ wq
cnoreabbrev WQ wq
cnoreabbrev W w
cnoreabbrev Q q
cnoreabbrev Qall qall
set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite

" ========================
" 
" Tab Navigation
"
" ========================
nnoremap <silent>tk :tabnext<CR>
nnoremap <silent>tj :tabprev<CR>
nnoremap tn :tabnew<CR>
nnoremap td  :tabclose<CR>
nnoremap th  :tabfirst<CR>
nnoremap tl  :tablast<CR>
nnoremap te  :tabe<Space>
nnoremap tm  :tabm<Space>

" ========================
" 
" Statusline
"
" ========================
" TODO
set cmdheight=2 " space below the statusline
"set laststatus=2
"set statusline=
"set statusline+=%#function#\ %l "color theming
"set statusline+=%f "add file name to statusline %t
set laststatus=2
set statusline=
set statusline+=%1*\ %f\ %*
set statusline+=%= "LHS/RHS  divider
set statusline+=%2*\ %{FugitiveStatusline()}
set statusline+=%2*\ %l/%L "Line current/Linemax
set statusline+=%2*\ %m "is modified
set statusline+=%2*\ %r "is readonly
"set statusline+=%3*\ ‹‹
"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
"set statusline+=%3*\ ::
"set statusline+=%3*\ %n
"set statusline+=%3*\ ››\ %*


"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
" ========================
" 
" Cursor Specific Options
"
" ========================
set cul "cursor line is highlighted
set guicursor=n-v-c-sm:block-Cursor
set guicursor+=i-ci-ve:ver25-iCursor
set guicursor+=r-cr-o:hor20

highlight Cursor guifg=white guibg=black
highlight iCursor guifg=white guibg=steelblue

hi! TermCursor guifg=NONE guibg=#ebdbb2 gui=NONE cterm=NONE
hi! TermCursorNC guifg=#ebdbb2 guibg=#3c3836 gui=NONE cterm=NONE


" ===============
"
" git
"
" ===============
noremap <Leader>ga :Gwrite<CR>
noremap <Leader>gc :Gcommit<CR>
noremap <Leader>gsh :Gpush<CR>
noremap <Leader>gll :Gpull<CR>
noremap <Leader>gs :Gstatus<CR>
noremap <Leader>gb :Gblame<CR>
noremap <Leader>gd :Gvdiff<CR>
"noremap <Leader>gr :Gremove<CR>

" ========================
" 
" Nerdtree
"
" ========================
map <silent><C-a> :NERDTreeToggle<CR>

let g:NERDTreeWinSize=70
let g:NERDTreeChDirMode=2
let g:NERDTreeIgnore=['\.rbc$', '\~$', '\.pyc$', '\.db$', '\.sqlite$', '__pycache__']
let g:NERDTreeSortOrder=['^__\.py$', '\/$', '*', '\.swp$', '\.bak$', '\~$']
let g:NERDTreeShowBookmarks=1
let g:nerdtree_tabs_focus_on_files=1
let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
let g:NERDTreeWinPos = "right"
autocmd VimEnter * NERDTree | wincmd p
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif "Exit Vim if NERDTree is the only window remaining in the only tab.
" =========================
" 
" Filetype Specfic Options
"
" =========================
"
" =====
" Make
" =====
autocmd Filetype make set noexpandtab "force tabs for make
" =====
" Python   
" =====
autocmd Filetype python set tabstop=4 
autocmd Filetype python set softtabstop=4
autocmd Filetype python set shiftwidth=4
autocmd Filetype python set textwidth=79 "pep conformance 🤔
autocmd Filetype python set autoindent 
autocmd Filetype python set expandtab
autocmd Filetype python set fileformat=unix 
"add #type: ignore to EOL to ignore type warnings for pyright:
autocmd Filetype python map <silent>,ignore $a #type: ignore<Esc> 
" =====
" Rust   
" =====
autocmd Filetype rust map <silent><leader><leader> :w<CR>:!rustfmt %<CR>:!cargo check<CR>
" =====
" Mutt   
" =====
au BufRead /tmp/mutt-* set tw=72
" ==============
" LaTeX Snippets
" ==============
nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
" =================
"  Yank Highlighting
" =================
let g:highlightedyank_highlight_duration = 1000
" =================
"  Lastplace Cursor
" =================
let g:lastplace_ignore = "gitcommit,gitrebase,svn,hgcommit"
" ========================
" Fix Search Highlighting
" ========================
nmap <silent> <Esc> :nohlsearch<CR>
imap <silent> <Esc> <Esc>:nohlsearch<CR>
" ========================
" Splits
" ========================
set splitbelow splitright
map <C-h> <C-w>h
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l

inoremap <left> <nop>
inoremap <right> <nop>
inoremap <down> <nop>
inoremap <up> <nop>

nnoremap <left> <nop>
nnoremap <right> <nop>
nnoremap <down> <nop>
nnoremap <up> <nop>


" ========================
" Tagbar
" ========================
nmap <C-s> :TagbarToggle<CR>
let g:tagbar_autoclose = 1
let g:tagbar_autofocus = 1
"let g:tagbar_left = 1
let g_tagbar_width = 15


let g:UltiSnipsExpandTrigger="<F2>" "need to remap away from default <tab> to avoid conflict with coc autocomplete
let g:UltiSnipsJumpForwardTrigger="<c-k>"
let g:UltiSnipsJumpBackwardTrigger="<c-j>"


" provide custom statusline: lightline.vim, vim-airline.
