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
    let selectedLineCount: Int
    let boxWidth: Int?
    let boxHeight: Int?

    init(
        lineNumber: Int, displayColumn: Int, utf16Offset: Int,
        selectedCharacterCount: Int, selectedUTF16Length: Int,
        selectionRangeCount: Int, selectedLineCount: Int = 0,
        boxWidth: Int? = nil, boxHeight: Int? = nil
    ) {
        self.lineNumber = lineNumber; self.displayColumn = displayColumn
        self.utf16Offset = utf16Offset
        self.selectedCharacterCount = selectedCharacterCount
        self.selectedUTF16Length = selectedUTF16Length
        self.selectionRangeCount = selectionRangeCount
        self.selectedLineCount = selectedLineCount
        self.boxWidth = boxWidth; self.boxHeight = boxHeight
    }
}
