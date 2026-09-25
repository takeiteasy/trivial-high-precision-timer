# CI

CI runs a small set of jobs automatically and the full platform matrix on
request. The matrix cells are listed in [testing](testing.md#ci).

## When jobs run

| Trigger | Jobs |
|---|---|
| Push to `trunk` or `master`, or pull request | Tier 1, chosen by changed paths |
| Docs-only change | None |
| `[ci full]` in the latest commit message | Full matrix |
| `ci-full` label on a pull request | Full matrix on every push while labelled |
| Tag `v*` | Full matrix |
| Manual dispatch | Full matrix, narrowed by inputs |

New pushes cancel the previous run for the same branch or pull request.

## Tiers

| Tier | Jobs | Runs |
|---|---|---|
| 1 | SBCL / Linux, Fallback / Linux | Any code change |
| 1 | JSCL / node | JSCL file changes[^focus] |
| 2 | Every other platform and Lisp, CLISP | Full matrix only |

The job list lives in [`.github/ci-matrix.json`](../.github/ci-matrix.json).
[`.github/scripts/plan.sh`](../.github/scripts/plan.sh) selects from it.

## Running a slice

```sh
gh workflow run ci.yml -f os=macos              # every macOS job
gh workflow run ci.yml -f os=linux -f lisp=abcl # ABCL on Linux only
gh workflow run ci.yml -f lisp=ccl              # CCL on every OS
```

`os` is `all`, `linux`, `macos`, or `windows`. `lisp` is matched against the
Lisp name in the matrix (`sbcl`, `ccl`, `ecl`, `abcl`, `clisp`, `jscl`).

## Before dispatching

Run the suite locally first; see [testing](testing.md#running-locally). Dispatch
a slice for the platforms you cannot run.

## sr.ht builds

[`.build.yml`](../.build.yml) runs the suite on Linux with SBCL on every push
to the sr.ht mirror, at no GitHub cost. It covers the same ground as the tier 1
SBCL job.

## Cost

Private repositories bill macOS minutes at about ten times and Windows at about
twice the Linux rate; public repositories use standard runners for free.

[^focus]: `jscl-backend.lisp`, `jscl-load.lisp`, and `tests/run-jscl.lisp`. The
    path lists are in the `paths` section of the matrix file.
