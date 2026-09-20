# Testing

The suite lives in `tests/` and has no external dependencies: it must run under
ABCL and JSCL, neither of which can load FiveAM, Parachute or rove.

| File | Role |
|---|---|
| `tests/harness.lisp` | `deftest`, `is`, `is=`, `is-close`, `run-tests` |
| `tests/suite.lisp` | The tests |
| `tests/run.lisp` | Entry point for every implementation with ASDF |
| `tests/run-jscl.lisp` | Entry point for JSCL |

Both runners exit non-zero when an assertion fails.

## Running locally

```sh
sbcl --script tests/run.lisp
ccl --batch --quiet --load tests/run.lisp
ecl --shell tests/run.lisp
abcl --batch --load tests/run.lisp
ros -Q run --load tests/run.lisp
```

Or through ASDF:

```lisp
(asdf:test-system :trivial-high-precision-timer)
```

### Pure-CL fallback

```sh
rm -rf ~/.cache/common-lisp
THPT_FORCE_FALLBACK=1 sbcl --script tests/run.lisp
```

The cache must be cleared: ASDF does not recompile on a feature change alone,
so without it the run silently reports green against the native backend. Each
run prints which backend it compiled.

### JSCL

```sh
git clone --depth 1 https://github.com/jscl-project/jscl.git
(cd jscl && npm install && ./make.sh)
node jscl/dist/jscl-node.js tests/run-jscl.lisp
```

## Writing tests

Arithmetic carries the suite. CI runners are noisy VMs, so anything involving
`sleep` asserts a loose lower bound and no upper bound.

The suite lives in the library's own package so it can assert on internals.

### JSCL constraints

JSCL miscompiles a subtraction with a negative literal operand — `(- a b -1)`
produces invalid JavaScript. Write `(+ (- a b) 1)` instead. It also evaluates
declarations in method bodies, so `(declare (ignore ...))` is unusable there.
Tests that cannot run under JSCL are guarded with `#-jscl`.

## CI

`.github/workflows/ci.yml` runs one job per cell.

| OS | SBCL | CCL | ECL | ABCL | CLISP | Forced fallback |
|---|---|---|---|---|---|---|
| Linux | ✅ | ✅ | ✅ | ✅ | ✅ (fallback) | ✅ |
| macOS | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| Windows | ✅ | — | — | ⚠️ | — | ✅ |

A separate job builds JSCL and runs the suite under node.

Roswell supports few implementations on Windows, which is why CCL and ECL are
absent there and ABCL is non-blocking. See the README for platforms CI does not
cover at all.
