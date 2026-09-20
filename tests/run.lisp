;;;; run.lisp — ASDF entry point for the test suite
;;;;
;;;;   sbcl --script tests/run.lisp
;;;;   ccl --batch --quiet --load tests/run.lisp
;;;;   ecl --shell tests/run.lisp
;;;;   abcl --batch --load tests/run.lisp
;;;;   ros -Q run --load tests/run.lisp
;;;;
;;;; Set THPT_FORCE_FALLBACK in the environment to build against the pure-CL
;;;; backend instead of the platform one. Clear ~/.cache/common-lisp first:
;;;; ASDF does not recompile on a feature change alone.

(require :asdf)

(unless (find-package '#:quicklisp)
  (dolist (candidate '("quicklisp/setup.lisp" ".roswell/lisp/quicklisp/setup.lisp"))
    (let ((setup (merge-pathnames candidate (user-homedir-pathname))))
      (when (probe-file setup)
        (load setup)
        (return)))))

(let ((force (uiop:getenv "THPT_FORCE_FALLBACK")))
  (when (and force (string/= force ""))
    (pushnew :thpt-force-fallback *features*)))

(push (uiop:getcwd) asdf:*central-registry*)

(let ((quickload (and (find-package '#:ql) (find-symbol "QUICKLOAD" '#:ql))))
  (if quickload
      (funcall quickload :trivial-high-precision-timer/tests)
      (asdf:load-system :trivial-high-precision-timer/tests)))

(uiop:quit
 (if (uiop:symbol-call '#:trivial-high-precision-timer '#:run-tests) 0 1))
