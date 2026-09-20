;;;; harness.lisp — minimal test harness
;;;;
;;;; Zero dependencies and conservative CL: the suite has to run under ABCL and
;;;; JSCL, neither of which can load FiveAM, Parachute or rove. Defined inside
;;;; the library package so the suite can reach internals without a nickname,
;;;; which JSCL's package support does not reliably provide.

(in-package #:trivial-high-precision-timer)

(defvar *tests* '())
(defvar *passed* 0)
(defvar *failed* 0)
(defvar *current-test* nil)

(defmacro deftest (name &body body)
  `(progn
     (defun ,name () ,@body)
     (pushnew ',name *tests*)
     ',name))

(defun check (ok label)
  (if ok
      (setf *passed* (+ *passed* 1))
      (progn
        (setf *failed* (+ *failed* 1))
        (format t "    FAIL ~a: ~a~%" *current-test* label)))
  ok)

(defmacro is (form &optional label)
  "Assert FORM is true."
  `(check ,form ,(or label (format nil "~s" form))))

(defmacro is= (expected form)
  "Assert FORM equals EXPECTED, reporting both on failure."
  (let ((e (gensym)) (a (gensym)))
    `(let ((,e ,expected) (,a ,form))
       (check (equal ,e ,a)
              (format nil "~s => ~s, expected ~s" ',form ,a ,e)))))

(defmacro is-close (expected form tolerance)
  "Assert FORM is within TOLERANCE of EXPECTED."
  (let ((e (gensym)) (a (gensym)) (tol (gensym)))
    `(let ((,e ,expected) (,a ,form) (,tol ,tolerance))
       (check (<= (abs (- ,a ,e)) ,tol)
              (format nil "~s => ~s, expected ~s +/- ~s" ',form ,a ,e ,tol)))))

(defun run-one (name)
  (setf *current-test* name)
  #+jscl (funcall name)
  #-jscl
  (handler-case (funcall name)
    (error (e)
      (setf *failed* (+ *failed* 1))
      (format t "    ERROR ~a: ~a~%" name e))))

(defun run-tests ()
  "Run every registered test. Returns T when all assertions passed."
  (setf *passed* 0 *failed* 0)
  (format t "~&Running ~d tests~%" (length *tests*))
  (dolist (name (reverse *tests*))
    (run-one name))
  (format t "~&~d passed, ~d failed~%" *passed* *failed*)
  (zerop *failed*))
