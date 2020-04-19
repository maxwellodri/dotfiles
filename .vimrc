set tabstop=4
set softtabstop=0
set shiftwidth=4
set expandtab
set smarttab
set autoindent
"color blue
"color darkblue
"color default
"color delek
"color desert
"color elflord
"color evening
"color industry
"color koehler
"color morning
"color murphy
"color pablo
"color peachpuff
"color ron
"color shine
"color slate
"color torte
"color zellner
color molokai
set clipboard=unnamedplus

set number
set relativenumber
set nocompatible
set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys


"plugin stuff with pathogen below : need to install pathogen separately
filetype off
execute pathogen#infect()
execute pathogen#helptags()
filetype plugin indent on
syntax on
set sessionoptions-=options

autocmd Filetype make set noexpandtab
autocmd FileType tex setlocal spell spelllang=en_au
autocmd Filetype c set shiftwidth=4
autocmd Filetype cpp set shiftwidth=4

"Python
"let python_highlight_all=1
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

"tagba
nmap <C-s> :TagbarToggle<CR>
let g:tagbar_autoclose = 1
let g:tagbar_autofocus = 1
"let g:tagbar_left = 1
let g_tagbar_width = 15

