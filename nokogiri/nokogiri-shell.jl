#| nokogiri-shell.jl -- shell displaying custom groups

   $Id$

   Copyright (C) 2000 John Harper <john@dcs.warwick.ac.uk>

   This file is part of sawfish.

   sawfish is free software; you can redistribute it and/or modify it
   under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   sawfish is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with sawfish; see the file COPYING.  If not, write to
   the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
|#

(define-structure nokogiri-shell

    (export initialize-shell
	    destroy-shell
	    run-shell)
  
    (open rep
	  gtk
	  nokogiri-group
	  nokogiri-slot
	  nokogiri-apply
	  nokogiri-widget
	  nokogiri-layout
	  nokogiri-user-level
	  nokogiri-config)

  (defvar *nokogiri-buttons* nil)

  (defvar *nokogiri-flatten-groups* nil)

  (define main-window)
  (define group-tree-widget)
  (define slot-box-widget)

  (define active-slots '())

  (define ok-widget)
  (define apply-widget)
  (define revert-widget)
  (define cancel-widget)

  (define (initialize-shell &optional socket-id)
    (let ((vbox (gtk-vbox-new nil box-spacing))
	  (paned (gtk-hpaned-new))
	  (hbox (gtk-hbutton-box-new))
	  (s-scroller (and (not socket-id) (gtk-scrolled-window-new))))

      (setq main-window (if socket-id
			    (gtk-plug-new socket-id)
			  (gtk-window-new 'toplevel)))
      (if socket-id
	  (gtk-widget-set-usize main-window 500 400)
	(gtk-window-set-policy main-window nil t nil)
	(gtk-widget-set-usize main-window 600 500))

      (setq slot-box-widget (gtk-vbox-new nil box-spacing))

      (gtk-container-border-width main-window box-border)
      (gtk-container-border-width slot-box-widget box-border)
      (when s-scroller
	(gtk-scrolled-window-set-policy s-scroller 'automatic 'automatic)
	(gtk-scrolled-window-add-with-viewport s-scroller slot-box-widget))

      (let ((group (get-group top-group)))
	(fetch-group group)
	(if (and (not *nokogiri-flatten-groups*) (group-sub-groups group))
	    (let ((paned (gtk-hpaned-new))
		  (g-scroller (gtk-scrolled-window-new)))
	      (setq group-tree-widget (make-group-tree (get-group top-group)))
	      (gtk-container-border-width group-tree-widget box-border)
	      (gtk-scrolled-window-set-policy g-scroller 'automatic 'automatic)
	      (gtk-container-add vbox paned)
	      (gtk-paned-add1 paned g-scroller)
	      (gtk-paned-add2 paned (or s-scroller slot-box-widget))
	      (gtk-paned-set-position paned 150)
	      (gtk-scrolled-window-add-with-viewport g-scroller
						     group-tree-widget))
	  (gtk-container-add vbox (or s-scroller slot-box-widget))))

      (unless socket-id
	(setq ok-widget (gtk-button-new-with-label (_ "OK")))
	(setq apply-widget (gtk-button-new-with-label (_ "Try")))
	(setq revert-widget (gtk-button-new-with-label (_ "Revert")))
	(setq cancel-widget (gtk-button-new-with-label (_ "Cancel")))
	(gtk-window-set-title main-window (_ "Nokogiri"))
	(gtk-widget-set-name main-window (_ "Nokogiri"))
	(gtk-window-set-wmclass main-window "main" "Nokogiri"))

      (gtk-signal-connect main-window "delete_event" on-quit)
      (gtk-container-add main-window vbox)

      (unless socket-id
	(gtk-button-box-set-layout hbox 'end)
	(gtk-box-pack-end vbox hbox)
	(gtk-signal-connect ok-widget "clicked" on-ok)
	(gtk-signal-connect apply-widget "clicked" on-apply)
	(gtk-signal-connect cancel-widget "clicked" on-cancel)
	(gtk-signal-connect revert-widget "clicked" on-revert)
	(gtk-container-add hbox apply-widget)
	(gtk-container-add hbox revert-widget)
	(gtk-container-add hbox ok-widget)
	(gtk-container-add hbox cancel-widget))

      (gtk-widget-show-all main-window)
      (set-button-states)

      (when socket-id
	(setq *nokogiri-apply-immediately* nil)
	(set-input-handler standard-input capplet-input)
	(add-hook '*nokogiri-slot-changed-hook* capplet-state-changed))

      (if group-tree-widget
	  (progn
	    (gtk-tree-select-item group-tree-widget 0)
	    (mapc gtk-tree-item-expand
		  (gtk-container-children group-tree-widget)))
	(select-group (get-group top-group)))))

  (define (destroy-shell)
    (when main-window
      (gtk-widget-destroy main-window)
      (setq main-window nil)
      (setq group-tree-widget nil)
      (setq slot-box-widget nil)
      (setq ok-widget nil)
      (setq apply-widget nil)
      (setq revert-widget nil)
      (setq cancel-widget nil)))

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
    (define (show-hide w state)
      ((if state gtk-widget-show gtk-widget-hide) w))
    (when apply-widget
      (show-hide apply-widget (eq *nokogiri-buttons* 'apply/revert/cancel/ok))
      (gtk-widget-set-sensitive apply-widget (changes-to-apply-p)))
    (when revert-widget
      (show-hide revert-widget (memq *nokogiri-buttons*
				     '(revert/cancel/ok
				       apply/revert/cancel/ok)))
      (gtk-widget-set-sensitive revert-widget (changes-to-revert-p)))
    (when ok-widget
      (gtk-widget-set-sensitive ok-widget (or (eq *nokogiri-buttons* 'ok)
					      (changes-to-apply-p)
					      (changes-to-revert-p))))
    (when cancel-widget
      (show-hide cancel-widget (memq *nokogiri-buttons*
				     '(revert/cancel/ok
				       apply/revert/cancel/ok)))))

;;; displaying custom groups

  (define (get-slots group)
    (fetch-group group)
    (filter slot-is-appropriate-p (group-slots group)))

  (define (display-flattened group)

    (define (iter book group slots)
      (when slots
	(let ((layout (layout-slots (group-layout group) slots)))
	  (setq active-slots (nconc active-slots slots))
	  (gtk-notebook-append-page
	   book layout (gtk-label-new (group-real-name group)))))
      (mapc (lambda (sub)
	      (let ((slots (get-slots sub)))
		(when (or slots (group-sub-groups group))
		  (iter book sub slots))))
	    (get-sub-groups group)))

    (let ((notebook (gtk-notebook-new)))
      (gtk-notebook-set-scrollable notebook 1)
      (gtk-notebook-popup-enable notebook)
      (iter notebook group (get-slots group))
      (gtk-widget-show notebook)
      (gtk-container-add slot-box-widget notebook)))

  (define (display-unflattened group)
    (let* ((slots (get-slots group)))
      (gtk-container-add
       slot-box-widget (layout-slots (group-layout group) slots))
      (setq active-slots (nconc active-slots slots))))

  (define (add-group-widgets group)
    (if (and *nokogiri-flatten-groups* (group-sub-groups group))
	(display-flattened group)
      (display-unflattened group))
    (update-all-dependences))

  (define (remove-group-widgets group)
    (mapc (lambda (s)
	    (let ((w (slot-gtk-widget s)))
	      (when (gtk-widget-parent w)
		(gtk-container-remove (gtk-widget-parent w) w))
	      (set-slot-layout s nil))) active-slots)
    (setq active-slots '())
    (mapc (lambda (w)
	    (gtk-container-remove slot-box-widget w))
	  (gtk-container-children slot-box-widget)))

  (define (run-shell &optional socket-id)
    (initialize-configs)
    (initialize-shell socket-id)
    (catch 'nokogiri-exit
      (recursive-edit)))

  (add-hook '*nokogiri-slot-changed-hook* set-button-states t)
  (add-hook '*nokogiri-group-selected-hook* add-group-widgets)
  (add-hook '*nokogiri-group-deselected-hook* remove-group-widgets)

  (define-config-item 'nokogiri-buttons
		      '*nokogiri-buttons*
		      (lambda ()
			(set-button-states)
			(setq *nokogiri-apply-immediately*
			      (memq *nokogiri-buttons*
				    '(ok revert/cancel/ok)))))

;;; capplet interfacing

  ;; called when there's input available on stdin
  (defun capplet-input ()
    (let ((tem (read-line standard-input)))
      (condition-case nil
	  (progn
	    (cond ((string-match "apply" tem) (on-apply))
		  ((string-match "revert" tem) (on-revert))
		  ((string-match "ok" tem) (on-ok))
		  ((string-match "cancel" tem) (on-cancel)))
	    (write standard-output ?\001)
	    (flush-file standard-output))
	(end-of-stream))))

  (defun capplet-state-changed ()
    (write standard-output ?c)
    (flush-file standard-output))

  (defun capplet-no-group ()
    (write standard-output ?g)
    (flush-file standard-output)))