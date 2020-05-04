"        _                    
" __   _(_)_ __ ___  _ __ ___ 
" \ \ / / | '_ ` _ \| '__/ __|
"  \ V /| | | | | | | | | (__ 
"   \_/ |_|_| |_| |_|_|  \___|

let mapleader =" "
filetype off
execute pathogen#infect()
execute pathogen#helptags()
filetype plugin indent on
syntax on
set sessionoptions-=options

"   basics:
    set tabstop=4
    set softtabstop=0
    set shiftwidth=4
    set expandtab
    set smarttab
    set autoindent
    set path+=** ""recursive subdirectory search
    set wildmenu
    set wildmode=longest,list,full
    set encoding=utf-8
    "color pablo
    color molokai
    set clipboard=unnamedplus
    set number
    set nocompatible
    set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys

autocmd Filetype make set noexpandtab "force tabs for make
"PEP8 approved:
autocmd Filetype python set tabstop=4 
autocmd Filetype python set softtabstop=4
autocmd Filetype python set shiftwidth=4
"autocmd Filetype python set textwidth=79
autocmd Filetype python set autoindent 
autocmd Filetype python set expandtab
autocmd Filetype python set fileformat=unix 

"NERDTREE
let g:NERDTreeWinSize=15
map <C-a> :NERDTreeToggle<CR>

"Syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message

"tagbar
nmap <C-s> :TagbarToggle<CR>
let g:tagbar_autoclose = 1
let g:tagbar_autofocus = 1
"let g:tagbar_left = 1
let g_tagbar_width = 15

"snippets:
nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i


command! Texit !pdflatex % 
command! Maketags !ctags -R .
map <leader>o :setlocal spell! spelllang=en_au<CR>
autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
"usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
"stack
    set splitbelow splitright
    map <C-h> <C-w>h
    map <C-j> <C-w>j
    map <C-k> <C-w>k
    map <C-l> <C-w>l
