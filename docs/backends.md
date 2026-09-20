# Backends

The library selects a backend at compile time from the Lisp implementation and
target OS. Backends are tried in the order listed; the first that applies wins.

| Priority | Lisp | OS | API | Typical resolution |
|---|---|---|---|---|
| 1 | SBCL, CCL, CLISP, Clasp, … (via CFFI) | macOS / iOS | `mach_absolute_time` | ~1 ns |
| 2 | SBCL, CCL, CLISP, Clasp, … (via CFFI) | Linux, FreeBSD, OpenBSD, NetBSD | `clock_gettime(CLOCK_MONOTONIC)` | ~1 ns |
| 3 | SBCL, CCL, CLISP, Clasp, … (via CFFI) | Windows | `QueryPerformanceCounter` | ~100 ns |
| 4 | ECL | macOS / iOS | `mach_absolute_time` (via `ffi:c-inline`) | ~1 ns |
| 5 | ECL | Linux, Android, BSD | `clock_gettime(CLOCK_MONOTONIC)` (via `ffi:c-inline`) | ~1 ns |
| 6 | ECL | Windows | `QueryPerformanceCounter` (via `ffi:c-inline`) | ~100 ns§ |
| 7 | JSCL | Browser / Node.js | `performance.now()` | ~5 µs† |
| 8 | ABCL | JVM (any OS) | `System.nanoTime()` | ~1 µs |
| 9 | Any | Any | `get-internal-real-time` | varies‡ |

† Browsers clamp `performance.now()` resolution to ~1 ms or ~5 µs depending on
site isolation settings (Spectre mitigations). Node.js retains nanosecond
resolution.

§ Untested: Roswell does not run ECL on Windows, so whether ECL defines
`:windows` there is unverified. If it does not, this build takes priority 9.

‡ Fallback resolution depends on the implementation's
`internal-time-units-per-second`: SBCL ~1 µs, CCL / ECL ~1 ms, CLISP ~10 ms.

ECL uses its own native FFI (`ffi:c-inline`) rather than CFFI because `dlopen`
is restricted on iOS and some embedded targets. Every other implementation uses
CFFI.

## Backend selection

The feature `:thpt-native` is present when one of priorities 1–8 applies. Every
native backend is gated on it, so an OS the library does not recognise falls
through to priority 9 rather than compiling a half-defined native backend.

## Forcing the fallback

Priority 9 is otherwise unreachable — every platform with a runner has a native
backend. Push `:thpt-force-fallback` before loading to select it:

```lisp
(pushnew :thpt-force-fallback *features*)
(asdf:load-system :trivial-high-precision-timer)
```

This also drops the CFFI dependency, so it is the way to use the library on an
implementation where CFFI does not build. ASDF does not recompile on a feature
change alone — clear `~/.cache/common-lisp/` first.

## JSCL

JSCL ships no ASDF. Load the library by hand instead:

```lisp
(load "jscl-load.lisp")
```

JSCL has no `double-float` type specifier, so `sec`, `ms`, `us` and `ns` return
its `float`, which is a JavaScript double either way.
