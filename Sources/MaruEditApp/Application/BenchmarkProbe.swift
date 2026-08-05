import Foundation

/// Opt-in readiness events for the repository's external performance scripts.
/// Normal launches do no file I/O: the probe is enabled only by an explicit
/// command-line argument supplied by those scripts.
enum BenchmarkProbe {
    private static let eventFile: URL? = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--maruedit-benchmark-events"),
              arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1])
    }()
    static var isEnabled: Bool { eventFile != nil }
    private static var consumedRequestLines = 0

    static func record(_ event: String, detail: String = "") {
        guard let eventFile else { return }
        let safeDetail = detail.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let timestamp = Date().timeIntervalSince1970
        let line = "\(event)\t\(String(format: "%.9f", timestamp))\t\(safeDetail)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: eventFile.path) {
            FileManager.default.createFile(atPath: eventFile.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: eventFile) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // A benchmark probe must never affect editor behavior.
        }
    }

    static func consumeOpenRequests() -> [URL] {
        guard let eventFile,
              let text = try? String(contentsOf: eventFile, encoding: .utf8) else { return [] }
        let requests = text.split(separator: "\n").compactMap { line -> URL? in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0] == "open-request" else { return nil }
            return URL(fileURLWithPath: String(fields[1]))
        }
        guard requests.count > consumedRequestLines else { return [] }
        defer { consumedRequestLines = requests.count }
        return Array(requests.dropFirst(consumedRequestLines))
    }
}
