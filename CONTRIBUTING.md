# Contributing to MaruEdit

Thanks for your interest in contributing. MaruEdit is a small, focused project — contributions that keep it small and focused are welcome.

## Principles

- **No third-party dependencies.** MaruEdit compiles with `swift build` alone — no SPM packages, no CocoaPods, no frameworks.
- **AppKit only.** No SwiftUI, no web views, no Electron.
- **Keep the binary small.** Every feature should justify its weight.

## Getting Started

1. Fork the repository and clone your fork:

   ```bash
   git clone https://github.com/<your-username>/maruedit.git
   cd maruedit
   git remote add upstream https://github.com/tosnetwork/maruedit.git
   ```

2. Build and run:

   ```bash
   bash build.sh
   open MaruEdit.app
   ```

   Requires Xcode Command Line Tools and macOS 13+.

## Making Changes

1. Create a branch from `main`:

   ```bash
   git checkout -b feature/your-change
   ```

2. Make your changes. Keep commits small and descriptive.

3. Verify the app builds and runs:

   ```bash
   bash build.sh
   open MaruEdit.app
   ```

4. Push to your fork and open a pull request against `main`.

## What to Contribute

- Bug fixes
- Performance improvements
- New syntax highlighting grammars
- Keyboard shortcut additions
- Accessibility improvements
- Documentation

## What to Avoid

- Adding third-party dependencies
- Large features that significantly increase binary size
- UI frameworks other than AppKit
- Changes that break macOS 13 compatibility

## Code Style

- Follow existing patterns in the codebase.
- Use `// MARK: -` to organize sections within files.
- Keep files focused — one responsibility per file.
- Prefer clarity over cleverness.

## Reporting Issues

Use the [GitHub issue tracker](https://github.com/tosnetwork/maruedit/issues). Please include:

- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console output if relevant (`open MaruEdit.app` from Terminal to see logs)
