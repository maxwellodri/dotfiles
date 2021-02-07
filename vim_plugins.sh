#!/bin/sh
#below taken from pathogen github page 
mkdir -p ~/.vim/autoload ~/.vim/bundle ~/.vim/colors && \
cd ~/.vim/colors && curl -LSO https://raw.githubusercontent.com/tomasr/molokai/master/colors/molokai.vim #molokai theme


curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
cd $dotfiles/vim
vim -S coc-installer.vim

#https://github.com/szymonmaszke/vimpyter #for jupyter notebook
#git clone https://github.com/vim/vim.git #vim src
#vim sensible:
#cd ~/.vim/bundle && \
#git clone https://github.com/tpope/vim-sensible.git
#git clone https://github.com/rust-lang/rust.vim #rustc syntax highlighting
#git clone https://github.com/ycm-core/YouCompleteMe #autocomplete - requires at minmum python3, cmake and vim - node, npm, rust, go mono are useful
#git clone https://github.com/majutsushi/tagbar #requires ctags
#git clone https://github.com/tikhomirov/vim-glsl #glsl syntax highlighting
#git clone https://github.com/preservim/nerdtree.git ~/.vim/bundle/nerdtree
#git clone https://github.com/Chiel92/vim-autoformat #also make sure that default formatters are installed for each language
#git clone --depth=1 https://github.com/vim-syntastic/syntastic.git
#git clone https://github.com/dense-analysis/ale.git
#cd YouCompleteMe && git submodule update --init --recursive 
