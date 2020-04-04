#!/bin/sh
#below taken from pathogen github page 
#install pathogen
#git clone https://github.com/vim/vim.git #vim src
mkdir -p ~/.vim/autoload ~/.vim/bundle ~/.vim/colors && \
curl -LSso ~/.vim/autoload/pathogen.vim https://tpo.pe/pathogen.vim
#vim sensible:
cd ~/.vim/bundle && \
git clone https://github.com/tpope/vim-sensible.git
git clone https://github.com/rust-lang/rust.vim #rustc syntax highlighting
git clone https://github.com/ycm-core/YouCompleteMe #autocomplete - requires at minmum python3, cmake and vim - node, npm, rust, go mono are useful
cd YouCompleteMe && git submodule update --init --recursive 
curl -LSO https://raw.githubusercontent.com/tomasr/molokai/master/colors/molokai.vim #molokai theme


#https://github.com/szymonmaszke/vimpyter #for jupyter notebook
