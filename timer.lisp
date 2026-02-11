;;;; timer.lisp — High-precision timer for Common Lisp
;;;; Based on sokol_time.h by Andre Weissflog (https://github.com/floooh/sokol)
;;;;
;;;; Backends (in priority order):
;;;;   1. CFFI — macOS (mach_absolute_time), Linux/BSD (clock_gettime), Windows (QPC)
;;;;   2. ECL native FFI — same OS APIs, for iOS/Android/embedded where dlopen fails
;;;;   3. JSCL — JavaScript performance.now() for WebAssembly/browser
;;;;   4. ABCL — Java System.nanoTime() for JVM
;;;;   5. Pure CL — get-internal-real-time fallback for any conforming implementation

(in-package #:trivial-high-precision-timer)

;;; ————————————————————————————————————————————————
;;; Timer resolution
;;; ————————————————————————————————————————————————

(defvar *timer-resolution* :ns
  "Output resolution for timer values returned by NOW, DIFF, SINCE, and LAPTIME.
One of :NS (nanoseconds), :US (microseconds), :MS (milliseconds), or :S (seconds).
When :S, values are returned as DOUBLE-FLOAT; otherwise as integers.
Must be set before calling SETUP, or call SETUP again after changing.")

;;; ————————————————————————————————————————————————
;;; Internal state
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

(defun %normalize-ns (nanoseconds)
  "Convert raw nanoseconds to the current *timer-resolution*."
  (ecase *timer-resolution*
    (:ns nanoseconds)
    (:us (floor nanoseconds 1000))
    (:ms (floor nanoseconds 1000000))
    (:s  (/ (coerce nanoseconds 'double-float) 1000000000.0d0))))

;;; ————————————————————————————————————————————————
;;; Backend: CFFI (SBCL, CCL, LispWorks, Clasp, etc.)
;;; ————————————————————————————————————————————————

#-(or ecl jscl abcl)
(progn
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
      (tp (:pointer (:struct timespec))))
    #+linux (defconstant +clock-monotonic+ 1)
    #+freebsd (defconstant +clock-monotonic+ 4)
    #+(or openbsd netbsd) (defconstant +clock-monotonic+ 3))

  #+windows
  (progn
    (cffi:defcfun ("QueryPerformanceFrequency" %query-performance-frequency) :boolean
      (frequency (:pointer :int64)))
    (cffi:defcfun ("QueryPerformanceCounter" %query-performance-counter) :boolean
      (count (:pointer :int64)))))

;;; ————————————————————————————————————————————————
;;; Backend: ECL native FFI (iOS, Android, desktop)
;;; Uses ffi:c-inline to bypass CFFI's dlopen, which
;;; is restricted on iOS and some embedded targets.
;;; ————————————————————————————————————————————————

#+ecl
(progn
  #+darwin
  (progn
    (ffi:clines "#include <mach/mach_time.h>")
    (defun %ecl-mach-absolute-time ()
      (ffi:c-inline () () :unsigned-long-long
        "mach_absolute_time()" :one-liner t))
    (defun %ecl-mach-timebase-numer ()
      (ffi:c-inline () () :unsigned-int
        "{ mach_timebase_info_data_t i; mach_timebase_info(&i);
           @(return 0) = i.numer; }"
        :one-liner nil))
    (defun %ecl-mach-timebase-denom ()
      (ffi:c-inline () () :unsigned-int
        "{ mach_timebase_info_data_t i; mach_timebase_info(&i);
           @(return 0) = i.denom; }"
        :one-liner nil)))

  #+(and unix (not darwin))
  (progn
    (ffi:clines "#include <time.h>")
    (defun %ecl-clock-gettime-ns ()
      (ffi:c-inline () () :unsigned-long-long
        "{
          struct timespec ts;
          clock_gettime(CLOCK_MONOTONIC, &ts);
          @(return 0) = (unsigned long long)ts.tv_sec * 1000000000ULL
                      + (unsigned long long)ts.tv_nsec;
        }" :one-liner nil)))

  #+windows
  (progn
    (ffi:clines "#include <windows.h>")
    (defun %ecl-qpc ()
      (ffi:c-inline () () :long-long
        "{ LARGE_INTEGER c; QueryPerformanceCounter(&c);
           @(return 0) = c.QuadPart; }"
        :one-liner nil))
    (defun %ecl-qpf ()
      (ffi:c-inline () () :long-long
        "{ LARGE_INTEGER f; QueryPerformanceFrequency(&f);
           @(return 0) = f.QuadPart; }"
        :one-liner nil))))

;;; ————————————————————————————————————————————————
;;; Backend dispatch: %backend-setup and %now-ns
;;; Exactly one definition of each is compiled per build.
;;; ————————————————————————————————————————————————

(declaim (inline %now-ns))

;;; --- ECL Darwin (macOS / iOS) ---

#+(and ecl darwin)
(progn
  (defun %backend-setup ()
    (setf *timebase-numer* (%ecl-mach-timebase-numer))
    (setf *timebase-denom* (%ecl-mach-timebase-denom))
    (setf *start* (%ecl-mach-absolute-time)))
  (defun %now-ns ()
    (%int64-muldiv (- (%ecl-mach-absolute-time) *start*)
                   *timebase-numer* *timebase-denom*)))

;;; --- ECL Unix (Linux / Android / BSD) ---

#+(and ecl unix (not darwin))
(progn
  (defun %backend-setup ()
    (setf *start* (%ecl-clock-gettime-ns)))
  (defun %now-ns ()
    (- (%ecl-clock-gettime-ns) *start*)))

;;; --- ECL Windows ---

#+(and ecl windows)
(progn
  (defun %backend-setup ()
    (setf *freq* (%ecl-qpf))
    (setf *start* (%ecl-qpc)))
  (defun %now-ns ()
    (%int64-muldiv (- (%ecl-qpc) *start*) 1000000000 *freq*)))

;;; --- CFFI Darwin (macOS) ---

#+(and (not ecl) (not jscl) (not abcl) darwin)
(progn
  (defun %backend-setup ()
    (cffi:with-foreign-object (info '(:struct mach-timebase-info-data))
      (%mach-timebase-info info)
      (setf *timebase-numer*
            (cffi:foreign-slot-value info '(:struct mach-timebase-info-data) 'numer))
      (setf *timebase-denom*
            (cffi:foreign-slot-value info '(:struct mach-timebase-info-data) 'denom))
      (setf *start* (%mach-absolute-time))))
  (defun %now-ns ()
    (%int64-muldiv (- (%mach-absolute-time) *start*)
                   *timebase-numer* *timebase-denom*)))

;;; --- CFFI Unix (Linux / FreeBSD / OpenBSD / NetBSD) ---

#+(and (not ecl) (not jscl) (not abcl) unix (not darwin))
(progn
  (defun %backend-setup ()
    (cffi:with-foreign-object (ts '(:struct timespec))
      (%clock-gettime +clock-monotonic+ ts)
      (setf *start*
            (+ (* (cffi:foreign-slot-value ts '(:struct timespec) 'tv-sec)
                  1000000000)
               (cffi:foreign-slot-value ts '(:struct timespec) 'tv-nsec)))))
  (defun %now-ns ()
    (cffi:with-foreign-object (ts '(:struct timespec))
      (%clock-gettime +clock-monotonic+ ts)
      (- (+ (* (cffi:foreign-slot-value ts '(:struct timespec) 'tv-sec)
                1000000000)
            (cffi:foreign-slot-value ts '(:struct timespec) 'tv-nsec))
         *start*))))

;;; --- CFFI Windows ---

#+(and (not ecl) (not jscl) (not abcl) windows)
(progn
  (defun %backend-setup ()
    (cffi:with-foreign-object (freq :int64)
      (%query-performance-frequency freq)
      (setf *freq* (cffi:mem-ref freq :int64)))
    (cffi:with-foreign-object (count :int64)
      (%query-performance-counter count)
      (setf *start* (cffi:mem-ref count :int64))))
  (defun %now-ns ()
    (cffi:with-foreign-object (count :int64)
      (%query-performance-counter count)
      (%int64-muldiv (- (cffi:mem-ref count :int64) *start*)
                     1000000000
                     *freq*))))

;;; --- JSCL (WebAssembly / browser) ---
;;; Uses performance.now() which returns milliseconds as a float.
;;; Effective resolution is ~5us in modern browsers (Spectre mitigations).
;;; Requires a modern environment where performance is a global
;;; (all browsers, Node.js >= 16).

#+jscl
(progn
  (defun %jscl-now-ns ()
    (round (* (#j:performance:now) 1000000)))
  (defun %backend-setup ()
    (setf *start* (%jscl-now-ns)))
  (defun %now-ns ()
    (- (%jscl-now-ns) *start*)))

;;; --- ABCL (JVM) ---
;;; Uses System.nanoTime() — monotonic, nanosecond precision.

#+abcl
(progn
  (defun %backend-setup ()
    (setf *start* (java:jstatic "nanoTime" "java.lang.System")))
  (defun %now-ns ()
    (- (java:jstatic "nanoTime" "java.lang.System") *start*)))

;;; --- Pure CL fallback ---
;;; Uses get-internal-real-time. Resolution varies by implementation:
;;;   SBCL ~1us, CCL ~1ms, ECL ~1ms, CLISP ~10ms.
;;; This is the catch-all when no platform-specific backend is available.

#-(or jscl abcl darwin unix windows)
(progn
  (defun %cl-time-ns ()
    (%int64-muldiv (get-internal-real-time)
                   1000000000
                   internal-time-units-per-second))
  (defun %backend-setup ()
    (setf *start* (%cl-time-ns)))
  (defun %now-ns ()
    (- (%cl-time-ns) *start*)))

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
  "Initialize the timer. Must be called once before any other timer functions.
Respects the current value of *timer-resolution*."
  (%backend-setup)
  (setf *initialized* t)
  (values))

(defun now ()
  "Get current time since SETUP in the resolution specified by *timer-resolution*.
The value has no relation to wall-clock time and is only useful
for computing time differences."
  (assert *initialized* ()
          "Timer not initialized. Call (trivial-high-precision-timer:setup) first.")
  (%normalize-ns (%now-ns)))

(declaim (inline diff))
(defun diff (new-ticks old-ticks)
  "Compute the time difference between NEW-TICKS and OLD-TICKS.
Result is in the current *timer-resolution*. Always returns a positive,
non-zero value (returns 1 tick minimum to prevent division by zero)."
  (if (> new-ticks old-ticks)
      (- new-ticks old-ticks)
      1))

(declaim (inline since))
(defun since (start-ticks)
  "Return elapsed time since START-TICKS in the current *timer-resolution*.
Shorthand for (DIFF (NOW) START-TICKS)."
  (diff (now) start-ticks))

(defun laptime (last-time)
  "Measure lap/frame time. LAST-TIME is the tick value from the previous call
\(or 0 on the first call). Returns (VALUES elapsed-ticks current-ticks).

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
  "Round a measured frame duration to the nearest common display refresh rate.
Returns the input unchanged if no common rate matches.
Works correctly regardless of *timer-resolution* setting."
  (let ((frame-ns (ecase *timer-resolution*
                    (:ns frame-ticks)
                    (:us (* frame-ticks 1000))
                    (:ms (* frame-ticks 1000000))
                    (:s  (round (* frame-ticks 1000000000.0d0))))))
    (loop for entry across *refresh-rates*
          for ns  = (car entry)
          for tol = (cdr entry)
          when (< (- ns tol) frame-ns (+ ns tol))
            do (return (%normalize-ns ns))
          finally (return frame-ticks))))

;;; ————————————————————————————————————————————————
;;; Unit conversion (resolution-aware)
;;; ————————————————————————————————————————————————

(declaim (inline sec ms us ns))

(defun sec (ticks)
  "Convert ticks (in current *timer-resolution*) to seconds (double-float)."
  (* (coerce ticks 'double-float)
     (ecase *timer-resolution*
       (:ns 1.0d-9)
       (:us 1.0d-6)
       (:ms 1.0d-3)
       (:s  1.0d0))))

(defun ms (ticks)
  "Convert ticks (in current *timer-resolution*) to milliseconds (double-float)."
  (* (coerce ticks 'double-float)
     (ecase *timer-resolution*
       (:ns 1.0d-6)
       (:us 1.0d-3)
       (:ms 1.0d0)
       (:s  1.0d3))))

(defun us (ticks)
  "Convert ticks (in current *timer-resolution*) to microseconds (double-float)."
  (* (coerce ticks 'double-float)
     (ecase *timer-resolution*
       (:ns 1.0d-3)
       (:us 1.0d0)
       (:ms 1.0d3)
       (:s  1.0d6))))

(defun ns (ticks)
  "Convert ticks (in current *timer-resolution*) to nanoseconds (double-float)."
  (* (coerce ticks 'double-float)
     (ecase *timer-resolution*
       (:ns 1.0d0)
       (:us 1.0d3)
       (:ms 1.0d6)
       (:s  1.0d9))))
