# trivial-high-precision-timer

A cross-platform high-precision monotonic timer for Common Lisp, ported from [sokol_time.h](https://github.com/floooh/sokol).

Uses the best available OS timer on each platform:

- **macOS** — `mach_absolute_time`
- **Linux** — `clock_gettime(CLOCK_MONOTONIC)`
- **Windows** — `QueryPerformanceCounter`

## Quick Start

```lisp
(ql:quickload :trivial-high-precision-timer)
(use-package :trivial-high-precision-timer)

;; Initialize once before use
(setup)

;; Measure elapsed time
(let ((start (now)))
  (sleep 0.5)
  (format t "Elapsed: ~,3f ms~%" (ms (diff (now) start))))

;; Or use SINCE as shorthand
(let ((start (now)))
  (sleep 0.1)
  (format t "Elapsed: ~,6f sec~%" (sec (since start))))

;; Lap timing (e.g. frame timing in a loop)
(let ((last 0))
  (dotimes (i 3)
    (sleep 0.016)
    (multiple-value-bind (dt cur) (laptime last)
      (setf last cur)
      (format t "Frame ~D: ~,3f ms~%" i (ms dt)))))
```

## API

| Function | Description |
|---|---|
| `(setup)` | Initialize the timer. Call once before any other functions. |
| `(now)` | Current time in nanosecond ticks (monotonic, not wall-clock). |
| `(diff new old)` | Difference between two tick values. Always positive, minimum 1. |
| `(since start)` | Elapsed ticks since `start`. Shorthand for `(diff (now) start)`. |
| `(laptime last)` | Returns `(values elapsed-ns current-ticks)`. Pass 0 for the first call. |
| `(round-to-common-refresh-rate ticks)` | Snap a frame duration to the nearest common display refresh rate (60--240 Hz). |
| `(sec ticks)` | Convert ticks to seconds (double-float). |
| `(ms ticks)` | Convert ticks to milliseconds (double-float). |
| `(us ticks)` | Convert ticks to microseconds (double-float). |
| `(ns ticks)` | Convert ticks to nanoseconds (double-float). |

## License

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.html)
