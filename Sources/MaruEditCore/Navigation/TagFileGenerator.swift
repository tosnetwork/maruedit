import Foundation

/// Generates a deterministic, portable `tags` file without requiring an
/// external ctags installation. The deliberately conservative recognizers
/// cover the declaration forms most useful to editor navigation.
public struct TagFileGenerator: Sendable {
    public struct Summary: Equatable, Sendable {
        public let fileCount: Int
        public let tagCount: Int
        public let outputURL: URL
    }

    public enum GenerationError: Error, Equatable {
        case notDirectory
        case tooManyFiles(limit: Int)
    }

    public let maximumFiles: Int
    public let maximumFileBytes: Int

    public init(maximumFiles: Int = 20_000, maximumFileBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumFiles = maximumFiles
        self.maximumFileBytes = maximumFileBytes
    }

    public func generate(in root: URL) throws -> Summary {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GenerationError.notDirectory
        }
        let files = try sourceFiles(in: root)
        var entries: [(name: String, path: String, line: Int, kind: String)] = []
        for file in files {
            let canonicalFile = file.standardizedFileURL.resolvingSymlinksInPath()
            guard let values = try? canonicalFile.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= maximumFileBytes,
                  let text = try? String(contentsOf: canonicalFile, encoding: .utf8) else { continue }
            let rootComponents = root.pathComponents
            let fileComponents = canonicalFile.pathComponents
            guard fileComponents.starts(with: rootComponents) else { continue }
            let relativePath = fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
            entries.append(contentsOf: tags(in: text, fileExtension: canonicalFile.pathExtension.lowercased()).map {
                ($0.name, relativePath, $0.line, $0.kind)
            })
        }
        entries.sort {
            if $0.name != $1.name { return $0.name < $1.name }
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.line < $1.line
        }
        var output = "!_TAG_FILE_FORMAT\t2\t/extended format; --format=1 will not append ;\" to lines/\n"
        output += "!_TAG_FILE_SORTED\t1\t/0=unsorted, 1=sorted, 2=foldcase/\n"
        for entry in entries {
            output += "\(entry.name)\t\(entry.path)\t\(entry.line);\"\t\(entry.kind)\n"
        }
        let outputURL = root.appendingPathComponent("tags")
        try AtomicFileWriter.write(Data(output.utf8), to: outputURL)
        return Summary(fileCount: files.count, tagCount: entries.count, outputURL: outputURL)
    }

    private func sourceFiles(in root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let extensions = Set(["swift", "m", "mm", "h", "c", "cc", "cpp", "cxx", "java", "kt", "kts", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "php"])
        let excludedDirectories = Set([".git", ".build", "build", "DerivedData", "node_modules", "vendor"])
        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants(); continue
            }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  extensions.contains(url.pathExtension.lowercased()) else { continue }
            guard result.count < maximumFiles else { throw GenerationError.tooManyFiles(limit: maximumFiles) }
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    private func tags(in text: String, fileExtension: String) -> [(name: String, line: Int, kind: String)] {
        let patterns: [(String, String)]
        switch fileExtension {
        case "py": patterns = [(#"^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)"#, "f"), (#"^\s*class\s+([A-Za-z_]\w*)"#, "c")]
        case "rb": patterns = [(#"^\s*def\s+(?:self\.)?([A-Za-z_]\w*[!?=]?)"#, "f"), (#"^\s*(?:class|module)\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)"#, "c")]
        case "go": patterns = [(#"^\s*func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)"#, "f"), (#"^\s*type\s+([A-Za-z_]\w*)\s+(?:struct|interface)"#, "t")]
        case "rs": patterns = [(#"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_]\w*)"#, "f"), (#"^\s*(?:pub\s+)?(?:struct|enum|trait|type)\s+([A-Za-z_]\w*)"#, "t")]
        default: patterns = [
            (#"^\s*(?:(?:public|private|internal|open|static|final|export|abstract)\s+)*(?:class|struct|enum|protocol|interface|typealias|actor)\s+([A-Za-z_$]\w*)"#, "t"),
            (#"^\s*(?:(?:public|private|internal|open|static|class|final|override|mutating|async|export)\s+)*(?:func|function)\s+([A-Za-z_$]\w*)"#, "f"),
        ]
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [(String, Int, String)] = []
        for (index, line) in lines.enumerated() {
            let value = String(line)
            for (pattern, kind) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                      let range = Range(match.range(at: 1), in: value) else { continue }
                result.append((String(value[range]), index + 1, kind)); break
            }
        }
        return result
    }
}
