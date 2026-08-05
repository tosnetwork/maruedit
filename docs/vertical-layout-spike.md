# Vertical layout feasibility spike

AppKit's TextKit 1 stack successfully lays out mixed Japanese and Latin text
with `NSTextContainer.layoutOrientation = .vertical`. The executable
`VerticalLayoutFeasibilityTests` gate verifies that the glyph manager produces
a non-empty vertical layout on supported macOS versions.

This proves the rendering primitive, not production readiness. A shipped mode
still needs vertical hit testing, selection and caret QA, IME candidate-window
placement, ruby/tate-chu-yoko policy, printing, accessibility navigation, and
horizontal scrolling integration. MC9 therefore retains the spike and its
test, while keeping vertical mode out of the user-facing feature set until
those interaction gates can be completed without weakening text editing.
