# Frequently Asked Questions

## Is MaruEdit an official Maru product?

No. It is an independent MIT-licensed macOS project and is neither affiliated
with nor endorsed by Maru's developers.

## Does it send telemetry?

No. MaruEdit has no analytics or telemetry client. Macros have no network API,
and external commands run only when configured and invoked by the user.

## Which macOS versions are supported?

The deployment target is macOS 13. Current CI covers the hosted macOS versions
and architectures listed in the [beta matrix](beta-test-matrix.md); unavailable
retired runner images are called out rather than reported as tested.

## Can it preserve Windows and Japanese files?

Yes. Encoding, BOM, and LF/CRLF/CR policy are modeled separately. Always check
the status bar when automatic detection is ambiguous, especially for short
legacy-encoded files.

## Can I use Maru macros?

Not directly. MaruEdit provides a controlled JavaScript API and a documented
partial compatibility layer. See [Macros](macros.md).

## Why is a very large file read-only?

The 1.0 editor uses TextKit 1. Reduced mode prevents an unexpectedly large file
from freezing editing or exhausting memory. Exact limits are documented in
[Large-file mode](large-file-mode.md).

## Where are settings stored?

Preferences use the application defaults domain. User macro and external-tool
configuration lives under `~/Library/Application Support/MaruEdit/`. Security-
scoped bookmarks are used when persistent file access requires consent.
