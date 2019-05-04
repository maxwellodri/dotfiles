set tabstop=4
set softtabstop=0
set shiftwidth=4
set expandtab
set smarttab
set autoindent
syntax on
set clipboard=unnamedplus
"set spell "spell checking

set number
set relativenumber

filetype on
autocmd Filetype make set noexpandtab

"plugin stuff with pathogen below : need to install pathogen separately
set nocompatible
filetype plugin indent on
execute pathogen#infect()
set sessionoptions-=options




