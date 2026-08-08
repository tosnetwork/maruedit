import XCTest
import MaruEditCore
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class DocumentTests: XCTestCase {

    func testNewDocumentDefaults() async {
        let doc = Document()
        XCTAssertNil(doc.fileURL)
        XCTAssertEqual(doc.content, "")
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.displayName, "Untitled")
        XCTAssertEqual(doc.language, .plainText)
        XCTAssertEqual(doc.encoding, .utf8)
        XCTAssertFalse(doc.hasByteOrderMark)
        XCTAssertEqual(doc.lineEnding, .lf)
    }

    func testLocalizedDisplayNameTracksLanguageForUnnamedDocumentsOnly() async {
        let priorLanguage = AppLocalization.language
        defer { AppLocalization.language = priorLanguage }

        let untitled = Document()
        XCTAssertTrue(untitled.isUntitled)
        AppLocalization.language = .english
        XCTAssertEqual(untitled.localizedDisplayName, "Untitled")
        AppLocalization.language = .japanese
        XCTAssertEqual(untitled.localizedDisplayName, "無題")
        // Canonical displayName never changes with language — it's the
        // language-independent identity used by tests and internal checks.
        XCTAssertEqual(untitled.displayName, "Untitled")

        let named = Document(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"))
        XCTAssertFalse(named.isUntitled)
        XCTAssertEqual(named.localizedDisplayName, "notes.txt")
    }

    func testMarkModifiedAndSaved() async {
        let doc = Document(content: "hello")
        XCTAssertFalse(doc.isModified)

        doc.content = "hello world"
        doc.markModified()
        XCTAssertTrue(doc.isModified)

        doc.markSaved()
        XCTAssertFalse(doc.isModified)
    }

    func testFormatChangesRemainModifiedUntilSaved() async {
        let doc = Document(content: "unchanged")
        doc.markFormatModified()
        XCTAssertTrue(doc.isModified)
        doc.markModified()
        XCTAssertTrue(doc.isModified, "matching text must not clear an unsaved format change")
        doc.markSaved()
        XCTAssertFalse(doc.isModified)
    }

    func testSaveAndReopenRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = Document(content: "let x = 1\n")
        try original.save(to: url)
        XCTAssertFalse(original.isModified)

        let reopened = try Document.open(url: url)
        XCTAssertEqual(reopened.content, "let x = 1\n")
        XCTAssertEqual(reopened.language, .swift)
        XCTAssertEqual(reopened.displayName, url.lastPathComponent)
    }

    func testOpenPartialCreatesModifiedUntitledDocumentWithoutSourceIdentity() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditPartial-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("A日B".utf8).write(to: url)

        let document = try Document.openPartial(url: url, offset: 1, length: 3, forcing: .utf8)
        XCTAssertEqual(document.content, "日")
        XCTAssertEqual(document.encoding, .utf8)
        XCTAssertEqual(document.displayName, "\(url.lastPathComponent) [Partial]")
        XCTAssertNil(document.fileURL, "a partial document must never overwrite its source")
        XCTAssertTrue(document.isModified, "a partial document requires an explicit save destination")
    }

    func testAppendSavePreservesDocumentIdentityAndUsesItsEncodingAndLineEndings() async throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditAppend-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: target) }
        try Data("prefix\r\n".utf8).write(to: target)
        let document = Document(content: "日本語\n")
        document.encoding = .utf8
        document.lineEnding = .crlf
        document.markFormatModified()
        try document.appendContent(to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "prefix\r\n日本語\r\n")
        XCTAssertNil(document.fileURL)
        XCTAssertTrue(document.isModified)
    }

    func testFileContentInsertionLoaderDetectsEncodingAndNormalizesLineEndings() async throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditInsert-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: target) }
        try Data("one\r\ntwo\r".utf8).write(to: target)
        XCTAssertEqual(try Document.normalizedText(contentsOf: target), "one\ntwo\n")
    }

    func testRenameMovesFileAndRefreshesDocumentIdentityAndLanguage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("before.txt")
        let destination = directory.appendingPathComponent("after.swift")
        try Data("let value = 1".utf8).write(to: source)
        let document = try Document.open(url: source)
        try document.rename(to: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(document.fileURL, destination)
        XCTAssertEqual(document.language, .swift)
        XCTAssertEqual(document.fileIdentity, FileIdentity.of(destination))
        XCTAssertEqual(document.content, "let value = 1")
    }

    func testRenameRefusesToOverwriteAnExistingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.txt")
        let destination = directory.appendingPathComponent("existing.txt")
        try Data("source".utf8).write(to: source); try Data("existing".utf8).write(to: destination)
        let document = try Document.open(url: source)
        XCTAssertThrowsError(try document.rename(to: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
        XCTAssertEqual(document.fileURL, source)
    }

    func testOpenAppliesFileTypeProfileEncodingAndSyntax() async throws {
        let sample = "日本語"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).legacy")
        try XCTUnwrap(sample.data(using: .shiftJIS)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = FileTypeProfile(
            id: "user.legacy", name: "Legacy Script", extensions: ["legacy"],
            settings: FileTypeSettings(
                tabWidth: 8, indentWidth: 2, indentStyle: .spaces, wrapLines: true,
                encoding: .windows31J, syntax: .shell, lineComment: ";;"))
        let resolver = FileTypeProfileResolver(profiles: [
            SourcedFileTypeProfile(profile, source: .user),
        ])

        let document = try Document.open(url: url, resolver: resolver)

        XCTAssertEqual(document.content, sample)
        XCTAssertEqual(document.encoding, .windows31J)
        XCTAssertEqual(document.language, .shell)
        XCTAssertEqual(document.fileTypeProfile, profile)
    }

    func testProfileLoadPolicyCandidateOrderAndReadOnly() async throws {
        let sample = "日本語"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditPolicy-\(UUID().uuidString).legacy")
        try XCTUnwrap(sample.data(using: .shiftJIS)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = FileTypeProfile(
            id: "legacy", name: "Legacy", extensions: ["legacy"],
            settings: FileTypeSettings(loadPolicy: ProfileLoadPolicy(
                opensReadOnly: true, encodingCandidateOrder: [.shiftJISClassic])))
        let resolver = FileTypeProfileResolver(profiles: [.init(profile, source: .user)])
        let document = try Document.open(url: url, resolver: resolver)
        XCTAssertEqual(document.content, sample)
        XCTAssertEqual(document.encoding, .shiftJISClassic)
        XCTAssertTrue(document.isReadOnly)
    }

    func testProfileTemplateAndSaveBackupPoliciesAreApplied() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditPolicy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let template = directory.appendingPathComponent("template.txt")
        try "starter".write(to: template, atomically: true, encoding: .utf8)
        let profile = FileTypeProfile(
            id: "text", name: "Text", extensions: ["txt"], settings: FileTypeSettings(
                templatePath: template.path,
                savePolicy: ProfileSavePolicy(
                    backup: BackupSettings(enabled: true, suffix: ".bak"),
                    ensuresFinalNewline: true, trimsTrailingWhitespace: true)))
        let templated = try Document.fromTemplate(profile: profile)
        XCTAssertEqual(templated.content, "starter")
        XCTAssertTrue(templated.isModified)

        let target = directory.appendingPathComponent("target.txt")
        try "old".write(to: target, atomically: true, encoding: .utf8)
        let resolver = FileTypeProfileResolver(profiles: [.init(profile, source: .user)])
        let document = try Document.open(url: target, resolver: resolver)
        document.content = "new  "
        document.markModified()
        try document.save()
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "new\n")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil).contains {
                $0.lastPathComponent.hasPrefix("target.txt.") && $0.lastPathComponent.hasSuffix(".bak")
            })
    }

    // MARK: - Encoding preservation (M2-02)
    //
    // These are the tests that matter most: opening a non-UTF-8 file and
    // saving it must never silently re-encode it to UTF-8. Each test
    // reads the RAW BYTES back off disk after save() — not just the
    // decoded String — to prove the file itself, not just in-memory
    // state, stayed in its original encoding.

    private let japaneseSample = "日本語のテキストファイルです。漢字とひらがなとカタカナ。"

    func testOpeningLegacyEncodedFilePreservesEncodingOnSave() async throws {
        guard let originalBytes = japaneseSample.data(using: .japaneseEUC) else {
            return XCTFail("setup")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try originalBytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertEqual(doc.encoding, .eucJP)
        XCTAssertEqual(doc.content, japaneseSample)

        // Modify and save — the file on disk must still be EUC-JP, not UTF-8.
        doc.content = japaneseSample + "\n追加行"
        doc.markModified()
        try doc.save()

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertNil(String(data: rawBytesAfterSave, encoding: .utf8), "must not have been silently re-encoded to UTF-8")
        XCTAssertEqual(String(data: rawBytesAfterSave, encoding: .japaneseEUC), japaneseSample + "\n追加行")
    }

    func testByteOrderMarkIsPreservedAcrossSave() async throws {
        var originalBytes = Data([0xEF, 0xBB, 0xBF])
        originalBytes.append(Data("hello".utf8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try originalBytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertTrue(doc.hasByteOrderMark)
        XCTAssertEqual(doc.content, "hello", "BOM must not appear as a literal character in content")

        doc.content = "hello world"
        doc.markModified()
        try doc.save()

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertEqual(rawBytesAfterSave.prefix(3), Data([0xEF, 0xBB, 0xBF]), "BOM must survive a save")
        XCTAssertEqual(rawBytesAfterSave.dropFirst(3), Data("hello world".utf8))
    }

    func testSavingUnrepresentableCharacterThrowsInsteadOfCorrupting() async throws {
        guard let originalBytes = japaneseSample.data(using: .japaneseEUC) else {
            return XCTFail("setup")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try originalBytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        doc.content = "😀" // not representable in EUC-JP
        doc.markModified()

        XCTAssertThrowsError(try doc.save()) { error in
            guard case DocumentSaveError.unrepresentable(let encoding, let characters) = error else {
                return XCTFail("expected DocumentSaveError.unrepresentable, got \(error)")
            }
            XCTAssertEqual(encoding, .eucJP)
            XCTAssertEqual(characters.map { $0.character }, ["😀"])
            XCTAssertEqual(characters.first?.line, 1)
            XCTAssertEqual(characters.first?.column, 1)
        }

        // The original file on disk must be untouched by the failed save.
        let rawBytesAfterFailedSave = try Data(contentsOf: url)
        XCTAssertEqual(rawBytesAfterFailedSave, originalBytes)
    }

    func testReopenForcingEncodingResetsModifiedState() async throws {
        guard let originalBytes = japaneseSample.data(using: .japaneseEUC) else {
            return XCTFail("setup")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try originalBytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Force-open with the wrong encoding first, to prove reopen(forcing:) corrects it.
        let doc = try Document.open(url: url) // auto-detects as EUC-JP correctly
        try doc.reopen(forcing: .eucJP)

        XCTAssertEqual(doc.content, japaneseSample)
        XCTAssertEqual(doc.encoding, .eucJP)
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.cursorPosition, 0)
    }

    // MARK: - Line endings (M2-03)
    //
    // Like the encoding tests above, these read raw bytes back off disk
    // after save() — proving the file itself round-trips, not just that
    // in-memory content parses back correctly.

    private func write(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try Data(bytes).write(to: url)
        return url
    }

    func testOpeningNormalizesContentToLFInMemory() async throws {
        let url = try write(Array("a\r\nb\r\nc\r\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertEqual(doc.content, "a\nb\nc\n", "in-memory content must always be \\n-normalized")
        XCTAssertEqual(doc.lineEnding, .crlf)
    }

    func testUnmodifiedCRLFFileStaysCRLFAfterSave() async throws {
        let originalBytes = Array("a\r\nb\r\nc\r\n".utf8)
        let url = try write(originalBytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        try doc.save() // no edits — must still preserve CRLF, not silently normalize to LF

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertEqual(Array(rawBytesAfterSave), originalBytes)
    }

    func testUnmodifiedCRFileStaysCRAfterSave() async throws {
        let originalBytes = Array("a\rb\rc\r".utf8)
        let url = try write(originalBytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        try doc.save()

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertEqual(Array(rawBytesAfterSave), originalBytes)
    }

    func testEditingCRLFFileAndSavingKeepsCRLF() async throws {
        let url = try write(Array("a\r\nb\r\nc\r\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        doc.content += "d\n" // edited in-memory (LF, as all in-memory edits are)
        doc.markModified()
        try doc.save()

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertEqual(String(data: rawBytesAfterSave, encoding: .utf8), "a\r\nb\r\nc\r\nd\r\n")
    }

    func testNoTrailingNewlineIsNotAddedOnSave() async throws {
        let url = try write(Array("no trailing newline".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertEqual(doc.lineEnding, .none)
        try doc.save()

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertEqual(String(data: rawBytesAfterSave, encoding: .utf8), "no trailing newline")
    }

    func testMixedLineEndingFileFallsBackToLFWhenSavedWithoutExplicitResolution() async throws {
        // Document.save() alone (no UI layer) defaults an unresolved
        // .mixed lineEnding to LF — a safe, documented fallback. The
        // *required user choice* this task's acceptance criterion refers
        // to is enforced by MainWindowController's save flow, not here.
        let url = try write(Array("a\nb\r\nc\rd\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        guard case .mixed = doc.lineEnding else {
            return XCTFail("expected .mixed, got \(doc.lineEnding)")
        }
        try doc.save()

        let rawBytesAfterSave = try Data(contentsOf: url)
        XCTAssertEqual(String(data: rawBytesAfterSave, encoding: .utf8), "a\nb\nc\nd\n")
    }

    // MARK: - Atomic save and attributes (M2-05)

    func testSavePreservesUnusualPermissions() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try Data("original".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertEqual(doc.posixPermissions, 0o600)

        doc.content = "changed"
        doc.markModified()
        try doc.save()

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testFileIdentityAndModificationDateRefreshAfterSave() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertNotNil(doc.fileIdentity)
        XCTAssertNotNil(doc.lastKnownModificationDate)

        doc.content = "changed"
        doc.markModified()
        try doc.save()

        XCTAssertEqual(doc.fileIdentity, FileIdentity.of(url), "identity must reflect the just-saved file")
        XCTAssertNotNil(doc.lastKnownModificationDate)
    }

    func testSaveAsToExistingFilePreservesThatFilesPermissionsNotTheOriginals() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try Data("source".utf8).write(to: sourceURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceURL.path)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).txt")
        try Data("destination, pre-existing".utf8).write(to: destinationURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destinationURL.path)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let doc = try Document.open(url: sourceURL)
        XCTAssertEqual(doc.posixPermissions, 0o600)

        try doc.save(to: destinationURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o644, "Save As onto an existing file must preserve *that* file's permissions, not the source document's")
    }

    func testWriteFailureThrowsWriteFailedAndLeavesDocumentUnmarkedAsSaved() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("file.txt")
        try Data("original".utf8).write(to: url)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let doc = try Document.open(url: url)
        doc.content = "changed"
        doc.markModified()

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        XCTAssertThrowsError(try doc.save()) { error in
            guard case DocumentSaveError.writeFailed = error else {
                return XCTFail("expected writeFailed, got \(error)")
            }
        }
        XCTAssertTrue(doc.isModified, "a failed save must not mark the document as saved")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        XCTAssertEqual(try Data(contentsOf: url), Data("original".utf8))
    }

    // MARK: - Read-only detection (M2-08)

    func testNewUnnamedDocumentIsNeverReadOnly() async {
        XCTAssertFalse(Document().isReadOnly)
    }

    func testViewModeDisablesEditingWithoutChangingFilesystemReadOnlyState() async {
        let doc = Document(content: "inspect")
        XCTAssertFalse(doc.isEditingDisabled)
        doc.isViewMode = true
        XCTAssertTrue(doc.isEditingDisabled)
        XCTAssertFalse(doc.isReadOnly)
        XCTAssertTrue(doc.propertiesSummary.contains("Mode: View"))
        doc.isViewMode = false
        XCTAssertFalse(doc.isEditingDisabled)
    }

    func testOpeningWritableFileLeavesIsReadOnlyFalse() async throws {
        let url = try write(Array("hello".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertFalse(doc.isReadOnly)
    }

    func testOpeningReadOnlyFileSetsIsReadOnly() async throws {
        let url = try write(Array("hello".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        let doc = try Document.open(url: url)
        XCTAssertTrue(doc.isReadOnly)
    }

    func testRefreshReadOnlyStateDetectsPermissionChangeWhileOpen() async throws {
        let url = try write(Array("hello".utf8))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        let doc = try Document.open(url: url)
        XCTAssertFalse(doc.isReadOnly)

        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        XCTAssertTrue(doc.refreshReadOnlyState(), "a real permission change must be reported")
        XCTAssertTrue(doc.isReadOnly)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertTrue(doc.refreshReadOnlyState(), "flipping back to writable must also be reported")
        XCTAssertFalse(doc.isReadOnly)
    }

    func testRefreshReadOnlyStateReturnsFalseWhenUnchanged() async throws {
        let url = try write(Array("hello".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try Document.open(url: url)
        XCTAssertFalse(doc.refreshReadOnlyState(), "no permission change happened, so nothing should be reported")
    }

    func testRefreshReadOnlyStateOnUnnamedDocumentIsNoOp() async {
        let doc = Document()
        XCTAssertFalse(doc.refreshReadOnlyState())
        XCTAssertFalse(doc.isReadOnly)
    }

    func testReopenForcingEncodingRefreshesReadOnlyState() async throws {
        let url = try write(Array("hello".utf8))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }

        let doc = try Document.open(url: url)
        XCTAssertFalse(doc.isReadOnly)

        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        try doc.reopen(forcing: .utf8)
        XCTAssertTrue(doc.isReadOnly)
    }
}
