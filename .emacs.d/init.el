(setq user-emacs-directory "/home/maxwell/.emacs.d/") 
(setenv "HOME" "/home/maxwell/")
(require 'package)
(package-initialize)
(setq package-archives '(("melpa" . "http://melpa.org/packages/")
                         ("gnu" . "http://elpa.gnu.org/packages/")))

(defconst ha/emacs-directory (concat (getenv "HOME") "/.emacs.d/"))
(defun ha/emacs-subdirectory (d) (expand-file-name d ha/emacs-directory))

(setq custom-file (expand-file-name "custom.el" ha/emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-verbose t)
(setq use-package-always-ensure t)
(eval-when-compile (require 'use-package))
(use-package auto-compile
  :config (auto-compile-on-load-mode))
(setq load-prefer-newer t)

(use-package org
  :ensure t)

(use-package evil
  :ensure t
  :config
  (evil-mode 1))

;; the rest of the configuration can be found in:
(org-babel-load-file (concat user-emacs-directory "config.org"))


(fset 'yes-or-no-p 'y-or-n-p)
(server-start)

;;Theming
(load-theme 'misterioso t)
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


