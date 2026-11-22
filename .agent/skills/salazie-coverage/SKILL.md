---
name: salazie-coverage
description: Measure GDScript statement coverage of Salazie's gdUnit4 suites, find the untested lines of a script, and raise the CI coverage floor. Use when adding tests, when the coverage job is red, or before claiming a script is covered. Not for running the plain test suite (`salazie-verify`).
---

# Salazie coverage

Godot has no built-in coverage and gdUnit4 does not measure it, so the project
ships its own tool in `tools/coverage/`. It copies the project to a scratch
directory, inserts one `SalazieCov.hit(file, line)` call before every statement
inside a function body, runs gdUnit4 on the copy and reports per script. The
working tree is never modified.

## Run it

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot   # `godot` on Linux/CI
bash tools/coverage/run.sh                 # table, lowest coverage first
bash tools/coverage/run.sh --show-missed   # plus the missed line ranges
bash tools/coverage/run.sh --min 85        # exit 1 below 85 %
```

Requirements: `addons/gdUnit4` installed (see `salazie-verify`) and Python 3.9+.
A run takes about one minute with a warm import cache.

Outputs, all under `reports/coverage/` (ignored by Git):

| File | Content |
|---|---|
| `summary.json` | total, per-script counts and the missed line numbers |
| `lcov.info` | lcov tracefile for external viewers |
| `tests.log` | the gdUnit4 output of the instrumented run |
| `import.log` | the import pass of the instrumented copy |

## Find what a script is missing

```bash
python3 - <<'PY'
import json
data = json.load(open("reports/coverage/summary.json"))
print(data["files"]["scripts/farm/crop_plot.gd"]["missed"])
PY
```

Line numbers are those of the real script, not of the instrumented copy.

## What is counted

Statements inside `func` bodies of `scripts/**/*.gd`.

Not counted: declarations (`var`, `const`, `signal`, `func` headers), `else` /
`elif` headers, `match` patterns, the continuation lines of a multi-line
statement, and lambdas written inside a call's parentheses. A line such as
`if x: return` counts once, so a one-line branch reads as covered as soon as
the condition was evaluated. Treat 100 % as "every statement ran", not "every
branch was taken".

## Writing the missing tests

- Tests go in `tests/unit/test_*.gd` and follow the rules in `AGENTS.md`:
  observable behaviour, no frame-rate-dependent assertion.
- Do not write a test whose only purpose is to execute a line. If a line cannot
  be reached through behaviour worth asserting, it is probably dead code:
  delete it instead.
- Autoload state (`Campaign`, `GameState`, `Economy`, `SceneRouter`) survives
  between suites. Reset what a test changes in `after_test()`.

## The CI gate

The `coverage` job in `.github/workflows/godot-ci.yml` runs the same script
with `--min "$COVERAGE_MIN"` and publishes the table to the job summary. Raise
`COVERAGE_MIN` in the same PR that raises the coverage; keep it about one point
under the measured value, because a few random branches make the total move by
a tenth of a point between runs. Never lower it to make a PR pass.

## When the instrumented copy does not compile

`run.sh` stops with "the instrumented project does not compile" and the
offending lines from `import.log`. The instrumenter is line-based; a construct
it does not understand shows up here. Reproduce with:

```bash
python3 tools/coverage/test_coverage.py
```

Add the failing construct as a case there, then fix `instrument_source` in
`tools/coverage/coverage.py`.
