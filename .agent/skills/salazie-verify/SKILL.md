---
name: salazie-verify
description: Verify Salazie changes with Godot 4.7 import, gdUnit4 tests, a headless smoke run, and Linux/Windows/macOS/Web exports. Use before committing gameplay, scene, asset, export, or CI changes.
---

# Salazie verification

Run from the repository root. Target Godot **4.7.2**, the version used by CI.

## 1. Resolve the Godot binary

```bash
# macOS
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot

# Linux/CI: usually on PATH
GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --version
```

## 2. Import the project

`.godot/` is ignored, so import after a fresh checkout or cache cleanup:

```bash
"$GODOT_BIN" --headless --import
```

## 3. Run gdUnit4 tests

The addon is not committed. Install it locally once if needed:

```bash
if [ ! -d addons/gdUnit4 ]; then
  tmp="$(mktemp -d)"
  git clone --depth 1 --branch v6.2.3 https://github.com/godot-gdunit-labs/gdUnit4 "$tmp/gdUnit4"
  mkdir -p addons
  cp -R "$tmp/gdUnit4/addons/gdUnit4" addons/
  rm -rf "$tmp"
fi

GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

gdUnit4 v6 needs `--ignoreHeadlessMode` when using `--headless`. If that mode
misbehaves on your machine, drop `--headless --ignoreHeadlessMode` and run the
same command with a display.

## 4. Smoke test every reachable scene

```bash
GODOT_BIN="$GODOT_BIN" bash tools/ci/smoke.sh
```

The script runs the boot scene, the three maps, the ending and the sandbox
headless for 60 frames each, and fails on any `SCRIPT ERROR` or `ERROR:` line.
The exit code alone is not enough: Godot can exit 0 after runtime errors. Logs
land in `reports/smoke/`. CI runs the same script.

## 5. Export when exports or project settings changed

```bash
mkdir -p export/linux export/windows export/macos export/web

"$GODOT_BIN" --headless --export-release "Linux" export/linux/salazie.x86_64
test -f export/linux/salazie.x86_64

"$GODOT_BIN" --headless --export-release "Windows Desktop" export/windows/salazie.exe
test -f export/windows/salazie.exe

"$GODOT_BIN" --headless --export-release "macOS" export/macos/salazie.zip
test -f export/macos/salazie.zip

"$GODOT_BIN" --headless --export-release "Web" export/web/index.html
test -f export/web/index.html
```

Godot's export command can exit 0 when it prints `Project export ... failed`.
Always assert that the output file exists.

macOS uses the **universal** template and therefore requires:

```ini
[rendering]
textures/vram_compression/import_etc2_astc=true
```

If macOS fails with `Requested template binary "godot_macos_release.x86_64" not
found`, the preset was probably switched back to `x86_64`; see Godot issue
#121170. Keep the preset on `universal` and the project setting above enabled.

## 6. CI verification

```bash
gh pr checks
gh run view --log-failed
```

## Report format

Return:

1. **PASS/FAIL** for import, tests, smoke, and each export.
2. The exact command and the relevant error lines for failures.
3. File:line references and the smallest suggested next action.

Do not edit project files while verifying.
