import Foundation
import XCTest

final class ChromeParityAuditTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testEveryStableCommandIsDocumentedExactlyOnce() throws {
        let source = try String(contentsOf: repositoryRoot
            .appendingPathComponent("Sources/MaruEditApp/Commands/AppCommands.swift"))
        let documentation = try String(contentsOf: repositoryRoot.appendingPathComponent("docs/commands.md"))
        let sourceIDs = captures(#"CommandID\("([^"]+)"\)"#, in: source)
        let documentedIDs = documentation.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("| `"), let end = line.dropFirst(3).firstIndex(of: "`") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 3)..<end])
        }
        XCTAssertEqual(Set(documentedIDs), Set(sourceIDs))
        XCTAssertEqual(documentedIDs.count, Set(documentedIDs).count, "command documentation has duplicates")
    }

    func testPublishedParityMatrixHasNoUnresolvedCompatibleStatus() throws {
        let matrix = try String(contentsOf: repositoryRoot
            .appendingPathComponent("docs/hidemaru-chrome-parity.md"))
        XCTAssertFalse(matrix.contains("| Missing |"))
        XCTAssertFalse(matrix.contains("| Partial |"))
        XCTAssertFalse(matrix.contains("missing "))
    }

    private func captures(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }
}
