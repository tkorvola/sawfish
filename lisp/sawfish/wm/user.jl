;; user.jl -- do user-local initialization
;;
;; Copyright (C) 2000 John Harper <john@dcs.warwick.ac.uk>
;;
;; This file is part of sawfish.
;;
;; sawfish is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; sawfish is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with sawfish; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301 USA.

;; Commentary:

;; The idea is that the `user' module is where all user code gets to
;; play. By default it has a set of modules opened so that it looks
;; pretty much how the old non-modular wm looked.

;; This means that the `sawfish.wm' structures aren't modified by user
;; code, this is a good thing, since it means that modules importing
;; `sawfish.wm.foo' know what they are getting (no random user
;; bindings)

;; The downside is that it's harder for user extensions to redefine
;; existing code, IMHO this may also be a good thing..

(define-structure user

    (export )

    ((open rep
	   rep.regexp
	   rep.system
	   rep.io.files
	   rep.io.processes
	   sawfish.wm
	   sawfish.wm.util.groups
	   sawfish.wm.util.display-window
	   sawfish.wm.util.compat
	   sawfish.wm.ext.error-handler
	   sawfish.wm.ext.apps-menu
	   sawfish.wm.edge.conf
	   sawfish.wm.edge.actions
	   sawfish.wm.frames
	   sawfish.wm.menus
	   sawfish.wm.commands.launcher
	   sawfish.wm.ext.wallpaper
	   sawfish.wm.prg.compton
	   sawfish.wm.prg.conky
	   sawfish.wm.prg.trayer
	   sawfish.wm.prg.xgamma
	   sawfish.wm.prg.xmobar
	   sawfish.wm.prg.xmodmap
	   sawfish.wm.prg.xsettingsd)
     (access sawfish.wm.integration.kde
	     sawfish.wm.integration.gnome
	     sawfish.wm.integration.xfce
	     sawfish.wm.integration.mate
	     sawfish.wm.integration.lxde
	     sawfish.wm.integration.lumina)

     (set-binds))

  ;; "none" looks ugly, but if you are to change it to "", fix
  ;; apps-menu, too, or it will break.
  (defvar desktop-environment "none"
    "Running desktop environment, detected by Sawfish.
Possible values are \"kde\", \"gnome\", \"mate\", \"xfce\", \"lxde\", \"lumina\" or \"none\".")

  (defvar want-poweroff-menu t
    "Add poweroff menu if you don't use GNOME / KDE / XFCE / Razor-Qt / LXDE / Lumina.")

  (defvar want-extra-menu-entries t
    "Provide additional entries in root menu.")

  (defvar after-init-hook nil
    "Hook to be run after initialisation.
Can be used to repair damage done in user.jl after reading
.sawfish/rc.")

  (setq *user-structure* 'user)

  ;; frame-style loaded if user hasn't set their own
  (define fallback-frame-style 'StyleTab)

  ;; give root-window 'WINDOW_MANAGER property with value sawfish
  (unless batch-mode
    (set-x-text-property 'root 'WINDOW_MANAGER (vector "sawfish")))

  (define rc-files '("~/.sawfishrc" "~/.sawfish/rc"))

  ;; initialize the special variable pointing at this structure
  (structure () (open rep rep.structures)
    (setq *user-module* (get-structure 'user)))

  (define (safe-load . args)
    (condition-case data
	(apply load args)
      (error
       (error-handler-function (car data) (cdr data)))))

  (define (rename-old-stuff)
    (when (and (file-directory-p "~/.sawmill")
	       (not (file-exists-p "~/.sawfish")))
      (rename-file "~/.sawmill" "~/.sawfish")
      (message "Renamed directory ~/.sawmill -> ~/.sawfish")
      (make-symlink "~/.sawmill" ".sawfish")
      (message "Created .sawmill symlink (delete if unwanted)"))

    (when (and (file-exists-p "~/.sawmillrc")
	       (not (file-exists-p "~/.sawfishrc")))
      (rename-file "~/.sawmillrc" "~/.sawfishrc")
      (message "Renamed file ~/.sawmillrc -> ~/.sawfishrc"))
    )

  ;; Detect desktop environment.
  ;; These functions have to non-nil if it detects a DE, otherwise nil.
  ;; It should also initialize, and set `desktop-environment',
  ;; and probably `want-poweroff-menu', too.
  (define (detect-desktop-environment)
    (or (sawfish.wm.integration.gnome#detect-gnome)
	(sawfish.wm.integration.mate#detect-mate)
	(sawfish.wm.integration.kde#detect-kde)
	(sawfish.wm.integration.xfce#detect-xfce)
	(sawfish.wm.integration.lxde#detect-lxde)
	(sawfish.wm.integration.lumina#detect-lumina))
    )

  ;; Don't signal an error even if user "require" them. These modules
  ;; existed in the past.
  (provide 'sawfish-defaults)
  (provide 'sawfish.wm.defaults)

;;; From here, executed at startup.

  ;; load ~/.sawfish/rc
  (setq error-destination 'init)
  (unless (get-command-line-option "--no-rc")
    (condition-case error-data
	(progn
	  ;; First the site-wide stuff
	  (load-all "site-init" (lambda (f) (safe-load f nil t)))

	  ;; then the users rep configuration, or site-wide defaults
	  (or (safe-load (concat (user-home-directory) ".reprc") t t t)
	      (safe-load "rep-defaults" t))

	  (unless batch-mode
	    (rename-old-stuff)
	    ;; detect DE before loading rc
            (detect-desktop-environment)

	    ;; then the customized options
	    (condition-case data
		(custom-load-user-file)
	      (error
	       (format (stderr-file) "error in custom file--> %S\n" data)))

	    ;; then the sawfish specific user configuration
	    (let loop ((rest rc-files))
	      (when rest
		(if (file-exists-p (car rest))
		    ;; Print stack trace on error during exeuction
		    ;; of ~/.sawfish/rc
		    (let ((%in-condition-case nil))
		      (safe-load (car rest) t t t))
		  (loop (cdr rest)))))))
      (error
       (format (stderr-file) "error in local config--> %S\n" error-data))))

  (when (equal desktop-environment "kde")
    (sawfish.wm.integration.kde#kde-late-init))

  (when (equal desktop-environment "lumina")
    (sawfish.wm.integration.lumina#lumina-window-matchers))

  (unless batch-mode
    (when want-extra-menu-entries
      (let ((menu root-menu))
        (user-require 'sawfish.wm.ext.run-application)
        (nconc menu `(()))
	(unless (equal xterm-program "")
	  (nconc menu `((,(_ "Open _Terminal") (xterm)))))
        (unless (equal filemanager-program "")
          (nconc menu `((,(_ "_Open Home") (filemanager "~")))))
	(unless (equal browser-program "")
	  (nconc menu `((,(_ "Open _Browser") (browser)))))
	(nconc menu `((,(_ "_Run Application") (run-application))))
        (nconc menu `((,(_ "_Kill Window") (system "xkill &")))))))

  ;; generate apps-menu from *.desktop files
  (unless batch-mode
    (init-apps-menu))

  ;; initialize edges, unless disabled
  (when (and (not batch-mode)
	   edge-actions-enabled)
      (activate-edges t))

  ;; apply customized frame-fonts
  (when use-custom-font
    (update-frame-font))

  ;; apply customized font-colors
  (when use-custom-font-color
    (update-frame-font-color))

  ;; apply customized cursor-shapes
  (when use-custom-button-cursor-shape
    (update-button-cursor-shape))

  ;; apply customized border-width/color
  (when use-custom-border
    (update-border-color-width))

  ;; apply customized text-position
  (when use-custom-text-position
    (update-text-position))

  (when want-poweroff-menu
    (add-poweroff-menu))

  ;; use a default theme if none given
  (unless (or batch-mode default-frame-style)
    (setq default-frame-style fallback-frame-style))

  (unless (and (boundp 'window-menu) window-menu)
    (require 'sawfish.wm.ext.beos-window-menu))

  ;; Use all arguments which are left.
  (let ((do-load (lambda (name)
		   (cond ((file-exists-p name)
			  (load name nil t t))
			 ((string-match "\\.jlc?$" name)
			  (load name))
			 (t (require (intern name))))))
	arg)
    (while (setq arg (car command-line-args))
      (setq command-line-args (cdr command-line-args))
      (cond
       ((member arg '("-f" "--call"))
	(setq arg (car command-line-args))
	(setq command-line-args (cdr command-line-args))
	((symbol-value (read-from-string arg))))
       ((member arg '("-l" "--load"))
	(setq arg (car command-line-args))
	(setq command-line-args (cdr command-line-args))
	(do-load arg))
       ((member arg '("-q" "--quit"))
	(throw 'quit 0))
       (t (do-load arg)))))

  (unless batch-mode
    (add-hook 'before-restart-hook
      (lambda () (let ((sc (get-window-by-class
			     "Sawfish-Configurator" #:regex t)))
		   (when sc
		     (delete-window-safely sc)
		     (system "touch ~/.restart_sc &")))))

    (add-hook 'before-exit-hook
      (lambda () (let ((sc (get-window-by-class
			     "Sawfish-Configurator" #:regex t)))
		   (when sc
		     (delete-window-safely sc)))))

    (when (file-exists-p "~/.restart_sc")
      (system "sawfish-config &")
      (delete-file "~/.restart_sc")))

  ;; auto-start handling
  (unless batch-mode
    (when init-xgamma
      (add-hook 'after-initialization-hook (lambda () (xgamma-set-from-cfg t t t)) t))
    (when init-wallpaper
      (add-hook 'after-initialization-hook set-wallpaper t))
    (when init-trayer
      (add-hook 'after-initialization-hook start-trayer t))
    (when init-xmobar
      (add-hook 'after-initialization-hook start-xmobar t))
    (when init-xmodmap
      (add-hook 'after-initialization-hook load-xmodmap t)
      (add-hook 'before-restart-hook restore-keymap t))
    (when init-xsettingsd
      (add-hook 'after-initialization-hook start-xsettingsd t))
    (when init-conky
      (add-hook 'after-initialization-hook start-conky t)))

  (when (eq error-destination 'init)
    (setq error-destination 'standard-error))
    
  (call-hook 'after-init-hook))

;; prevent this file being loaded as a module
nil
