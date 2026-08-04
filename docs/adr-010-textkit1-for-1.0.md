# ADR-010: Keep TextKit 1 for MaruEdit 1.0

- Status: Accepted
- Date: 2026-08-05

## Context

MaruEdit 1.0 already has tested TextKit 1 behavior for multiple selections,
BOX virtual space, CJK IME reconciliation, line numbers/bookmarks, incremental
highlighting, Undo, and accessibility. TextKit 2 is newer but adopting it is a
behavioral migration, not a type-name substitution.

The isolated M7-05 target proved basic TextKit 2 layout, multiple selected
ranges, and marked-text protocol availability. It did not provide native BOX
semantics or a gutter replacement. Its one comparable Debug full-layout sample
was slower (0.521 s versus 0.308 s for TextKit 1).

## Decision

MaruEdit 1.0 remains on TextKit 1. The spike target stays isolated and compiling
as evidence and a future adapter test bed. Production code must not introduce a
runtime TextKit switch or duplicate editor implementation.

## Consequences

The 1.0 release keeps the mature selection/IME/layout path and avoids a late
rewrite without a demonstrated performance benefit. TextKit 2 remains a valid
2.0 project only after the exit criteria in `textkit2-spike.md` are met. This
decision is based on measured behavior and migration risk, not a preference for
older APIs.
