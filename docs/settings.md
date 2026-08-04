# Settings

Open Settings with **Command-,** or the MaruEdit application menu. The native
window contains General, Editor, Appearance, Files, Search, Key Bindings,
Macros, and Advanced groups. Its search field filters these groups by their
localized names.

The Editor and Appearance groups currently expose the typed preferences that
already affect the editor: font family and size, tab width, line wrapping, and
line-number visibility. Changes are saved immediately and applied to both the
open document and documents loaded later. Applying appearance settings changes
attributes only; it does not modify document text or its Undo history.

**Restore Group Defaults** changes only the selected group's fields. Groups
whose features arrive in later M5/M6 tasks remain visible and searchable so
their controls can be added without redesigning navigation.

All controls use native keyboard focus and accessibility APIs. Settings labels,
group names, search, reset, and explanatory text are available in English,
Japanese, and Simplified Chinese, selected from the system language.

Release UI verification on 2026-08-04 opened the Japanese Settings window via
Command-, and confirmed all eight groups, focused search, localized explanatory
text, and the group-default button rendered correctly.
