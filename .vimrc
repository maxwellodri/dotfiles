"        _                    
" __   _(_)_ __ ___  _ __ ___ 
" \ \ / / | '_ ` _ \| '__/ __|
"  \ V /| | | | | | | | | (__ 
"   \_/ |_|_| |_| |_|_|  \___|
"                             

filetype off
set termguicolors
let s:plug = '~/.vim/plugged'
function! CocPlugins(arg)
  :CocInstall coc-rust-analyzer
  :CocInstall coc-json 
  :CocInstall coc-tsserver
  :CocInstall coc-html
  :CocInstall coc-css
  :CocInstall coc-sh
"  :CocInstall coc-clangd
  :CocInstall coc-highlight
  :CocInstall coc-yaml
endfunction
" ==========
"
" Plugins
"
" ==========
" =============
" Autocomplete
" =============
"
call plug#begin(s:plug)
"coc requires node, force update of coc plugins with :CocUpdate!
Plug 'neoclide/coc.nvim', {'branch': 'release', 'do': function('CocPlugins') }
"let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0 (old)
" =================
" Language Support
" =================
Plug 'sheerun/vim-polyglot' "all in one bundle
Plug 'rust-lang/rust.vim'
Plug 'tikhomirov/vim-glsl'
Plug 'JuliaEditorSupport/julia-vim'
Plug 'kevinoid/vim-jsonc'
" ====
" Git
" ====
Plug 'tpope/vim-fugitive'
" ======
" Search
" ======
Plug 'PeterRincker/vim-searchlight'
" ==============
" Miscellaneous
" ==============
Plug 'tpope/vim-sensible'
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
Plug 'pineapplegiant/spaceduck'
" =======
" Unused 
" =======
"Plug 'preservim/tagbar'        "requires ctags  to be installed
"Plug 'preservim/nerdtree'
"let g:NERDTreeWinSize=15
"map <C-a> :NERDTreeToggle<CR>
"
call plug#end()

" ===============
"
" Colour Options
"
" ===============
set background=dark    
let g:tokyonight_style = 'night' " available: night, storm
let g:tokyonight_enable_italic = 1
let g:tokyonight_current_word = 'underline'
let g:deus_termcolors=256
color pablo "fallback
color codedark
color tokyonight
color molokai

"set t_Co=256
"let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
"let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
"
"
" =============
" 
" Basic Options 
"
" =============
filetype plugin indent on
syntax on
set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
set statusline+=%{FugitiveStatusline()}
set statusline+=%t "add file name to statusline
set sessionoptions-=options
set tabstop=4
set softtabstop=0
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
map <leader>o :setlocal spell! spelllang=en_au<CR>

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
"autocmd Filetype python set textwidth=79
autocmd Filetype python set autoindent 
autocmd Filetype python set expandtab
autocmd Filetype python set fileformat=unix 
" ==============
" LaTeX Snippets
" ==============
nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
" =================
"  Compile from vim
" =================
"command! Texit !pdflatex % 
"command PP !python %
"command! Maketags !ctags -R
"autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
"usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
"stack
"
" ========================
" Fix Search Highlighting
" ========================
nmap <Esc> :nohlsearch<CR>q:<CR>
imap <Esc> <Esc>:nohlsearch<CR>q:<CR>



"Remaps:
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


"Tagbar:
nmap <C-s> :TagbarToggle<CR>
let g:tagbar_autoclose = 1
let g:tagbar_autofocus = 1
"let g:tagbar_left = 1
let g_tagbar_width = 15

"Coc:
set cmdheight=2
set updatetime=300
set shortmess+=c
if has("patch-8.1.1564")
  set signcolumn=number
else
  set signcolumn=yes
endif
" Use tab for trigger completion with characters ahead and navigate.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction
" Use <c-space> to trigger completion.
inoremap <silent><expr> <c-space> coc#refresh()
" Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
" position. Coc only does snippet and additional edit on confirm.
" <cr> could be remapped by other vim plugin, try `:verbose imap <CR>`.
if exists('*complete_info')
  inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
else
  inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
endif

" Use `[g` and `]g` to navigate diagnostics
" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)


" GoTo code navigation.
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" Use K to show documentation in preview window.
nnoremap <silent> K :call <SID>show_documentation()<CR>

function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  else
    call CocAction('doHover')
  endif
endfunction

" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.
nmap <leader>rn <Plug>(coc-rename)
map <leader><leader> :w<CR>:!rustfmt %<CR>

" Formatting selected code.
xmap <leader>f  <Plug>(coc-format-selected)
nmap <leader>f  <Plug>(coc-format-selected)

augroup mygroup
  autocmd!
  " Setup formatexpr specified filetype(s).
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  " Update signature help on jump placeholder.
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end

" Applying codeAction to the selected region.
" Example: `<leader>aap` for current paragraph
xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)

" Remap keys for applying codeAction to the current buffer.
nmap <leader>ac  <Plug>(coc-codeaction)
" Apply AutoFix to problem on the current line.
nmap <leader>qf  <Plug>(coc-fix-current)

" Map function and class text objects
" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)

" Use CTRL-S for selections ranges.
" Requires 'textDocument/selectionRange' support of LS, ex: coc-tsserver
nmap <silent> <C-s> <Plug>(coc-range-select)
xmap <silent> <C-s> <Plug>(coc-range-select)

" Add `:Format` command to format current buffer.
command! -nargs=0 Format :call CocAction('format')

" Add `:Fold` command to fold current buffer.
command! -nargs=? Fold :call     CocAction('fold', <f-args>)

" Add `:OR` command for organize imports of the current buffer.
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')

" Add (Neo)Vim's native statusline support.
" NOTE: Please see `:h coc-status` for integrations with external plugins that
" provide custom statusline: lightline.vim, vim-airline.

" Mappings for CoCList
" Show all diagnostics.
nnoremap <silent><nowait> <space>a  :<C-u>CocList diagnostics<cr>
" Manage extensions.
nnoremap <silent><nowait> <space>e  :<C-u>CocList extensions<cr>
" Show commands.
nnoremap <silent><nowait> <space>c  :<C-u>CocList commands<cr>
" Find symbol of current document.
nnoremap <silent><nowait> <space>o  :<C-u>CocList outline<cr>
" Search workspace symbols.
nnoremap <silent><nowait> <space>s  :<C-u>CocList -I symbols<cr>
" Do default action for next item.
nnoremap <silent><nowait> <space>j  :<C-u>CocNext<CR>
" Do default action for previous item.
nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
" Resume latest coc list.
nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>

let g:UltiSnipsExpandTrigger="<F2>" "need to remap away from default <tab> to avoid conflict with coc autocomplete
let g:UltiSnipsJumpForwardTrigger="<c-k>"
let g:UltiSnipsJumpBackwardTrigger="<c-j>"
