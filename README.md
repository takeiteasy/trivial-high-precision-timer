# trivial-high-precision-timer

A cross-platform high-precision monotonic timer for Common Lisp.

## Quick Start

```lisp
(ql:quickload :trivial-high-precision-timer)
(use-package :trivial-high-precision-timer)

;; Create a timer (captures start time immediately)
(defvar *timer* (make-precision-timer))

;; Measure elapsed time
(let ((start (now *timer*)))
  (sleep 0.5)
  (format t "Elapsed: ~,3f ms~%" (ms *timer* (diff *timer* (now *timer*) start))))

;; Or use SINCE as shorthand
(let ((start (now *timer*)))
  (sleep 0.1)
  (format t "Elapsed: ~,6f sec~%" (sec *timer* (since *timer* start))))

;; Lap timing (e.g. frame timing in a loop)
(let ((last 0))
  (dotimes (i 3)
    (sleep 0.016)
    (multiple-value-bind (dt cur) (laptime *timer* last)
      (setf last cur)
      (format t "Frame ~D: ~,3f ms~%" i (ms *timer* dt)))))

;; Multiple independent timers
(let ((t1 (make-precision-timer))
      (t2 (make-precision-timer :resolution :us)))
  (sleep 0.1)
  (format t "t1: ~D ns, t2: ~D us~%" (now t1) (now t2)))
```

## API

| Function | Description |
|---|---|
| `(make-precision-timer &key resolution)` | Create a new timer. `resolution` is `:ns` (default), `:us`, `:ms`, or `:s`. Start time is captured immediately. |
| `(precision-timer-resolution timer)` | Return the resolution keyword of a timer instance. |
| `(precision-timer-start timer)` | Return the raw platform tick captured at timer creation. |
| `(now timer)` | Elapsed time since the timer was created, in the timer's resolution. |
| `(diff timer new old)` | Difference between two `now` values. Always positive, minimum 1. |
| `(since timer start)` | Elapsed ticks since `start`. Shorthand for `(diff timer (now timer) start)`. |
| `(laptime timer last)` | Returns `(values elapsed-ticks current-ticks)`. Pass 0 for the first call. |
| `(round-to-common-refresh-rate timer ticks)` | Snap a frame duration to the nearest common display refresh rate (60--240 Hz). |
| `(sec timer ticks)` | Convert ticks to seconds (double-float). |
| `(ms timer ticks)` | Convert ticks to milliseconds (double-float). |
| `(us timer ticks)` | Convert ticks to microseconds (double-float). |
| `(ns timer ticks)` | Convert ticks to nanoseconds (double-float). |

## Backends

The library selects a backend at compile time based on the Lisp implementation and target OS. Backends are tried in the order listed; the first one that applies is used.

| Priority | Lisp | OS | API | Typical resolution |
|---|---|---|---|---|
| 1 | SBCL, CCL, LispWorks, Clasp, … (via CFFI) | macOS / iOS | `mach_absolute_time` | ~1 ns |
| 2 | SBCL, CCL, LispWorks, Clasp, … (via CFFI) | Linux, FreeBSD, OpenBSD, NetBSD | `clock_gettime(CLOCK_MONOTONIC)` | ~1 ns |
| 3 | SBCL, CCL, LispWorks, Clasp, … (via CFFI) | Windows | `QueryPerformanceCounter` | ~100 ns |
| 4 | ECL | macOS / iOS | `mach_absolute_time` (via `ffi:c-inline`) | ~1 ns |
| 5 | ECL | Linux, Android, BSD | `clock_gettime(CLOCK_MONOTONIC)` (via `ffi:c-inline`) | ~1 ns |
| 6 | ECL | Windows | `QueryPerformanceCounter` (via `ffi:c-inline`) | ~100 ns |
| 7 | JSCL | Browser / Node.js | `performance.now()` | ~5 µs† |
| 8 | ABCL | JVM (any OS) | `System.nanoTime()` | ~1 µs |
| 9 | Any | Any | `get-internal-real-time` | varies‡ |

† Browsers clamp `performance.now()` resolution to ~1 ms or ~5 µs depending on site isolation settings (Spectre mitigations). Node.js retains nanosecond resolution.

‡ Pure CL fallback resolution depends on the implementation's `internal-time-units-per-second`: SBCL ~1 µs, CCL / ECL ~1 ms, CLISP ~10 ms.

ECL uses its own native FFI (`ffi:c-inline`) rather than CFFI because `dlopen` is restricted on iOS and some embedded targets. All other implementations use CFFI when it is available.

## License

[GPLv3](LICENSE)
