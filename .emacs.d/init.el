(setq user-emacs-directory "/home/maxwell/.emacs.d/") 
(require 'package)
(package-initialize)
(add-to-list 'package-archives '("gnu" . "http://elpa.gnu.org/packages/"))
(add-to-list 'package-archives '("melpa" . "http://stable.melpa.org/packages/"))

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
