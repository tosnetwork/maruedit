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

    func testOfficialHidemaru957InventoryIsCompleteAndWellFormed() throws {
        let inventory = try String(contentsOf: repositoryRoot
            .appendingPathComponent("docs/hidemaru-9.57-menu-inventory.tsv"))
        let lines = inventory.split(separator: "\n")
        XCTAssertEqual(lines.first, "menu\tofficial_label_ja\tofficial_label_en\tplacement")

        let rows = try lines.dropFirst().map { line -> [String] in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 4 else {
                throw NSError(domain: "ChromeParityAudit", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Malformed inventory row: \(line)"])
            }
            return columns
        }
        let expectedCounts = [
            "File": 42, "Edit": 51, "Conv": 14, "Disp": 25, "Insert": 11,
            "Search": 71, "Hilight": 4, "Bookmark": 2, "Tool": 28,
            "Window": 43, "Macro": 9, "Other": 26, "Help": 10,
        ]
        XCTAssertEqual(Dictionary(grouping: rows, by: { $0[0] }).mapValues(\.count), expectedCounts)
        XCTAssertEqual(rows.count, 336)
        XCTAssertTrue(rows.allSatisfy { !$0[1].isEmpty })
        XCTAssertTrue(rows.allSatisfy { ["menu", "binding"].contains($0[3]) })

        let uniqueKeys = Set(rows.map { "\($0[0])\u{1f}\($0[1])" })
        XCTAssertEqual(uniqueKeys.count, rows.count, "official inventory contains duplicate menu/label rows")
        XCTAssertTrue(rows.contains { $0[0] == "Search" && $0[2] == "grep and replace(@)..." })
        XCTAssertTrue(rows.contains { $0[0] == "Window" && $0[2] == "Next Maruo Editor(with minimize)" })
        XCTAssertTrue(rows.contains { $0[0] == "Help" && $0[2] == "External Help 6(6)" })
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
