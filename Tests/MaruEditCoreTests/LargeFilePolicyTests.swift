import XCTest
@testable import MaruEditCore

final class LargeFilePolicyTests: XCTestCase {
    func testBenchmarkDerivedThresholdBoundaries() {
        let reduced = LargeFilePolicy.reducedFeaturesThreshold
        let confirmation = LargeFilePolicy.confirmationThreshold
        let maximum = LargeFilePolicy.maximumMaterializedSize

        XCTAssertEqual(LargeFilePolicy.recommendation(forByteCount: reduced - 1), .normal)
        XCTAssertEqual(LargeFilePolicy.recommendation(forByteCount: reduced), .reducedFeatures)
        XCTAssertEqual(LargeFilePolicy.recommendation(forByteCount: confirmation), .confirmationRequired)
        XCTAssertEqual(LargeFilePolicy.recommendation(forByteCount: maximum), .confirmationRequired)
        XCTAssertEqual(LargeFilePolicy.recommendation(forByteCount: maximum + 1), .tooLarge)
    }

    func testInspectsMetadataWithoutReadingContents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LargeFilePolicy-\(UUID().uuidString)")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 32 * 1_024 * 1_024)
        try handle.close()

        XCTAssertEqual(try LargeFilePolicy.fileSize(at: url), 32 * 1_024 * 1_024)
    }
}
