;;(setq visible-bell t)
(setq ring-bell-function 'ignore)
(define-key global-map (kbd "RET") nil)
;; Remove initial buffer, set index file
(setq inhibit-startup-message t)
(setq initial-buffer-choice (concat org-directory "/index.org"))
(eval-when-compile (require 'use-package))

(use-package auto-compile
  :config (auto-compile-on-load-mode))
(setq load-prefer-newer t)

(fset 'yes-or-no-p 'y-or-n-p)
(server-start)

;;Theming
(load-theme 'misterioso t)

;; Hide Scroll bar,menu bar, tool bar
(scroll-bar-mode -1)
(tool-bar-mode -1)
(menu-bar-mode -1)

;; Line numbering
(global-display-line-numbers-mode)
(setq display-line-numbers-type t)

(setq evil-emacs-state-cursor '("red" box))
(setq evil-normal-state-cursor '("green" box))
(setq evil-visual-state-cursor '("orange" box))
(setq evil-insert-state-cursor '("red" bar))
(setq evil-replace-state-cursor '("red" bar))
(setq evil-operator-state-cursor '("red" hollow))
;;Leader Key
(evil-set-leader 'normal (kbd "SPC"))
;;(define-key org-mode-map (kbd "SPC SPC") 'org-open-at-point-global)
(evil-define-key 'normal org-mode-map
  (kbd "<leader> <leader>") 'org-open-at-point-global)


;;Unbind space,tab and return
(with-eval-after-load 'evil-maps
  (define-key evil-motion-state-map (kbd "SPC") nil)
  (define-key evil-motion-state-map (kbd "RET") nil)
  (define-key evil-motion-state-map (kbd "TAB") nil)
  (define-key evil-insert-state-map (kbd "RET") 'newline)
  ;;(define-key evil-normal-state-map (kbd "SPC") 'newline)
)

;;(use-package evil-search-highlight-persist)
;;(require 'evil-search-highlight-persist)
;;(global-evil-search-highlight-persist t)

(define-key org-mode-map (kbd "RET") nil)

(use-package rustic
  :ensure t
  )

(setq org-src-fontify-natively t
      org-src-tab-acts-natively t
      org-confirm-babel-evaluate nil
      org-edit-src-content-indentation 0)

;; Display battery for when in full screen mode
;; (display-battery-mode t)
;; Keybindings
;; (global-set-key (kbd "<f5>") 'revert-buffer)
;; (global-set-key (kbd "<f3>") 'org-export-dispatch)
;; (global-set-key (kbd "<f6>") 'eshell) 
;; (global-set-key (kbd "<f7>") 'ranger) 
;; (global-set-key (kbd "<f8>") 'magit)
