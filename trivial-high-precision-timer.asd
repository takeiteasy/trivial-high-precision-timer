;;;; trivial-high-precision-timer.asd

(asdf:defsystem #:trivial-high-precision-timer
  :description "A cross-platform high-precision timer for Common Lisp"
  :author "George Watson <gigolo@hotmail.co.uk>"
  :license  "MIT"
  :version "0.1.0"
  :serial t
  ;; JSCL loads via jscl-load.lisp, not ASDF.
  :depends-on (#-(or ecl jscl abcl thpt-force-fallback) :cffi)
  :components ((:file "trivial-high-precision-timer"))
  :in-order-to ((asdf:test-op (asdf:test-op #:trivial-high-precision-timer/tests))))

(asdf:defsystem #:trivial-high-precision-timer/tests
  :description "Test suite for trivial-high-precision-timer"
  :license "MIT"
  :serial t
  :depends-on (#:trivial-high-precision-timer)
  :components ((:module "tests"
                :components ((:file "harness")
                             (:file "suite"))))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call '#:trivial-high-precision-timer '#:run-tests)
               (error "Test suite failed."))))
