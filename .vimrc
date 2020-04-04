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

autocmd Filetype python set shiftwidth=4
autocmd Filetype c set shiftwidth=4




