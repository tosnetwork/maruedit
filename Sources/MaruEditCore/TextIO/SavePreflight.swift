import Foundation

/// One character that can't be represented in a target encoding, located
/// by 1-based line and column (matching how `Ln`/`Col` are already shown
/// elsewhere in the app, e.g. the status bar).
public struct UnrepresentableCharacter: Sendable, Equatable {
    public let character: String
    public let line: Int
    public let column: Int
}

public struct SavePreflightResult: Sendable, Equatable {
    public let isRepresentable: Bool
    public let unrepresentableCharacters: [UnrepresentableCharacter]
}

/// Checks whether text can be losslessly saved in a target encoding
/// *before* writing anything, per ROADMAP.md M2-04 / section 10.2 — so a
/// caller can offer the user a real choice (convert to UTF-8, or cancel)
/// instead of either silently corrupting the file or a bare "can't save"
/// error with no detail.
public enum SavePreflight {
    public static func check(_ text: String, encoding: TextEncoding) -> SavePreflightResult {
        guard let foundationEncoding = encoding.foundationEncoding else {
            return SavePreflightResult(isRepresentable: false, unrepresentableCharacters: [])
        }

        // Fast path: almost every save is fully representable.
        if text.data(using: foundationEncoding) != nil {
            return SavePreflightResult(isRepresentable: true, unrepresentableCharacters: [])
        }

        // Slow path: only reached when something is actually wrong —
        // locate every offending character by scanning line/column.
        var problems: [UnrepresentableCharacter] = []
        var line = 1
        var column = 1
        for character in text {
            if String(character).data(using: foundationEncoding) == nil {
                problems.append(UnrepresentableCharacter(character: String(character), line: line, column: column))
            }
            if character == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return SavePreflightResult(isRepresentable: problems.isEmpty, unrepresentableCharacters: problems)
    }
}
