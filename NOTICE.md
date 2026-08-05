# NOTICE

MaruEdit is an independent, open-source project and is not affiliated with
or endorsed by the developers of Maru Editor. See `ROADMAP.md` sections
3 and 4 for the full intellectual-property and product-analysis boundaries
this project operates under.

## Upstream Attribution

MaruEdit is a fork of **LiteEdit** (https://github.com/arietan/lite-edit),
licensed under the MIT License. The original LiteEdit copyright notice is
preserved in `LICENSE` alongside MaruEdit's own copyright line, as required
by the MIT License's attribution term. See `UPSTREAM.md` for the exact base
commit, how it was determined, and the policy for reviewing future upstream
fixes.

```
LiteEdit
Copyright (c) 2026 arietan
https://github.com/arietan/lite-edit
Licensed under the MIT License.
```

## Modifications Made by MaruEdit

Starting from the LiteEdit codebase at the commit recorded in `UPSTREAM.md`,
MaruEdit has so far:

- renamed the package, executable target, application name, bundle
  identifier, menu titles, and window titles from LiteEdit to MaruEdit;
- replaced the generated application icon with an original placeholder
  (MaruEdit does not reuse LiteEdit's generated icon design);
- updated build scripts, GitHub issue/PR templates, and CI workflow
  references accordingly;
- removed marketing copy and links that were specific to the LiteEdit
  project's own distribution (landing page URL, analytics, Homebrew tap);
- added `NOTICE.md`, `UPSTREAM.md`, and `ROADMAP.md` to define MaruEdit's
  own product direction as a keyboard-first, Maru-workflow-inspired
  macOS text editor, independent of LiteEdit's original scope.

Further modifications are tracked through ordinary Git history and, for
architectural decisions, through ADRs referenced in `ROADMAP.md` section 6.

## Other Third-Party References

MaruEdit's `ROADMAP.md` documents CotEditor (Apache-2.0) as an architectural
and behavioral *reference*, not a code dependency. No CotEditor source code
or image assets are included in this repository. If Apache-2.0 source is
ever intentionally ported in the future, the source, copyright, and license
will be recorded here per ROADMAP.md section 3.3.

MaruEdit does not include, link against, decompile, or derive from any
Maru Editor source code, binaries, icons, or other protected resources.
See `ROADMAP.md` section 3.1 for what is and is not permitted when studying
Maru's publicly observable behavior.
