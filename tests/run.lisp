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

;;; ASDF comes from the implementation where it has one and from Quicklisp
;;; otherwise: CLISP ships neither ASDF nor UIOP.
(ignore-errors (require :asdf))

(unless (find-package '#:quicklisp)
  (dolist (candidate '("quicklisp/setup.lisp" ".roswell/lisp/quicklisp/setup.lisp"))
    (let ((setup (merge-pathnames candidate (user-homedir-pathname))))
      (when (probe-file setup)
        (load setup)
        (return)))))

(unless (find-package '#:uiop)
  (error "No ASDF available. Install Quicklisp, or use an implementation that ~
          provides ASDF."))

(let ((force (uiop:getenv "THPT_FORCE_FALLBACK")))
  (when (and force (string/= force ""))
    (pushnew :thpt-force-fallback *features*)))

(push (uiop:getcwd) asdf:*central-registry*)

(let ((quickload (and (find-package '#:ql) (find-symbol "QUICKLOAD" '#:ql))))
  (if quickload
      (funcall quickload :trivial-high-precision-timer/tests)
      (asdf:load-system :trivial-high-precision-timer/tests)))

;;; A green run proves nothing unless the intended backend is the one that got
;;; compiled: every test passes identically on either. ASDF does not recompile
;;; on a feature change, so a stale FASL is the likely way to get this wrong.
(let ((forced (let ((v (uiop:getenv "THPT_FORCE_FALLBACK")))
                (and v (string/= v "") t)))
      (native (and (find :thpt-native *features*) t)))
  (when (eq forced native)
    (format t "~&Backend mismatch: THPT_FORCE_FALLBACK is ~a but :THPT-NATIVE is ~a.~%~
                 Clear ~~/.cache/common-lisp and rerun.~%"
            (if forced "set" "unset")
            (if native "present" "absent"))
    (uiop:quit 2)))

(uiop:quit
 (if (uiop:symbol-call '#:trivial-high-precision-timer '#:run-tests) 0 1))
