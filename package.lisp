;;;; package.lisp

(defpackage #:trivial-high-precision-timer
  (:use #:cl)
  (:export #:setup
           #:now
           #:diff
           #:since
           #:laptime
           #:round-to-common-refresh-rate
           #:sec
           #:ms
           #:us
           #:ns))
