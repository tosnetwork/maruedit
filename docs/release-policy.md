# 1.0 Feature Freeze and Defect Policy

The 1.0 feature freeze begins with M8-01. Until `v1.0.0`, changes are limited
to defect fixes, security and privacy corrections, accessibility fixes,
localization corrections, release engineering, tests, and documentation.
Feature ideas are deferred to a post-1.0 milestone unless they are required to
resolve a P0 or P1 defect.

## Priorities

- **P0:** confirmed or credible data loss, a security boundary failure,
  inability to start the application, or a critical reproducible crash. A P0
  blocks every release and receives immediate rollback or fix work.
- **P1:** a severe failure in Save, Find, Grep, text input, encoding/line-ending
  preservation, or another core workflow with no safe practical workaround. A
  P1 blocks 1.0.
- **P2:** a functional defect or missed engineering target with a reasonable
  workaround that does not put user data or security at risk. P2 issues may be
  published as known limitations and scheduled after 1.0.

Priority labels in GitHub are the canonical classification. Classification
must include reproduction details, affected versions, user impact, workaround,
and the evidence required to close the issue. Lowering a priority requires a
written explanation; closing a P0/P1 requires a regression test where
practical.

## M8-01 audit

On 5 August 2026 the complete open issue list contained three measured
performance gaps and no correctness, security, startup-failure, crash, Save,
Find, Grep, or text-input defect. The three open items are classified P2:

- [#1: cold launch exceeds the 300 ms target](https://github.com/tosnetwork/maruedit/issues/1)
- [#2: 1 MB file open narrowly exceeds the 200 ms target](https://github.com/tosnetwork/maruedit/issues/2)
- [#3: idle RSS exceeds the 80 MB target](https://github.com/tosnetwork/maruedit/issues/3)

Accordingly, the audit result is P0 = 0 and P1 = 0. This is a point-in-time
release decision, not a claim that defects cannot exist; the count must be
rechecked at M8-06 immediately before tagging.

