# 1.0 Beta Test Matrix

This matrix separates repeatable automated evidence from checks that require a
human, physical hardware, or an OS service. A blank result is not treated as a
pass.

## Platforms

| Runtime / architecture | Provider | Status |
|---|---|---|
| macOS 13 / Apple Silicon or Intel | — | Unavailable: GitHub retired the macOS 13 hosted image; no local macOS 13 hardware is attached. Deployment remains set to 13.0. |
| macOS 14 / Apple Silicon | GitHub Actions `macos-14` | CI matrix pending first run |
| macOS 15 / Apple Silicon | GitHub Actions `macos-15` | CI matrix pending first run |
| macOS 15 / Intel x86_64 | GitHub Actions `macos-15-intel` | CI matrix pending first run |
| macOS 26 / Apple Silicon | Local MacBook Air M2 and GitHub Actions `macos-26` | Local 402-test suite passed; CI matrix pending first run |

GitHub's current runner-image catalog is the source of truth for available
hosted images. The workflow names exact images rather than `macos-latest`, so a
future alias migration cannot silently change beta coverage.

## Functional coverage

| Area | Automated evidence | Manual evidence / remaining work |
|---|---|---|
| English, Japanese, Simplified Chinese | Localization tables and tests cover all three explicit values | Switch each system language and inspect menus/dialog truncation |
| Japanese IME | `CJKIMETests` exercise marked text, commit, cancel, replacement, multi-selection collapse, and undo | Real Kotoeri composition documented in `docs/ime-testing.md` |
| Chinese IME | Same NSTextInputClient composition contracts | Real Pinyin composition documented in `docs/ime-testing.md` |
| UTF and Japanese legacy encodings | Encoding detector/loader/saver fixtures | Open/save representative user files |
| LF, CRLF, CR, mixed | Line-ending detector and byte-level round trips | Inspect status and mixed-save prompt |
| External file modification | Modified, deleted, moved, and same-path replacement tests | Edit an open file from another application |
| Multiple windows and tabs | Independent controller close-order and isolation tests | Open/close two visible windows in both orders |
| Grep cancellation | Token and Swift Task cancellation tests | Cancel a visible long directory scan |
| Macro permissions | Denial, remembered decision, bookmark, revocation, and fail-closed tests | Inspect permission prompts and management UI |
| Accessibility | Explicit labels/roles/values and keyboard-navigation tests | VoiceOver smoke: editor, tabs, Find, status, Grep results, Settings |

## Reproduction

```bash
bash scripts/beta-smoke.sh
swift test
bash build.sh
```

The headless suite deliberately avoids modal `NSAlert` paths; those would
deadlock without a user to click them and are represented by lower-level logic
tests plus the manual checklist above.
