(require 'use-package)
(load-theme 'misterioso t)
(use-package rustic)
;;Theme ;;
;;Misc stuff (fset 'yes-or-no-p 'y-or-n-p)
(setenv "HOME" "/home/maxwell/")
(server-start)

;; Remove initial buffer, set index file
(setq inhibit-startup-message t)
(setq initial-buffer-choice (concat user-emacs-directory "index.org"))
;; Hide Scroll bar,menu bar, tool bar
(scroll-bar-mode -1)
(tool-bar-mode -1)
(menu-bar-mode -1)

;; Line numbering
(global-display-line-numbers-mode)
(setq display-line-numbers-type t)

;; Display battery for when in full screen mode
;; (display-battery-mode t)

;; Keybindings
;; (global-set-key (kbd "<f5>") 'revert-buffer)
;; (global-set-key (kbd "<f3>") 'org-export-dispatch)
;; (global-set-key (kbd "<f6>") 'eshell) 
;; (global-set-key (kbd "<f7>") 'ranger) 
;; (global-set-key (kbd "<f8>") 'magit) 


(setq org-src-fontify-natively t
    org-src-tab-acts-natively t
    org-confirm-babel-evaluate nil
    org-edit-src-content-indentation 0)



;;Evil Config

;;(use-package evil-search-highlight-persist)

(setq evil-emacs-state-cursor '("red" box))
(setq evil-normal-state-cursor '("green" box))
(setq evil-visual-state-cursor '("orange" box))
(setq evil-insert-state-cursor '("red" bar))
(setq evil-replace-state-cursor '("red" bar))
(setq evil-operator-state-cursor '("red" hollow))

;;(require 'evil-search-highlight-persist)
;;(global-evil-search-highlight-persist t)


;;Rust Config
