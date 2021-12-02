commit 8bb55580815bab1c3f6d14ac220f38b007ba5128
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Fri Oct 15 23:31:31 2021 +1000

    split off emacs org files to be managed by nextcloud, only init.el remains

diff --git a/.vimrc b/.vimrc
index bba1c3a..b1c5389 100644
--- a/.vimrc
+++ b/.vimrc
@@ -298,3 +298,8 @@ nnoremap <right> <nop>
 nnoremap <down> <nop>
 nnoremap <up> <nop>
 
+set t_u7=
+
+
+
+

commit 4ba875c6ec04f28e8bfbdb36c94353f5ef624122
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon Oct 11 16:29:51 2021 +1000

    split vimrc and init.nvim

diff --git a/.vimrc b/.vimrc
index bc64a05..bba1c3a 100644
--- a/.vimrc
+++ b/.vimrc
@@ -5,70 +5,6 @@
 "   \_/ |_|_| |_| |_|_|  \___|
 "                             
 set termguicolors
-let s:plug = '~/.vim/plugged'
-call plug#begin(s:plug)
-"coc requires node, force update of coc plugins with :CocUpdate!
-Plug 'neoclide/coc.nvim', {'branch': 'release' }
-"let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0 (old)
-" =================
-" Language Support
-" =================
-Plug 'sheerun/vim-polyglot' "all in one bundle
-Plug 'rust-lang/rust.vim'
-Plug 'tikhomirov/vim-glsl'
-Plug 'JuliaEditorSupport/julia-vim'
-Plug 'kevinoid/vim-jsonc'
-Plug 'lervag/vimtex'
-Plug 'ron-rs/ron.vim'
-Plug 'leafgarland/typescript-vim'
-Plug 'raimon49/requirements.txt.vim' "requirement.txt support
-Plug 'alvan/vim-closetag' "html tag closing
-Plug 'jupyter-vim/jupyter-vim' "see https://github.com/jupyter-vim/jupyter-vim for setup instructions
-" ====
-" Git
-" ====
-Plug 'tpope/vim-fugitive'
-" ======
-" Search/find
-" ======
-Plug 'PeterRincker/vim-searchlight'
-Plug 'preservim/nerdtree'
-Plug 'Xuyuanp/nerdtree-git-plugin'
-Plug 'ryanoasis/vim-devicons'
-" ==============
-" Miscellaneous
-" ==============
-Plug 'tpope/vim-sensible'
-Plug 'machakann/vim-highlightedyank' "highlight on yank
-Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
-Plug 'luochen1990/rainbow'
-"Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
-" =========
-" Snippets
-" =========
-Plug 'SirVer/ultisnips'
-Plug 'honza/vim-snippets'
-" ===============
-" Wiki 
-" ===============
-Plug 'vimwiki/vimwiki'
-" ===============
-" Color Schemes
-" ===============
-Plug 'tomasiser/vim-code-dark'
-Plug 'tomasr/molokai'
-Plug 'morhetz/gruvbox'
-Plug 'ghifarit53/tokyonight-vim' 
-
-Plug 'sainnhe/edge'
-"Plug 'pineapplegiant/spaceduck'
-" =======
-" Unused 
-" =======
-"Plug 'preservim/tagbar'        "requires ctags  to be installed
-"
-call plug#end()
-
 " =============
 " 
 " Basic Options 
@@ -146,61 +82,6 @@ nnoremap tl  :tablast<CR>
 nnoremap tt  :tabe<Space>
 nnoremap tm  :tabm<Space>
 
-" ========================
-" 
-" Statusline
-"
-" ========================
-"
-set cmdheight=2 " space below the statusline
-function! StatusDiagnostic() abort
-  let info = get(b:, 'coc_diagnostic_info', {})
-  if empty(info) | return '' | endif
-  let msgs = []
-  if get(info, 'error', 0)
-    call add(msgs, 'E' . info['error'])
-  endif
-  if get(info, 'warning', 0)
-	call add(msgs, 'W' . info['warning'])
-  endif
-  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
-endfunction
-
-set laststatus=2
-set statusline=
-set statusline+=%2*\ %f\ %*
-set statusline+=%= "LHS/RHS  divider
-"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
-set statusline+=%1*\ %{StatusDiagnostic()} "coc diagnostics
-set statusline+=%1*\ %{FugitiveStatusline()} "fugitive
-set statusline+=%1*\ %l/%L\ (%c) "Line current/Linemax
-set statusline+=%1*\ %m "is modified
-set statusline+=%1*\ %r "is readonly
-
-hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
-hi User2 guifg=#000000 guibg=#959ca6
-hi User3 guifg=#000000 guibg=#4cbf99
-
-"set laststatus=2
-"set statusline=
-"set statusline+=%2*\ %l
-"set statusline+=\ %*
-"set statusline+=%1*\ ‹‹
-"set statusline+=%1*\ %f\ %*
-"set statusline+=%1*\ ››
-"set statusline+=%1*\ %m
-"set statusline+=%3*\ %F
-"set statusline+=%=
-"set statusline+=%3*\ ‹‹
-"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
-"set statusline+=%3*\ ::
-"set statusline+=%3*\ %n
-"set statusline+=%3*\ ››\ %*
-"
-"hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
-"hi User2 guifg=#000000 guibg=#959ca6
-"hi User3 guifg=#000000 guibg=#4cbf99
-"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
 " ========================
 " 
 " Cursor Specific Options
@@ -209,40 +90,6 @@ hi User3 guifg=#000000 guibg=#4cbf99
 set cul "cursor line is highlighted
 set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
 highlight Cursor guifg=white guibg=white
-" ===============
-" Coc.nvim 
-" ===============
-let g:coc_global_extensions = [
-  \ 'coc-snippets',
-  \ 'coc-pairs',
-  \ 'coc-tsserver',
-  \ 'coc-eslint', 
-  \ 'coc-prettier', 
-  \ 'coc-json', 
-  \ 'coc-rust-analyzer',
-  \ 'coc-tsserver',
-  \ 'coc-html',
-  \ 'coc-css',
-  \ 'coc-sh',
-  \ 'coc-pyright',
-  \ 'coc-xml',
-  \ 'coc-julia',
-  \ 'coc-highlight',
-  \ 'coc-yaml',
-  \ 'coc-pyright',
-  \ ]
-let g:coc_user_config = {}
-let g:coc_user_config['coc.preferences.jumpCommand'] = ':vsp'
-let g:coc_start_at_startup = 1
-let g:coc_enable_locationlist = 1
-nmap <silent> gd :call CocAction('jumpDefinition', 'vsp')<CR>
-"nmap <silent> gd <Plug>(coc-definition)
-"inoremap <left> <nop>
-"inoremap <right> <nop>
-"inoremap <down> CocNext Coc
-"inoremap <up> CocPrev
-"imap <up> CocPrev
-
 set updatetime=300
 set shortmess+=c
 if has("patch-8.1.1564")
@@ -250,143 +97,8 @@ if has("patch-8.1.1564")
 else
   set signcolumn=yes
 endif
-" Use tab for trigger completion with characters ahead and navigate.
-" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
-" other plugin before putting this into your config.
-inoremap <silent><expr> <TAB>
-      \ pumvisible() ? "\<C-n>" :
-      \ <SID>check_back_space() ? "\<TAB>" :
-      \ coc#refresh()
-inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
-
-inoremap <silent><expr> <down>
-      \ pumvisible() ? "\<C-n>" :
-      \ <SID>check_back_space() ? "\<TAB>" :
-      \ coc#refresh()
-inoremap <expr><S-up> pumvisible() ? "\<C-p>" : "\<C-h>" 
-
-function! s:check_back_space() abort
-  let col = col('.') - 1
-  return !col || getline('.')[col - 1]  =~# '\s'
-endfunction
-" Use <c-space> to trigger completion.
-inoremap <silent><expr> <c-space> coc#refresh()
-" Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
-" position. Coc only does snippet and additional edit on confirm.
-" <cr> could be remapped by other vim plugin, try `:verbose imap <CR>`.
-if exists('*complete_info')
-  inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
-else
-  inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
-endif
-
-" Use `[g` and `]g` to navigate diagnostics
-" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
-nmap <silent> [g <Plug>(coc-diagnostic-prev)
-nmap <silent> ]g <Plug>(coc-diagnostic-next)
-
-
-" GoTo code navigation.
-nmap <silent> gy <Plug>(coc-type-definition)
-nmap <silent> gi <Plug>(coc-implementation)
-nmap <silent> gr <Plug>(coc-references)
-
-" Use K to show documentation in preview window.
-nnoremap <silent> K :call <SID>show_documentation()<CR>
-
-function! s:show_documentation()
-  if (index(['vim','help'], &filetype) >= 0)
-    execute 'h '.expand('<cword>')
-  else
-    call CocAction('doHover')
-  endif
-endfunction
-
-nmap <leader>rn <Plug>(coc-rename)
-" Highlight the symbol and its references when holding the cursor.
-autocmd CursorHold * silent call CocActionAsync('highlight')
 
-" Symbol renaming.
-
-" Formatting selected code.
-xmap <leader>f  <Plug>(coc-format-selected)
-nmap <leader>f  <Plug>(coc-format-selected)
-
-augroup mygroup
-  autocmd!
-  " Setup formatexpr specified filetype(s).
-  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
-  " Update signature help on jump placeholder.
-  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
-augroup end
-
-" Applying codeAction to the selected region.
-" Example: `<leader>aap` for current paragraph
-xmap <leader>a  <Plug>(coc-codeaction-selected)
-nmap <leader>a  <Plug>(coc-codeaction-selected)
-
-" Remap keys for applying codeAction to the current buffer.
-nmap <leader>ac  <Plug>(coc-codeaction)
-" Apply AutoFix to problem on the current line.
-nmap <leader>qf  <Plug>(coc-fix-current)
-
-" Map function and class text objects
-" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
-xmap if <Plug>(coc-funcobj-i)
-omap if <Plug>(coc-funcobj-i)
-xmap af <Plug>(coc-funcobj-a)
-omap af <Plug>(coc-funcobj-a)
-xmap ic <Plug>(coc-classobj-i)
-omap ic <Plug>(coc-classobj-i)
-xmap ac <Plug>(coc-classobj-a)
-omap ac <Plug>(coc-classobj-a)
-
-" Use CTRL-S for selections ranges.
-" Requires 'textDocument/selectionRange' support of LS, ex: coc-tsserver
-nmap <silent> <C-s> <Plug>(coc-range-select)
-xmap <silent> <C-s> <Plug>(coc-range-select)
-
-" Add `:Format` command to format current buffer.
-command! -nargs=0 Format :call CocAction('format')
-
-" Add `:Fold` command to fold current buffer.
-command! -nargs=? Fold :call     CocAction('fold', <f-args>)
-
-" Add `:OR` command for organize imports of the current buffer.
-command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
-
-
-" Mappings for CoCList
-" Show all diagnostics.
-nnoremap <silent><nowait> <space>a  :<C-u>CocList diagnostics<cr>
-" Manage extensions.
-nnoremap <silent><nowait> <space>e  :<C-u>CocList extensions<cr>
-" Show commands.
-nnoremap <silent><nowait> <space>c  :<C-u>CocList commands<cr>
-" Find symbol of current document.
-nnoremap <silent><nowait> <space>o  :<C-u>CocList outline<cr>
-" Search workspace symbols.
-nnoremap <silent><nowait> <space>s  :<C-u>CocList -I symbols<cr>
-" Do default action for next item.
-nnoremap <silent><nowait> <space>j  :<C-u>CocNext<CR>
-" Do default action for previous item.
-nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
-" Resume latest coc list.
-nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
-
-" ===============
-"
-" git
-"
-" ===============
-noremap <Leader>ga :Gwrite<CR>
-noremap <Leader>gc :Gcommit<CR>
-noremap <Leader>gsh :Gpush<CR>
-noremap <Leader>gll :Gpull<CR>
-noremap <Leader>gs :Gstatus<CR>
-noremap <Leader>gb :Gblame<CR>
-noremap <Leader>gd :Gvdiff<CR>
-"noremap <Leader>gr :Gremove<CR> ===============
+"===============
 "
 " Colour Options
 "
@@ -397,9 +109,9 @@ let g:tokyonight_enable_italic = 1
 let g:tokyonight_current_word = 'underline'
 let g:deus_termcolors=256
 color pablo "fallback
-color tokyonight
-color codedark
-color molokai
+"color tokyonight
+"color codedark
+"color molokai
 
 "
 "
@@ -460,50 +172,6 @@ cnoreabbrev Qall qall
 set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
 " ========================
 " 
-" Statusline
-"
-" ========================
-"
-set cmdheight=2 " space below the statusline
-function! StatusDiagnostic() abort
-  let info = get(b:, 'coc_diagnostic_info', {})
-  if empty(info) | return '' | endif
-  let msgs = []
-  if get(info, 'error', 0)
-    call add(msgs, 'E' . info['error'])
-  endif
-  if get(info, 'warning', 0)
-	call add(msgs, 'W' . info['warning'])
-  endif
-  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
-endfunction
-"set laststatus=2
-"set statusline=
-"set statusline+=%#function#\ %l "color theming
-"set statusline+=%f "add file name to statusline %t
-set laststatus=2
-set statusline=
-set statusline+=%1*\ %f\ %*
-set statusline+=%= "LHS/RHS  divider
-"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
-set statusline+=%2*\ %{StatusDiagnostic()}
-set statusline+=%2*\ %{FugitiveStatusline()}
-set statusline+=%2*\ %l/%L "Line current/Linemax
-set statusline+=%2*\ %m "is modified
-set statusline+=%2*\ %r "is readonly
-"set statusline+=%3*\ ‹‹
-"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
-"set statusline+=%3*\ ::
-"set statusline+=%3*\ %n
-"set statusline+=%3*\ ››\ %*
-
-hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
-hi User2 guifg=#000000 guibg=#959ca6
-hi User3 guifg=#CCCCCC guibg=#444444
-
-"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
-" ========================
-" 
 " Cursor Specific Options
 "
 " ========================
@@ -630,36 +298,3 @@ nnoremap <right> <nop>
 nnoremap <down> <nop>
 nnoremap <up> <nop>
 
-" ========================
-" closetag
-" ========================
-let g:closetag_filenames = '*.html,*.xhtml,*.phtml'
-let g:closetag_xhtml_filenames = '*.xhtml,*.jsx, *.tsx'
-let g:closetag_xhtml_filenames = '*.xhtml,*.jsx, *.tsx'
-let g:closetag_xhtml_filetypes = 'xhtml,jsx, tsx'
-let g:closetag_emptyTags_caseSensitive = 1
-let g:closetag_regions = {
-    \ 'typescript.tsx': 'jsxRegion,tsxRegion',
-    \ 'javascript.jsx': 'jsxRegion',
-    \ }
-let g:closetag_shortcut = '>'
-let g:closetag_close_shortcut = '<leader>>'
-
-" ========================
-" Tagbar
-" ========================
-nmap <C-s> :TagbarToggle<CR>
-let g:tagbar_autoclose = 1
-let g:tagbar_autofocus = 1
-"let g:tagbar_left = 1
-let g_tagbar_width = 15
-
-
-let g:UltiSnipsExpandTrigger="<F2>" "need to remap away from default <tab> to avoid conflict with coc autocomplete
-let g:UltiSnipsJumpForwardTrigger="<c-k>"
-let g:UltiSnipsJumpBackwardTrigger="<c-j>"
-
-
-" Add (Neo)Vim's native statusline support.
-" NOTE: Please see `:h coc-status` for integrations with external plugins that
-" provide custom statusline: lightline.vim, vim-airline.

commit 7bf06d194b764f728453ca9f3e4200c6c0d368f1
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Fri Jul 2 22:56:37 2021 +1000

    added icons to vim

diff --git a/.vimrc b/.vimrc
index 7daab31..bc64a05 100644
--- a/.vimrc
+++ b/.vimrc
@@ -6,33 +6,9 @@
 "                             
 set termguicolors
 let s:plug = '~/.vim/plugged'
-function! CocPlugins(arg)
-  CocInstall coc-rust-analyzer
-  CocInstall coc-json 
-  CocInstall coc-tsserver
-  CocInstall coc-html
-  CocInstall coc-css
-  CocInstall coc-sh
-  CocInstall coc-pyright
-  CocInstall coc-xml
-"  CocInstall coc-clangd
-  CocInstall coc-julia
-  CocInstall coc-highlight
-  CocInstall coc-yaml
-  CocInstall coc-pyright
-  CocEnable
-endfunction
-" ==========
-"
-" Plugins
-" ==========
-" =============
-" Autocomplete
-" =============
-"
 call plug#begin(s:plug)
 "coc requires node, force update of coc plugins with :CocUpdate!
-Plug 'neoclide/coc.nvim', {'branch': 'release', 'do': function('CocPlugins') }
+Plug 'neoclide/coc.nvim', {'branch': 'release' }
 "let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0 (old)
 " =================
 " Language Support
@@ -57,6 +33,8 @@ Plug 'tpope/vim-fugitive'
 " ======
 Plug 'PeterRincker/vim-searchlight'
 Plug 'preservim/nerdtree'
+Plug 'Xuyuanp/nerdtree-git-plugin'
+Plug 'ryanoasis/vim-devicons'
 " ==============
 " Miscellaneous
 " ==============
@@ -234,6 +212,25 @@ highlight Cursor guifg=white guibg=white
 " ===============
 " Coc.nvim 
 " ===============
+let g:coc_global_extensions = [
+  \ 'coc-snippets',
+  \ 'coc-pairs',
+  \ 'coc-tsserver',
+  \ 'coc-eslint', 
+  \ 'coc-prettier', 
+  \ 'coc-json', 
+  \ 'coc-rust-analyzer',
+  \ 'coc-tsserver',
+  \ 'coc-html',
+  \ 'coc-css',
+  \ 'coc-sh',
+  \ 'coc-pyright',
+  \ 'coc-xml',
+  \ 'coc-julia',
+  \ 'coc-highlight',
+  \ 'coc-yaml',
+  \ 'coc-pyright',
+  \ ]
 let g:coc_user_config = {}
 let g:coc_user_config['coc.preferences.jumpCommand'] = ':vsp'
 let g:coc_start_at_startup = 1
@@ -527,6 +524,19 @@ let g:NERDTreeSortOrder=['^__\.py$', '\/$', '*', '\.swp$', '\.bak$', '\~$']
 let g:NERDTreeShowBookmarks=1
 let g:nerdtree_tabs_focus_on_files=1
 let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
+let g:NERDTreeGitStatusUseNerdFonts = 1
+let g:NERDTreeGitStatusIndicatorMapCustom = {
+                \ 'Modified'  :'✹',
+                \ 'Staged'    :'✚',
+                \ 'Untracked' :'✭',
+                \ 'Renamed'   :'➜',
+                \ 'Unmerged'  :'═',
+                \ 'Deleted'   :'✖',
+                \ 'Dirty'     :'✗',
+                \ 'Ignored'   :'☒',
+                \ 'Clean'     :'✔︎',
+                \ 'Unknown'   :'?',
+                \ }
 " =========================
 " 
 " Jupyter Vim

commit f4f98fa7e7dcdc6839eeaf436972fe7d027bbf52
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon Jun 14 12:57:41 2021 +1000

    aabbccdd

diff --git a/.vimrc b/.vimrc
index 59bad95..7daab31 100644
--- a/.vimrc
+++ b/.vimrc
@@ -16,6 +16,7 @@ function! CocPlugins(arg)
   CocInstall coc-pyright
   CocInstall coc-xml
 "  CocInstall coc-clangd
+  CocInstall coc-julia
   CocInstall coc-highlight
   CocInstall coc-yaml
   CocInstall coc-pyright
@@ -46,6 +47,7 @@ Plug 'ron-rs/ron.vim'
 Plug 'leafgarland/typescript-vim'
 Plug 'raimon49/requirements.txt.vim' "requirement.txt support
 Plug 'alvan/vim-closetag' "html tag closing
+Plug 'jupyter-vim/jupyter-vim' "see https://github.com/jupyter-vim/jupyter-vim for setup instructions
 " ====
 " Git
 " ====
@@ -61,6 +63,7 @@ Plug 'preservim/nerdtree'
 Plug 'tpope/vim-sensible'
 Plug 'machakann/vim-highlightedyank' "highlight on yank
 Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
+Plug 'luochen1990/rainbow'
 "Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
 " =========
 " Snippets
@@ -236,6 +239,7 @@ let g:coc_user_config['coc.preferences.jumpCommand'] = ':vsp'
 let g:coc_start_at_startup = 1
 let g:coc_enable_locationlist = 1
 nmap <silent> gd :call CocAction('jumpDefinition', 'vsp')<CR>
+"nmap <silent> gd <Plug>(coc-definition)
 "inoremap <left> <nop>
 "inoremap <right> <nop>
 "inoremap <down> CocNext Coc
@@ -525,11 +529,26 @@ let g:nerdtree_tabs_focus_on_files=1
 let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
 " =========================
 " 
+" Jupyter Vim
+"
+" =========================
+let g:jupyter_mapkeys = 1
+" =========================
+" 
 " Filetype Specfic Options
 "
 " =========================
 "
 " =====
+" vimrc
+" =====
+if has('autocmd') " ignore this section if your vim does not support autocommands
+    augroup reload_vimrc
+        autocmd!
+        autocmd! BufWritePost $MYVIMRC,$MYGVIMRC nested source %
+    augroup END
+endif
+" =====
 " Make
 " =====
 autocmd Filetype make set noexpandtab "force tabs for make
@@ -552,6 +571,8 @@ autocmd Filetype python map <silent>,ignore $a #type: ignore<Esc>
 "
 " TODO autocmd Filetype rust map <leader>t :tabe "$(git rev-parse --show-toplevel)/Cargo.toml"
 
+let g:rustfmt_autosave = 1
+let g:rust_cargo_use_clippy = 1
 autocmd Filetype rust map <silent><leader><leader> :w<CR>:!rustfmt %<CR>:!cargo check<CR>
 autocmd Filetype rust map <silent><leader>r :w<CR>:!rustfmt %<CR>:!cargo run<CR>
 " =====
@@ -566,12 +587,16 @@ nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 " =================
 "  Yank Highlighting
 " =================
-let g:highlightedyank_highlight_duration = 1000
+let g:highlightedyank_highlight_duration = 700
 " =================
 "  Lastplace Cursor
 " =================
 let g:lastplace_ignore = "gitcommit,gitrebase,svn,hgcommit"
 " ========================
+" Rainbow Brackets
+" ========================
+let g:rainbow_active = 1 "set to 0 if you want to enable it later via :RainbowToggle
+" ========================
 " Fix Search Highlighting
 " ========================
 nmap <silent> <Esc> :nohlsearch<CR>

commit 7d027b7f382034582e86761074b4acd16bef5582
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Fri Mar 26 22:14:46 2021 +1000

    aabb

diff --git a/.vimrc b/.vimrc
index 75404e8..59bad95 100644
--- a/.vimrc
+++ b/.vimrc
@@ -4,7 +4,7 @@
 "  \ V /| | | | | | | | | (__ 
 "   \_/ |_|_| |_| |_|_|  \___|
 "                             
-"set termguicolors
+set termguicolors
 let s:plug = '~/.vim/plugged'
 function! CocPlugins(arg)
   CocInstall coc-rust-analyzer
@@ -68,13 +68,17 @@ Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
 Plug 'SirVer/ultisnips'
 Plug 'honza/vim-snippets'
 " ===============
+" Wiki 
+" ===============
+Plug 'vimwiki/vimwiki'
+" ===============
 " Color Schemes
 " ===============
 Plug 'tomasiser/vim-code-dark'
 Plug 'tomasr/molokai'
 Plug 'morhetz/gruvbox'
 Plug 'ghifarit53/tokyonight-vim' 
-Plug 'ajmwagar/vim-deus' 
+
 Plug 'sainnhe/edge'
 "Plug 'pineapplegiant/spaceduck'
 " =======
@@ -117,18 +121,23 @@ set nocompatible
 set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
 call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
 set hidden
+
+" ========================
+" 
+"  Basic Keybindings
+"
+" ========================
 let mapleader =" "
 "toggle spellchecker:
 map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
 "reload vimrc:
-map <silent><leader>v :so $MYVIMRC<CR> 
-nnoremap <leader>b :ls<CR>:b<space>
+map <silent><leader>v :so $MYVIMRC<CR>:echo "Reloaded $MYVIMRC"
 "generic compile script:
 nnoremap <leader>c :!compile %<CR>
 
 " Search mappings: Going to the next one in a search will center on the line it's found in.
-nnoremap n nzzzv
-nnoremap N Nzzzv
+"nnoremap n nzzzv
+"nnoremap N Nzzzv
 "Abbreviations
 cnoreabbrev W! w!
 cnoreabbrev Q! q!
@@ -142,6 +151,20 @@ cnoreabbrev Q q
 cnoreabbrev Qall qall
 set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
 
+" ========================
+" 
+" Tab Navigation
+"
+" ========================
+nnoremap tk :tabnext<CR>
+nnoremap tj :tabprev<CR>
+nnoremap tn :tabnew<CR>
+nnoremap td  :tabclose<CR>
+nnoremap th  :tabfirst<CR>
+nnoremap tl  :tablast<CR>
+nnoremap tt  :tabe<Space>
+nnoremap tm  :tabm<Space>
+
 " ========================
 " 
 " Statusline
@@ -204,7 +227,7 @@ hi User3 guifg=#000000 guibg=#4cbf99
 " ========================
 set cul "cursor line is highlighted
 set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
-highlight Cursor guifg=white guibg=black
+highlight Cursor guifg=white guibg=white
 " ===============
 " Coc.nvim 
 " ===============
@@ -412,9 +435,9 @@ call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
 set hidden
 let mapleader =" "
 "toggle spellchecker:
-map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
+map <silent><leader>o :setlocal spell! spelllang=en_au<CR>:echo "Toggle Spellcheck"<CR>
 "reload vimrc:
-map <silent><leader>v :so $MYVIMRC<CR> 
+map <silent><leader>v :so $MYVIMRC<CR>:echo "Reloaded vimrc"<CR>
 nnoremap <leader>b :ls<CR>:b<space>
 "generic compile script:
 nnoremap <leader>c :w<CR>:!compile %<CR>
@@ -526,7 +549,11 @@ autocmd Filetype python map <silent>,ignore $a #type: ignore<Esc>
 " =====
 " Rust   
 " =====
+"
+" TODO autocmd Filetype rust map <leader>t :tabe "$(git rev-parse --show-toplevel)/Cargo.toml"
+
 autocmd Filetype rust map <silent><leader><leader> :w<CR>:!rustfmt %<CR>:!cargo check<CR>
+autocmd Filetype rust map <silent><leader>r :w<CR>:!rustfmt %<CR>:!cargo run<CR>
 " =====
 " Mutt   
 " =====

commit 1b2e4fd3f9f1f47f1b4a5f6e516bb4ae71541a9f
Merge: bbcf16e 484af51
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 9 12:29:30 2021 +1000

    Merge branch 'master' of github.com:maxwellodri/dotfiles
    merge

commit bbcf16eb301c6898599260a0e5ac873ef657ce03
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 9 12:29:25 2021 +1000

    premerge

diff --git a/.vimrc b/.vimrc
index 7ff9d66..49b8824 100644
--- a/.vimrc
+++ b/.vimrc
@@ -16,6 +16,7 @@ function! CocPlugins(arg)
   CocInstall coc-css
   CocInstall coc-sh
   CocInstall coc-pyright
+  CocInstall coc-xml
 "  CocInstall coc-clangd
   CocInstall coc-highlight
   CocInstall coc-yaml
@@ -296,7 +297,7 @@ map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
 map <silent><leader>v :so $MYVIMRC<CR> 
 nnoremap <leader>b :ls<CR>:b<space>
 "generic compile script:
-nnoremap <leader>c :w<CR>!compile %<CR>
+nnoremap <leader>c :w<CR>:!compile %<CR>
 
 " Search mappings: Going to the next one in a search will center on the line it's found in.
 nnoremap n nzzzv

commit 484af51c700a15dfd2955a3c192a07d1cc0d4ea6
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 9 12:25:11 2021 +1000

    a

diff --git a/.vimrc b/.vimrc
index db32854..2929f47 100644
--- a/.vimrc
+++ b/.vimrc
@@ -4,7 +4,7 @@
 "  \ V /| | | | | | | | | (__ 
 "   \_/ |_|_| |_| |_|_|  \___|
 "                             
-set termguicolors
+"set termguicolors
 let s:plug = '~/.vim/plugged'
 function! CocPlugins(arg)
   CocInstall coc-rust-analyzer

commit a770651742a306038b50e737f35dccc7883a09b9
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 9 00:56:18 2021 +1000

    thinkpad, tmux, zprofile, dstatus battery indicator updated

diff --git a/.vimrc b/.vimrc
index 37e27d9..db32854 100644
--- a/.vimrc
+++ b/.vimrc
@@ -44,6 +44,7 @@ Plug 'lervag/vimtex'
 Plug 'ron-rs/ron.vim'
 Plug 'leafgarland/typescript-vim'
 Plug 'raimon49/requirements.txt.vim' "requirement.txt support
+Plug 'alvan/vim-closetag' "html tag closing
 " ====
 " Git
 " ====
@@ -566,8 +567,24 @@ nnoremap <right> <nop>
 nnoremap <down> <nop>
 nnoremap <up> <nop>
 
+" ========================
+" closetag
+" ========================
+let g:closetag_filenames = '*.html,*.xhtml,*.phtml'
+let g:closetag_xhtml_filenames = '*.xhtml,*.jsx, *.tsx'
+let g:closetag_xhtml_filenames = '*.xhtml,*.jsx, *.tsx'
+let g:closetag_xhtml_filetypes = 'xhtml,jsx, tsx'
+let g:closetag_emptyTags_caseSensitive = 1
+let g:closetag_regions = {
+    \ 'typescript.tsx': 'jsxRegion,tsxRegion',
+    \ 'javascript.jsx': 'jsxRegion',
+    \ }
+let g:closetag_shortcut = '>'
+let g:closetag_close_shortcut = '<leader>>'
 
-"Tagbar:
+" ========================
+" Tagbar
+" ========================
 nmap <C-s> :TagbarToggle<CR>
 let g:tagbar_autoclose = 1
 let g:tagbar_autofocus = 1

commit 62086191bcc05e8ee5a5cb94f17e04061154dd1f
Merge: 2ac32f6 58dadfc
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 2 23:50:56 2021 +1000

    fixed merge

commit 2ac32f6be6affa0ab13587b7cd0779ee0544422c
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 2 23:48:34 2021 +1000

    vimrc

diff --git a/.vimrc b/.vimrc
index afebd36..f495d29 100644
--- a/.vimrc
+++ b/.vimrc
@@ -4,8 +4,6 @@
 "  \ V /| | | | | | | | | (__ 
 "   \_/ |_|_| |_| |_|_|  \___|
 "                             
-
-filetype on
 set termguicolors
 let s:plug = '~/.vim/plugged'
 function! CocPlugins(arg)
@@ -61,7 +59,7 @@ Plug 'preservim/nerdtree'
 Plug 'tpope/vim-sensible'
 Plug 'machakann/vim-highlightedyank' "highlight on yank
 Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
-Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
+"Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
 " =========
 " Snippets
 " =========
@@ -84,6 +82,127 @@ Plug 'sainnhe/edge'
 "
 call plug#end()
 
+" =============
+" 
+" Basic Options 
+"
+" =============
+filetype on
+"set termguicolors
+set title
+set titlestring=%F "necessary to be able to 'toggle' configs in sxhkd
+if exists('$SHELL')
+    set shell=$SHELL
+else
+    set shell=/bin/sh
+endif
+filetype plugin indent on
+syntax on
+set sessionoptions-=options
+set tabstop=4
+set softtabstop=2
+set expandtab
+set smarttab
+set autoindent
+set path+=** ""recursive subdirectory search
+set wildmenu
+set wildmode=longest,list,full
+set encoding=utf-8
+syntax enable
+set clipboard=unnamedplus
+set number
+set nocompatible
+set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
+call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
+set hidden
+let mapleader =" "
+"toggle spellchecker:
+map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
+"reload vimrc:
+map <silent><leader>v :so $MYVIMRC<CR> 
+nnoremap <leader>b :ls<CR>:b<space>
+"generic compile script:
+nnoremap <leader>c :!compile %<CR>
+
+" Search mappings: Going to the next one in a search will center on the line it's found in.
+nnoremap n nzzzv
+nnoremap N Nzzzv
+"Abbreviations
+cnoreabbrev W! w!
+cnoreabbrev Q! q!
+cnoreabbrev Qall! qall!
+cnoreabbrev Wq wq
+cnoreabbrev Wa wa
+cnoreabbrev wQ wq
+cnoreabbrev WQ wq
+cnoreabbrev W w
+cnoreabbrev Q q
+cnoreabbrev Qall qall
+set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
+
+" ========================
+" 
+" Statusline
+"
+" ========================
+"
+set cmdheight=2 " space below the statusline
+function! StatusDiagnostic() abort
+  let info = get(b:, 'coc_diagnostic_info', {})
+  if empty(info) | return '' | endif
+  let msgs = []
+  if get(info, 'error', 0)
+    call add(msgs, 'E' . info['error'])
+  endif
+  if get(info, 'warning', 0)
+	call add(msgs, 'W' . info['warning'])
+  endif
+  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
+endfunction
+
+set laststatus=2
+set statusline=
+set statusline+=%2*\ %f\ %*
+set statusline+=%= "LHS/RHS  divider
+"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
+set statusline+=%1*\ %{StatusDiagnostic()} "coc diagnostics
+set statusline+=%1*\ %{FugitiveStatusline()} "fugitive
+set statusline+=%1*\ %l/%L\ (%c) "Line current/Linemax
+set statusline+=%1*\ %m "is modified
+set statusline+=%1*\ %r "is readonly
+
+hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
+hi User2 guifg=#000000 guibg=#959ca6
+hi User3 guifg=#000000 guibg=#4cbf99
+
+"set laststatus=2
+"set statusline=
+"set statusline+=%2*\ %l
+"set statusline+=\ %*
+"set statusline+=%1*\ ‹‹
+"set statusline+=%1*\ %f\ %*
+"set statusline+=%1*\ ››
+"set statusline+=%1*\ %m
+"set statusline+=%3*\ %F
+"set statusline+=%=
+"set statusline+=%3*\ ‹‹
+"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
+"set statusline+=%3*\ ::
+"set statusline+=%3*\ %n
+"set statusline+=%3*\ ››\ %*
+"
+"hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
+"hi User2 guifg=#000000 guibg=#959ca6
+"hi User3 guifg=#000000 guibg=#4cbf99
+"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
+" ========================
+" 
+" Cursor Specific Options
+"
+" ========================
+set cul "cursor line is highlighted
+set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
+highlight Cursor guifg=white guibg=black
 " ===============
 " Coc.nvim 
 " ===============
@@ -257,115 +376,6 @@ color tokyonight
 color codedark
 color molokai
 
-"
-"
-" =============
-" 
-" Basic Options 
-"
-" =============
-set title
-set titlestring=%F "necessary to be able to 'toggle' configs in sxhkd
-if exists('$SHELL')
-    set shell=$SHELL
-else
-    set shell=/bin/sh
-endif
-filetype plugin indent on
-syntax on
-set sessionoptions-=options
-set tabstop=4
-set softtabstop=2
-set expandtab
-set smarttab
-set autoindent
-set path+=** ""recursive subdirectory search
-set wildmenu
-set wildmode=longest,list,full
-set encoding=utf-8
-syntax enable
-set clipboard=unnamedplus
-set number
-set nocompatible
-set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
-call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
-set hidden
-let mapleader =" "
-"toggle spellchecker:
-map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
-"reload vimrc:
-map <silent><leader>v :so $MYVIMRC<CR> 
-nnoremap <leader>b :ls<CR>:b<space>
-"generic compile script:
-nnoremap <leader>c :!compile %<CR>
-
-" Search mappings: Going to the next one in a search will center on the line it's found in.
-nnoremap n nzzzv
-nnoremap N Nzzzv
-"Abbreviations
-cnoreabbrev W! w!
-cnoreabbrev Q! q!
-cnoreabbrev Qall! qall!
-cnoreabbrev Wq wq
-cnoreabbrev Wa wa
-cnoreabbrev wQ wq
-cnoreabbrev WQ wq
-cnoreabbrev W w
-cnoreabbrev Q q
-cnoreabbrev Qall qall
-set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
-" ========================
-" 
-" Statusline
-"
-" ========================
-"
-set cmdheight=2 " space below the statusline
-function! StatusDiagnostic() abort
-  let info = get(b:, 'coc_diagnostic_info', {})
-  if empty(info) | return '' | endif
-  let msgs = []
-  if get(info, 'error', 0)
-    call add(msgs, 'E' . info['error'])
-  endif
-  if get(info, 'warning', 0)
-	call add(msgs, 'W' . info['warning'])
-  endif
-  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
-endfunction
-"set laststatus=2
-"set statusline=
-"set statusline+=%#function#\ %l "color theming
-"set statusline+=%f "add file name to statusline %t
-set laststatus=2
-set statusline=
-set statusline+=%1*\ %f\ %*
-set statusline+=%= "LHS/RHS  divider
-"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
-set statusline+=%2*\ %{StatusDiagnostic()}
-set statusline+=%2*\ %{FugitiveStatusline()}
-set statusline+=%2*\ %l/%L "Line current/Linemax
-set statusline+=%2*\ %m "is modified
-set statusline+=%2*\ %r "is readonly
-"set statusline+=%3*\ ‹‹
-"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
-"set statusline+=%3*\ ::
-"set statusline+=%3*\ %n
-"set statusline+=%3*\ ››\ %*
-
-hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
-hi User2 guifg=#000000 guibg=#959ca6
-hi User3 guifg=#CCCCCC guibg=#444444
-
-"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
-" ========================
-" 
-" Cursor Specific Options
-"
-" ========================
-set cul "cursor line is highlighted
-set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
-highlight Cursor guifg=white guibg=black
 " ========================
 " 
 " Nerdtree

commit 0f2c1f85599e2b3e4b7bd8afbc85f01746b7d5d6
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Mar 2 10:46:22 2021 +1000

    premerge

diff --git a/.vimrc b/.vimrc
index afebd36..7ff9d66 100644
--- a/.vimrc
+++ b/.vimrc
@@ -241,8 +241,7 @@ noremap <Leader>gll :Gpull<CR>
 noremap <Leader>gs :Gstatus<CR>
 noremap <Leader>gb :Gblame<CR>
 noremap <Leader>gd :Gvdiff<CR>
-"noremap <Leader>gr :Gremove<CR>
-" ===============
+"noremap <Leader>gr :Gremove<CR> ===============
 "
 " Colour Options
 "
@@ -297,7 +296,7 @@ map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
 map <silent><leader>v :so $MYVIMRC<CR> 
 nnoremap <leader>b :ls<CR>:b<space>
 "generic compile script:
-nnoremap <leader>c :!compile %<CR>
+nnoremap <leader>c :w<CR>!compile %<CR>
 
 " Search mappings: Going to the next one in a search will center on the line it's found in.
 nnoremap n nzzzv

commit dac4f306d71bd4077a3259a5d7b7067b4a6c9ab3
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Sun Feb 28 14:54:55 2021 +1000

    updated imrc

diff --git a/.vimrc b/.vimrc
index 5799c66..afebd36 100644
--- a/.vimrc
+++ b/.vimrc
@@ -15,6 +15,7 @@ function! CocPlugins(arg)
   CocInstall coc-html
   CocInstall coc-css
   CocInstall coc-sh
+  CocInstall coc-pyright
 "  CocInstall coc-clangd
   CocInstall coc-highlight
   CocInstall coc-yaml
@@ -44,6 +45,7 @@ Plug 'kevinoid/vim-jsonc'
 Plug 'lervag/vimtex'
 Plug 'ron-rs/ron.vim'
 Plug 'leafgarland/typescript-vim'
+Plug 'raimon49/requirements.txt.vim' "requirement.txt support
 " ====
 " Git
 " ====
@@ -57,6 +59,9 @@ Plug 'preservim/nerdtree'
 " Miscellaneous
 " ==============
 Plug 'tpope/vim-sensible'
+Plug 'machakann/vim-highlightedyank' "highlight on yank
+Plug 'farmergreg/vim-lastplace' "Keep cursor on quit
+Plug 'Raimondi/delimitMate' "auto create quotes, bracket pairs 
 " =========
 " Snippets
 " =========
@@ -82,15 +87,17 @@ call plug#end()
 " ===============
 " Coc.nvim 
 " ===============
+let g:coc_user_config = {}
+let g:coc_user_config['coc.preferences.jumpCommand'] = ':vsp'
 let g:coc_start_at_startup = 1
 let g:coc_enable_locationlist = 1
+nmap <silent> gd :call CocAction('jumpDefinition', 'vsp')<CR>
 "inoremap <left> <nop>
 "inoremap <right> <nop>
 "inoremap <down> CocNext Coc
 "inoremap <up> CocPrev
 "imap <up> CocPrev
 
-set cmdheight=2
 set updatetime=300
 set shortmess+=c
 if has("patch-8.1.1564")
@@ -135,7 +142,6 @@ nmap <silent> ]g <Plug>(coc-diagnostic-next)
 
 
 " GoTo code navigation.
-nmap <silent> gd <Plug>(coc-definition)
 nmap <silent> gy <Plug>(coc-type-definition)
 nmap <silent> gi <Plug>(coc-implementation)
 nmap <silent> gr <Plug>(coc-references)
@@ -223,6 +229,19 @@ nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
 " Resume latest coc list.
 nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
 
+" ===============
+"
+" git
+"
+" ===============
+noremap <Leader>ga :Gwrite<CR>
+noremap <Leader>gc :Gcommit<CR>
+noremap <Leader>gsh :Gpush<CR>
+noremap <Leader>gll :Gpull<CR>
+noremap <Leader>gs :Gstatus<CR>
+noremap <Leader>gb :Gblame<CR>
+noremap <Leader>gd :Gvdiff<CR>
+"noremap <Leader>gr :Gremove<CR>
 " ===============
 "
 " Colour Options
@@ -245,6 +264,13 @@ color molokai
 " Basic Options 
 "
 " =============
+set title
+set titlestring=%F "necessary to be able to 'toggle' configs in sxhkd
+if exists('$SHELL')
+    set shell=$SHELL
+else
+    set shell=/bin/sh
+endif
 filetype plugin indent on
 syntax on
 set sessionoptions-=options
@@ -265,14 +291,36 @@ set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
 call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
 set hidden
 let mapleader =" "
-map <leader>o :setlocal spell! spelllang=en_au<CR>
-
+"toggle spellchecker:
+map <silent><leader>o :setlocal spell! spelllang=en_au<CR>
+"reload vimrc:
+map <silent><leader>v :so $MYVIMRC<CR> 
+nnoremap <leader>b :ls<CR>:b<space>
+"generic compile script:
+nnoremap <leader>c :!compile %<CR>
+
+" Search mappings: Going to the next one in a search will center on the line it's found in.
+nnoremap n nzzzv
+nnoremap N Nzzzv
+"Abbreviations
+cnoreabbrev W! w!
+cnoreabbrev Q! q!
+cnoreabbrev Qall! qall!
+cnoreabbrev Wq wq
+cnoreabbrev Wa wa
+cnoreabbrev wQ wq
+cnoreabbrev WQ wq
+cnoreabbrev W w
+cnoreabbrev Q q
+cnoreabbrev Qall qall
+set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.pyc,*.db,*.sqlite
 " ========================
 " 
 " Statusline
 "
 " ========================
 "
+set cmdheight=2 " space below the statusline
 function! StatusDiagnostic() abort
   let info = get(b:, 'coc_diagnostic_info', {})
   if empty(info) | return '' | endif
@@ -309,6 +357,7 @@ hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
 hi User2 guifg=#000000 guibg=#959ca6
 hi User3 guifg=#CCCCCC guibg=#444444
 
+"set statusline=%F%m%r%h%w%=(%{&ff}/%Y)\ (line\ %l\/%L,\ col\ %c)\
 " ========================
 " 
 " Cursor Specific Options
@@ -322,8 +371,15 @@ highlight Cursor guifg=white guibg=black
 " Nerdtree
 "
 " ========================
-let g:NERDTreeWinSize=25
 map <C-a> :NERDTreeToggle<CR>
+
+let g:NERDTreeWinSize=25
+let g:NERDTreeChDirMode=2
+let g:NERDTreeIgnore=['\.rbc$', '\~$', '\.pyc$', '\.db$', '\.sqlite$', '__pycache__']
+let g:NERDTreeSortOrder=['^__\.py$', '\/$', '*', '\.swp$', '\.bak$', '\~$']
+let g:NERDTreeShowBookmarks=1
+let g:nerdtree_tabs_focus_on_files=1
+let g:NERDTreeMapOpenInTabSilent = '<RightMouse>'
 " =========================
 " 
 " Filetype Specfic Options
@@ -340,10 +396,17 @@ autocmd Filetype make set noexpandtab "force tabs for make
 autocmd Filetype python set tabstop=4 
 autocmd Filetype python set softtabstop=4
 autocmd Filetype python set shiftwidth=4
-"autocmd Filetype python set textwidth=79 "pep conformance except this line
+autocmd Filetype python set textwidth=79 "pep conformance 🤔
 autocmd Filetype python set autoindent 
 autocmd Filetype python set expandtab
 autocmd Filetype python set fileformat=unix 
+autocmd Filetype python map <silent><leader><leader> :w<CR>:CocCommand python.runLinting<CR>
+"add #type: ignore to EOL to ignore type warnings for pyright:
+autocmd Filetype python map <silent>,ignore $a #type: ignore<Esc> 
+" =====
+" Rust   
+" =====
+autocmd Filetype rust map <silent><leader><leader> :w<CR>:!rustfmt %<CR>:!cargo check<CR>
 " =====
 " Mutt   
 " =====
@@ -354,29 +417,26 @@ au BufRead /tmp/mutt-* set tw=72
 nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
 nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 " =================
-"  Compile from vim
+"  Yank Highlighting
 " =================
-"command! Texit !pdflatex % 
-"command PP !python %
-"command! Maketags !ctags -R
-"autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
-"usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
-"stack
-"
+let g:highlightedyank_highlight_duration = 1000
+" =================
+"  Lastplace Cursor
+" =================
+let g:lastplace_ignore = "gitcommit,gitrebase,svn,hgcommit"
 " ========================
 " Fix Search Highlighting
 " ========================
 nmap <silent> <Esc> :nohlsearch<CR>
 imap <silent> <Esc> <Esc>:nohlsearch<CR>
-
-
-
-"Remaps:
-    set splitbelow splitright
-    map <C-h> <C-w>h
-    map <C-j> <C-w>j
-    map <C-k> <C-w>k
-    map <C-l> <C-w>l
+" ========================
+" Splits
+" ========================
+set splitbelow splitright
+map <C-h> <C-w>h
+map <C-j> <C-w>j
+map <C-k> <C-w>k
+map <C-l> <C-w>l
 
 inoremap <left> <nop>
 inoremap <right> <nop>
@@ -401,7 +461,6 @@ let g:UltiSnipsExpandTrigger="<F2>" "need to remap away from default <tab> to av
 let g:UltiSnipsJumpForwardTrigger="<c-k>"
 let g:UltiSnipsJumpBackwardTrigger="<c-j>"
 
-map <leader><leader> :w<CR>:!rustfmt %<CR>
 
 " Add (Neo)Vim's native statusline support.
 " NOTE: Please see `:h coc-status` for integrations with external plugins that

commit f9c76bf914d51dedc6aef35a5d12b4994613f862
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon Feb 22 17:04:44 2021 +1000

    started lemonbar+dwm

diff --git a/.vimrc b/.vimrc
index 81fe6a0..5799c66 100644
--- a/.vimrc
+++ b/.vimrc
@@ -49,9 +49,10 @@ Plug 'leafgarland/typescript-vim'
 " ====
 Plug 'tpope/vim-fugitive'
 " ======
-" Search
+" Search/find
 " ======
 Plug 'PeterRincker/vim-searchlight'
+Plug 'preservim/nerdtree'
 " ==============
 " Miscellaneous
 " ==============
@@ -75,9 +76,6 @@ Plug 'sainnhe/edge'
 " Unused 
 " =======
 "Plug 'preservim/tagbar'        "requires ctags  to be installed
-"Plug 'preservim/nerdtree'
-"let g:NERDTreeWinSize=15
-"map <C-a> :NERDTreeToggle<CR>
 "
 call plug#end()
 
@@ -85,6 +83,7 @@ call plug#end()
 " Coc.nvim 
 " ===============
 let g:coc_start_at_startup = 1
+let g:coc_enable_locationlist = 1
 "inoremap <left> <nop>
 "inoremap <right> <nop>
 "inoremap <down> CocNext Coc
@@ -205,9 +204,6 @@ command! -nargs=? Fold :call     CocAction('fold', <f-args>)
 " Add `:OR` command for organize imports of the current buffer.
 command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
 
-" Add (Neo)Vim's native statusline support.
-" NOTE: Please see `:h coc-status` for integrations with external plugins that
-" provide custom statusline: lightline.vim, vim-airline.
 
 " Mappings for CoCList
 " Show all diagnostics.
@@ -251,9 +247,6 @@ color molokai
 " =============
 filetype plugin indent on
 syntax on
-set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
-set statusline+=%{FugitiveStatusline()}
-set statusline+=%t "add file name to statusline
 set sessionoptions-=options
 set tabstop=4
 set softtabstop=2
@@ -274,6 +267,48 @@ set hidden
 let mapleader =" "
 map <leader>o :setlocal spell! spelllang=en_au<CR>
 
+" ========================
+" 
+" Statusline
+"
+" ========================
+"
+function! StatusDiagnostic() abort
+  let info = get(b:, 'coc_diagnostic_info', {})
+  if empty(info) | return '' | endif
+  let msgs = []
+  if get(info, 'error', 0)
+    call add(msgs, 'E' . info['error'])
+  endif
+  if get(info, 'warning', 0)
+	call add(msgs, 'W' . info['warning'])
+  endif
+  return join(msgs, ' ') . ' ' . get(g:, 'coc_status', '')
+endfunction
+"set laststatus=2
+"set statusline=
+"set statusline+=%#function#\ %l "color theming
+"set statusline+=%f "add file name to statusline %t
+set laststatus=2
+set statusline=
+set statusline+=%1*\ %f\ %*
+set statusline+=%= "LHS/RHS  divider
+"set statusline+=%2*\ %{coc#status()}%{get(b:,'coc_current_function','')}
+set statusline+=%2*\ %{StatusDiagnostic()}
+set statusline+=%2*\ %{FugitiveStatusline()}
+set statusline+=%2*\ %l/%L "Line current/Linemax
+set statusline+=%2*\ %m "is modified
+set statusline+=%2*\ %r "is readonly
+"set statusline+=%3*\ ‹‹
+"set statusline+=%3*\ %{strftime('%R',getftime(expand('%')))}
+"set statusline+=%3*\ ::
+"set statusline+=%3*\ %n
+"set statusline+=%3*\ ››\ %*
+
+hi User1 guifg=#FFFFFF guibg=#191f26 gui=BOLD
+hi User2 guifg=#000000 guibg=#959ca6
+hi User3 guifg=#CCCCCC guibg=#444444
+
 " ========================
 " 
 " Cursor Specific Options
@@ -282,6 +317,13 @@ map <leader>o :setlocal spell! spelllang=en_au<CR>
 set cul "cursor line is highlighted
 set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
 highlight Cursor guifg=white guibg=black
+" ========================
+" 
+" Nerdtree
+"
+" ========================
+let g:NERDTreeWinSize=25
+map <C-a> :NERDTreeToggle<CR>
 " =========================
 " 
 " Filetype Specfic Options
@@ -324,8 +366,8 @@ nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 " ========================
 " Fix Search Highlighting
 " ========================
-nmap <Esc> :nohlsearch<CR>
-imap <Esc> <Esc>:nohlsearch<CR>
+nmap <silent> <Esc> :nohlsearch<CR>
+imap <silent> <Esc> <Esc>:nohlsearch<CR>
 
 
 
@@ -360,3 +402,7 @@ let g:UltiSnipsJumpForwardTrigger="<c-k>"
 let g:UltiSnipsJumpBackwardTrigger="<c-j>"
 
 map <leader><leader> :w<CR>:!rustfmt %<CR>
+
+" Add (Neo)Vim's native statusline support.
+" NOTE: Please see `:h coc-status` for integrations with external plugins that
+" provide custom statusline: lightline.vim, vim-airline.

commit b32ccf53314c459cac56ed4c9387fe91399d0191
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Feb 16 12:24:32 2021 +1000

    start bspwm transition

diff --git a/.vimrc b/.vimrc
index 524a098..81fe6a0 100644
--- a/.vimrc
+++ b/.vimrc
@@ -5,24 +5,25 @@
 "   \_/ |_|_| |_| |_|_|  \___|
 "                             
 
-filetype off
+filetype on
 set termguicolors
 let s:plug = '~/.vim/plugged'
 function! CocPlugins(arg)
-  :CocInstall coc-rust-analyzer
-  :CocInstall coc-json 
-  :CocInstall coc-tsserver
-  :CocInstall coc-html
-  :CocInstall coc-css
-  :CocInstall coc-sh
-"  :CocInstall coc-clangd
-  :CocInstall coc-highlight
-  :CocInstall coc-yaml
+  CocInstall coc-rust-analyzer
+  CocInstall coc-json 
+  CocInstall coc-tsserver
+  CocInstall coc-html
+  CocInstall coc-css
+  CocInstall coc-sh
+"  CocInstall coc-clangd
+  CocInstall coc-highlight
+  CocInstall coc-yaml
+  CocInstall coc-pyright
+  CocEnable
 endfunction
 " ==========
 "
 " Plugins
-"
 " ==========
 " =============
 " Autocomplete
@@ -41,6 +42,8 @@ Plug 'tikhomirov/vim-glsl'
 Plug 'JuliaEditorSupport/julia-vim'
 Plug 'kevinoid/vim-jsonc'
 Plug 'lervag/vimtex'
+Plug 'ron-rs/ron.vim'
+Plug 'leafgarland/typescript-vim'
 " ====
 " Git
 " ====
@@ -49,7 +52,6 @@ Plug 'tpope/vim-fugitive'
 " Search
 " ======
 Plug 'PeterRincker/vim-searchlight'
-Plug 'ron-rs/ron.vim'
 " ==============
 " Miscellaneous
 " ==============
@@ -80,129 +82,15 @@ Plug 'sainnhe/edge'
 call plug#end()
 
 " ===============
-"
-" Colour Options
-"
+" Coc.nvim 
 " ===============
-set background=dark    
-let g:tokyonight_style = 'night' " available: night, storm
-let g:tokyonight_enable_italic = 1
-let g:tokyonight_current_word = 'underline'
-let g:deus_termcolors=256
-color pablo "fallback
-color tokyonight
-color codedark
-color molokai
-
-"
-"
-" =============
-" 
-" Basic Options 
-"
-" =============
-filetype plugin indent on
-syntax on
-set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
-set statusline+=%{FugitiveStatusline()}
-set statusline+=%t "add file name to statusline
-set sessionoptions-=options
-set tabstop=4
-set softtabstop=0
-set expandtab
-set smarttab
-set autoindent
-set path+=** ""recursive subdirectory search
-set wildmenu
-set wildmode=longest,list,full
-set encoding=utf-8
-syntax enable
-set clipboard=unnamedplus
-set number
-set nocompatible
-set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
-call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
-set hidden
-let mapleader =" "
-map <leader>o :setlocal spell! spelllang=en_au<CR>
-
-" ========================
-" 
-" Cursor Specific Options
-"
-" ========================
-set cul "cursor line is highlighted
-set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
-highlight Cursor guifg=white guibg=black
-" =========================
-" 
-" Filetype Specfic Options
-"
-" =========================
-"
-" =====
-" Make
-" =====
-autocmd Filetype make set noexpandtab "force tabs for make
-" =====
-" Python   
-" =====
-autocmd Filetype python set tabstop=4 
-autocmd Filetype python set softtabstop=4
-autocmd Filetype python set shiftwidth=4
-"autocmd Filetype python set textwidth=79 "pep conformance except this line
-autocmd Filetype python set autoindent 
-autocmd Filetype python set expandtab
-autocmd Filetype python set fileformat=unix 
-" ==============
-" LaTeX Snippets
-" ==============
-nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
-nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
-" =================
-"  Compile from vim
-" =================
-"command! Texit !pdflatex % 
-"command PP !python %
-"command! Maketags !ctags -R
-"autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
-"usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
-"stack
-"
-" ========================
-" Fix Search Highlighting
-" ========================
-nmap <Esc> :nohlsearch<CR>
-imap <Esc> <Esc>:nohlsearch<CR>
-
+let g:coc_start_at_startup = 1
+"inoremap <left> <nop>
+"inoremap <right> <nop>
+"inoremap <down> CocNext Coc
+"inoremap <up> CocPrev
+"imap <up> CocPrev
 
-
-"Remaps:
-    set splitbelow splitright
-    map <C-h> <C-w>h
-    map <C-j> <C-w>j
-    map <C-k> <C-w>k
-    map <C-l> <C-w>l
-
-inoremap <left> <nop>
-inoremap <right> <nop>
-inoremap <down> <nop>
-inoremap <up> <nop>
-
-nnoremap <left> <nop>
-nnoremap <right> <nop>
-nnoremap <down> <nop>
-nnoremap <up> <nop>
-
-
-"Tagbar:
-nmap <C-s> :TagbarToggle<CR>
-let g:tagbar_autoclose = 1
-let g:tagbar_autofocus = 1
-"let g:tagbar_left = 1
-let g_tagbar_width = 15
-
-"Coc:
 set cmdheight=2
 set updatetime=300
 set shortmess+=c
@@ -220,6 +108,12 @@ inoremap <silent><expr> <TAB>
       \ coc#refresh()
 inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
 
+inoremap <silent><expr> <down>
+      \ pumvisible() ? "\<C-n>" :
+      \ <SID>check_back_space() ? "\<TAB>" :
+      \ coc#refresh()
+inoremap <expr><S-up> pumvisible() ? "\<C-p>" : "\<C-h>" 
+
 function! s:check_back_space() abort
   let col = col('.') - 1
   return !col || getline('.')[col - 1]  =~# '\s'
@@ -258,12 +152,11 @@ function! s:show_documentation()
   endif
 endfunction
 
+nmap <leader>rn <Plug>(coc-rename)
 " Highlight the symbol and its references when holding the cursor.
 autocmd CursorHold * silent call CocActionAsync('highlight')
 
 " Symbol renaming.
-nmap <leader>rn <Plug>(coc-rename)
-map <leader><leader> :w<CR>:!rustfmt %<CR>
 
 " Formatting selected code.
 xmap <leader>f  <Plug>(coc-format-selected)
@@ -334,6 +227,136 @@ nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
 " Resume latest coc list.
 nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
 
+" ===============
+"
+" Colour Options
+"
+" ===============
+set background=dark    
+let g:tokyonight_style = 'night' " available: night, storm
+let g:tokyonight_enable_italic = 1
+let g:tokyonight_current_word = 'underline'
+let g:deus_termcolors=256
+color pablo "fallback
+color tokyonight
+color codedark
+color molokai
+
+"
+"
+" =============
+" 
+" Basic Options 
+"
+" =============
+filetype plugin indent on
+syntax on
+set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
+set statusline+=%{FugitiveStatusline()}
+set statusline+=%t "add file name to statusline
+set sessionoptions-=options
+set tabstop=4
+set softtabstop=2
+set expandtab
+set smarttab
+set autoindent
+set path+=** ""recursive subdirectory search
+set wildmenu
+set wildmode=longest,list,full
+set encoding=utf-8
+syntax enable
+set clipboard=unnamedplus
+set number
+set nocompatible
+set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
+call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
+set hidden
+let mapleader =" "
+map <leader>o :setlocal spell! spelllang=en_au<CR>
+
+" ========================
+" 
+" Cursor Specific Options
+"
+" ========================
+set cul "cursor line is highlighted
+set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
+highlight Cursor guifg=white guibg=black
+" =========================
+" 
+" Filetype Specfic Options
+"
+" =========================
+"
+" =====
+" Make
+" =====
+autocmd Filetype make set noexpandtab "force tabs for make
+" =====
+" Python   
+" =====
+autocmd Filetype python set tabstop=4 
+autocmd Filetype python set softtabstop=4
+autocmd Filetype python set shiftwidth=4
+"autocmd Filetype python set textwidth=79 "pep conformance except this line
+autocmd Filetype python set autoindent 
+autocmd Filetype python set expandtab
+autocmd Filetype python set fileformat=unix 
+" =====
+" Mutt   
+" =====
+au BufRead /tmp/mutt-* set tw=72
+" ==============
+" LaTeX Snippets
+" ==============
+nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
+nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
+" =================
+"  Compile from vim
+" =================
+"command! Texit !pdflatex % 
+"command PP !python %
+"command! Maketags !ctags -R
+"autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
+"usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
+"stack
+"
+" ========================
+" Fix Search Highlighting
+" ========================
+nmap <Esc> :nohlsearch<CR>
+imap <Esc> <Esc>:nohlsearch<CR>
+
+
+
+"Remaps:
+    set splitbelow splitright
+    map <C-h> <C-w>h
+    map <C-j> <C-w>j
+    map <C-k> <C-w>k
+    map <C-l> <C-w>l
+
+inoremap <left> <nop>
+inoremap <right> <nop>
+inoremap <down> <nop>
+inoremap <up> <nop>
+
+nnoremap <left> <nop>
+nnoremap <right> <nop>
+nnoremap <down> <nop>
+nnoremap <up> <nop>
+
+
+"Tagbar:
+nmap <C-s> :TagbarToggle<CR>
+let g:tagbar_autoclose = 1
+let g:tagbar_autofocus = 1
+"let g:tagbar_left = 1
+let g_tagbar_width = 15
+
+
 let g:UltiSnipsExpandTrigger="<F2>" "need to remap away from default <tab> to avoid conflict with coc autocomplete
 let g:UltiSnipsJumpForwardTrigger="<c-k>"
 let g:UltiSnipsJumpBackwardTrigger="<c-j>"
+
+map <leader><leader> :w<CR>:!rustfmt %<CR>

commit f955acea5ec3dcbd20977dfecfcb293874329824
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Wed Feb 10 11:43:04 2021 +1000

    added compiler script

diff --git a/.vimrc b/.vimrc
index 6128dad..524a098 100644
--- a/.vimrc
+++ b/.vimrc
@@ -40,6 +40,7 @@ Plug 'rust-lang/rust.vim'
 Plug 'tikhomirov/vim-glsl'
 Plug 'JuliaEditorSupport/julia-vim'
 Plug 'kevinoid/vim-jsonc'
+Plug 'lervag/vimtex'
 " ====
 " Git
 " ====
@@ -67,7 +68,7 @@ Plug 'morhetz/gruvbox'
 Plug 'ghifarit53/tokyonight-vim' 
 Plug 'ajmwagar/vim-deus' 
 Plug 'sainnhe/edge'
-Plug 'pineapplegiant/spaceduck'
+"Plug 'pineapplegiant/spaceduck'
 " =======
 " Unused 
 " =======
@@ -89,13 +90,10 @@ let g:tokyonight_enable_italic = 1
 let g:tokyonight_current_word = 'underline'
 let g:deus_termcolors=256
 color pablo "fallback
-color codedark
 color tokyonight
+color codedark
 color molokai
 
-"set t_Co=256
-"let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
-"let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
 "
 "
 " =============
@@ -128,6 +126,14 @@ set hidden
 let mapleader =" "
 map <leader>o :setlocal spell! spelllang=en_au<CR>
 
+" ========================
+" 
+" Cursor Specific Options
+"
+" ========================
+set cul "cursor line is highlighted
+set guicursor=n-v-c-sm:block,i-ci-ve:ver25-Cursor,r-cr-o:hor20
+highlight Cursor guifg=white guibg=black
 " =========================
 " 
 " Filetype Specfic Options
@@ -144,7 +150,7 @@ autocmd Filetype make set noexpandtab "force tabs for make
 autocmd Filetype python set tabstop=4 
 autocmd Filetype python set softtabstop=4
 autocmd Filetype python set shiftwidth=4
-"autocmd Filetype python set textwidth=79
+"autocmd Filetype python set textwidth=79 "pep conformance except this line
 autocmd Filetype python set autoindent 
 autocmd Filetype python set expandtab
 autocmd Filetype python set fileformat=unix 
@@ -166,8 +172,8 @@ nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 " ========================
 " Fix Search Highlighting
 " ========================
-nmap <Esc> :nohlsearch<CR>q:<CR>
-imap <Esc> <Esc>:nohlsearch<CR>q:<CR>
+nmap <Esc> :nohlsearch<CR>
+imap <Esc> <Esc>:nohlsearch<CR>
 
 
 

commit 3f67f66706206e54f13f49e6a1156a1b0d439513
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Feb 9 20:30:19 2021 +1000

    woops

diff --git a/.vimrc b/.vimrc
index 9602848..6128dad 100644
--- a/.vimrc
+++ b/.vimrc
@@ -76,7 +76,6 @@ Plug 'pineapplegiant/spaceduck'
 "let g:NERDTreeWinSize=15
 "map <C-a> :NERDTreeToggle<CR>
 "
->>>>>>> cb5aa707a931df23daf5c8d2d74536eaa6df9145
 call plug#end()
 
 " ===============

commit ca3c6fd490633378c5403edc30a2de57c109f7f3
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Feb 9 20:29:28 2021 +1000

    fixed error in vimrc

diff --git a/.vimrc b/.vimrc
index 2e95cdb..9602848 100644
--- a/.vimrc
+++ b/.vimrc
@@ -48,9 +48,7 @@ Plug 'tpope/vim-fugitive'
 " Search
 " ======
 Plug 'PeterRincker/vim-searchlight'
-<<<<<<< HEAD
 Plug 'ron-rs/ron.vim'
-=======
 " ==============
 " Miscellaneous
 " ==============

commit 55aea3caf798dba8b46aa43420fd6b79b7bcf963
Merge: ec65da4 f029a57
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Feb 9 20:24:01 2021 +1000

    fixed merge

commit ec65da4ca4c7b18d6b3b0c7c3582c99e225e5412
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Feb 9 20:22:56 2021 +1000

    coc ron plugin

diff --git a/.vimrc b/.vimrc
index 2122b3f..dc1865e 100644
--- a/.vimrc
+++ b/.vimrc
@@ -1,4 +1,5 @@
-"
+
+
 "_                    
 " __   _(_)_ __ ___  _ __ ___ 
 " \ \ / / | '_ ` _ \| '__/ __|
@@ -16,6 +17,7 @@ Plug 'majutsushi/tagbar'        "requires ctags  to be installed
 "Plug 'preservim/nerdtree'
 Plug 'JuliaEditorSupport/julia-vim'
 Plug 'PeterRincker/vim-searchlight'
+Plug 'ron-rs/ron.vim'
 call plug#end()
 filetype plugin indent on
 syntax on

commit 595aa09f40f4ee6b9a17609c7950bbb26f94bcb8
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon Feb 8 19:37:07 2021 +1000

    updated dwm, pywal/wallpaper support

diff --git a/.vimrc b/.vimrc
index 3642400..4acd5cf 100644
--- a/.vimrc
+++ b/.vimrc
@@ -15,7 +15,7 @@ function! CocPlugins(arg)
   :CocInstall coc-html
   :CocInstall coc-css
   :CocInstall coc-sh
-  :CocInstall coc-clangd
+"  :CocInstall coc-clangd
   :CocInstall coc-highlight
   :CocInstall coc-yaml
 endfunction
@@ -106,6 +106,7 @@ filetype plugin indent on
 syntax on
 set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
 set statusline+=%{FugitiveStatusline()}
+set statusline+=%t "add file name to statusline
 set sessionoptions-=options
 set tabstop=4
 set softtabstop=0

commit 68b6b06aa164bca589ce51b5a4d987c25f5154db
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon Feb 8 02:29:05 2021 +1000

    merged coc plugins installer into vimrc

diff --git a/.vimrc b/.vimrc
index 9120899..3642400 100644
--- a/.vimrc
+++ b/.vimrc
@@ -6,20 +6,36 @@
 "                             
 
 filetype off
+set termguicolors
+let s:plug = '~/.vim/plugged'
+function! CocPlugins(arg)
+  :CocInstall coc-rust-analyzer
+  :CocInstall coc-json 
+  :CocInstall coc-tsserver
+  :CocInstall coc-html
+  :CocInstall coc-css
+  :CocInstall coc-sh
+  :CocInstall coc-clangd
+  :CocInstall coc-highlight
+  :CocInstall coc-yaml
+endfunction
 " ==========
 "
 " Plugins
 "
 " ==========
-call plug#begin('~/.vim/plugged')
 " =============
 " Autocomplete
 " =============
-Plug 'neoclide/coc.nvim', {'branch': 'release'} "Requires node
+"
+call plug#begin(s:plug)
+"coc requires node, force update of coc plugins with :CocUpdate!
+Plug 'neoclide/coc.nvim', {'branch': 'release', 'do': function('CocPlugins') }
 "let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0 (old)
 " =================
 " Language Support
 " =================
+Plug 'sheerun/vim-polyglot' "all in one bundle
 Plug 'rust-lang/rust.vim'
 Plug 'tikhomirov/vim-glsl'
 Plug 'JuliaEditorSupport/julia-vim'
@@ -42,15 +58,15 @@ Plug 'tpope/vim-sensible'
 Plug 'SirVer/ultisnips'
 Plug 'honza/vim-snippets'
 " ===============
-" Colour Schemes
+" Color Schemes
 " ===============
 Plug 'tomasiser/vim-code-dark'
 Plug 'tomasr/molokai'
-"color pablo "fallback
-color molokai
-"color codedark
-"set background=dark
-"color solarized
+Plug 'morhetz/gruvbox'
+Plug 'ghifarit53/tokyonight-vim' 
+Plug 'ajmwagar/vim-deus' 
+Plug 'sainnhe/edge'
+Plug 'pineapplegiant/spaceduck'
 " =======
 " Unused 
 " =======
@@ -60,6 +76,26 @@ color molokai
 "map <C-a> :NERDTreeToggle<CR>
 "
 call plug#end()
+
+" ===============
+"
+" Colour Options
+"
+" ===============
+set background=dark    
+let g:tokyonight_style = 'night' " available: night, storm
+let g:tokyonight_enable_italic = 1
+let g:tokyonight_current_word = 'underline'
+let g:deus_termcolors=256
+color pablo "fallback
+color codedark
+color tokyonight
+color molokai
+
+"set t_Co=256
+"let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
+"let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
+"
 "
 " =============
 " 
@@ -68,6 +104,8 @@ call plug#end()
 " =============
 filetype plugin indent on
 syntax on
+set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
+set statusline+=%{FugitiveStatusline()}
 set sessionoptions-=options
 set tabstop=4
 set softtabstop=0
@@ -116,9 +154,9 @@ nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 " =================
 "  Compile from vim
 " =================
-command! Texit !pdflatex % 
-command PP !python %
-command! Maketags !ctags -R
+"command! Texit !pdflatex % 
+"command PP !python %
+"command! Maketags !ctags -R
 "autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
 "usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
 "stack
@@ -269,7 +307,6 @@ command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organize
 " Add (Neo)Vim's native statusline support.
 " NOTE: Please see `:h coc-status` for integrations with external plugins that
 " provide custom statusline: lightline.vim, vim-airline.
-set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
 
 " Mappings for CoCList
 " Show all diagnostics.
@@ -289,6 +326,6 @@ nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
 " Resume latest coc list.
 nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
 
-let g:UltiSnipsExpandTrigger="," "need to remap away from default <tab> to avoid conflict with coc autocomplete
+let g:UltiSnipsExpandTrigger="<F2>" "need to remap away from default <tab> to avoid conflict with coc autocomplete
 let g:UltiSnipsJumpForwardTrigger="<c-k>"
 let g:UltiSnipsJumpBackwardTrigger="<c-j>"

commit 53d17c62ceae270a48d94ae79c2d815a134ccbf2
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon Feb 8 00:08:36 2021 +1000

    streamlined vim config

diff --git a/.vimrc b/.vimrc
index 1923432..9120899 100644
--- a/.vimrc
+++ b/.vimrc
@@ -1,58 +1,106 @@
-
+"        _                    
 " __   _(_)_ __ ___  _ __ ___ 
 " \ \ / / | '_ ` _ \| '__/ __|
 "  \ V /| | | | | | | | | (__ 
 "   \_/ |_|_| |_| |_|_|  \___|
+"                             
 
 filetype off
+" ==========
+"
+" Plugins
+"
+" ==========
 call plug#begin('~/.vim/plugged')
+" =============
+" Autocomplete
+" =============
 Plug 'neoclide/coc.nvim', {'branch': 'release'} "Requires node
-"let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0
-Plug 'tpope/vim-sensible'
+"let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0 (old)
+" =================
+" Language Support
+" =================
 Plug 'rust-lang/rust.vim'
 Plug 'tikhomirov/vim-glsl'
-Plug 'majutsushi/tagbar'        "requires ctags  to be installed
-"Plug 'preservim/nerdtree'
 Plug 'JuliaEditorSupport/julia-vim'
-Plug 'PeterRincker/vim-searchlight'
 Plug 'kevinoid/vim-jsonc'
+" ====
+" Git
+" ====
+Plug 'tpope/vim-fugitive'
+" ======
+" Search
+" ======
+Plug 'PeterRincker/vim-searchlight'
+" ==============
+" Miscellaneous
+" ==============
+Plug 'tpope/vim-sensible'
+" =========
+" Snippets
+" =========
 Plug 'SirVer/ultisnips'
 Plug 'honza/vim-snippets'
+" ===============
+" Colour Schemes
+" ===============
+Plug 'tomasiser/vim-code-dark'
+Plug 'tomasr/molokai'
+"color pablo "fallback
+color molokai
+"color codedark
+"set background=dark
+"color solarized
+" =======
+" Unused 
+" =======
+"Plug 'preservim/tagbar'        "requires ctags  to be installed
+"Plug 'preservim/nerdtree'
+"let g:NERDTreeWinSize=15
+"map <C-a> :NERDTreeToggle<CR>
+"
 call plug#end()
+"
+" =============
+" 
+" Basic Options 
+"
+" =============
 filetype plugin indent on
 syntax on
-"set nohlsearch
 set sessionoptions-=options
-
-"   basics:
-    set tabstop=4
-    set softtabstop=0
-    set shiftwidth=4
-    set expandtab
-    set smarttab
-    set autoindent
-    set path+=** ""recursive subdirectory search
-    set wildmenu
-    set wildmode=longest,list,full
-    set encoding=utf-8
-    syntax enable
-    "set background=dark
-    "color solarized
-    "color pablo
-    color molokai
-    set clipboard=unnamedplus
-    set number
-    set nocompatible
-    set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
-    call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
-    set hidden
-
+set tabstop=4
+set softtabstop=0
+set expandtab
+set smarttab
+set autoindent
+set path+=** ""recursive subdirectory search
+set wildmenu
+set wildmode=longest,list,full
+set encoding=utf-8
+syntax enable
+set clipboard=unnamedplus
+set number
+set nocompatible
+set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
+call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
+set hidden
 let mapleader =" "
 map <leader>o :setlocal spell! spelllang=en_au<CR>
-"Filetypes:
-"Make:
+
+" =========================
+" 
+" Filetype Specfic Options
+"
+" =========================
+"
+" =====
+" Make
+" =====
 autocmd Filetype make set noexpandtab "force tabs for make
-"Python:
+" =====
+" Python   
+" =====
 autocmd Filetype python set tabstop=4 
 autocmd Filetype python set softtabstop=4
 autocmd Filetype python set shiftwidth=4
@@ -60,29 +108,28 @@ autocmd Filetype python set shiftwidth=4
 autocmd Filetype python set autoindent 
 autocmd Filetype python set expandtab
 autocmd Filetype python set fileformat=unix 
-"LaTeX Snippets:
+" ==============
+" LaTeX Snippets
+" ==============
 nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
 nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
-"Commands:
+" =================
+"  Compile from vim
+" =================
 command! Texit !pdflatex % 
 command PP !python %
 command! Maketags !ctags -R
 "autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
 "usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
 "stack
-"Fix Search Highlighting:
-autocmd InsertEnter * nohlsearch "EndHighlight()
+"
+" ========================
+" Fix Search Highlighting
+" ========================
 nmap <Esc> :nohlsearch<CR>q:<CR>
 imap <Esc> <Esc>:nohlsearch<CR>q:<CR>
 
 
-function EndHighlight()
-    "match
-    "let s:lastsearch = @/
-    "nohlsearch
-    nohl
-    "redraw
-endfunction
 
 "Remaps:
     set splitbelow splitright
@@ -100,10 +147,6 @@ nnoremap <left> <nop>
 nnoremap <right> <nop>
 nnoremap <down> <nop>
 nnoremap <up> <nop>
-"Plugins:
-"Nerdtree:
-let g:NERDTreeWinSize=15
-map <C-a> :NERDTreeToggle<CR>
 
 
 "Tagbar:
@@ -151,6 +194,7 @@ endif
 nmap <silent> [g <Plug>(coc-diagnostic-prev)
 nmap <silent> ]g <Plug>(coc-diagnostic-next)
 
+
 " GoTo code navigation.
 nmap <silent> gd <Plug>(coc-definition)
 nmap <silent> gy <Plug>(coc-type-definition)
@@ -245,6 +289,6 @@ nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
 " Resume latest coc list.
 nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
 
-let g:UltiSnipsExpandTrigger="<tab>"
+let g:UltiSnipsExpandTrigger="," "need to remap away from default <tab> to avoid conflict with coc autocomplete
 let g:UltiSnipsJumpForwardTrigger="<c-k>"
 let g:UltiSnipsJumpBackwardTrigger="<c-j>"

commit 47161f2941186ba5f502bc6ac0f2b601004b9f42
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Sun Feb 7 23:10:50 2021 +1000

    updated vimrc and accomadating coc plugins

diff --git a/.vimrc b/.vimrc
index 5e40693..1923432 100644
--- a/.vimrc
+++ b/.vimrc
@@ -1,4 +1,4 @@
-"_                    
+
 " __   _(_)_ __ ___  _ __ ___ 
 " \ \ / / | '_ ` _ \| '__/ __|
 "  \ V /| | | | | | | | | (__ 
@@ -15,10 +15,13 @@ Plug 'majutsushi/tagbar'        "requires ctags  to be installed
 "Plug 'preservim/nerdtree'
 Plug 'JuliaEditorSupport/julia-vim'
 Plug 'PeterRincker/vim-searchlight'
+Plug 'kevinoid/vim-jsonc'
+Plug 'SirVer/ultisnips'
+Plug 'honza/vim-snippets'
 call plug#end()
 filetype plugin indent on
 syntax on
-set nohlsearch
+"set nohlsearch
 set sessionoptions-=options
 
 "   basics:
@@ -68,13 +71,17 @@ command! Maketags !ctags -R
 "usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
 "stack
 "Fix Search Highlighting:
-autocmd InsertEnter * call EndHighlight()
+autocmd InsertEnter * nohlsearch "EndHighlight()
+nmap <Esc> :nohlsearch<CR>q:<CR>
+imap <Esc> <Esc>:nohlsearch<CR>q:<CR>
+
 
 function EndHighlight()
-    match
-    let s:lastsearch = @/
-    nohlsearch
-    redraw
+    "match
+    "let s:lastsearch = @/
+    "nohlsearch
+    nohl
+    "redraw
 endfunction
 
 "Remaps:
@@ -238,3 +245,6 @@ nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
 " Resume latest coc list.
 nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
 
+let g:UltiSnipsExpandTrigger="<tab>"
+let g:UltiSnipsJumpForwardTrigger="<c-k>"
+let g:UltiSnipsJumpBackwardTrigger="<c-j>"

commit a103f361543c885f4eaddaff6911920e7a769138
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Sun Feb 7 14:01:20 2021 +1000

    minor edit

diff --git a/.vimrc b/.vimrc
index 2122b3f..5e40693 100644
--- a/.vimrc
+++ b/.vimrc
@@ -1,4 +1,3 @@
-"
 "_                    
 " __   _(_)_ __ ___  _ __ ___ 
 " \ \ / / | '_ ` _ \| '__/ __|

commit 2efca504d9d6de55c8ac795b9feb0444c464c755
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Fri Feb 5 12:11:12 2021 +1000

    helo

diff --git a/.vimrc b/.vimrc
index ff64f5e..2122b3f 100644
--- a/.vimrc
+++ b/.vimrc
@@ -8,7 +8,7 @@
 filetype off
 call plug#begin('~/.vim/plugged')
 Plug 'neoclide/coc.nvim', {'branch': 'release'} "Requires node
-let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0
+"let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0
 Plug 'tpope/vim-sensible'
 Plug 'rust-lang/rust.vim'
 Plug 'tikhomirov/vim-glsl'

commit 0591869469791aa1fd05021eb63eafab99203ccb
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Sun Jan 24 21:18:04 2021 +1000

    added debian server options

diff --git a/.vimrc b/.vimrc
index a777b79..ff64f5e 100644
--- a/.vimrc
+++ b/.vimrc
@@ -7,7 +7,8 @@
 
 filetype off
 call plug#begin('~/.vim/plugged')
-Plug 'neoclide/coc.nvim', {'branch': 'release'} "Rquires node
+Plug 'neoclide/coc.nvim', {'branch': 'release'} "Requires node
+let g:coc_disable_startup_warning = 1 "Because debian version is <0.4.0
 Plug 'tpope/vim-sensible'
 Plug 'rust-lang/rust.vim'
 Plug 'tikhomirov/vim-glsl'

commit 9cfe202cd280acd2ae874124825724fecd3a1e7f
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Sep 8 23:01:08 2020 +1000

    a

diff --git a/.vimrc b/.vimrc
index 0ebe950..a777b79 100644
--- a/.vimrc
+++ b/.vimrc
@@ -57,7 +57,7 @@ autocmd Filetype python set shiftwidth=4
 autocmd Filetype python set autoindent 
 autocmd Filetype python set expandtab
 autocmd Filetype python set fileformat=unix 
-"Snippets:
+"LaTeX Snippets:
 nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
 nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 "Commands:

commit b3f2ffaaa7ecf63bb596bef0b72c72f978092aea
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Fri Aug 21 08:39:27 2020 +1000

    fixed installation process

diff --git a/.vimrc b/.vimrc
index 2e111ba..0ebe950 100644
--- a/.vimrc
+++ b/.vimrc
@@ -1,4 +1,5 @@
-"        _                    
+"
+"_                    
 " __   _(_)_ __ ___  _ __ ___ 
 " \ \ / / | '_ ` _ \| '__/ __|
 "  \ V /| | | | | | | | | (__ 
@@ -17,6 +18,7 @@ Plug 'PeterRincker/vim-searchlight'
 call plug#end()
 filetype plugin indent on
 syntax on
+set nohlsearch
 set sessionoptions-=options
 
 "   basics:

commit 1b4a1f252b0841c732571d183860f217ef8d0d44
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Sat Aug 8 01:35:27 2020 +1000

    updated for mail

diff --git a/.vimrc b/.vimrc
index 5002450..2e111ba 100644
--- a/.vimrc
+++ b/.vimrc
@@ -11,7 +11,8 @@ Plug 'tpope/vim-sensible'
 Plug 'rust-lang/rust.vim'
 Plug 'tikhomirov/vim-glsl'
 Plug 'majutsushi/tagbar'        "requires ctags  to be installed
-Plug 'preservim/nerdtree'
+"Plug 'preservim/nerdtree'
+Plug 'JuliaEditorSupport/julia-vim'
 Plug 'PeterRincker/vim-searchlight'
 call plug#end()
 filetype plugin indent on
@@ -163,6 +164,7 @@ autocmd CursorHold * silent call CocActionAsync('highlight')
 
 " Symbol renaming.
 nmap <leader>rn <Plug>(coc-rename)
+map <leader><leader> :w<CR>:!rustfmt %<CR>
 
 " Formatting selected code.
 xmap <leader>f  <Plug>(coc-format-selected)

commit f050436167f325ca42416ae25d562dc15146ca1d
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Thu Jul 2 06:22:02 2020 +1000

    updated installation procedure

diff --git a/.vimrc b/.vimrc
index 19e37fa..5002450 100644
--- a/.vimrc
+++ b/.vimrc
@@ -4,10 +4,16 @@
 "  \ V /| | | | | | | | | (__ 
 "   \_/ |_|_| |_| |_|_|  \___|
 
-let mapleader =" "
 filetype off
-execute pathogen#infect()
-execute pathogen#helptags()
+call plug#begin('~/.vim/plugged')
+Plug 'neoclide/coc.nvim', {'branch': 'release'} "Rquires node
+Plug 'tpope/vim-sensible'
+Plug 'rust-lang/rust.vim'
+Plug 'tikhomirov/vim-glsl'
+Plug 'majutsushi/tagbar'        "requires ctags  to be installed
+Plug 'preservim/nerdtree'
+Plug 'PeterRincker/vim-searchlight'
+call plug#end()
 filetype plugin indent on
 syntax on
 set sessionoptions-=options
@@ -23,7 +29,7 @@ set sessionoptions-=options
     set wildmenu
     set wildmode=longest,list,full
     set encoding=utf-8
-    "syntax enable
+    syntax enable
     "set background=dark
     "color solarized
     "color pablo
@@ -33,9 +39,14 @@ set sessionoptions-=options
     set nocompatible
     set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
     call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
+    set hidden
 
+let mapleader =" "
+map <leader>o :setlocal spell! spelllang=en_au<CR>
+"Filetypes:
+"Make:
 autocmd Filetype make set noexpandtab "force tabs for make
-"PEP8 approved:
+"Python:
 autocmd Filetype python set tabstop=4 
 autocmd Filetype python set softtabstop=4
 autocmd Filetype python set shiftwidth=4
@@ -43,41 +54,27 @@ autocmd Filetype python set shiftwidth=4
 autocmd Filetype python set autoindent 
 autocmd Filetype python set expandtab
 autocmd Filetype python set fileformat=unix 
-
-"NERDTREE
-let g:NERDTreeWinSize=15
-map <C-a> :NERDTreeToggle<CR>
-
-"Syntastic
-"set statusline+=%#warningmsg#
-"set statusline+=%{SyntasticStatuslineFlag()}
-"set statusline+=%*
-
-"let g:syntastic_always_populate_loc_list = 1
-"let g:syntastic_auto_loc_list = 1
-"let g:syntastic_check_on_open = 1
-"let g:syntastic_check_on_wq = 0
-"let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
-
-"tagbar
-nmap <C-s> :TagbarToggle<CR>
-let g:tagbar_autoclose = 1
-let g:tagbar_autofocus = 1
-"let g:tagbar_left = 1
-let g_tagbar_width = 15
-
-"snippets:
+"Snippets:
 nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
 nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
-
-
+"Commands:
 command! Texit !pdflatex % 
 command PP !python %
-command! Maketags !ctags -R .
-map <leader>o :setlocal spell! spelllang=en_au<CR>
-autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
+command! Maketags !ctags -R
+"autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
 "usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
 "stack
+"Fix Search Highlighting:
+autocmd InsertEnter * call EndHighlight()
+
+function EndHighlight()
+    match
+    let s:lastsearch = @/
+    nohlsearch
+    redraw
+endfunction
+
+"Remaps:
     set splitbelow splitright
     map <C-h> <C-w>h
     map <C-j> <C-w>j
@@ -93,5 +90,147 @@ nnoremap <left> <nop>
 nnoremap <right> <nop>
 nnoremap <down> <nop>
 nnoremap <up> <nop>
-"set undodir ~/.vimdid
-"set undofile
+"Plugins:
+"Nerdtree:
+let g:NERDTreeWinSize=15
+map <C-a> :NERDTreeToggle<CR>
+
+
+"Tagbar:
+nmap <C-s> :TagbarToggle<CR>
+let g:tagbar_autoclose = 1
+let g:tagbar_autofocus = 1
+"let g:tagbar_left = 1
+let g_tagbar_width = 15
+
+"Coc:
+set cmdheight=2
+set updatetime=300
+set shortmess+=c
+if has("patch-8.1.1564")
+  set signcolumn=number
+else
+  set signcolumn=yes
+endif
+" Use tab for trigger completion with characters ahead and navigate.
+" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
+" other plugin before putting this into your config.
+inoremap <silent><expr> <TAB>
+      \ pumvisible() ? "\<C-n>" :
+      \ <SID>check_back_space() ? "\<TAB>" :
+      \ coc#refresh()
+inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"
+
+function! s:check_back_space() abort
+  let col = col('.') - 1
+  return !col || getline('.')[col - 1]  =~# '\s'
+endfunction
+" Use <c-space> to trigger completion.
+inoremap <silent><expr> <c-space> coc#refresh()
+" Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
+" position. Coc only does snippet and additional edit on confirm.
+" <cr> could be remapped by other vim plugin, try `:verbose imap <CR>`.
+if exists('*complete_info')
+  inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
+else
+  inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
+endif
+
+" Use `[g` and `]g` to navigate diagnostics
+" Use `:CocDiagnostics` to get all diagnostics of current buffer in location list.
+nmap <silent> [g <Plug>(coc-diagnostic-prev)
+nmap <silent> ]g <Plug>(coc-diagnostic-next)
+
+" GoTo code navigation.
+nmap <silent> gd <Plug>(coc-definition)
+nmap <silent> gy <Plug>(coc-type-definition)
+nmap <silent> gi <Plug>(coc-implementation)
+nmap <silent> gr <Plug>(coc-references)
+
+" Use K to show documentation in preview window.
+nnoremap <silent> K :call <SID>show_documentation()<CR>
+
+function! s:show_documentation()
+  if (index(['vim','help'], &filetype) >= 0)
+    execute 'h '.expand('<cword>')
+  else
+    call CocAction('doHover')
+  endif
+endfunction
+
+" Highlight the symbol and its references when holding the cursor.
+autocmd CursorHold * silent call CocActionAsync('highlight')
+
+" Symbol renaming.
+nmap <leader>rn <Plug>(coc-rename)
+
+" Formatting selected code.
+xmap <leader>f  <Plug>(coc-format-selected)
+nmap <leader>f  <Plug>(coc-format-selected)
+
+augroup mygroup
+  autocmd!
+  " Setup formatexpr specified filetype(s).
+  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
+  " Update signature help on jump placeholder.
+  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
+augroup end
+
+" Applying codeAction to the selected region.
+" Example: `<leader>aap` for current paragraph
+xmap <leader>a  <Plug>(coc-codeaction-selected)
+nmap <leader>a  <Plug>(coc-codeaction-selected)
+
+" Remap keys for applying codeAction to the current buffer.
+nmap <leader>ac  <Plug>(coc-codeaction)
+" Apply AutoFix to problem on the current line.
+nmap <leader>qf  <Plug>(coc-fix-current)
+
+" Map function and class text objects
+" NOTE: Requires 'textDocument.documentSymbol' support from the language server.
+xmap if <Plug>(coc-funcobj-i)
+omap if <Plug>(coc-funcobj-i)
+xmap af <Plug>(coc-funcobj-a)
+omap af <Plug>(coc-funcobj-a)
+xmap ic <Plug>(coc-classobj-i)
+omap ic <Plug>(coc-classobj-i)
+xmap ac <Plug>(coc-classobj-a)
+omap ac <Plug>(coc-classobj-a)
+
+" Use CTRL-S for selections ranges.
+" Requires 'textDocument/selectionRange' support of LS, ex: coc-tsserver
+nmap <silent> <C-s> <Plug>(coc-range-select)
+xmap <silent> <C-s> <Plug>(coc-range-select)
+
+" Add `:Format` command to format current buffer.
+command! -nargs=0 Format :call CocAction('format')
+
+" Add `:Fold` command to fold current buffer.
+command! -nargs=? Fold :call     CocAction('fold', <f-args>)
+
+" Add `:OR` command for organize imports of the current buffer.
+command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
+
+" Add (Neo)Vim's native statusline support.
+" NOTE: Please see `:h coc-status` for integrations with external plugins that
+" provide custom statusline: lightline.vim, vim-airline.
+set statusline^=%{coc#status()}%{get(b:,'coc_current_function','')}
+
+" Mappings for CoCList
+" Show all diagnostics.
+nnoremap <silent><nowait> <space>a  :<C-u>CocList diagnostics<cr>
+" Manage extensions.
+nnoremap <silent><nowait> <space>e  :<C-u>CocList extensions<cr>
+" Show commands.
+nnoremap <silent><nowait> <space>c  :<C-u>CocList commands<cr>
+" Find symbol of current document.
+nnoremap <silent><nowait> <space>o  :<C-u>CocList outline<cr>
+" Search workspace symbols.
+nnoremap <silent><nowait> <space>s  :<C-u>CocList -I symbols<cr>
+" Do default action for next item.
+nnoremap <silent><nowait> <space>j  :<C-u>CocNext<CR>
+" Do default action for previous item.
+nnoremap <silent><nowait> <space>k  :<C-u>CocPrev<CR>
+" Resume latest coc list.
+nnoremap <silent><nowait> <space>p  :<C-u>CocListResume<CR>
+

commit df1cd57e850bd1adfa524cd7f5e538240da0e9fc
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Jun 23 09:43:58 2020 +1000

    fixed bug

diff --git a/.vimrc b/.vimrc
index 6c8d858..19e37fa 100644
--- a/.vimrc
+++ b/.vimrc
@@ -49,15 +49,15 @@ let g:NERDTreeWinSize=15
 map <C-a> :NERDTreeToggle<CR>
 
 "Syntastic
-set statusline+=%#warningmsg#
-set statusline+=%{SyntasticStatuslineFlag()}
-set statusline+=%*
+"set statusline+=%#warningmsg#
+"set statusline+=%{SyntasticStatuslineFlag()}
+"set statusline+=%*
 
-let g:syntastic_always_populate_loc_list = 1
-let g:syntastic_auto_loc_list = 1
-let g:syntastic_check_on_open = 1
-let g:syntastic_check_on_wq = 0
-let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
+"let g:syntastic_always_populate_loc_list = 1
+"let g:syntastic_auto_loc_list = 1
+"let g:syntastic_check_on_open = 1
+"let g:syntastic_check_on_wq = 0
+"let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
 
 "tagbar
 nmap <C-s> :TagbarToggle<CR>

commit f98064747367338383ae13afd675863c4fd460a9
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Tue Jun 16 05:07:40 2020 +1000

    updated status

diff --git a/.vimrc b/.vimrc
index 5b8542f..6c8d858 100644
--- a/.vimrc
+++ b/.vimrc
@@ -83,3 +83,15 @@ autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
     map <C-j> <C-w>j
     map <C-k> <C-w>k
     map <C-l> <C-w>l
+
+inoremap <left> <nop>
+inoremap <right> <nop>
+inoremap <down> <nop>
+inoremap <up> <nop>
+
+nnoremap <left> <nop>
+nnoremap <right> <nop>
+nnoremap <down> <nop>
+nnoremap <up> <nop>
+"set undodir ~/.vimdid
+"set undofile

commit e18acdf39b98aa198ec656357b24e447a694e38a
Merge: 45148e8 9016a36
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Sun Jun 7 22:50:53 2020 +1000

    fixed dwm startup

commit 29ea5696dae2a35050786b74dfab020f5019b726
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon May 25 13:34:07 2020 +1000

    thinkpad

diff --git a/.vimrc b/.vimrc
index bfc4c81..1728672 100644
--- a/.vimrc
+++ b/.vimrc
@@ -69,6 +69,7 @@ nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 
 
 command! Texit !pdflatex % 
+command PP !python %
 command! Maketags !ctags -R .
 map <leader>o :setlocal spell! spelllang=en_au<CR>
 autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &

commit 772e774cdd5659131fbb12de08c2bdbd064dfcdf
Author: Maxwell Odri <maxwellodri@gmail.com>
Date:   Mon May 18 13:55:41 2020 +1000

    initial mutt

diff --git a/.vimrc b/.vimrc
index fd8d476..bfc4c81 100644
--- a/.vimrc
+++ b/.vimrc
@@ -29,6 +29,7 @@ set sessionoptions-=options
     set number
     set nocompatible
     set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
+    call mkdir(expand('%:h'), 'p') "autocreate parent directory if it doesnt exist
 
 autocmd Filetype make set noexpandtab "force tabs for make
 "PEP8 approved:

commit 327e828d7b6f82a680734e6c0db553b64d90b418
Author: maxwellodri <maxwellodri@gmail.com>
Date:   Tue May 5 03:54:00 2020 +1000

    fixed screenshot script

diff --git a/.vimrc b/.vimrc
index 6abcd9c..fd8d476 100644
--- a/.vimrc
+++ b/.vimrc
@@ -1,37 +1,10 @@
-set tabstop=4
-set softtabstop=0
-set shiftwidth=4
-set expandtab
-set smarttab
-set autoindent
-"color blue
-"color darkblue
-"color default
-"color delek
-"color desert
-"color elflord
-"color evening
-"color industry
-"color koehler
-"color morning
-"color murphy
-"color pablo
-"color peachpuff
-"color ron
-"color shine
-"color slate
-"color torte
-"color zellner
-color molokai
-set clipboard=unnamedplus
+"        _                    
+" __   _(_)_ __ ___  _ __ ___ 
+" \ \ / / | '_ ` _ \| '__/ __|
+"  \ V /| | | | | | | | | (__ 
+"   \_/ |_|_| |_| |_|_|  \___|
 
-set number
-"set relativenumber
-set nocompatible
-set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
-
-
-"plugin stuff with pathogen below : need to install pathogen separately
+let mapleader =" "
 filetype off
 execute pathogen#infect()
 execute pathogen#helptags()
@@ -39,13 +12,26 @@ filetype plugin indent on
 syntax on
 set sessionoptions-=options
 
-autocmd Filetype make set noexpandtab
-autocmd FileType tex setlocal spell spelllang=en_au
-autocmd Filetype c set shiftwidth=4
-autocmd Filetype cpp set shiftwidth=4
+"   basics:
+    set tabstop=4
+    set softtabstop=0
+    set shiftwidth=4
+    set expandtab
+    set smarttab
+    set autoindent
+    set path+=** ""recursive subdirectory search
+    set wildmenu
+    set wildmode=longest,list,full
+    set encoding=utf-8
+    "color pablo
+    color molokai
+    set clipboard=unnamedplus
+    set number
+    set nocompatible
+    set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
 
-"Python
-"let python_highlight_all=1
+autocmd Filetype make set noexpandtab "force tabs for make
+"PEP8 approved:
 autocmd Filetype python set tabstop=4 
 autocmd Filetype python set softtabstop=4
 autocmd Filetype python set shiftwidth=4
@@ -59,15 +45,15 @@ let g:NERDTreeWinSize=15
 map <C-a> :NERDTreeToggle<CR>
 
 "Syntastic
-"set statusline+=%#warningmsg#
-"set statusline+=%{SyntasticStatuslineFlag()}
-"set statusline+=%*
+set statusline+=%#warningmsg#
+set statusline+=%{SyntasticStatuslineFlag()}
+set statusline+=%*
 
-"let g:syntastic_always_populate_loc_list = 1
-"let g:syntastic_auto_loc_list = 1
-"let g:syntastic_check_on_open = 1
-"let g:syntastic_check_on_wq = 0
-"let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
+let g:syntastic_always_populate_loc_list = 1
+let g:syntastic_auto_loc_list = 1
+let g:syntastic_check_on_open = 1
+let g:syntastic_check_on_wq = 0
+let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
 
 "tagbar
 nmap <C-s> :TagbarToggle<CR>
@@ -76,6 +62,19 @@ let g:tagbar_autofocus = 1
 "let g:tagbar_left = 1
 let g_tagbar_width = 15
 
-"Automatically reload sxhkd on write:
-autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
+"snippets:
+nnoremap ,latex :-1read $dotfiles/snippets/assignment.tex<CR>72jo
+nnoremap ,texfig :-1read $dotfiles/snippets/figure.tex<CR><CR>$i
 
+
+command! Texit !pdflatex % 
+command! Maketags !ctags -R .
+map <leader>o :setlocal spell! spelllang=en_au<CR>
+autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
+"usage: ^]: jump to tag under cursorm g^] ambiguos tags, ^t, jump back up tag
+"stack
+    set splitbelow splitright
+    map <C-h> <C-w>h
+    map <C-j> <C-w>j
+    map <C-k> <C-w>k
+    map <C-l> <C-w>l

commit a14c5185fb8af04d8e074c4c6ae093e80d37a5b3
Author: maxwellodri <maxwellodri@gmail.com>
Date:   Fri Apr 24 07:30:38 2020 +1000

    EOL i3

diff --git a/.vimrc b/.vimrc
index 2db4bd8..6abcd9c 100644
--- a/.vimrc
+++ b/.vimrc
@@ -26,7 +26,7 @@ color molokai
 set clipboard=unnamedplus
 
 set number
-set relativenumber
+"set relativenumber
 set nocompatible
 set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
 
@@ -59,20 +59,23 @@ let g:NERDTreeWinSize=15
 map <C-a> :NERDTreeToggle<CR>
 
 "Syntastic
-set statusline+=%#warningmsg#
-set statusline+=%{SyntasticStatuslineFlag()}
-set statusline+=%*
+"set statusline+=%#warningmsg#
+"set statusline+=%{SyntasticStatuslineFlag()}
+"set statusline+=%*
 
-let g:syntastic_always_populate_loc_list = 1
-let g:syntastic_auto_loc_list = 1
-let g:syntastic_check_on_open = 1
-let g:syntastic_check_on_wq = 0
-let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
+"let g:syntastic_always_populate_loc_list = 1
+"let g:syntastic_auto_loc_list = 1
+"let g:syntastic_check_on_open = 1
+"let g:syntastic_check_on_wq = 0
+"let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
 
-"tagba
+"tagbar
 nmap <C-s> :TagbarToggle<CR>
 let g:tagbar_autoclose = 1
 let g:tagbar_autofocus = 1
 "let g:tagbar_left = 1
 let g_tagbar_width = 15
 
+"Automatically reload sxhkd on write:
+autocmd BufWritePost *sxhkdrc !killall sxhkd; setsid sxhkd &
+

commit 002ced5095f09f63f4277b199ed0d0f19117226f
Author: maxwellodri <maxwellodri@gmail.com>
Date:   Sun Apr 19 21:49:32 2020 +1000

    Fixed template.tex synatx

diff --git a/.vimrc b/.vimrc
index 8e69438..2db4bd8 100644
--- a/.vimrc
+++ b/.vimrc
@@ -67,6 +67,7 @@ let g:syntastic_always_populate_loc_list = 1
 let g:syntastic_auto_loc_list = 1
 let g:syntastic_check_on_open = 1
 let g:syntastic_check_on_wq = 0
+let g:syntastic_tex_lacheck_quiet_messages = { 'regex': '\Vpossible unwanted space at' } "Annoying LaTeX Message
 
 "tagba
 nmap <C-s> :TagbarToggle<CR>

commit 8efe0b79fe7e001749b1c4d55031150e9415ff6e
Author: maxwellodri <maxwellodri@gmail.com>
Date:   Fri Apr 17 23:24:02 2020 +1000

    cleaned up the repo file structure a bit

diff --git a/.vimrc b/.vimrc
index 9031517..8e69438 100644
--- a/.vimrc
+++ b/.vimrc
@@ -42,6 +42,7 @@ set sessionoptions-=options
 autocmd Filetype make set noexpandtab
 autocmd FileType tex setlocal spell spelllang=en_au
 autocmd Filetype c set shiftwidth=4
+autocmd Filetype cpp set shiftwidth=4
 
 "Python
 "let python_highlight_all=1
@@ -67,4 +68,10 @@ let g:syntastic_auto_loc_list = 1
 let g:syntastic_check_on_open = 1
 let g:syntastic_check_on_wq = 0
 
+"tagba
+nmap <C-s> :TagbarToggle<CR>
+let g:tagbar_autoclose = 1
+let g:tagbar_autofocus = 1
+"let g:tagbar_left = 1
+let g_tagbar_width = 15
 

commit fe1e866053e34127f0e94440f51325f9c0511d49
Author: maxwellodri <maxwellodri@gmail.com>
Date:   Sat Apr 11 01:03:57 2020 +1000

    Cleaned up the syntax on bashrc a bit

diff --git a/.vimrc b/.vimrc
index cbe61e7..9031517 100644
--- a/.vimrc
+++ b/.vimrc
@@ -41,10 +41,30 @@ set sessionoptions-=options
 
 autocmd Filetype make set noexpandtab
 autocmd FileType tex setlocal spell spelllang=en_au
+autocmd Filetype c set shiftwidth=4
 
+"Python
+"let python_highlight_all=1
+autocmd Filetype python set tabstop=4 
+autocmd Filetype python set softtabstop=4
 autocmd Filetype python set shiftwidth=4
-autocmd Filetype c set shiftwidth=4
+"autocmd Filetype python set textwidth=79
+autocmd Filetype python set autoindent 
+autocmd Filetype python set expandtab
+autocmd Filetype python set fileformat=unix 
+
+"NERDTREE
+let g:NERDTreeWinSize=15
+map <C-a> :NERDTreeToggle<CR>
 
+"Syntastic
+set statusline+=%#warningmsg#
+set statusline+=%{SyntasticStatuslineFlag()}
+set statusline+=%*
 
+let g:syntastic_always_populate_loc_list = 1
+let g:syntastic_auto_loc_list = 1
+let g:syntastic_check_on_open = 1
+let g:syntastic_check_on_wq = 0
 
 

commit a1fd8588b23fc97e2f0a37c153474b74edac0ced
Author: maxwellodri <maxwellodri@gmail.com>
Date:   Sun Apr 5 03:37:21 2020 +1000

    5/4/2020 - added todo list

diff --git a/.vimrc b/.vimrc
index ab9c984..cbe61e7 100644
--- a/.vimrc
+++ b/.vimrc
@@ -4,22 +4,47 @@ set shiftwidth=4
 set expandtab
 set smarttab
 set autoindent
-syntax on
+"color blue
+"color darkblue
+"color default
+"color delek
+"color desert
+"color elflord
+"color evening
+"color industry
+"color koehler
+"color morning
+"color murphy
+"color pablo
+"color peachpuff
+"color ron
+"color shine
+"color slate
+"color torte
+"color zellner
+color molokai
 set clipboard=unnamedplus
-"set spell "spell checking
 
 set number
 set relativenumber
+set nocompatible
+set whichwrap=b,s,<,>,[,] "traverse end of line with arrow keys
 
-filetype on
-autocmd Filetype make set noexpandtab
 
 "plugin stuff with pathogen below : need to install pathogen separately
-set nocompatible
-filetype plugin indent on
+filetype off
 execute pathogen#infect()
+execute pathogen#helptags()
+filetype plugin indent on
+syntax on
 set sessionoptions-=options
 
+autocmd Filetype make set noexpandtab
+autocmd FileType tex setlocal spell spelllang=en_au
+
+autocmd Filetype python set shiftwidth=4
+autocmd Filetype c set shiftwidth=4
+
 
 
 

commit b38fee7b97277559188f05870e1d83212e65c2ec
Author: maxwell <maxwellodri@gmail.com>
Date:   Sat May 4 23:10:27 2019 +1000

    removed commit history because made repo v large

diff --git a/.vimrc b/.vimrc
new file mode 100644
index 0000000..ab9c984
--- /dev/null
+++ b/.vimrc
@@ -0,0 +1,25 @@
+set tabstop=4
+set softtabstop=0
+set shiftwidth=4
+set expandtab
+set smarttab
+set autoindent
+syntax on
+set clipboard=unnamedplus
+"set spell "spell checking
+
+set number
+set relativenumber
+
+filetype on
+autocmd Filetype make set noexpandtab
+
+"plugin stuff with pathogen below : need to install pathogen separately
+set nocompatible
+filetype plugin indent on
+execute pathogen#infect()
+set sessionoptions-=options
+
+
+
+
