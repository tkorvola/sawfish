;; nokogiri-shell.jl -- shell displaying custom groups
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

(define-structure sawfish.cfg.shell

    (export run-shell)

    (open rep
	  gui.gtk-2.gtk
	  rep.system
	  rep.regexp
	  rep.io.files
	  rep.io.streams
	  rep.io.timers
	  sawfish.gtk.widget
	  sawfish.cfg.i18n
	  sawfish.cfg.group
	  sawfish.cfg.slot
	  sawfish.cfg.apply
	  sawfish.cfg.layout
	  sawfish.cfg.config
	  sawfish.cfg.wm)

  (defvar *nokogiri-flatten-groups* nil)

  (define main-window)
  (define group-tree-widget)
  (define slot-box-widget)

  (define active-slots '())

  (define ok-widget)
  (define revert-widget)
  (define wiki-button)
  (define doc-button)
  (define about-button)
  (define edit-button)
  (define install-theme-label)
  (define install-theme-button)

  (define (initialize-shell)
    (let ((vbox (gtk-vbox-new nil box-spacing))
	  (hbox-a (gtk-hbutton-box-new))
	  (hbox-b (gtk-hbutton-box-new))
	  (s-scroller (gtk-scrolled-window-new))
	  root-container)

      (setq main-window (gtk-window-new 'toplevel))

      (gtk-box-set-homogeneous hbox-a t)
      (gtk-box-set-homogeneous hbox-b t)
      (gtk-window-set-resizable main-window t)
      (gtk-window-set-icon-name main-window "sawfish-config")
      (gtk-window-set-default-size main-window 550 400)
      (setq root-container (gtk-frame-new))
      (gtk-frame-set-shadow-type root-container 'etched-in)
      (gtk-container-add main-window root-container)

      (setq slot-box-widget (gtk-vbox-new nil box-spacing))

      (gtk-container-set-border-width vbox box-border)
      (gtk-container-set-border-width slot-box-widget box-border)
      (when s-scroller
	(gtk-scrolled-window-set-policy s-scroller 'automatic 'automatic)
	(gtk-scrolled-window-add-with-viewport s-scroller slot-box-widget))

      (let ((group (get-group top-group)))
	(fetch-group group)
	(if (and (not *nokogiri-flatten-groups*)
		 (group-sub-groups group))
	    (let ((paned (gtk-hpaned-new))
		  (g-scroller (gtk-scrolled-window-new)))
	      (setq group-tree-widget (make-group-tree (get-group top-group)))
	      (gtk-container-set-border-width group-tree-widget box-border)
	      (gtk-scrolled-window-set-policy g-scroller 'automatic 'automatic)
	      (gtk-container-add vbox paned)
	      (gtk-paned-add1 paned g-scroller)
	      (gtk-paned-add2 paned (or s-scroller slot-box-widget))
	      (gtk-paned-set-position paned 250)
	      (gtk-scrolled-window-add-with-viewport g-scroller
						     group-tree-widget))
	  (gtk-container-add vbox (or s-scroller slot-box-widget))))


	(setq ok-widget (gtk-button-new-from-stock "gtk-close"))
	(gtk-button-set-relief ok-widget 'none)
	(setq revert-widget (gtk-button-new-from-stock "gtk-undo"))
	(gtk-button-set-relief revert-widget 'none)
	
	(setq wiki-button (gtk-link-button-new-with-label "http://sawfish.wikia.com/" "Browse Wiki"))
	(gtk-button-set-relief wiki-button 'none)
	
	(setq edit-button (gtk-button-new-from-stock "gtk-edit"))
	(gtk-button-set-label edit-button "Edit RC")
	(gtk-button-set-relief edit-button 'none)
	
	(setq about-button (gtk-button-new-from-stock "gtk-about"))
	(gtk-button-set-relief about-button 'none)
	(setq doc-button (gtk-button-new-from-stock "gtk-help"))
	(gtk-button-set-relief doc-button 'none)
	
	(setq install-theme-label (gtk-label-new "Install theme:"))
	(setq install-theme-button (gtk-file-chooser-button-new '() 'open))
	(gtk-file-chooser-set-filename install-theme-button "~")

	(gtk-window-set-title main-window (_ "Sawfish Configurator"))
	(gtk-widget-set-name main-window (_ "Sawfish Configurator"))
	(gtk-window-set-wmclass main-window "sawfish-configurator"
                                "Sawfish-Configurator")

      (g-signal-connect main-window "delete_event" on-quit)

	(gtk-box-set-spacing hbox-a button-box-spacing)
	(gtk-button-box-set-layout hbox-a 'spread)

	(gtk-box-set-spacing hbox-b button-box-spacing)
	(gtk-button-box-set-layout hbox-b 'spread)
	
	(gtk-box-pack-end vbox hbox-b)
	(gtk-box-pack-end vbox hbox-a)

	(g-signal-connect ok-widget "clicked" on-ok)
	(g-signal-connect revert-widget "clicked" on-revert)
	
	(g-signal-connect edit-button "clicked"
	  (lambda () (if (file-exists-p "~/.sawfishrc")
		         (system "xdg-open ~/.sawfishrc &")
		       (if (file-exists-p "~/.sawfish/rc")
			   (system "xdg-open ~/.sawfish/rc &")
			 (system "echo \";;; Sawfish Resource File\" > ~/.sawfishrc &")
			 (system "xdg-open ~/.sawfishrc &")))))
	
	(g-signal-connect about-button "clicked"
	  (lambda () (system "sawfish-about >/dev/null 2>&1 </dev/null &")))
	
	(g-signal-connect doc-button "clicked"
	  (lambda () (system "x-terminal-emulator -e \"info sawfish Top\" &")))
	
	(g-signal-connect install-theme-button "file-set"
	  (lambda () (let ((file (gtk-file-chooser-get-filename install-theme-button))
			   (filex))
		       (unless (file-exists-p "~/.sawfish/themes/")
			 (unless (file-exists-p "~/.sawfish/")
			   (make-directory "~/.sawfish/"))
			 (make-directory "~/.sawfish/themes/"))
		       (setq filex (last (string-split "/" file)))
		       (gtk-file-chooser-set-filename install-theme-button "~")
		       (if (string-match "\\.tar" filex)
			   (copy-file file (concat "~/.sawfish/themes/" filex))
			 (sawfish-config-display-info "Only tar-archives can be installed at the moment." nil)))))

	(gtk-container-add hbox-a wiki-button)
	(gtk-container-add hbox-b install-theme-label)
	(gtk-container-add hbox-b install-theme-button)
	(gtk-container-add hbox-b doc-button)
	(gtk-container-add hbox-b edit-button)
	(gtk-container-add hbox-a about-button)
	(gtk-container-add hbox-a revert-widget)
	(gtk-container-add hbox-a ok-widget)

      (gtk-container-add root-container vbox)
      (gtk-widget-show-all main-window)
      (set-button-states)

      (if group-tree-widget
	  (progn
	    (gtk-tree-select-item group-tree-widget 0)
	    (mapc gtk-tree-item-expand
		  (gtk-container-get-children group-tree-widget)))
	(select-group (get-group top-group)))))

  (define (destroy-shell)
    (when main-window
      (gtk-widget-destroy main-window)
      (setq main-window nil)
      (setq group-tree-widget nil)
      (setq slot-box-widget nil)
      (setq ok-widget nil)
      (setq revert-widget nil)))

  (define (on-quit)
    (destroy-shell)
    (throw 'nokogiri-exit t))

  (define (on-ok)
    (apply-slot-changes)
    (on-quit))

  (define (on-apply)
    (apply-slot-changes)
    (set-button-states))

  (define (on-cancel)
    (revert-slot-changes)
    (on-quit))

  (define (on-revert)
    (revert-slot-changes)
    (set-button-states))

  (define (set-button-states)
    (when revert-widget
      (gtk-widget-set-sensitive revert-widget (changes-to-revert-p)))
    (when ok-widget
      (gtk-widget-set-sensitive ok-widget t)))

;;; displaying custom groups

  (define (get-slots group)
    (fetch-group group)
    (group-slots group))

  (define (add-active-slots slots)
    (setq active-slots (nconc active-slots
			      (filter (lambda (x)
					(not (memq x active-slots))) slots))))

  (define (display-book-tree group)

    (define (iter group slots)
      (let ((group-page (and slots (layout-slots (group-layout group) slots))))
	(add-active-slots slots)
	(when (and group-page (gtk-container-p group-page))
	  (gtk-container-set-border-width group-page box-border))
	(if (group-sub-groups group)
	    (let ((book (gtk-notebook-new)))
	      (gtk-notebook-set-scrollable book t)
	      (gtk-notebook-popup-enable book t)
	      (when group-page
		(gtk-notebook-append-page
		 book group-page (gtk-label-new (_ (group-real-name group)))))
	      (mapc (lambda (sub)
		      (fetch-group sub)
		      (let ((slots (get-slots sub)))
			(when (or slots (group-sub-groups sub))
			  (let ((page (iter sub slots)))
			    (when page
			      (gtk-notebook-append-page
			       book page (gtk-label-new
					  (_ (group-real-name sub)))))))))
		    (get-sub-groups group))
	      (gtk-widget-show book)
	      book)
	  group-page)))

    (let ((page (iter group (get-slots group))))
      (when page
	(gtk-container-add slot-box-widget page))))

  (define (display-flattened group)

    (define (iter book group slots)
      (when slots
	(let ((layout (layout-slots (group-layout group) slots)))
	  (add-active-slots slots)
          (gtk-box-pack-start book layout)
	  (when (gtk-container-p layout)
	    (gtk-container-set-border-width layout box-border))))
      (mapc (lambda (sub)
	      (fetch-group sub)
	      (let ((slots (get-slots sub)))
		(when (or slots (group-sub-groups group))
		  (iter book sub slots))))
	    (get-sub-groups group)))

    (let ((notebook (gtk-vbox-new nil 0)))
      (iter notebook group (get-slots group))
      (gtk-widget-show notebook)
      (gtk-container-add slot-box-widget notebook)))

  (define (display-unflattened group)
    (let* ((slots (get-slots group)))
      (gtk-container-add
       slot-box-widget (layout-slots (group-layout group) slots))
      (add-active-slots slots)))

  (define (add-group-widgets group)
    (if (and *nokogiri-flatten-groups* (group-sub-groups group))
	(display-book-tree group)
      (display-unflattened group))
    (update-all-dependences))

  (define (remove-group-widgets group)
    (declare (unused group))
    (mapc (lambda (s)
	    (let ((w (slot-gtk-widget s)))
	      (when (gtk-widget-parent w)
		(gtk-container-remove (gtk-widget-parent w) w))
	      (set-slot-layout s nil))) active-slots)
    (setq active-slots '())
    (mapc (lambda (w)
	    (gtk-container-remove slot-box-widget w))
	  (gtk-container-get-children slot-box-widget)))

  (define (sawfish-config-display-info text kill)
    (let ((window (gtk-window-new 'toplevel))
	  (vbox (gtk-vbox-new nil box-spacing))
	  (label (gtk-label-new text))
	  (button (gtk-button-new-from-stock "gtk-ok")))

      (gtk-window-set-title window "SawfishConfig Info")
      (gtk-window-set-icon-name window "gtk-info")

      (gtk-container-set-border-width window 10)
      
      (gtk-label-set-line-wrap label t)
      
      (gtk-widget-set-size-request label 225 45)
      
      (if kill
	  (progn
	    (g-signal-connect window "delete_event" (lambda () throw 'quit 1))
	    (g-signal-connect button "clicked" (lambda () (throw 'quit 1))))
	(g-signal-connect window "delete_event"
			  (lambda () (gtk-widget-destroy window)))
	(g-signal-connect button "clicked"
			  (lambda () (gtk-widget-destroy window))))
	    
      (gtk-container-add window vbox)
      (gtk-container-add vbox label)
      (gtk-container-add vbox button)

      (gtk-widget-show-all window)

      (setq interrupt-mode 'exit)
      (recursive-edit)
      (throw 'quit 1)))

  (define (run-shell)
    (condition-case nil
	(wm-locale-dir)
      (error (sawfish-config-display-info "Sawfish's configurator needs a running Sawfish. Aborting." t)))
    (when (get-command-line-option "--help")
      (write standard-output "\
usage: sawfish-config [OPTIONS...]\n
where OPTIONS are any of:\n
  --group=GROUP-NAME
  --flatten\n")
      (throw 'quit 0))

    (let ((group (get-command-line-option "--group" t)))
      (when group
	(setq group (read-from-string group))
	(set-top-group (if (listp group) group `(root ,group)))))

    (when (get-command-line-option "--flatten")
      (setq *nokogiri-flatten-groups* t))

    (setq interrupt-mode 'exit)
    (i18n-init)

    (initialize-configs)
    (initialize-shell)

    (catch 'nokogiri-exit
      (recursive-edit))
    (throw 'quit 0))

  (add-hook '*nokogiri-slot-changed-hook* set-button-states t)
  (add-hook '*nokogiri-group-selected-hook* add-group-widgets)
  (add-hook '*nokogiri-group-deselected-hook* remove-group-widgets))
