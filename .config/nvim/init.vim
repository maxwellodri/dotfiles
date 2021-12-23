set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath=&runtimepath
source ~/.vimrc
lua <<EOF
require('lspconfig').pyright.setup{
  settings = {
    pyright = {
        disableLanguageServices = true,
        disableOrganizeImports  = true,
      }
  }
}
EOF
