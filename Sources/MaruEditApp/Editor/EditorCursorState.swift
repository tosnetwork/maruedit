import Foundation

/// Explicit cursor/selection coordinates for UI consumers. Display columns
/// are one-based visual cells; UTF-16 offsets are zero-based storage indices.
/// They must never be used interchangeably.
struct EditorCursorState: Equatable {
    let lineNumber: Int
    let displayColumn: Int
    let utf16Offset: Int
    let selectedCharacterCount: Int
    let selectedUTF16Length: Int
    let selectionRangeCount: Int
}
