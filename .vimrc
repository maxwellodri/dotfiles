"        _                    
" __   _(_)_ __ ___  _ __ ___ 
" \ \ / / | '_ ` _ \| '__/ __|
"  \ V /| | | | | | | | | (__ 
"   \_/ |_|_| |_| |_|_|  \___|
"                             
set termguicolors
let s:plug = '~/.vim/plugged'
function! CocPlugins(arg)
  CocInstall coc-rust-analyzer
  CocInstall coc-json 
  CocInstall coc-tsserver
  CocInstall coc-html
  CocInstall coc-css
  CocInstall coc-sh
  CocInstall coc-pyright
  CocInstall coc-xml
"  CocInstall coc-clangd
  CocInstall coc-highlight
  CocInstall coc-yaml
  CocInstall coc-pyright
  CocEnable
endfunction
" ==========
"
" Plugins
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
Plug 'lervag/vimtex'
Plug 'ron-rs/ron.vim'
Plug 'leafgarland/typescript-vim'
Plug 'raimon49/requirements.txt.vim' "requirement.txt support
Plug 'alvan/vim-closetag' "html tag closing
" ====
" Git
" ====
Plug 'tpope/vim-fugitive'
" ======
" Search/find
" ======
Plug 'PeterRincker/vim-searchlight'
Plug 'preservim/nerdtree'
" ==============
" Miscellaneous
" ==============
Plug 'tpope/vim-sensible'
Plug 'machakann/vim-highlightedyank' "highlight on yank
Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
"Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
" =========
" Snippets
" =========
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
" ===============
" Wiki 
" ===============
Plug 'vimwiki/vimwiki'
" ===============
" Color Schemes
" ===============
Plug 'tomasiser/vim-code-dark'
Plug 'tomasr/molokai'
Plug 'morhetz/gruvbox'
Plug 'ghifarit53/tokyonight-vim' 

Plug 'sainnhe/edge'
"Plug 'pineapplegiant/spaceduck'
" =======
" Unused 
" =======
"Plug 'preservim/tagbar'        "requires ctags  to be installed
"
call plug#end()

" =============
" 
" Basic Options 
"
" =============
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

" ========================
" 
"  Basic Keybindings
"
" ========================
let mapleader =" "
"toggle spellchecker:
map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
"reload vimrc:
map <silent><leader>v :so $MYVIMRC<CR>:echo "Reloaded $MYVIMRC"
"generic compile script:
nnoremap <leader>c :!compile %<CR>

" Search mappings: Going to the next one in a search will center on the line it's found in.
"nnoremap n nzzzv
"nnoremap N Nzzzv
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
nnoremap tk :tabnext<CR>
nnoremap tj :tabprev<CR>
nnoremap tn :tabnew<CR>
nnoremap td  :tabclose<CR>
nnoremap th  :tabfirst<CR>
nnoremap tl  :tablast<CR>
nnoremap tt  :tabe<Space>
nnoremap tm  :tabm<Space>

" ========================
" 
" Statusline
"
" ========================
"
set cmdheight=2 " space below the statusline
function! StatusDiagnostic() abort
  let info = get(b:, 'coc_diagnostic_info', {})
  if empty(info) | return '' | endif
  let msgs = []
  if get(info, 'error', 0)
    call add(msgs, 'E' . info['error'])
  endif
  if get(info, 'warning', 0)
	call add(msgs, 'W' . info['warning'])
  endif
  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
endfunction

set laststatus=2
set statusline=
set statusline+=%2*\ %f\ %*
set statusline+=%= "LHS/RHS  divider
"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
set statusline+=%1*\ %{StatusDiagnostic()} "coc diagnostics
set statusline+=%1*\ %{FugitiveStatusline()} "fugitive
set statusline+=%1*\ %l/%L\ (%c) "Line current/Linemax
set statusline+=%1*\ %m "is modified
set statusline+=%1*\ %r "is readonly

hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
hi User2 guifg=#000000 guibg=#959ca6
hi User3 guifg=#000000 guibg=#4cbf99

"set laststatus=2
"set statusline=
"set statusline+=%2*\ %l
"set statusline+=\ %*
"set statusline+=%1*\ ‹‹
"set statusline+=%1*\ %f\ %*
"set statusline+=%1*\ ››
"set statusline+=%1*\ %m
"set statusline+=%3*\ %F
"set statusline+=%=
"set statusline+=%3*\ ‹‹
"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
"set statusline+=%3*\ ::
"set statusline+=%3*\ %n
"set statusline+=%3*\ ››\ %*
"
"hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
"hi User2 guifg=#000000 guibg=#959ca6
"hi User3 guifg=#000000 guibg=#4cbf99
"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
" ========================
" 
" Cursor Specific Options
"
" ========================
set cul "cursor line is highlighted
set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
highlight Cursor guifg=white guibg=white
" ===============
" Coc.nvim 
" ===============
let g:coc_user_config = {}
let g:coc_user_config['coc.preferences.jumpCommand'] = ':vsp'
let g:coc_start_at_startup = 1
let g:coc_enable_locationlist = 1
nmap <silent> gd :call CocAction('jumpDefinition', 'vsp')<CR>
"inoremap <left> <nop>
"inoremap <right> <nop>
"inoremap <down> CocNext Coc
"inoremap <up> CocPrev
"imap <up> CocPrev

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

inoremap <silent><expr> <down>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-up> pumvisible() ? "\<C-p>" : "\<C-h>" 

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

nmap <leader>rn <Plug>(coc-rename)
" Highlight the symbol and its references when holding the cursor.
autocmd CursorHold * silent call CocActionAsync('highlight')

" Symbol renaming.

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
"noremap <Leader>gr :Gremove<CR> ===============
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
color tokyonight
color codedark
color molokai

"
"
" =============
" 
" Basic Options 
"
" =============
set title
set titlestring=%F "necessary to be able to 'toggle' configs in sxhkd
if exists('$SHELL')
    set shell=$SHELL
else
    set shell=/bin/sh
endif
filetype plugin indent on
syntax on
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
map <silent><leader>o :setlocal spell! spelllang=en_au<CR>:echo "Toggle Spellcheck"<CR>
"reload vimrc:
map <silent><leader>v :so $MYVIMRC<CR>:echo "Reloaded vimrc"<CR>
nnoremap <leader>b :ls<CR>:b<space>
"generic compile script:
nnoremap <leader>c :w<CR>:!compile %<CR>

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
" Statusline
"
" ========================
"
set cmdheight=2 " space below the statusline
function! StatusDiagnostic() abort
  let info = get(b:, 'coc_diagnostic_info', {})
  if empty(info) | return '' | endif
  let msgs = []
  if get(info, 'error', 0)
    call add(msgs, 'E' . info['error'])
  endif
  if get(info, 'warning', 0)
	call add(msgs, 'W' . info['warning'])
  endif
  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
endfunction
"set laststatus=2
"set statusline=
"set statusline+=%#function#\ %l "color theming
"set statusline+=%f "add file name to statusline %t
set laststatus=2
set statusline=
set statusline+=%1*\ %f\ %*
set statusline+=%= "LHS/RHS  divider
"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
set statusline+=%2*\ %{StatusDiagnostic()}
set statusline+=%2*\ %{FugitiveStatusline()}
set statusline+=%2*\ %l/%L "Line current/Linemax
set statusline+=%2*\ %m "is modified
set statusline+=%2*\ %r "is readonly
"set statusline+=%3*\ ‹‹
"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
"set statusline+=%3*\ ::
"set statusline+=%3*\ %n
"set statusline+=%3*\ ››\ %*

hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
hi User2 guifg=#000000 guibg=#959ca6
hi User3 guifg=#CCCCCC guibg=#444444

"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
" ========================
" 
" Cursor Specific Options
"
" ========================
set cul "cursor line is highlighted
set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
highlight Cursor guifg=white guibg=black
" ========================
" 
" Nerdtree
"
" ========================
map <C-a> :NERDTreeToggle<CR>

let g:NERDTreeWinSize=25
let g:NERDTreeChDirMode=2
let g:NERDTreeIgnore=['\.rbc$', '\~$', '\.pyc$', '\.db$', '\.sqlite$', '__pycache__']
let g:NERDTreeSortOrder=['^__\.py$', '\/$', '*', '\.swp$', '\.bak$', '\~$']
let g:NERDTreeShowBookmarks=1
let g:nerdtree_tabs_focus_on_files=1
let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
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
autocmd Filetype python map <silent><leader><leader> :w<CR>:CocCommand python.runLinting<CR>
"add #type: ignore to EOL to ignore type warnings for pyright:
autocmd Filetype python map <silent>,ignore $a #type: ignore<Esc> 
" =====
" Rust   
" =====
"
" TODO autocmd Filetype rust map <leader>t :tabe "$(git rev-parse --show-toplevel)/Cargo.toml"

autocmd Filetype rust map <silent><leader><leader> :w<CR>:!rustfmt %<CR>:!cargo check<CR>
autocmd Filetype rust map <silent><leader>r :w<CR>:!rustfmt %<CR>:!cargo run<CR>
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
" closetag
" ========================
let g:closetag_filenames = '*.html,*.xhtml,*.phtml'
let g:closetag_xhtml_filenames = '*.xhtml,*.jsx, *.tsx'
let g:closetag_xhtml_filenames = '*.xhtml,*.jsx, *.tsx'
let g:closetag_xhtml_filetypes = 'xhtml,jsx, tsx'
let g:closetag_emptyTags_caseSensitive = 1
let g:closetag_regions = {
    \ 'typescript.tsx': 'jsxRegion,tsxRegion',
    \ 'javascript.jsx': 'jsxRegion',
    \ }
let g:closetag_shortcut = '>'
let g:closetag_close_shortcut = '<leader>>'

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


" Add (Neo)Vim's native statusline support.
" NOTE: Please see `:h coc-status` for integrations with external plugins that
" provide custom statusline: lightline.vim, vim-airline.
