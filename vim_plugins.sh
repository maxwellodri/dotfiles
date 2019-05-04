#!/bin/sh
#below taken from pathogen github page 
#install pathogen
#git clone https://github.com/vim/vim.git #vim src
mkdir -p ~/.vim/autoload ~/.vim/bundle && \
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
#vim sensible:
cd ~/.vim/bundle && \
git clone https://github.com/tpope/vim-sensible.git
git clone https://github.com/rust-lang/rust.vim #rustc syntax highlighting
