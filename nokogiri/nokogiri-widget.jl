#| nokogiri-widget.jl -- high-level widget encapsulation

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

(define-structure nokogiri-widget

    (export define-widget-type
	    widget-type-constructor
	    make-widget
	    widget-ref
	    widget-set
	    widget-clear
	    widget-gtk-widget
	    widget-valid-p
	    call-callback
	    make-signal-callback
	    set-widget-enabled
	    enable-widget
	    disable-widget
	    box-spacing
	    box-border)

    (open rep
	  gtk)

  (defconst box-spacing 4)
  (defconst box-border 5)

  ;; predefined widget types are:

  ;;	(symbol OPTIONS...)
  ;;	(string)
  ;;	(number [MIN [MAX]])
  ;;	(boolean [LABEL])
  ;;	(color)
  ;;	(font)
  ;;	(or ITEMS...)
  ;;	(and ITEMS...)
  ;;	(v-and ITEMS...)
  ;;	(h-and ITEMS...)
  ;;	(labelled LABEL ITEM)
  ;;	(optional ITEM)

  ;; items without arguments may be specified by name, i.e. `string'
  ;; instead of `(string)'

  (define (define-widget-type name constructor)
    (put name 'nokogiri-widget-constructor constructor))

  (define (widget-type-constructor name)
    (or (get name 'nokogiri-widget-constructor)
	;; try to dynamically load the widget constructor..
	(let ((module-name (intern (concat "nokogiri-widgets/"
					   (symbol-name name)))))
	  (condition-case nil
	      (progn
		(require module-name)
		(get name 'nokogiri-widget-constructor))
	    (error (widget-type-constructor 'unknown))))))
  
  ;; stack `and' items horizontally by default
  (define and-direction (make-fluid 'horizontal))

  (define callback-enabled (make-fluid t))


;;; High level widget management

  ;; each widget is a function taking a single argument, the operation to
  ;; perform on the item. Operations include:

  ;;	(ref) => VALUE
  ;; 	(set VALUE)
  ;;	(clear)
  ;;	gtk-widget => GTK-WIDGET
  ;;	(validp ARG) => BOOL

  ;; functional operations return the function to perform the operation

  ;; create a new item of type defined by CELL, either a list (TYPE ARGS...)
  ;; or a single symbol TYPE. CALLBACK is a function to be called whenever
  ;; the item's value changes
  (define (make-widget cell &optional callback)
    (let*
	((type (or (car cell) cell))
	 (maker (or (widget-type-constructor type)
		    (widget-type-constructor 'unknown))))
      (if maker
	  (apply maker callback (cdr cell))
	(error "No widget of type %s" type))))

  (define (widget-ref item) ((item 'ref)))

  (define (widget-set item value)
    (let-fluids ((callback-enabled nil))
      ((item 'set) value)))

  (define (widget-clear item)
    (let-fluids ((callback-enabled nil))
      ((item 'clear))))

  (define (widget-gtk-widget item) (item 'gtk-widget))

  (define (widget-valid-p item value) ((item 'validp) value))

  (define (set-widget-enabled item enabled)
    (gtk-widget-set-sensitive (widget-gtk-widget item) enabled))

  (define (enable-widget item) (set-widget-enabled item t))
  (define (disable-widget item) (set-widget-enabled item nil))

  (define (get-key lst key) (cadr (memq key lst)))

  (define (call-callback fun)
    (when (and fun (fluid callback-enabled))
      (fun)))

  (define (make-signal-callback fun) (lambda () (call-callback fun)))


;;; Predefined widget constructors

  (define (make-choice-item changed-callback . options)
    (let ((omenu (gtk-option-menu-new))
	  (menu (gtk-menu-new))
	  value)
      (let loop ((rest options)
		 (last nil))
	(when rest
	  (let ((button (gtk-radio-menu-item-new-with-label-from-widget
			 last (symbol-name (car rest)))))
	    (gtk-menu-append menu button)
	    (gtk-widget-show button)
	    (gtk-signal-connect button "toggled"
				(lambda (w)
				  (when (gtk-check-menu-item-active w)
				    (setq value (car rest))
				    (call-callback changed-callback))))
	    (loop (cdr rest) button))))
      (gtk-option-menu-set-menu omenu menu)
      (gtk-widget-show-all omenu)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (setq value x)
		   (let ((idx (list-index options x)))
		     (gtk-option-menu-set-history omenu idx)
		     (do ((i 0 (1+ i))
			  (rest (gtk-container-children menu) (cdr rest)))
			 ((null rest))
		       (gtk-check-menu-item-set-state (car rest) (= i idx))))))
	  ((clear) nop)
	  ((ref) (lambda () value))
	  ((gtk-widget) omenu)
	  ((validp) (lambda (x) (memq x options)))))))

  (define-widget-type 'choice make-choice-item)

  (define (make-symbol-item changed-callback &rest options)
    (let ((widget (gtk-combo-new)))
      (when changed-callback
	(gtk-signal-connect
	 (gtk-combo-entry widget)
	 "changed" (make-signal-callback changed-callback)))
      (when options
	(gtk-combo-set-popdown-strings
	 widget (cons "" (mapcar symbol-name options))))
      (gtk-widget-show widget)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (gtk-entry-set-text (gtk-combo-entry widget)
				       (if x (symbol-name x) ""))))
	  ((clear) (lambda ()
		     (gtk-entry-set-text (gtk-combo-entry widget) "")))
	  ((ref) (lambda ()
		   (string->symbol
		    (gtk-entry-get-text (gtk-combo-entry widget)))))
	  ((gtk-widget) widget)
	  ((validp) symbolp)))))

  (define-widget-type 'symbol make-symbol-item)

  (define (make-string-item changed-callback)
    (let ((widget (gtk-entry-new)))
      (when changed-callback
	(gtk-signal-connect
	 widget "changed" (make-signal-callback changed-callback)))
      (gtk-widget-show widget)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (gtk-entry-set-text widget x)))
	  ((clear) (lambda ()
		     (gtk-entry-set-text widget "")))
	  ((ref) (lambda () (gtk-entry-get-text widget)))
	  ((gtk-widget) widget)
	  ((validp) stringp)))))

  (define-widget-type 'string make-string-item)

  (define (make-number-item changed-callback &optional minimum maximum)
    (let ((widget (gtk-spin-button-new (gtk-adjustment-new
					(or minimum 0)
					(or minimum 0)
					(or maximum 65535)
					1 16 0) 1 0)))
      (when changed-callback
	(gtk-signal-connect
	 widget "changed" (make-signal-callback changed-callback)))
      (gtk-widget-show widget)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (when (numberp x)
		     (gtk-spin-button-set-value widget x))))
	  ((clear) nop)
	  ((ref) (lambda ()
		   (let ((value (gtk-spin-button-get-value-as-float widget)))
		     (if (integerp value)
			 (inexact->exact value)
		       value))))
	  ((gtk-widget) widget)
	  ((validp) numberp)))))

  (define-widget-type 'number make-number-item)

  (define (make-boolean-item changed-callback &optional label)
    (let ((widget (if label
		      (gtk-check-button-new-with-label label)
		    (gtk-check-button-new))))
      (when label
	(gtk-label-set-justify (car (gtk-container-children widget)) 'left))
      (when changed-callback
	(gtk-signal-connect
	 widget "toggled" (make-signal-callback changed-callback)))
      (gtk-widget-show widget)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (gtk-toggle-button-set-state widget x)))
	  ((clear) (lambda ()
		     (gtk-toggle-button-set-state widget nil)))
	  ((ref) (lambda ()
		   (gtk-toggle-button-active widget)))
	  ((gtk-widget) widget)
	  ((validp) (lambda () t))))))

  (define-widget-type 'boolean make-boolean-item)


;;; ``Meta'' widgets

  (define (make-or-item changed-callback &rest items)
    (setq items (mapcar (lambda (x)
			  (make-widget x changed-callback)) items))
    (let* ((box (gtk-vbox-new nil box-spacing))
	   (hboxes (mapcar (lambda ()
			     (gtk-hbox-new nil box-spacing)) items))
	   (checks (mapcar (lambda ()
			     (gtk-check-button-new)) items))
	   (enabled (make-list (length items) nil))
	   (enabled-item nil)
	   (refresh-item
	    (lambda ()
	      (setq enabled (mapcar (lambda (x)
				      (eq enabled-item x)) items))
	      (let ((i 0))
		(mapc (lambda (x)
			(set-widget-enabled x (eq enabled-item x))
			(gtk-toggle-button-set-state
			 (nth i checks) (eq enabled-item x))
			(setq i (1+ i))) items))
	      (call-callback changed-callback)))
	   (toggle-fun
	    (lambda (index)
	      (when (or (eq (nth index items) enabled-item)
			(gtk-toggle-button-active (nth index checks)))
		(setq enabled-item (and (gtk-toggle-button-active
					 (nth index checks))
					(nth index items))))
	      (refresh-item))))
      (do ((i 0 (1+ i)))
	  ((= i (length items)))
	(gtk-signal-connect (nth i checks) "toggled" (lambda ()
						       (toggle-fun i)))
	(gtk-container-border-width (nth i hboxes) box-border)
	(gtk-box-pack-start box (nth i hboxes))
	(gtk-box-pack-start (nth i hboxes) (nth i checks))
	(gtk-box-pack-start (nth i hboxes) (widget-gtk-widget (nth i items))))
      (refresh-item)
      (gtk-widget-show-all box)
      (lambda (op)
	(case op
	  ((set)
	   (lambda (x)
	     (if (null x)
		 (setq enabled-item nil)
	       (if (and enabled-item (widget-valid-p enabled-item x))
		   ;; set the enabled value if possible
		   (widget-set enabled-item x)
		 ;; look for a matching type
		 (catch 'done
		   (do ((i 0 (1+ i)))
		       ((= i (length items)))
		     (when (widget-valid-p (nth i items) x)
		       (setq enabled-item (nth i items))
		       (widget-set enabled-item x)
		       (throw 'done t)))
		   (message (format nil (_ "No matching item for %S") x)))))
	     (refresh-item)))
	  ((clear) (lambda ()
		     (setq enabled-item nil)
		     (mapc (lambda (item)
			     (widget-clear item)) items)
		     (refresh-item)))
	  ((ref) (lambda ()
		   (and enabled-item (widget-ref enabled-item))))
	  ((gtk-widget) box)
	  ((validp) (lambda (x)
		      (catch 'out
			(do ((i 0 (1+ i)))
			    ((= i (length items)))
			  (when (widget-valid-p (nth i items) x)
			    (throw 'out t))))))))))

  (define-widget-type 'or make-or-item)

  (defun make-and-item (changed-callback &rest items)
    (setq items (mapcar (lambda (x)
			  (make-widget x changed-callback)) items))
    (let
	((box ((if (eq (fluid and-direction) 'horizontal)
		   gtk-hbox-new
		 gtk-vbox-new) nil box-spacing)))
      (do ((i 0 (1+ i)))
	  ((= i (length items)))
	(gtk-box-pack-start box (widget-gtk-widget (nth i items))))
      (gtk-container-border-width box box-border)
      (gtk-widget-show-all box)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (do ((i 0 (1+ i)))
		       ((= i (length items)))
		     (widget-set (nth i items) (nth i x)))))
	  ((clear) (lambda () (mapc widget-clear items)))
	  ((ref) (lambda () (mapcar widget-ref items)))
	  ((gtk-widget) box)
	  ((validp) (lambda (x)
		      (cond ((null x))
			    ((or (not (listp x))
				 (/= (length x) (length items)))
			     nil)
			    (t
			     (catch 'out
			       (do ((i 0 (1+ i)))
				   ((= i (length items)))
				 (unless (widget-valid-p
					  (nth i items) (nth i x))
				   (throw 'out nil)))
			       t)))))))))

  (define-widget-type 'and make-and-item)

  (define-widget-type 'h-and (lambda (&rest args)
			       (let-fluids ((and-direction 'horizontal))
				 (apply make-and-item args))))

  (define-widget-type 'v-and (lambda (&rest args)
			       (let-fluids ((and-direction 'vertical))
				 (apply make-and-item args))))

  (define (make-labelled-item changed-callback label item)
    (let ((box (gtk-hbox-new nil box-spacing)))
      (setq item (make-widget item changed-callback))
      (gtk-container-border-width box box-border)
      (gtk-box-pack-start box (widget-gtk-widget item))
      (gtk-box-pack-start box (gtk-label-new label))
      (gtk-widget-show-all box)
      (lambda (op)
	(if (eq op 'gtk-widget)
	    box
	  (item op)))))

  (define-widget-type 'labelled make-labelled-item)

  (define (make-optional-item changed-callback item)
    (let ((box (gtk-hbox-new nil box-spacing))
	  (check (gtk-check-button-new)))
      (setq item (make-widget item changed-callback))
      (gtk-box-pack-start box check)
      (gtk-box-pack-start box (widget-gtk-widget item))
      (gtk-signal-connect
       check "toggled"
       (lambda ()
	 (set-widget-enabled item (gtk-toggle-button-active check))
	 (call-callback changed-callback)))
      (gtk-toggle-button-set-state check nil)
      (gtk-widget-set-sensitive (widget-gtk-widget item) nil)
      (gtk-widget-show-all box)
      (lambda (op)
	(case op
	  ((set) (lambda (x)
		   (when x
		     (widget-set item x))
		   (set-widget-enabled item x)
		   (gtk-toggle-button-set-state check x)))
	  ((clear) (lambda ()
		     (widget-clear item)
		     (disable-widget item)
		     (gtk-toggle-button-set-state check nil)))
	  ((ref) (lambda ()
		   (and (gtk-toggle-button-active check) (widget-ref item))))
	  ((gtk-widget) box)
	  ((validp) (lambda (x)
		      (or (null x) (widget-valid-p item x))))))))

  (define-widget-type 'optional make-optional-item)


;;; widget used for unknown widget types

  (define (make-unknown-item changed-callback)
    (let ((label (gtk-label-new (format nil "** unknown widget **  ")))
	  value)
      (gtk-widget-show label)
      (lambda (op)
	(case op
	  ((set) (lambda (x) (setq value x)))
	  ((clear) (lambda () (setq value nil)))
	  ((ref) (lambda () value))
	  ((gtk-widget) label)
	  ((validp) (lambda (x) t))))))

  (define-widget-type 'unknown make-unknown-item)


;;; utility functions

  (define (string->symbol string)
    (condition-case nil
	(let ((data (read-from-string string)))
	  (and (symbolp data) data))
      (error)))

  (define (list-index lst x)
    (do ((i 0 (1+ i))
	 (rest lst (cdr rest)))
	((eq (car rest) x) i))))