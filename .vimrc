"
"        _                    
" __   _(_)_ __ ___  _ __ ___ 
" \ \ / / | '_ ` _ \| '__/ __|
"  \ V /| | | | | | | | | (__ 
"   \_/ |_|_| |_| |_|_|  \___|
"                             
"
filetype plugin indent on
syntax enable
call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
if exists('$SHELL') "probably unnecesary
    set shell=$SHELL
    else 
    set shell=/bin/sh 
    endif
" set variables
    set textwidth=0
    set nowrap
    set termguicolors
    set title
    set titlestring=%F "necessary to be able to 'toggle' configs in sxhkd
    set sessionoptions-=options
    set softtabstop=4
    set shiftwidth=0
    set expandtab
    set tabstop=4
    set shiftwidth=4
    set smarttab
    set autoindent
    set path+=** ""recursive subdirectory search
    set wildmenu
    set wildmode=longest,list,full
    set encoding=utf-8
    set clipboard=unnamedplus
    set number
    set nocompatible
    set ignorecase
    set smartcase
    set noswapfile
    set nobackup
    set scrolloff=8
    set incsearch
    set signcolumn=yes
    set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
    set hidden
    set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
    set wildignore+=*.pyc
    set wildignore+=*_build/*

" Leader bindings
    let mapleader =" "
    map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
    map <silent><leader>v :w<CR>:so $MYVIMRC<CR>:echo "Reloaded vimrc"<CR>
    nnoremap <leader>c :!compile %<CR> 
    nmap <silent> <Esc> :nohlsearch<CR>
    imap <silent> <Esc> <Esc>:nohlsearch<CR>
    "fix line indenting ==> 
    nnoremap <leader><TAB> ^=$ 
" Search mappings: Going to the next one in a search will center on the line it's found in.
    nnoremap n nzzzv
    nnoremap N Nzzzv
" Abbreviations Remaps
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
    nnoremap ZA :wqa<CR>



" Unbind Arrow Keys
    inoremap <left> <nop>
    inoremap <right> <nop>
    inoremap <down> <nop>
    inoremap <up> <nop>
    nnoremap <left> <nop>
    nnoremap <right> <nop>
    nnoremap <down> <nop>
    nnoremap <up> <nop>
    nnoremap K <nop>


" Cursor Options
    set cul "cursor line is highlighted
    set guicursor=n-v-c-sm:block-Cursor
    set guicursor+=i-ci-ve:ver25-iCursor
    set guicursor+=r-cr-o:hor20
function! s:get_visual_selection()
    " Why is this not a built-in Vim script function?!
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
    endfunction
" Split Options
    set splitbelow splitright
    "map <C-h> <C-w>h
    "map <C-j> <C-w>j
    "map <C-k> <C-w>k
    "map <C-l> <C-w>l
" Tab Navigation
    nnoremap <silent><leader>tk :tabnext<CR>
    nnoremap <silent><leader>tj :tabprev<CR>
    nnoremap <leader>tn :w<CR>:tabnew<CR>
    nnoremap <leader>td  :tabclose<CR>
    nnoremap <silent><leader>th  :tabfirst<CR>
    nnoremap <silent><leader>tl  :tablast<CR>
    nnoremap <leader>te  :w<CR>:tabe<Space>
    nnoremap <leader>tm  :tabm<Space>
    nnoremap <leader>tv  :vsplit<Space>


" Make Options
    autocmd Filetype make set noexpandtab "force tabs for make

    inoremap <left> <nop>

