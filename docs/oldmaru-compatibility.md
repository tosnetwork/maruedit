# OldMaru Workflow Compatibility

MaruEdit is an independent macOS project, not a port endorsed by OldMaru's
developers. Compatibility means familiar workflows, not binary or brand
compatibility.

| Workflow | 1.0 status | Notes |
|---|---|---|
| Text encoding/BOM/newline control | Supported | Includes UTF and Japanese legacy formats |
| Literal and regex Find/Replace | Supported | Unified engine and selection scope |
| Folder Grep and Grep Replace | Supported | Streaming results and preview-before-write |
| BOX selection and multiple selections | Supported | TextKit visual-column model |
| Japanese/Chinese IME | Supported | Composition has one primary caret |
| Custom and chorded keys | Supported | JSON profiles use stable command IDs |
| Per-file-type settings | Supported | File-type profiles |
| Macro automation | Partial compatibility | JavaScript API; see the detailed [macro matrix](compatibility/macro-compatibility.md) |
| External filters/tools | Supported with safeguards | Direct process mode preferred; shell mode warns every run |
| Native OldMaru macros/plugins | Not supported | No proprietary runtime or binary plugin ABI |
| Windows-only UI/integration | Not supported | macOS-native menus, security, and filesystem model |

Names and shortcuts are intentionally not copied where doing so would imply an
official relationship. See [NOTICE](../NOTICE.md) and [UPSTREAM](../UPSTREAM.md).

The broader product/UI comparison and prioritized compatibility backlog are in
[MaruEdit / OldMaru Product Gap Analysis](oldmaru-gap-analysis.md).
