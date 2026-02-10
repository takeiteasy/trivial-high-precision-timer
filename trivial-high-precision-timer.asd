;;;; trivial-high-precision-timer.asd

(asdf:defsystem #:trivial-high-precision-timer
  :description "A cross-platform high-precision timer for Common Lisp"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license  "GPLv3"
  :version "0.0.1"
  :serial t
  :depends-on (:cffi)
  :components ((:file "package")
               (:file "timer")))
