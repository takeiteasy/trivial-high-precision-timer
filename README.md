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
| `(diff timer new old)` | Difference between two `now` values, never negative. Returns 0 when they are equal or out of order. |
| `(since timer start)` | Elapsed ticks since `start`. Shorthand for `(diff timer (now timer) start)`. |
| `(laptime timer last)` | Returns `(values elapsed-ticks current-ticks)`. Pass 0 for the first call. |
| `(round-to-common-refresh-rate timer ticks)` | Snap a frame duration to the nearest common display refresh rate (60--240 Hz). |
| `(sec timer ticks)` | Convert ticks to seconds (double-float). |
| `(ms timer ticks)` | Convert ticks to milliseconds (double-float). |
| `(us timer ticks)` | Convert ticks to microseconds (double-float). |
| `(ns timer ticks)` | Convert ticks to nanoseconds (double-float). |

## Backends

The library picks a backend at compile time from the Lisp implementation and
target OS — `mach_absolute_time`, `clock_gettime`, `QueryPerformanceCounter`,
`performance.now()`, `System.nanoTime()`, or a pure-CL fallback.

See [docs/backends.md](docs/backends.md) for the full table, how selection
works, and how to force the fallback.

## Testing

```sh
sbcl --script tests/run.lisp
```

See [docs/testing.md](docs/testing.md) for the other implementations and the CI
matrix.

### Not covered by CI

| Platform | Why |
|---|---|
| FreeBSD, OpenBSD, NetBSD | No GitHub-hosted runner. Shares the `clock_gettime` path tested on Linux. |
| CCL, ECL on Windows | Roswell does not support them there. |
| iOS, Android | No runner. Shares the ECL `ffi:c-inline` paths tested on desktop. |
| LispWorks, Allegro | Commercial; no CI license. |
| 32-bit with 64-bit `time_t` | `timespec`'s `tv-sec` is declared `:long`, which is wrong there. |
| Browser JSCL | Node covers the JSCL backend; browser `performance.now()` clamping is not exercised. |

## License

[GPLv3](LICENSE)
