import AppKit
import Darwin
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class MemoryAuditTests: XCTestCase {
    func testTenOpenTenMegabyteDocumentsRemainEditable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditMemoryAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = Data(repeating: Character("a").asciiValue!, count: 10 * 1_024 * 1_024)
        var urls: [URL] = []
        for number in 0..<10 {
            let url = directory.appendingPathComponent("large-\(number).txt")
            try fixture.write(to: url, options: .atomic)
            urls.append(url)
        }

        let baseline = residentBytes()
        let documents = try urls.map { try Document.open(url: $0) }
        for document in documents {
            document.cachedTextStorage = NSTextStorage(string: document.content)
            document.cachedTextStorage?.append(NSAttributedString(string: "x"))
        }
        let resident = residentBytes()

        XCTAssertEqual(documents.count, 10)
        let expectedLength = 10 * 1_024 * 1_024 + 1
        XCTAssertTrue(documents.allSatisfy { $0.cachedTextStorage?.length == expectedLength })
        print("M7_MEMORY_10X10MB baseline=\(baseline) resident=\(resident) delta=\(resident - baseline)")
    }

    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
