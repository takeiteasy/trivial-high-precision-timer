;;;; timer.lisp — sokol_time.h port for Common Lisp via CFFI
;;;; Based on sokol_time.h by Andre Weissflog (https://github.com/floooh/sokol)

(in-package #:trivial-high-precision-timer)

;;; ————————————————————————————————————————————————
;;; Platform-specific CFFI bindings
;;; ————————————————————————————————————————————————

#+darwin
(progn
  (cffi:defcstruct mach-timebase-info-data
    (numer :uint32)
    (denom :uint32))

  (cffi:defcfun ("mach_timebase_info" %mach-timebase-info) :int
    (info (:pointer (:struct mach-timebase-info-data))))

  (cffi:defcfun ("mach_absolute_time" %mach-absolute-time) :uint64))

#+(and unix (not darwin))
(progn
  (cffi:defcstruct timespec
    (tv-sec :long)
    (tv-nsec :long))

  (cffi:defcfun ("clock_gettime" %clock-gettime) :int
    (clock-id :int)
    (tp (:pointer (:struct timespec)))))

#+windows
(progn
  (cffi:defcfun ("QueryPerformanceFrequency" %query-performance-frequency) :boolean
    (frequency (:pointer :int64)))

  (cffi:defcfun ("QueryPerformanceCounter" %query-performance-counter) :boolean
    (count (:pointer :int64))))

;;; ————————————————————————————————————————————————
;;; Constants
;;; ————————————————————————————————————————————————

;; CLOCK_MONOTONIC values per platform
#+linux (defconstant +clock-monotonic+ 1)
#+freebsd (defconstant +clock-monotonic+ 4)
#+(or openbsd netbsd) (defconstant +clock-monotonic+ 3)

;;; ————————————————————————————————————————————————
;;; Internal state (mirrors sokol_time _stm_state_t)
;;; ————————————————————————————————————————————————

(defvar *initialized* nil)
(defvar *start* 0)

#+darwin
(progn
  (defvar *timebase-numer* 1)
  (defvar *timebase-denom* 1))

#+windows
(defvar *freq* 1)

;;; ————————————————————————————————————————————————
;;; Internal helpers
;;; ————————————————————————————————————————————————

(declaim (inline %int64-muldiv))
(defun %int64-muldiv (value numer denom)
  "Overflow-safe multiply-divide, matching sokol_time's _stm_int64_muldiv.
Lisp bignums make overflow impossible, but we keep the same algorithm."
  (multiple-value-bind (q r) (floor value denom)
    (+ (* q numer) (floor (* r numer) denom))))

;;; ————————————————————————————————————————————————
;;; Refresh rate table (for round-to-common-refresh-rate)
;;; ————————————————————————————————————————————————

(defparameter *refresh-rates*
  ;; (duration-ns . tolerance-ns) — ranges must not overlap
  #((16666667 . 1000000)   ;  60 Hz
    (13888889 .  250000)   ;  72 Hz
    (13333333 .  250000)   ;  75 Hz
    (11764706 .  250000)   ;  85 Hz
    (11111111 .  250000)   ;  90 Hz
    (10000000 .  500000)   ; 100 Hz
    ( 8333333 .  500000)   ; 120 Hz
    ( 6944445 .  500000)   ; 144 Hz
    ( 4166667 . 1000000))) ; 240 Hz

;;; ————————————————————————————————————————————————
;;; Public API
;;; ————————————————————————————————————————————————

(defun setup ()
  "Initialize the timer. Must be called once before any other timer functions."
  #+darwin
  (cffi:with-foreign-object (info '(:struct mach-timebase-info-data))
    (%mach-timebase-info info)
    (setf *timebase-numer*
          (cffi:foreign-slot-value info '(:struct mach-timebase-info-data) 'numer))
    (setf *timebase-denom*
          (cffi:foreign-slot-value info '(:struct mach-timebase-info-data) 'denom))
    (setf *start* (%mach-absolute-time)))

  #+(and unix (not darwin))
  (cffi:with-foreign-object (ts '(:struct timespec))
    (%clock-gettime +clock-monotonic+ ts)
    (setf *start*
          (+ (* (cffi:foreign-slot-value ts '(:struct timespec) 'tv-sec)
                1000000000)
             (cffi:foreign-slot-value ts '(:struct timespec) 'tv-nsec))))

  #+windows
  (progn
    (cffi:with-foreign-object (freq :int64)
      (%query-performance-frequency freq)
      (setf *freq* (cffi:mem-ref freq :int64)))
    (cffi:with-foreign-object (count :int64)
      (%query-performance-counter count)
      (setf *start* (cffi:mem-ref count :int64))))

  (setf *initialized* t)
  (values))

(defun now ()
  "Get current point in time in nanoseconds since SETUP.
The value has no relation to wall-clock time and is only useful
for computing time differences."
  (assert *initialized* ()
          "Timer not initialized. Call (trivial-high-precision-timer:setup) first.")
  #+darwin
  (let ((mach-now (- (%mach-absolute-time) *start*)))
    (%int64-muldiv mach-now *timebase-numer* *timebase-denom*))

  #+(and unix (not darwin))
  (cffi:with-foreign-object (ts '(:struct timespec))
    (%clock-gettime +clock-monotonic+ ts)
    (- (+ (* (cffi:foreign-slot-value ts '(:struct timespec) 'tv-sec)
              1000000000)
          (cffi:foreign-slot-value ts '(:struct timespec) 'tv-nsec))
       *start*))

  #+windows
  (cffi:with-foreign-object (count :int64)
    (%query-performance-counter count)
    (%int64-muldiv (- (cffi:mem-ref count :int64) *start*)
                   1000000000
                   *freq*)))

(declaim (inline diff))
(defun diff (new-ticks old-ticks)
  "Compute the time difference between NEW-TICKS and OLD-TICKS in nanoseconds.
Always returns a positive, non-zero value."
  (if (> new-ticks old-ticks)
      (- new-ticks old-ticks)
      1))

(declaim (inline since))
(defun since (start-ticks)
  "Return the elapsed nanoseconds since START-TICKS.
Shorthand for (DIFF (NOW) START-TICKS)."
  (diff (now) start-ticks))

(defun laptime (last-time)
  "Measure lap/frame time. LAST-TIME is the tick value from the previous call
\(or 0 on the first call). Returns (VALUES elapsed-ns current-ticks).

Example:
  (let ((last 0))
    (multiple-value-bind (dt cur) (laptime last)
      (setf last cur)
      dt))"
  (let* ((current (now))
         (dt (if (zerop last-time)
                 0
                 (diff current last-time))))
    (values dt current)))

(defun round-to-common-refresh-rate (frame-ticks)
  "Round a measured frame duration (in nanoseconds) to the nearest common
display refresh rate. Returns the input unchanged if no common rate matches."
  (loop for entry across *refresh-rates*
        for ns    = (car entry)
        for tol   = (cdr entry)
        when (< (- ns tol) frame-ticks (+ ns tol))
          do (return ns)
        finally (return frame-ticks)))

(declaim (inline sec ms us ns))

(defun sec (ticks)
  "Convert nanosecond ticks to seconds (double-float)."
  (/ (coerce ticks 'double-float) 1000000000.0d0))

(defun ms (ticks)
  "Convert nanosecond ticks to milliseconds (double-float)."
  (/ (coerce ticks 'double-float) 1000000.0d0))

(defun us (ticks)
  "Convert nanosecond ticks to microseconds (double-float)."
  (/ (coerce ticks 'double-float) 1000.0d0))

(defun ns (ticks)
  "Convert nanosecond ticks to nanoseconds (double-float)."
  (coerce ticks 'double-float))
