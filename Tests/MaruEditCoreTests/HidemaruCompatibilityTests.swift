import XCTest
@testable import MaruEditCore

final class HidemaruCompatibilityTests: XCTestCase {
    func testEverySupportedPublicCommandBehavior() throws {
        try assertRun("selectall; toupper;", initial: "Ab c", selection: NSRange(location: 0, length: 0),
                      text: "AB C", selectionAfter: NSRange(location: 0, length: 4))
        try assertRun("selectall; tolower;", initial: "Ab C", selection: NSRange(location: 0, length: 0),
                      text: "ab c", selectionAfter: NSRange(location: 0, length: 4))
        try assertRun("gofiletop; insert \"<\"; gofileend; insert \"\\n>\";",
                      initial: "body", selection: NSRange(location: 2, length: 0),
                      text: "<body\n>", selectionAfter: NSRange(location: 7, length: 0))
        try assertRun("selectall; delete;", initial: "remove", selection: NSRange(location: 0, length: 0),
                      text: "", selectionAfter: NSRange(location: 0, length: 0))
        try assertRunMany("toupper;", initial: "ß x ab",
                          selections: [NSRange(location: 0, length: 1), NSRange(location: 4, length: 2)],
                          text: "SS x AB",
                          selectionsAfter: [NSRange(location: 0, length: 2), NSRange(location: 5, length: 2)])

        var message = ""
        let translated = try HidemaruCompatibility.translate("message \"hello\";")
        let text = UnsafeMutablePointer<String>.allocate(capacity: 1); text.initialize(to: "")
        let selections = UnsafeMutablePointer<[NSRange]>.allocate(capacity: 1)
        selections.initialize(to: [NSRange(location: 0, length: 0)])
        defer { text.deinitialize(count: 1); text.deallocate(); selections.deinitialize(count: 1); selections.deallocate() }
        _ = MacroEngine().execute(translated, host: host(
            text: text, selections: selections, message: { message = $0 }, begin: {}, end: {}))
        XCTAssertEqual(message, "hello")
    }

    func testUnsupportedSyntaxFailsExplicitly() {
        XCTAssertThrowsError(try HidemaruCompatibility.translate("run \"tool\";")) {
            XCTAssertEqual($0 as? HidemaruCompatibilityError, .unsafeCommand(line: 1, command: "run"))
        }
        XCTAssertThrowsError(try HidemaruCompatibility.translate("registry;")) {
            XCTAssertEqual($0 as? HidemaruCompatibilityError, .windowsOnlyCommand(line: 1, command: "registry"))
        }
        XCTAssertThrowsError(try HidemaruCompatibility.translate("#x = globalThis.secret;")) {
            guard case .invalidExpression = $0 as? HidemaruCompatibilityError else { return XCTFail("wrong diagnostic: \($0)") }
        }
    }

    func testVariablesExpressionsBranchesLoopsFunctionsAndSubroutines() throws {
        try assertRun(
            #"#i=0; $word=""; while(#i<3){$word=$word+"x"; #i=#i+1;} if($word=="xxx"){gofileend; insert "ok";} function append {gofileend; insert "!";} call append;"#,
            initial: "body", selection: NSRange(location: 0, length: 0),
            text: "bodyok!", selectionAfter: NSRange(location: 7, length: 0))
    }

    func testPortableStatementsRouteThroughStableCommands() throws {
        var commands: [String] = []
        let text = UnsafeMutablePointer<String>.allocate(capacity: 1); text.initialize(to: "")
        let selections = UnsafeMutablePointer<[NSRange]>.allocate(capacity: 1); selections.initialize(to: [])
        defer { text.deinitialize(count: 1); text.deallocate(); selections.deinitialize(count: 1); selections.deallocate() }
        var value = host(text: text, selections: selections, message: { _ in }, begin: {}, end: {})
        value.runCommand = { commands.append($0); return true }
        _ = MacroEngine().execute(try HidemaruCompatibility.translate(
            "findnext; findprevious; showoutline; nextwindow;"), host: value)
        XCTAssertEqual(commands, ["search.findNext", "search.findPrevious", "view.toggleSidebar", "window.next"])
    }

    func testRedistributableCorpusGeneratesPassingExecutableReport() {
        XCTAssertEqual(HidemaruCompatibilityCorpus.license, "CC0-1.0")
        let report = HidemaruCompatibilityCorpus.markdownReport()
        XCTAssertFalse(report.contains("FAIL"))
        for item in HidemaruCompatibilityCorpus.cases { XCTAssertTrue(report.contains(item.id)) }
    }

    func testFeatureFlagAndCatalogKeepNativeMacrosUnchanged() throws {
        XCTAssertFalse(HidemaruCompatibility.isEnabled(environment: [:], defaults: isolatedDefaults()))
        XCTAssertTrue(HidemaruCompatibility.isEnabled(
            environment: [HidemaruCompatibility.featureFlag: "1"], defaults: isolatedDefaults()))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let native = "maru.document.setText('native');"
        try native.write(to: directory.appendingPathComponent("native.js"), atomically: true, encoding: .utf8)
        try "selectall; toupper;".write(to: directory.appendingPathComponent("legacy.mac"), atomically: true, encoding: .utf8)
        let disabled = MacroCatalogLoader.load(from: directory)
        XCTAssertEqual(disabled.macros.count, 1); XCTAssertEqual(disabled.macros[0].source, native)
        let enabled = MacroCatalogLoader.load(from: directory, enableHidemaruCompatibility: true)
        XCTAssertEqual(enabled.macros.count, 2)
        XCTAssertTrue(enabled.macros.contains { $0.id.rawValue.hasPrefix("macro.compat.") && $0.metadata.name.contains("Experimental") })
        XCTAssertEqual(enabled.macros.first { $0.id.rawValue.hasPrefix("macro.user.") }?.source, native)
    }

    private func assertRun(_ source: String, initial: String, selection: NSRange,
                           text expectedText: String, selectionAfter expectedSelection: NSRange) throws {
        try assertRunMany(source, initial: initial, selections: [selection],
                          text: expectedText, selectionsAfter: [expectedSelection])
    }
    private func assertRunMany(_ source: String, initial: String, selections initialSelections: [NSRange],
                               text expectedText: String, selectionsAfter expectedSelections: [NSRange]) throws {
        let text = UnsafeMutablePointer<String>.allocate(capacity: 1); text.initialize(to: initial)
        let selections = UnsafeMutablePointer<[NSRange]>.allocate(capacity: 1); selections.initialize(to: initialSelections)
        defer { text.deinitialize(count: 1); text.deallocate(); selections.deinitialize(count: 1); selections.deallocate() }
        var begin = 0, end = 0
        let result = MacroEngine().execute(try HidemaruCompatibility.translate(source), host: host(
            text: text, selections: selections, message: { _ in }, begin: { begin += 1 }, end: { end += 1 }))
        if case .failure(let error) = result { XCTFail("\(error)") }
        XCTAssertEqual(text.pointee, expectedText); XCTAssertEqual(selections.pointee, expectedSelections)
        XCTAssertEqual(begin, 1); XCTAssertEqual(end, 1)
    }

    private func host(text: UnsafeMutablePointer<String>, selections: UnsafeMutablePointer<[NSRange]>,
                      message: @escaping (String) -> Void, begin: @escaping () -> Void,
                      end: @escaping () -> Void) -> MacroHost {
        MacroHost(allowedPermissions: [.currentDocument], runCommand: { _ in false },
                  documentText: { text.pointee }, setDocumentText: { text.pointee = $0 },
                  selectionsJSON: { Self.json(selections.pointee) }, setSelectionsJSON: {
                    guard let data = $0.data(using: .utf8),
                          let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Int]] else { return false }
                    selections.pointee = values.map { NSRange(location: $0["location"]!, length: $0["length"]!) }; return true
                  }, replaceSelections: { _ in }, readClipboard: { "" }, writeClipboard: { _ in },
                  showMessage: message, prompt: { _, _ in nil }, beginUndoGroup: { _ in begin() }, endUndoGroup: end)
    }
    private static func json(_ ranges: [NSRange]) -> String {
        let values = ranges.map { ["location": $0.location, "length": $0.length] }
        return String(data: try! JSONSerialization.data(withJSONObject: values), encoding: .utf8)!
    }
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "HidemaruCompatibilityTests.\(UUID().uuidString)")!
    }
}
