# Upstream Provenance

MaruEdit began as a fork of **LiteEdit**, a native macOS Swift/AppKit code
editor. This document records exactly where the fork started and how future
upstream fixes should be reviewed and integrated, per ROADMAP.md task M0-01.

## Upstream Project

| Field | Value |
|---|---|
| Project | LiteEdit |
| Repository | https://github.com/arietan/lite-edit |
| License | MIT License |
| Base branch | `main` |
| Base commit SHA | `0787bd0eaff0939b6a5513017f42068938275ab6` |
| Base commit date | 2026-04-23 |
| Base commit subject | "Run download alert daily instead of every 6 hours" |
| Base commit author | Hoan &lt;nnh.mike@gmail.com&gt; (public GitHub author of `arietan/lite-edit`) |
| Base commit relative to tags | 5 commits ahead of `v1.1.6` (the last tagged release before the base commit) |
| Import date into MaruEdit | 2026-08-04 |

## How the Base Commit Was Determined

The MaruEdit repository was not created with `git clone`/`git fork` — the
initial working tree was copied in as plain files and given a fresh commit
history starting from the LiteEdit → MaruEdit branding sync. To identify the
exact upstream revision after the fact, an `upstream` remote was added and
every source file that the branding sync did not touch was diffed
byte-for-byte against `upstream/main`:

```bash
git remote add upstream https://github.com/arietan/lite-edit
git fetch upstream --tags
diff <(git show upstream/main:Sources/LiteEdit/Document.swift) Sources/MaruEdit/Document.swift
# ... repeated for every file with no "LiteEdit" text to rename
```

`Document.swift`, `Theme.swift`, `SyntaxHighlighter.swift`, `TabBarView.swift`,
`FindBarView.swift`, `LineNumberView.swift`, `QuickOpenPanel.swift`,
`RecentItems.swift`, `SidebarViewController.swift`, `StatusBarView.swift`,
`EditorViewController.swift`, `EditorViewController+Shortcuts.swift`, and
`main.swift` are byte-identical to `upstream/main` at
`0787bd0eaff0939b6a5513017f42068938275ab6`. `AppDelegate.swift` and
`MainWindowController.swift` differ only in the literal `LiteEdit` →
`MaruEdit` text substitutions made during the branding sync. This confirms
the base commit precisely.

## Known Limitation

This repository's Git history does **not** contain LiteEdit's original
commit-by-commit history or author metadata — it starts fresh at the
branding-sync commit. Maintainers who need the original commit history can
inspect it directly through the `upstream` remote:

```bash
git log upstream/main
git log v1.0.0..v1.1.6 --oneline   # LiteEdit's own release history
```

Grafting that history into this repository's `main` branch would require a
history rewrite (e.g. `git replace` grafts or a merge with `--allow-unrelated-histories`
followed by a force-push), which is a destructive, one-way operation on a
branch that is already pushed to `origin/main`. That decision is left to an
explicit maintainer choice and is out of scope for this task.

## `upstream` Remote Configuration

```bash
git remote add upstream https://github.com/arietan/lite-edit
git fetch upstream --tags
```

`origin` continues to point at `https://github.com/tosnetwork/maruedit` and
is the only remote used for day-to-day pushes.

## Reviewing and Integrating Future Upstream Fixes

Because MaruEdit has already renamed `Sources/LiteEdit/` to
`Sources/MaruEditApp/` (and split part of it into `Sources/MaruEditCore/`
as of M1-01, with further divergence expected as the ROADMAP milestones
proceed), upstream commits generally will **not** apply with a clean
`git cherry-pick`. The expected workflow is manual review and porting, not
automatic merging:

1. `git fetch upstream`
2. `git log HEAD..upstream/main --oneline` to see what changed upstream since the base commit (or since the last review).
3. For each upstream commit that looks relevant (bug fix, correctness issue, non-branding behavior change), read the diff (`git show <sha>`) and manually port the equivalent change into `Sources/MaruEditApp/` (or `Sources/MaruEditCore/` if the equivalent code has since moved there).
4. Skip upstream commits that are LiteEdit-specific branding, landing-page, or release-process changes — MaruEdit's are independent.
5. Reference the upstream commit SHA in the MaruEdit commit message (e.g. `Port fix from upstream 0787bd0`) so the provenance stays traceable.
6. Record anything non-trivial in `NOTICE.md` or an ADR if it affects a foundational decision.

## License Notice

LiteEdit is MIT licensed. The original copyright notice is preserved in
`LICENSE` alongside the new MaruEdit copyright line. See `NOTICE.md` for the
full attribution statement.
