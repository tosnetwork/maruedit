import Foundation

public struct GrepReplaceMatch: Sendable, Equatable {
    public let index: Int
    public let range: NSRange
    public let before: String
    public let after: String
    public var isSelected: Bool
}

public struct GrepReplaceFileChange: Sendable, Equatable {
    public let url: URL
    public let encoding: TextEncoding
    public let hasByteOrderMark: Bool
    public let lineEnding: LineEndingState
    public let originalText: String
    public let originalData: Data
    public let originalIdentity: FileIdentity?
    public let originalModificationDate: Date?
    public let posixPermissions: Int
    public var isSelected: Bool
    public var matches: [GrepReplaceMatch]

    public var selectedMatchCount: Int { isSelected ? matches.filter(\.isSelected).count : 0 }
    public var previewText: String {
        guard isSelected else { return originalText }
        let result = NSMutableString(string: originalText)
        for match in matches.filter(\.isSelected).reversed() {
            result.replaceCharacters(in: match.range, with: match.after)
        }
        return result as String
    }
}

public struct GrepReplaceChangeSet: Sendable, Equatable {
    public let query: SearchQuery
    public let replacement: String
    public var files: [GrepReplaceFileChange]
    public let skipped: [URL: String]
    public let wasCancelled: Bool
    public var selectedFileCount: Int { files.filter { $0.isSelected && $0.selectedMatchCount > 0 }.count }
    public var selectedMatchCount: Int { files.reduce(0) { $0 + $1.selectedMatchCount } }
}

public enum GrepReplaceFileResult: Equatable, Sendable {
    case written(matchCount: Int, backupURL: URL)
    case conflict
    case encodingFailure
    case writeFailure(String)
    case cancelled
}

public struct GrepReplaceApplySummary: Sendable {
    public let transactionDirectory: URL
    public let results: [URL: GrepReplaceFileResult]
    public var writtenFiles: Int { results.values.filter { if case .written = $0 { true } else { false } }.count }
    public var failedFiles: Int { results.count - writtenFiles }
    public var wasCancelled: Bool { results.values.contains(.cancelled) }
}

private struct GrepReplaceRecoveryRecord: Codable {
    let originalPath: String
    let backupPath: String
    let createdAt: Date
}

public enum GrepReplaceService {
    public static func scan(
        request: GrepRequest, replacement: String,
        isCancelled: () -> Bool = { false }
    ) throws -> GrepReplaceChangeSet {
        var query = request.query; query.replacement = replacement; query.scope = .document
        let regex = try SearchEngine.compile(query)
        var files: [GrepReplaceFileChange] = [], skipped: [URL: String] = [:]
        DirectoryTraversal.traverse(request, isCancelled: isCancelled, onFile: { url in
            guard !isCancelled() else { return }
            do {
                let loaded = try TextFileLoader.load(contentsOf: url)
                let normalized = LineEndingDetector.normalize(loaded.content)
                let found = SearchEngine.matches(for: query, in: normalized, using: regex)
                guard !found.isEmpty, let data = try? Data(contentsOf: url) else { return }
                let ns = normalized as NSString
                let matches = found.enumerated().map { index, match in
                    GrepReplaceMatch(
                        index: index, range: match.range, before: ns.substring(with: match.range),
                        after: SearchEngine.replacement(for: match, in: normalized, query: query),
                        isSelected: true)
                }
                files.append(.init(
                    url: url, encoding: loaded.encoding, hasByteOrderMark: loaded.hasByteOrderMark,
                    lineEnding: LineEndingDetector.detect(loaded.content), originalText: normalized,
                    originalData: data, originalIdentity: loaded.fileIdentity,
                    originalModificationDate: loaded.modificationDate,
                    posixPermissions: loaded.posixPermissions, isSelected: true, matches: matches))
            } catch { skipped[url] = error.localizedDescription }
        }, onSkip: { url, reason in skipped[url] = reason.describedReason })
        return .init(query: query, replacement: replacement,
                     files: files.sorted { $0.url.path < $1.url.path }, skipped: skipped,
                     wasCancelled: isCancelled())
    }

    public static func apply(
        _ changeSet: GrepReplaceChangeSet, transactionDirectory: URL? = nil,
        isCancelled: () -> Bool = { false }
    ) -> GrepReplaceApplySummary {
        let directory = transactionDirectory ?? defaultTransactionDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var results: [URL: GrepReplaceFileResult] = [:]
        var records: [GrepReplaceRecoveryRecord] = []
        for file in changeSet.files where file.isSelected && file.selectedMatchCount > 0 {
            if isCancelled() { results[file.url] = .cancelled; continue }
            guard (try? Data(contentsOf: file.url)) == file.originalData else {
                results[file.url] = .conflict; continue
            }
            guard let data = encoded(file.previewText, like: file) else {
                results[file.url] = .encodingFailure; continue
            }
            let backup = directory.appendingPathComponent(UUID().uuidString + ".backup")
            do {
                try file.originalData.write(to: backup, options: .atomic)
                records.append(.init(originalPath: file.url.path, backupPath: backup.path, createdAt: Date()))
                try persist(records, in: directory)
                try TextFileSaver.save(data, to: file.url,
                                       preservingPermissionsFrom: file.posixPermissions)
                results[file.url] = .written(matchCount: file.selectedMatchCount, backupURL: backup)
            } catch { results[file.url] = .writeFailure(error.localizedDescription) }
        }
        try? persist(records, in: directory)
        return .init(transactionDirectory: directory, results: results)
    }

    private static func encoded(_ normalized: String, like file: GrepReplaceFileChange) -> Data? {
        let kind: LineEndingKind
        switch file.lineEnding {
        case .crlf: kind = .crlf
        case .cr: kind = .cr
        default: kind = .lf
        }
        let external = LineEndingDetector.applying(kind, to: normalized)
        guard let encoding = file.encoding.foundationEncoding,
              var data = external.data(using: encoding, allowLossyConversion: false) else { return nil }
        if file.hasByteOrderMark, let bom = file.encoding.byteOrderMark,
           !data.starts(with: bom) { data.insert(contentsOf: bom, at: 0) }
        return data
    }

    private static func defaultTransactionDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaruEdit/GrepReplaceTransactions/\(UUID().uuidString)", isDirectory: true)
    }

    private static func persist(_ records: [GrepReplaceRecoveryRecord], in directory: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileWriter.write(try encoder.encode(records),
                                   to: directory.appendingPathComponent("transaction.json"))
    }
}
