;; edge/misc.jl -- misc actions for EdgeActions

;; Copyright (C) 2011 Christopher Roy Bratusek <zanghar@freenet.de>

;; This file is part of sawfish.

;; sawfish is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; sawfish is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with sawfish; see the file COPYING.  If not, write to
;; the Free Software Foundation, 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301 USA.

(define-structure sawfish.wm.edge.misc

    (export maximize-action
   	    expose-windows-action)

    (open rep
	  rep.system
	  sawfish.wm.windows
	  sawfish.wm.commands
	  sawfish.wm.events
	  sawfish.wm.state.maximize
	  sawfish.wm.ext.expose)

  (define-structure-alias edge-misc sawfish.wm.edge.misc)

  (define (maximize-action)
    (let ((w (input-focus)))
      (allow-events 'async-both)
      (fake-release-window)
      (maximize-window w)))

  (define (expose-windows-action edge while-moving)
    (call-hook 'before-edge-action-hook (list 'expose-windows edge while-moving))
    (when while-moving
        (fake-release-window))
      (expose-windows-horizontally)
      (call-hook 'after-edge-action-hook (list 'expose-windows edge while-moving))))
