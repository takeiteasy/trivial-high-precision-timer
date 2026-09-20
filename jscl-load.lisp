;;;; jscl-load.lisp — load the library under JSCL
;;;;
;;;; JSCL ships no ASDF, so the two source files are loaded by hand in order.
;;;;   (load "jscl-load.lisp")

(load "trivial-high-precision-timer.lisp")
(load "jscl-backend.lisp")
