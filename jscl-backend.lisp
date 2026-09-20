;;;; jscl-backend.lisp — performance.now() timer for JSCL
;;;;
;;;; Read only by JSCL: #j: is its foreign-call syntax and no other reader
;;;; knows it. performance.now() returns milliseconds as a float; effective
;;;; resolution is ~5us in modern browsers (Spectre mitigations). Requires an
;;;; environment where performance is a global: all browsers, Node.js >= 16.

(in-package #:trivial-high-precision-timer)

(defun %ensure-platform-initialized ()
  (setf %platform-initialized% t))

(defun %raw-ticks ()
  (round (* (#j:performance:now) 1000000)))

(defun %ticks-to-ns (delta)
  delta)
