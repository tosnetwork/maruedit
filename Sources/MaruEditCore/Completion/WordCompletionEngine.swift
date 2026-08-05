import Foundation

public struct CompletionCandidate: Equatable, Sendable {
    public let word: String
    public let frequency: Int
    public let sourcePriority: Int
}

/// Deterministic, bounded word completion shared by UI and tests.
public enum WordCompletionEngine {
    public static let maximumInputLength = 5_000_000
    public static let maximumCandidates = 100

    public static func candidates(
        prefix: String, document: String, dictionaries: [String] = [],
        settings: CompletionSettings = CompletionSettings()
    ) -> [CompletionCandidate] {
        guard !prefix.isEmpty else { return [] }
        var counts: [String: (frequency: Int, priority: Int)] = [:]
        if settings.includesCurrentDocument {
            collect(document, priority: 0, into: &counts)
        }
        for (index, dictionary) in dictionaries.enumerated() {
            collect(dictionary, priority: index + 1, into: &counts)
        }
        let foldedPrefix = prefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var result = counts.compactMap { word, value -> CompletionCandidate? in
            let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard word != prefix, folded.hasPrefix(foldedPrefix) else { return nil }
            return CompletionCandidate(word: word, frequency: value.frequency, sourcePriority: value.priority)
        }
        result.sort {
            switch settings.ranking {
            case .frequency:
                if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
                if $0.sourcePriority != $1.sourcePriority { return $0.sourcePriority < $1.sourcePriority }
            case .alphabetical: break
            }
            return $0.word.localizedStandardCompare($1.word) == .orderedAscending
        }
        return Array(result.prefix(maximumCandidates))
    }

    private static func collect(
        _ input: String, priority: Int, into counts: inout [String: (frequency: Int, priority: Int)]
    ) {
        let bounded = String(input.prefix(maximumInputLength))
        var additions: [String] = []
        bounded.enumerateSubstrings(in: bounded.startIndex..<bounded.endIndex, options: .byWords) { word, _, _, _ in
            guard let word, word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return }
            additions.append(word)
        }
        for word in additions {
            let previous = counts[word] ?? (0, priority)
            counts[word] = (previous.frequency + 1, min(previous.priority, priority))
        }
    }
}

public enum CompletionDictionaryLoader {
    public static let maximumDictionaryBytes = 2 * 1_024 * 1_024

    public static func load(paths: [String]) -> [String] {
        paths.prefix(16).compactMap { path in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                  data.count <= maximumDictionaryBytes else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
