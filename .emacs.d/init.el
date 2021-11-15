(setq user-emacs-directory "/home/maxwell/.emacs.d/") 
(setenv "HOME" "/home/maxwell/")
(require 'package)
(package-initialize)
(setq package-archives '(("melpa" . "http://melpa.org/packages/")
                         ("gnu" . "http://elpa.gnu.org/packages/"))) (setq vc-follow-symlinks t)


(defconst ha/emacs-directory (concat (getenv "HOME") ".emacs.d/"))
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

(use-package org
  :ensure t)

(use-package evil
  :ensure t
  :init
  (setq evil-want-integration t) ;;Set to t by default.
  (setq evil-want-keybinding nil)
  :config
  (evil-mode 1))

(defconst config-org (expand-file-name "config.org" org-directory)
  "Should be ~/org/config.org on *nix"
)
;; the rest of the configuration can be found in:
(when (file-exists-p config-org)
  (org-babel-load-file config-org)
)

