#| nokogiri-group.jl -- group management

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

(define-structure nokogiri-group

    (export group-name
	    group-real-name
	    group-loaded-p
	    group-slots
	    group-sub-groups
	    group-layout
	    root-group
	    top-group
	    set-top-group
	    group-name-above
	    group-name-add
	    group-name=
	    get-group
	    fetch-group
	    update-group
	    get-sub-groups
	    group-parent
	    make-group-tree
	    select-group
	    redisplay-group)

    (open rep
	  gtk
	  records
	  tables
	  nokogiri-slot
	  nokogiri-wm)

  (define-record-type :group
    (make-group name)
    ;; [no predicate]
    (name group-name)					;full name (a list)
    (real-name group-real-name group-real-name-set)	;human-readable name
    (loaded group-loaded-p group-loaded-set)		;t iff members read
    (slots group-slots group-slots-set)			;list of slots
    (sub-groups group-sub-groups group-sub-groups-set)	;((SYMBOL . REAL)..)
    (tree group-tree group-tree-set)			;GtkTree of sub groups
    (layout group-layout group-layout-set))

  (define-record-discloser :group
    (lambda (g) (format nil "#<:group %s>" (group-name g))))

  ;; hash table of all group objects
  (define group-table (make-table equal-hash equal))

  (define root-group '(root))		;XXX should be a constant

  (define top-group root-group)

  (define (set-top-group g) (setq top-group g))

  (define current-group nil)

  (defvar *nokogiri-group-selected-hook* '())
  (defvar *nokogiri-group-deselected-hook* '())

  (define (get-key lst key) (cadr (memq key lst)))

;;; group name manipulation

  ;; return the name of the parent of the group called GROUP, or
  ;; nil if this is the topmost group
  (define (group-name-above group)
    (if (null (cdr group))
	'()
      (let ((name (copy-sequence group)))
	(rplacd (nthcdr (- (length name) 2) name) '())
	name)))

  (define (group-name-local group) (last group))

  ;; return the name of the child called CHILD of the group called GROUP
  (define (group-name-add group child)
    (append group (list child)))

  (define group-name= equal)

;;; group creation and loading

  ;; return the group called NAME
  (define (get-group name)
    (let ((group (table-ref group-table name)))
      (unless group
	(setq group (make-group name))
	(table-set group-table name group))
      group))

  ;; ensure that all data for GROUP has been read
  (define (fetch-group group)
    (unless (group-loaded-p group)
      (update-group group)))

  ;; forcibly reread data for GROUP
  (define (update-group group)
    (let ((data (wm-load-group (group-name group))))
      ;; DATA is (LAST-NAME-COMPONENT "REAL-NAME" (ITEMS...) OPTIONS...)
      ;; ITEMS are CUSTOM-NAME, or (SUB-GROUP-NAME REAL-NAME)
      (let ((real-name (cadr data))
	    (items (caddr data))
	    (layout (get-key (cdddr data) ':layout)))
	(group-real-name-set group real-name)
	(group-slots-set group (fetch-slots (group-name group)
					    (filter atom items)))
	(group-sub-groups-set group (filter consp items))
	(group-layout-set group (or layout 'vbox))
	(group-loaded-set group t)
	(mapc update-dependences (group-slots group)))))

  (define (get-sub-groups group)
    (mapcar (lambda (cell)
	      (let ((g (get-group (group-name-add (group-name group)
						  (car cell)))))
		(fetch-group g)
		g))
	    (group-sub-groups group)))

  ;; return the parent group of GROUP, or nil
  (define (group-parent group)
    (let ((parent-name (group-name-above (group-name group))))
      (and parent-name (get-group parent-name))))

;;; group widgetry

  (define (make-tree-item parent-name name real-name)
    (let ((item (gtk-tree-item-new-with-label real-name)))
      (gtk-signal-connect
       item "select" (group-selected parent-name name))
      (gtk-signal-connect
       item "deselect" (group-deselected parent-name name))
      item))

  (define (make-tree-subgroup group)
    (unless (group-tree group)
      ;; make sure we know the list of sub-groups
      (fetch-group group)
      (let ((tree (gtk-tree-new)))
	(mapc (lambda (sub)
		(gtk-tree-append
		 tree (make-tree-item (group-name group)
				      (car sub) (cadr sub))))
	      (group-sub-groups group))
	(gtk-widget-show-all tree)	
	(group-tree-set group tree)))
    (group-tree group))

  (define (make-group-tree group)
    (fetch-group group)
    (let ((tree (gtk-tree-new))
	  (item (make-tree-item (group-name-above (group-name group))
				(group-name-local (group-name group))
				(group-real-name group))))
      (gtk-tree-set-selection-mode tree 'browse)
      (gtk-tree-append tree item)
      (gtk-widget-show-all tree)
      tree))

  (define (group-selected parent-name name)
    ;; called when a tree node is selected
    (lambda (item)
      (let ((group (get-group (group-name-add parent-name name))))
	(setq current-group group)

	;; check for sub groups
	(fetch-group group)
	(when (and (group-sub-groups group) (not (group-tree group)))
	  (gtk-tree-item-set-subtree item (make-tree-subgroup group))
	  (gtk-tree-item-expand item))

	;; display the slots for this group
	(call-hook '*nokogiri-group-selected-hook* (list group)))))

  (define (group-deselected parent-name name)
    (lambda (item)
      (let ((group (get-group (group-name-add parent-name name))))
	(call-hook '*nokogiri-group-deselected-hook* (list group))
	(setq current-group nil))))

  (define (select-group group)
    (unless (eq current-group group)
      (when current-group
	(call-hook '*nokogiri-group-deselected-hook* (list current-group)))
      (setq current-group group)
      (call-hook '*nokogiri-group-selected-hook* (list current-group))))

  (define (redisplay-group)
    (when current-group
      (call-hook '*nokogiri-group-deselected-hook* (list current-group))
      (call-hook '*nokogiri-group-selected-hook* (list current-group)))))