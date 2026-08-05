import Foundation
@testable import MaruEditCore
import XCTest

final class StreamingFileBufferTests: XCTestCase {
    func testBoundedReadEditsAndStreamingWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("large.bin")
        let destination = directory.appendingPathComponent("edited.bin")
        let data = Data((0..<2_200_000).map { UInt8($0 % 251) })
        try data.write(to: source)
        let buffer = try StreamingFileBuffer(url: source)
        XCTAssertEqual(try buffer.read(offset: 1_048_570, length: 32), data.subdata(in: 1_048_570..<1_048_602))
        try buffer.stage(StreamingEdit(range: 3..<8, replacement: Data([9, 8])))
        try buffer.stage(StreamingEdit(range: 2_000_000..<2_000_001, replacement: Data([7, 6, 5])))
        XCTAssertThrowsError(try buffer.stage(StreamingEdit(range: 4..<6, replacement: Data())))
        try buffer.write(to: destination, chunkSize: 64 * 1024)
        var expected = data
        expected.replaceSubrange(2_000_000..<2_000_001, with: [7, 6, 5])
        expected.replaceSubrange(3..<8, with: [9, 8])
        XCTAssertEqual(try Data(contentsOf: destination), expected)
    }

    func testBinaryRowsIncludeOffsetsHexAndPrintableASCII() {
        let rows = BinaryViewModel.rows(data: Data([0x41, 0, 0x7E, 0xFF]), startingAt: 32, bytesPerRow: 2)
        XCTAssertEqual(rows.map(\.offset), [32, 34])
        XCTAssertEqual(rows.map(\.hexadecimal), ["41 00", "7E FF"])
        XCTAssertEqual(rows.map(\.ascii), ["A.", "~."])
    }
}
