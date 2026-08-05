import Foundation
import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp

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

    func testOfficialMaru957InventoryIsCompleteAndWellFormed() throws {
        let inventory = try String(contentsOf: repositoryRoot
            .appendingPathComponent("docs/maru-9.57-menu-inventory.tsv"))
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
        XCTAssertTrue(rows.contains { $0[0] == "Window" && $0[2] == "Next Maru Editor(with minimize)" })
        XCTAssertTrue(rows.contains { $0[0] == "Help" && $0[2] == "External Help 6(6)" })
    }

    func testAuditedOfficialMappingsResolveToRegisteredOrExplainedTargets() throws {
        let inventory = try tsv(named: "docs/maru-9.57-menu-inventory.tsv", columns: 4)
        let mappings = try tsv(named: "docs/maru-9.57-menu-mapping.tsv", columns: 5)
        let appCommands = try String(contentsOf: repositoryRoot
            .appendingPathComponent("Sources/MaruEditApp/Commands/AppCommands.swift"))
        let registeredIDs = Set(captures(#"CommandID\("([^"]+)"\)"#, in: appCommands))
        let documented = try String(contentsOf: repositoryRoot.appendingPathComponent("docs/commands.md"))

        let inventoryKeys = Set(inventory.map { "\($0[0])\u{1f}\($0[2])" })
        let mappingKeys = mappings.map { "\($0[0])\u{1f}\($0[1])" }
        XCTAssertEqual(mappings.count, inventory.count, "every official row must have one audited mapping")
        XCTAssertEqual(mappingKeys.count, Set(mappingKeys).count)
        XCTAssertTrue(mappingKeys.allSatisfy(inventoryKeys.contains), "mapping contains a non-official row")

        let allowed = Set(["stable", "native", "dynamic", "group", "unsupported"])
        for row in mappings {
            XCTAssertTrue(allowed.contains(row[2]), "unknown disposition for \(row[1])")
            XCTAssertFalse(row[3].isEmpty, "missing target for \(row[1])")
            XCTAssertFalse(row[4].isEmpty, "missing evidence for \(row[1])")
            if row[2] == "stable" {
                XCTAssertTrue(registeredIDs.contains(row[3]), "unregistered target \(row[3])")
                XCTAssertTrue(documented.contains("| `\(row[3])` |"), "undocumented target \(row[3])")
            }
        }

        // Menus listed here have completed row-for-row review. Adding a menu
        // is intentionally impossible until every official row is mapped.
        let completedMenus = Set([
            "File", "Edit", "Conv", "Disp", "Insert", "Search", "Hilight", "Bookmark", "Tool", "Window", "Macro", "Other", "Help",
        ])
        for menu in completedMenus {
            let official = inventory.filter { $0[0] == menu }.map { $0[2] }.sorted()
            let audited = mappings.filter { $0[0] == menu }.map { $0[1] }.sorted()
            XCTAssertEqual(audited, official, "\(menu) mapping is not exhaustive")
        }
    }

    func testPublishedParityMatrixHasNoUnresolvedCompatibleStatus() throws {
        let matrix = try String(contentsOf: repositoryRoot
            .appendingPathComponent("docs/maru-chrome-parity.md"))
        XCTAssertFalse(matrix.contains("| Missing |"))
        XCTAssertFalse(matrix.contains("| Partial |"))
        XCTAssertFalse(matrix.contains("missing "))
        XCTAssertFalse(matrix.contains("1. ❌"))
        XCTAssertFalse(matrix.contains("2. 🟡"))
    }

    func testPlatformMappingsAreExplicitAndNoCapabilityIsUnsupported() throws {
        let mappings = try tsv(named: "docs/maru-9.57-menu-mapping.tsv", columns: 5)
        XCTAssertFalse(mappings.contains { $0[2] == "unsupported" })
        let nativeTargets = Set(mappings.filter { $0[2] == "native" }.map { $0[3] })
        XCTAssertEqual(nativeTargets, Set([
            "NSApplication.terminate", "NSWindow.performClose",
            "NSApplication.orderFrontStandardAboutPanel", "macOS.inputSourceMenu",
            "macOS.mountedRemoteOpen", "macOS.mountedRemoteSave",
            "NSUndoManager.undo", "NSUndoManager.redo", "NSText.cut", "NSText.copy",
            "NSText.paste", "NSText.deleteForward", "NSText.deleteBackward", "NSText.selectAll",
            "NSText.moveUp", "NSText.moveDown", "NSText.moveForward", "NSText.moveBackward",
            "NSText.moveToBeginningOfParagraph", "NSText.moveToEndOfParagraph",
            "NSText.pageUp", "NSText.pageDown",
        ]))
        XCTAssertTrue(mappings.filter { ["native", "dynamic", "group"].contains($0[2]) }
            .allSatisfy { !$0[4].isEmpty && !$0[4].contains("not implemented") })
    }

    @MainActor
    func testEveryStableOfficialMappingIsPlacedInItsCorrespondingMenu() throws {
        _ = NSApplication.shared
        let app = AppDelegate(); app.buildMenu()
        let mappings = try tsv(named: "docs/maru-9.57-menu-mapping.tsv", columns: 5)
        let displayedMenu = [
            "Conv": "Convert", "Disp": "View", "Hilight": "Highlight", "Tool": "Tools",
        ]
        var missing: [String] = []
        for row in mappings where row[2] == "stable" {
            let title = displayedMenu[row[0]] ?? row[0]
            guard let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: { $0.title == title }) else {
                missing.append("\(row[0])/\(row[1]) -> missing menu \(title)"); continue
            }
            let ids = commandIDs(in: menu)
            if !ids.contains(row[3]) { missing.append("\(row[0])/\(row[1]) -> \(row[3])") }
        }
        XCTAssertEqual(missing, [], "stable mappings absent from official menu:\n" + missing.joined(separator: "\n"))
    }

    private func captures(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    private func tsv(named path: String, columns: Int) throws -> [[String]] {
        let text = try String(contentsOf: repositoryRoot.appendingPathComponent(path))
        return try text.split(separator: "\n").dropFirst().map { line in
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard values.count == columns else {
                throw NSError(domain: "ChromeParityAudit", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Malformed TSV row: \(line)"])
            }
            return values
        }
    }

    @MainActor
    private func commandIDs(in menu: NSMenu) -> Set<String> {
        Set(menu.items.flatMap { item -> [String] in
            let own = (item.representedObject as? CommandID).map { [$0.rawValue] } ?? []
            return own + (item.submenu.map { Array(commandIDs(in: $0)) } ?? [])
        })
    }
}
