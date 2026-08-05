import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class InMemoryGrepWorkflowTests: XCTestCase {
    func testUnsavedCurrentDocumentGrepAndOutputDocument() async throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(
            content: "TODO first\ndone\nTODO second", selections: [])
        controller.setSearchQueryForTesting(SearchQuery(pattern: "TODO"))
        controller.grepCurrentDocument()
        try await waitUntil { controller.outputMatchCountForTesting == 2 }

        controller.outputGrepResultsAsDocument()
        XCTAssertTrue(controller.currentDocumentTextForTesting.contains("Untitled:1:1: TODO first"))
        XCTAssertTrue(controller.currentDocumentTextForTesting.contains("2 matches"))
    }

    func testOpenDocumentGrepCanBeRefined() async throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "TODO parser", selections: [])
        controller.newDocument()
        controller.prepareUITestDocument(content: "TODO layout", selections: [])
        controller.setSearchQueryForTesting(SearchQuery(pattern: "TODO"))
        controller.grepOpenDocuments()
        try await waitUntil { controller.outputMatchCountForTesting == 2 }

        controller.setSearchQueryForTesting(SearchQuery(pattern: "parser"))
        controller.refineGrepResults()
        try await waitUntil { controller.outputMatchCountForTesting == 1 }
        XCTAssertTrue(controller.outputTextForTesting.contains("TODO parser"))
    }

    private func waitUntil(
        timeout: TimeInterval = 2, condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}
