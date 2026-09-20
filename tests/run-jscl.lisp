;;;; run-jscl.lisp — test entry point for JSCL
;;;;
;;;; JSCL has no ASDF, so everything is loaded by hand. Run from the repo root:
;;;;   node path/to/jscl/dist/jscl-node.js tests/run-jscl.lisp

(load "jscl-load.lisp")
(load "tests/harness.lisp")
(load "tests/suite.lisp")

(in-package #:trivial-high-precision-timer)

(unless (find :thpt-native *features*)
  (format t "~&Backend mismatch: JSCL must select a native backend.~%")
  (#j:process:exit 2))

(if (run-tests)
    (format t "~&JSCL suite passed~%")
    (progn
      (format t "~&JSCL suite FAILED~%")
      (#j:process:exit 1)))
