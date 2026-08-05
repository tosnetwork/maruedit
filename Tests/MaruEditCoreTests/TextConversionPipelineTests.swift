import XCTest
@testable import MaruEditCore

final class TextConversionPipelineTests: XCTestCase {
    func testOrderedParameterizedPipelineAndSelectiveWidth() throws {
        let registry = TextConversionRegistry()
        let result = try registry.apply([
            .init(moduleID: "width.full.alphanumeric"),
            .init(moduleID: "replace.literal", parameters: ["search": "Ａ", "replacement": "Ｘ"]),
        ], to: "A カナ かな")
        XCTAssertEqual(result, "Ｘ　カナ　かな")
    }

    func testCustomModuleRegistrationIsActuallyExtensible() throws {
        var registry = TextConversionRegistry(includeBuiltIns: false)
        registry.register(.init(id: "test.bracket", title: "Bracket") { text, parameters in
            (parameters["left"] ?? "[") + text + (parameters["right"] ?? "]")
        })
        XCTAssertEqual(try registry.apply([
            .init(moduleID: "test.bracket", parameters: ["left": "<", "right": ">"]),
        ], to: "value"), "<value>")
        XCTAssertThrowsError(try registry.apply([.init(moduleID: "missing")], to: "x"))
    }

    func testPresetStoreRoundTripsNamedStepChains() {
        let suite = "TextConversionPresetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TextConversionPresetStore(defaults: defaults)
        let preset = TextConversionPreset(name: "Custom", steps: [
            .init(moduleID: "replace.regex", parameters: ["pattern": #"\d+"#, "replacement": "#"]),
            .init(moduleID: "case.uppercase"),
        ])
        store.save([preset])
        XCTAssertEqual(store.load(), [preset])
    }
}
