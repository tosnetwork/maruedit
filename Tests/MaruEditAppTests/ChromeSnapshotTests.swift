import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp

@MainActor
final class ChromeSnapshotTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testClassicChromeScreenshotBaselinesCoverRequiredMatrix() throws {
        let outputDirectory = repositoryRoot.appendingPathComponent("docs/screenshots/chrome", isDirectory: true)
        if ProcessInfo.processInfo.environment["UPDATE_CHROME_SNAPSHOTS"] == "1" {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        for customized in [false, true] {
            for dark in [false, true] {
                for wide in [false, true] {
                    let name = "\(customized ? "custom" : "default")-\(dark ? "dark" : "light")-\(wide ? "wide" : "narrow").png"
                    let data = try render(customized: customized, dark: dark, wide: wide)
                    let baselineURL = outputDirectory.appendingPathComponent(name)
                    if ProcessInfo.processInfo.environment["UPDATE_CHROME_SNAPSHOTS"] == "1" {
                        try data.write(to: baselineURL, options: .atomic)
                    }
                    let baseline = try Data(contentsOf: baselineURL)
                    let actualImage = try XCTUnwrap(NSBitmapImageRep(data: data))
                    let baselineImage = try XCTUnwrap(NSBitmapImageRep(data: baseline))
                    XCTAssertEqual(actualImage.pixelsWide, baselineImage.pixelsWide, name)
                    XCTAssertEqual(actualImage.pixelsHigh, baselineImage.pixelsHigh, name)
                    XCTAssertGreaterThan(baseline.count, 20_000, "baseline must contain rendered chrome: \(name)")
                    XCTAssertTrue(hasVisualVariation(actualImage), "snapshot is blank: \(name)")
                    XCTAssertLessThan(sampledDifference(actualImage, baselineImage), 0.01,
                                      "classic chrome drifted from baseline: \(name)")
                }
            }
        }
    }

    private func render(customized: Bool, dark: Bool, wide: Bool) throws -> Data {
        let controller = MainWindowController()
        controller.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.window?.setContentSize(wide
            ? NSSize(width: 1_200, height: 760) : NSSize(width: 760, height: 520))
        controller.setClassicToolbarLayoutForTesting([
            "file.new", "file.open", "file.save", "file.print", "-",
            "responder.undo", "responder.redo", "-", "responder.cut", "responder.copy", "responder.paste", "-",
            "search.find", "search.replace", "search.findNext", "search.findPrevious", "-",
            "bookmark.toggle", "macro.run", "view.toggleSidebar", "app.settings",
        ])
        controller.setClassicFunctionKeyCommandsForTesting([
            .appHelp, .fileSave, .searchFind, .searchFindNext, .searchGrep, .appMacroMenu,
            .navigateToggleBookmark, .searchGoToLine, .searchReplace, .viewToggleSidebar,
            .viewToggleWrap, .appSettings,
        ])
        controller.setClassicToolbarDisplayModeForTesting(.iconOnly)
        controller.setClassicToolbarIconSizeForTesting(.medium)
        controller.setClassicToolbarSearchVisibleForTesting(true)
        controller.setFunctionKeyStripMergedForTesting(false)
        controller.prepareUITestDocument(
            content: "// Maru Classic\nfunc greet(name: String) {\n    print(\"Hello, \\(name)\")\n}\n",
            selections: [NSRange(location: 16, length: 0)])
        controller.newDocument()
        controller.prepareUITestDocument(
            content: "Search, edit marks, bookmarks, and Japanese text: 秀丸エディタ\n",
            selections: [NSRange(location: 8, length: 4)])
        if customized {
            controller.setClassicToolbarDisplayModeForTesting(.iconAndText)
            controller.setClassicToolbarIconSizeForTesting(.large)
            controller.setClassicToolbarSearchVisibleForTesting(true)
            controller.setFunctionKeyStripMergedForTesting(true)
        }
        guard let view = controller.window?.contentView else { throw CocoaError(.coderInvalidValue) }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.coderInvalidValue)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    private func hasVisualVariation(_ image: NSBitmapImageRep) -> Bool {
        guard image.pixelsWide > 1, image.pixelsHigh > 1 else { return false }
        var minimum = CGFloat(1), maximum = CGFloat(0)
        let stepX = max(1, image.pixelsWide / 80)
        let stepY = max(1, image.pixelsHigh / 60)
        for y in stride(from: 0, to: image.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: image.pixelsWide, by: stepX) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = color.redComponent * 0.2126
                    + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                minimum = min(minimum, luminance); maximum = max(maximum, luminance)
            }
        }
        return maximum - minimum > 0.1
    }

    private func sampledDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> CGFloat {
        let stepX = max(1, lhs.pixelsWide / 80)
        let stepY = max(1, lhs.pixelsHigh / 60)
        var difference = CGFloat.zero
        var samples = 0
        for y in stride(from: 0, to: lhs.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: lhs.pixelsWide, by: stepX) {
                guard let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                difference += abs(left.redComponent - right.redComponent)
                    + abs(left.greenComponent - right.greenComponent)
                    + abs(left.blueComponent - right.blueComponent)
                samples += 3
            }
        }
        return samples == 0 ? 1 : difference / CGFloat(samples)
    }
}
