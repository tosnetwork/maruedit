# Security Policy

## Supported versions

Until 1.0 is published, security fixes are made on `main`. After release, the
latest 1.x release and `main` receive security fixes; older versions are not
guaranteed support.

## Reporting a vulnerability

Do not open a public issue for an unpatched vulnerability. Use GitHub's
**Security > Report a vulnerability** private reporting flow for
`tosnetwork/maruedit`. Include the affected commit/version, macOS version,
reproduction, impact, and whether a proof-of-concept modifies user data.

Maintainers should acknowledge a complete report within seven days, validate
severity, prepare a private fix, and coordinate disclosure. Data loss,
arbitrary command execution without explicit configuration/consent, sandboxed
macro escape, signature failure, or secret exposure is handled as P0 under the
[release policy](docs/release-policy.md).

## Security boundaries

Documents and configured external commands are untrusted input. JavaScript
macros receive only explicit capability functions and no filesystem, network,
AppKit, controller, or Objective-C objects. External commands are intentionally
outside that sandbox and run with the user's authority; direct executable mode
and a minimal environment allowlist are the safe defaults. See the
[threat model](docs/security-threat-model.md).
