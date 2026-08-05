import XCTest
@testable import MaruEditCore

final class FileTypeOutlineRuleTests: XCTestCase {
    func testOutlineRulesRoundTripInProfile() throws {
        let rule = OutlineRule(id: "section", pattern: #"^== (.+) ==$"#)
        let profile = FileTypeProfile(
            id: "custom", name: "Custom", settings: FileTypeSettings(outlineRules: [rule]))
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(FileTypeProfile.self, from: data), profile)
    }

    func testRuleLengthBoundaryIsDeterministic() {
        let accepted = OutlineRule(pattern: "(" + String(repeating: "a", count: 1_022) + ")")
        let rejected = OutlineRule(pattern: "(" + String(repeating: "a", count: 1_023) + ")")
        XCTAssertNil(accepted.validationError())
        XCTAssertEqual(rejected.validationError(), .patternTooLong)
    }

    func testVersionOneSettingsWithoutOutlineRulesStillDecode() throws {
        let json = #"{"tabWidth":4,"indentWidth":4,"indentStyle":"spaces","wrapLines":false,"syntax":"plainText"}"#
        let settings = try JSONDecoder().decode(FileTypeSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.outlineRules)
    }

    func testVersionOneProfileLoadsAndMigratesToVersionTwo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTypeOutlineRuleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":1,"id":"legacy","name":"Legacy","filenamePatterns":[],"extensions":["old"],"priority":0,"settings":{"tabWidth":4,"indentWidth":4,"indentStyle":"spaces","wrapLines":false,"syntax":"plainText"}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("legacy.json"))

        let loaded = try XCTUnwrap(FileTypeProfileStore(directory: directory).loadUserProfiles().first)
        XCTAssertEqual(loaded.schemaVersion, FileTypeProfile.currentSchemaVersion)
        XCTAssertNil(loaded.settings.outlineRules)
    }
}
