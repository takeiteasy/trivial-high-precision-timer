;;;; trivial-high-precision-timer.asd

(asdf:defsystem #:trivial-high-precision-timer
  :description "A cross-platform high-precision timer for Common Lisp"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license  "GPLv3"
  :version "0.1.0"
  :serial t
  :depends-on (#-(or ecl jscl abcl) :cffi)
  :components ((:file "trivial-high-precision-timer")))
