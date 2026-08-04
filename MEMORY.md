# Project Memory

## Current State
MaruEdit — native macOS code editor (~3,000 lines Swift/AppKit), built on top of the LiteEdit codebase (renamed 2026-08-04; upstream history below predates the rename). Now following `ROADMAP.md` as the engineering source of truth, milestone M0 (fork/brand/baseline) complete, M1-01 (split into `MaruEditCore` + `MaruEditApp` SwiftPM targets) done. Builds with `swift build`; `bash build.sh` packages a ~700 KB `.app`.

## Architecture Decisions
- Pure AppKit + TextKit 1 (forced via `_ = textView.layoutManager`), no SwiftUI
- Global `NSEvent.addLocalMonitorForEvents` in `EditorShortcuts` handles shortcuts (Option+Up/Down, Cmd+Shift+K, Cmd+Shift+L)
- Multi-cursor edits bypass `didChangeText()` to avoid selection collapse from rehighlighting
- Auto-indent uses a `suppressAutoIndent` flag to prevent recursion when calling `insertText` from the delegate
- Tab switching uses NSTextStorage-per-document caching: each Document holds a `cachedTextStorage` that preserves text + highlighting attributes across tab switches. `loadDoc()` swaps via `layoutManager.replaceTextStorage()` for O(1) switches. Cursor/scroll restoration must be deferred (`DispatchQueue.main.async`) because `replaceTextStorage` invalidates layout asynchronously, resetting the selection.
- TabBarView exposes `setTabs(_:selectedIndex:)` (smart rebuild), `selectTab(at:)` (appearance only), `updateTab(at:item:)` (single tab label). Hot paths (tab click, keystroke) use targeted methods; structural changes (open/close tab) use `setTabs`.

## Known Issues & TODOs
- Auto-indent is whitespace-matching only; no smart indent (e.g. increase after `{`)
- Markdown fenced code blocks may still lose highlighting when editing deep inside them (visible-range rehighlight helps but multi-page code blocks can exceed the viewport)
- Large files (> 100k chars) use lazy viewport-only highlighting; text outside the viewport + buffer stays unhighlighted until scrolled to
- Landing page: merged into awesome-mac (101k+ stars); remaining enhancement ideas: animated demo GIF/video, real cold-start benchmarks, honest "Not for you if..." section, mobile hamburger nav, JSON-LD structured data

## Key Files & Patterns
- `Sources/MaruEditCore/Language.swift` — pure Foundation file-language model + detection, no AppKit; the first extraction into the Core target (M1-01)
- `Sources/MaruEditApp/EditorViewController.swift` — main text view, delegate, find/replace, auto-indent
- `Sources/MaruEditApp/EditorViewController+Shortcuts.swift` — line move, delete, multi-cursor edit
- `Sources/MaruEditApp/SyntaxHighlighter.swift` — regex-based highlighting for 20+ languages
- `Sources/MaruEditApp/MainWindowController.swift` — window, tabs, session persistence
- `Sources/MaruEditApp/SidebarViewController.swift` — file tree explorer

## Environment & Setup
- Requires macOS 13+, Xcode Command Line Tools, Swift 5.9
- Build: `swift build` or `bash build.sh`
- Run: `open MaruEdit.app`
