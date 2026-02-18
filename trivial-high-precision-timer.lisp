;;;; trivial-high-precision-timer.lisp — High-precision timer for Common Lisp
;;;;
;;;; Backends (in priority order):
;;;;   1. CFFI — macOS (mach_absolute_time), Linux/BSD (clock_gettime), Windows (QPC)
;;;;   2. ECL native FFI — same OS APIs, for iOS/Android/embedded where dlopen fails
;;;;   3. JSCL — JavaScript performance.now() for WebAssembly/browser
;;;;   4. ABCL — Java System.nanoTime() for JVM
;;;;   5. Pure CL — get-internal-real-time fallback for any conforming implementation

(defpackage #:trivial-high-precision-timer
  (:use #:cl)
  (:export #:precision-timer
           #:make-precision-timer
           #:precision-timer-resolution
           #:precision-timer-start
           #:now
           #:diff
           #:since
           #:laptime
           #:round-to-common-refresh-rate
           #:sec
           #:ms
           #:us
           #:ns))
           
(in-package #:trivial-high-precision-timer)

;;; ————————————————————————————————————————————————
;;; Internal state
;;; ————————————————————————————————————————————————

(defvar %platform-initialized% nil)

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

(defun %normalize-ns (nanoseconds resolution)
  "Convert raw nanoseconds to the given resolution keyword."
  (ecase resolution
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
;;; Backend dispatch: %ensure-platform-initialized,
;;; %raw-ticks, %ticks-to-ns
;;; Exactly one definition of each is compiled per build.
;;; ————————————————————————————————————————————————

;;; --- ECL Darwin (macOS / iOS) ---

#+(and ecl darwin)
(progn
  (defun %ensure-platform-initialized ()
    (unless %platform-initialized%
      (setf *timebase-numer* (%ecl-mach-timebase-numer))
      (setf *timebase-denom* (%ecl-mach-timebase-denom))
      (setf %platform-initialized% t)))
  (defun %raw-ticks ()
    (%ecl-mach-absolute-time))
  (defun %ticks-to-ns (delta)
    (%int64-muldiv delta *timebase-numer* *timebase-denom*)))

;;; --- ECL Unix (Linux / Android / BSD) ---

#+(and ecl unix (not darwin))
(progn
  (defun %ensure-platform-initialized ()
    (setf %platform-initialized% t))
  (defun %raw-ticks ()
    (%ecl-clock-gettime-ns))
  (defun %ticks-to-ns (delta)
    delta))

;;; --- ECL Windows ---

#+(and ecl windows)
(progn
  (defun %ensure-platform-initialized ()
    (unless %platform-initialized%
      (setf *freq* (%ecl-qpf))
      (setf %platform-initialized% t)))
  (defun %raw-ticks ()
    (%ecl-qpc))
  (defun %ticks-to-ns (delta)
    (%int64-muldiv delta 1000000000 *freq*)))

;;; --- CFFI Darwin (macOS) ---

#+(and (not ecl) (not jscl) (not abcl) darwin)
(progn
  (defun %ensure-platform-initialized ()
    (unless %platform-initialized%
      (cffi:with-foreign-object (info '(:struct mach-timebase-info-data))
        (%mach-timebase-info info)
        (setf *timebase-numer*
              (cffi:foreign-slot-value info '(:struct mach-timebase-info-data) 'numer))
        (setf *timebase-denom*
              (cffi:foreign-slot-value info '(:struct mach-timebase-info-data) 'denom)))
      (setf %platform-initialized% t)))
  (defun %raw-ticks ()
    (%mach-absolute-time))
  (defun %ticks-to-ns (delta)
    (%int64-muldiv delta *timebase-numer* *timebase-denom*)))

;;; --- CFFI Unix (Linux / FreeBSD / OpenBSD / NetBSD) ---

#+(and (not ecl) (not jscl) (not abcl) unix (not darwin))
(progn
  (defun %ensure-platform-initialized ()
    (setf %platform-initialized% t))
  (defun %raw-ticks ()
    (cffi:with-foreign-object (ts '(:struct timespec))
      (%clock-gettime +clock-monotonic+ ts)
      (+ (* (cffi:foreign-slot-value ts '(:struct timespec) 'tv-sec)
            1000000000)
         (cffi:foreign-slot-value ts '(:struct timespec) 'tv-nsec))))
  (defun %ticks-to-ns (delta)
    delta))

;;; --- CFFI Windows ---

#+(and (not ecl) (not jscl) (not abcl) windows)
(progn
  (defun %ensure-platform-initialized ()
    (unless %platform-initialized%
      (cffi:with-foreign-object (freq :int64)
        (%query-performance-frequency freq)
        (setf *freq* (cffi:mem-ref freq :int64)))
      (setf %platform-initialized% t)))
  (defun %raw-ticks ()
    (cffi:with-foreign-object (count :int64)
      (%query-performance-counter count)
      (cffi:mem-ref count :int64)))
  (defun %ticks-to-ns (delta)
    (%int64-muldiv delta 1000000000 *freq*)))

;;; --- JSCL (WebAssembly / browser) ---
;;; Uses performance.now() which returns milliseconds as a float.
;;; Effective resolution is ~5us in modern browsers (Spectre mitigations).
;;; Requires a modern environment where performance is a global
;;; (all browsers, Node.js >= 16).

#+jscl
(progn
  (defun %ensure-platform-initialized ()
    (setf %platform-initialized% t))
  (defun %raw-ticks ()
    (round (* (#j:performance:now) 1000000)))
  (defun %ticks-to-ns (delta)
    delta))

;;; --- ABCL (JVM) ---
;;; Uses System.nanoTime() — monotonic, nanosecond precision.

#+abcl
(progn
  (defun %ensure-platform-initialized ()
    (setf %platform-initialized% t))
  (defun %raw-ticks ()
    (java:jstatic "nanoTime" "java.lang.System"))
  (defun %ticks-to-ns (delta)
    delta))

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
  (defun %ensure-platform-initialized ()
    (setf %platform-initialized% t))
  (defun %raw-ticks ()
    (%cl-time-ns))
  (defun %ticks-to-ns (delta)
    delta))

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
;;; precision-timer CLOS class
;;; ————————————————————————————————————————————————

(defclass precision-timer ()
  ((start
    :reader precision-timer-start
    :documentation "Raw platform tick captured at timer creation. Not in resolution units.")
   (resolution
    :initarg :resolution
    :reader precision-timer-resolution
    :initform :ns
    :documentation "Output resolution: :NS (default), :US, :MS, or :S."))
  (:documentation "A high-precision monotonic timer. Create with MAKE-PRECISION-TIMER."))

(defmethod initialize-instance :after ((timer precision-timer) &key)
  (%ensure-platform-initialized)
  (setf (slot-value timer 'start) (%raw-ticks)))

(defun make-precision-timer (&key (resolution :ns))
  "Create a new high-precision timer. RESOLUTION is :NS (default), :US, :MS, or :S.
The start time is captured at the moment of this call."
  (check-type resolution (member :ns :us :ms :s))
  (make-instance 'precision-timer :resolution resolution))

;;; ————————————————————————————————————————————————
;;; Public API
;;; ————————————————————————————————————————————————

(defgeneric now (timer)
  (:documentation "Get elapsed time since the timer was created, in the timer's resolution.
The value has no relation to wall-clock time and is only useful
for computing time differences."))

(defmethod now ((timer precision-timer))
  (%normalize-ns (%ticks-to-ns (- (%raw-ticks) (precision-timer-start timer)))
                 (precision-timer-resolution timer)))

(defgeneric diff (timer new-ticks old-ticks)
  (:documentation "Compute the time difference between NEW-TICKS and OLD-TICKS.
Result is in the timer's resolution. Always returns a positive,
non-zero value (returns 1 tick minimum to prevent division by zero)."))

(defmethod diff ((timer precision-timer) new-ticks old-ticks)
  (if (> new-ticks old-ticks)
      (- new-ticks old-ticks)
      1))

(defgeneric since (timer start-ticks)
  (:documentation "Return elapsed time since START-TICKS in the timer's resolution.
Shorthand for (DIFF timer (NOW timer) START-TICKS)."))

(defmethod since ((timer precision-timer) start-ticks)
  (diff timer (now timer) start-ticks))

(defgeneric laptime (timer last-time)
  (:documentation "Measure lap/frame time. LAST-TIME is the tick value from the previous call
\(or 0 on the first call). Returns (VALUES elapsed-ticks current-ticks).

Example:
  (let ((last 0))
    (multiple-value-bind (dt cur) (laptime timer last)
      (setf last cur)
      dt))"))

(defmethod laptime ((timer precision-timer) last-time)
  (let* ((current (now timer))
         (dt (if (zerop last-time) 0 (diff timer current last-time))))
    (values dt current)))

(defgeneric round-to-common-refresh-rate (timer frame-ticks)
  (:documentation "Round a measured frame duration to the nearest common display refresh rate.
Returns the input unchanged if no common rate matches.
Works correctly regardless of the timer's resolution setting."))

(defmethod round-to-common-refresh-rate ((timer precision-timer) frame-ticks)
  (let* ((resolution (precision-timer-resolution timer))
         (frame-ns (ecase resolution
                     (:ns frame-ticks)
                     (:us (* frame-ticks 1000))
                     (:ms (* frame-ticks 1000000))
                     (:s  (round (* frame-ticks 1000000000.0d0))))))
    (loop for entry across *refresh-rates*
          for ns  = (car entry)
          for tol = (cdr entry)
          when (< (- ns tol) frame-ns (+ ns tol))
            do (return (%normalize-ns ns resolution))
          finally (return frame-ticks))))

;;; ————————————————————————————————————————————————
;;; Unit conversion (resolution-aware)
;;; ————————————————————————————————————————————————

(defgeneric sec (timer ticks)
  (:documentation "Convert ticks (in timer's resolution) to seconds (double-float)."))

(defmethod sec ((timer precision-timer) ticks)
  (* (coerce ticks 'double-float)
     (ecase (precision-timer-resolution timer)
       (:ns 1.0d-9)
       (:us 1.0d-6)
       (:ms 1.0d-3)
       (:s  1.0d0))))

(defgeneric ms (timer ticks)
  (:documentation "Convert ticks (in timer's resolution) to milliseconds (double-float)."))

(defmethod ms ((timer precision-timer) ticks)
  (* (coerce ticks 'double-float)
     (ecase (precision-timer-resolution timer)
       (:ns 1.0d-6)
       (:us 1.0d-3)
       (:ms 1.0d0)
       (:s  1.0d3))))

(defgeneric us (timer ticks)
  (:documentation "Convert ticks (in timer's resolution) to microseconds (double-float)."))

(defmethod us ((timer precision-timer) ticks)
  (* (coerce ticks 'double-float)
     (ecase (precision-timer-resolution timer)
       (:ns 1.0d-3)
       (:us 1.0d0)
       (:ms 1.0d3)
       (:s  1.0d6))))

(defgeneric ns (timer ticks)
  (:documentation "Convert ticks (in timer's resolution) to nanoseconds (double-float)."))

(defmethod ns ((timer precision-timer) ticks)
  (* (coerce ticks 'double-float)
     (ecase (precision-timer-resolution timer)
       (:ns 1.0d0)
       (:us 1.0d3)
       (:ms 1.0d6)
       (:s  1.0d9))))
