;;;; suite.lisp — tests for trivial-high-precision-timer
;;;;
;;;; Arithmetic carries the suite. Anything involving SLEEP asserts a loose
;;;; lower bound only: CI runners are noisy VMs and a flaky suite gets ignored.

(in-package #:trivial-high-precision-timer)

;;; ————————————————————————————————————————————————
;;; Backend identification
;;; ————————————————————————————————————————————————

(deftest backend-report
  (format t "  ~a ~a / ~a~%"
          (lisp-implementation-type)
          (lisp-implementation-version)
          (if (find :thpt-native *features*) "native backend" "pure-CL fallback"))
  (format t "  platform features:~{ ~a~}~%"
          (remove-if-not (lambda (f)
                           (member f '(:darwin :unix :linux :windows :freebsd
                                       :openbsd :netbsd :thpt-native
                                       :thpt-force-fallback)))
                         *features*))
  (is (integerp (%raw-ticks)) "%raw-ticks returns an integer"))

;;; ————————————————————————————————————————————————
;;; %int64-muldiv
;;; ————————————————————————————————————————————————

(deftest muldiv-identity
  ;; The whole point of the split multiply is to equal the exact result.
  (dolist (v (list 0 1 999 1000000 (expt 2 32) (expt 2 62) 123456789012345))
    (dolist (nd '((3 . 2) (1 . 1) (125 . 3) (1000000000 . 24000000)))
      (is= (floor (* v (car nd)) (cdr nd))
           (%int64-muldiv v (car nd) (cdr nd))))))

(deftest muldiv-known-values
  (is= 1500 (%int64-muldiv 1000 3 2))
  (is= 1000 (%int64-muldiv 1000 1 1))
  (is= 0 (%int64-muldiv 0 125 3)))

;;; ————————————————————————————————————————————————
;;; %normalize-ns
;;; ————————————————————————————————————————————————

(deftest normalize-ns
  (is= 1500 (%normalize-ns 1500 :ns))
  (is= 0 (%normalize-ns 0 :ns)))

(deftest normalize-us
  (is= 1 (%normalize-ns 1000 :us))
  (is= 1 (%normalize-ns 1999 :us) )
  (is= 2 (%normalize-ns 2000 :us))
  (is= 0 (%normalize-ns 999 :us)))

(deftest normalize-ms
  (is= 1 (%normalize-ns 1000000 :ms))
  (is= 0 (%normalize-ns 999999 :ms))
  (is= 1500 (%normalize-ns 1500000000 :ms)))

(deftest normalize-s
  (is-close 1.5d0 (%normalize-ns 1500000000 :s) 1d-12)
  (is-close 0.0d0 (%normalize-ns 0 :s) 1d-12)
  #-jscl
  (is (typep (%normalize-ns 1 :s) 'double-float) "seconds are double-float"))

;;; ————————————————————————————————————————————————
;;; Unit conversion
;;; ————————————————————————————————————————————————

(defun %expect-conversion (resolution ticks sec-v ms-v us-v ns-v)
  (let ((timer (make-precision-timer :resolution resolution)))
    (is-close sec-v (sec timer ticks) (* 1d-9 (max 1d0 (abs sec-v))))
    (is-close ms-v (ms timer ticks) (* 1d-9 (max 1d0 (abs ms-v))))
    (is-close us-v (us timer ticks) (* 1d-9 (max 1d0 (abs us-v))))
    (is-close ns-v (ns timer ticks) (* 1d-9 (max 1d0 (abs ns-v))))))

(deftest conversions-cover-every-resolution
  ;; One second expressed in each resolution converts to the same four values.
  (%expect-conversion :ns 1000000000 1d0 1000d0 1000000d0 1000000000d0)
  (%expect-conversion :us 1000000    1d0 1000d0 1000000d0 1000000000d0)
  (%expect-conversion :ms 1000       1d0 1000d0 1000000d0 1000000000d0)
  (%expect-conversion :s  1          1d0 1000d0 1000000d0 1000000000d0))

(deftest conversions-of-zero
  (%expect-conversion :ns 0 0d0 0d0 0d0 0d0)
  (%expect-conversion :s  0 0d0 0d0 0d0 0d0))

;;; ————————————————————————————————————————————————
;;; Refresh rate table
;;; ————————————————————————————————————————————————

(deftest refresh-rate-ranges-do-not-overlap
  (let ((n (length *refresh-rates*)))
    (dotimes (i n)
      (loop for j from (+ i 1) below n
            for a = (aref *refresh-rates* i)
            for b = (aref *refresh-rates* j)
            do (is (or (<= (+ (car a) (cdr a)) (- (car b) (cdr b)))
                       (<= (+ (car b) (cdr b)) (- (car a) (cdr a))))
                   (format nil "~a and ~a overlap" (car a) (car b)))))))

(deftest refresh-rate-exact-and-inside-tolerance
  ;; The bounds are written without a negative literal operand: JSCL
  ;; miscompiles (- a b -1) into invalid JavaScript. See ticket #4.
  (let ((timer (make-precision-timer :resolution :ns)))
    (dotimes (i (length *refresh-rates*))
      (let* ((entry (aref *refresh-rates* i))
             (duration (car entry))
             (tolerance (cdr entry))
             (upper (- (+ duration tolerance) 1))
             (lower (+ (- duration tolerance) 1)))
        (is= duration (round-to-common-refresh-rate timer duration))
        (is= duration (round-to-common-refresh-rate timer upper))
        (is= duration (round-to-common-refresh-rate timer lower))))))

(deftest refresh-rate-no-match-returns-input
  (let ((timer (make-precision-timer :resolution :ns)))
    ;; 1000 Hz and 10 Hz sit outside every band in the table.
    (is= 1000000 (round-to-common-refresh-rate timer 1000000))
    (is= 100000000 (round-to-common-refresh-rate timer 100000000))))

(deftest refresh-rate-across-resolutions
  ;; 60 Hz is 16666667 ns; each resolution should snap to its own rendering.
  (is= 16666667 (round-to-common-refresh-rate
                 (make-precision-timer :resolution :ns) 16600000))
  (is= 16666 (round-to-common-refresh-rate
              (make-precision-timer :resolution :us) 16600))
  (is= 16 (round-to-common-refresh-rate
           (make-precision-timer :resolution :ms) 16))
  (is-close 0.016666667d0
            (round-to-common-refresh-rate
             (make-precision-timer :resolution :s) 0.0166d0)
            1d-9))

;;; ————————————————————————————————————————————————
;;; diff / since / laptime
;;; ————————————————————————————————————————————————

(deftest diff-normal
  (let ((timer (make-precision-timer)))
    (is= 500 (diff timer 1500 1000))))

(deftest diff-equal-is-zero
  (let ((timer (make-precision-timer)))
    (is= 0 (diff timer 1000 1000))))

(deftest diff-reversed-is-zero
  (let ((timer (make-precision-timer)))
    (is= 0 (diff timer 1000 1500))))

(deftest diff-never-inflates-seconds
  ;; The old minimum-1 clamp reported a whole second here. MAX may return
  ;; either zero of either type when the arguments are equal, so test the
  ;; value rather than the representation.
  (let ((timer (make-precision-timer :resolution :s)))
    (is (zerop (diff timer 1.0d0 1.0d0)) "equal second values differ by zero")
    (is-close 0.5d0 (diff timer 1.5d0 1.0d0) 1d-12)))

(deftest since-is-non-negative
  (let ((timer (make-precision-timer)))
    (is (>= (since timer 0) 0) "since start is non-negative")))

(deftest laptime-first-call-is-zero
  (let ((timer (make-precision-timer)))
    (multiple-value-bind (dt current) (laptime timer 0)
      (is= 0 dt)
      (is (>= current 0) "laptime returns a usable current tick"))))

(deftest laptime-subsequent-calls-are-non-negative
  (let ((timer (make-precision-timer)))
    (multiple-value-bind (dt1 cur1) (laptime timer 0)
      (declare (ignore dt1))
      (multiple-value-bind (dt2 cur2) (laptime timer cur1)
        (is (>= dt2 0) "second lap is non-negative")
        (is (>= cur2 cur1) "current tick does not go backwards")))))

;;; ————————————————————————————————————————————————
;;; Timer construction
;;; ————————————————————————————————————————————————

(deftest resolution-is-readable
  (dolist (r '(:ns :us :ms :s))
    (is= r (precision-timer-resolution (make-precision-timer :resolution r)))))

(deftest default-resolution-is-ns
  (is= :ns (precision-timer-resolution (make-precision-timer))))

(deftest start-tick-is-captured
  (is (integerp (precision-timer-start (make-precision-timer)))
      "start tick is an integer"))

#-jscl
(deftest bad-resolution-is-rejected
  (is (handler-case (progn (make-precision-timer :resolution :fortnights) nil)
        (error () t))
      "an unknown resolution signals"))

(deftest timers-are-independent
  (let ((t1 (make-precision-timer)))
    (dotimes (i 10000) (%raw-ticks))
    (let ((t2 (make-precision-timer)))
      (is (>= (precision-timer-start t2) (precision-timer-start t1))
          "later timer starts no earlier")
      (is (>= (now t1) (now t2)) "older timer reports more elapsed time"))))

;;; ————————————————————————————————————————————————
;;; Clock behaviour
;;; ————————————————————————————————————————————————

(deftest clock-is-monotonic
  (let ((timer (make-precision-timer))
        (previous 0)
        (ok t))
    (dotimes (i 1000)
      (let ((current (now timer)))
        (when (< current previous) (setf ok nil))
        (setf previous current)))
    (is ok "now never decreases over 1000 calls")))

#-jscl
(deftest sleep-elapses-at-least-the-requested-time
  ;; Lower bound only. Runners oversleep by arbitrary amounts.
  (let ((timer (make-precision-timer)))
    (let ((start (now timer)))
      (sleep 0.05)
      (is (>= (ms timer (since timer start)) 40d0)
          "50ms sleep measures at least 40ms"))))
