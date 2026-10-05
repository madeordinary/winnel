import XCTest
import AppKit
import ImageIO
import WinnelCore
@testable import WinnelPlatform

final class PlatformTests: XCTestCase {
    @MainActor func testSyntheticRoundTripAndOwnMarker() throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("synthetic".utf8)), .init(type: "public.url", data: Data("https://example.invalid".utf8))])
        XCTAssertTrue(service.write(payload))
        if case .skipped(.marker) = service.readSnapshot() {} else { XCTFail("Own writes must not be ingested") }
        board.clearContents()
        let item = NSPasteboardItem()
        for representation in payload.representations { item.setData(representation.data, forType: .init(representation.type)) }
        XCTAssertTrue(board.writeObjects([item]))
        if case let .captured(result, _) = service.readSnapshot() { XCTAssertEqual(result, payload) } else { XCTFail("Synthetic copy expected") }
    }
    @MainActor func testConcealedUnknownAndExcluded() {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        board.declareTypes([.string, .init("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString("fixture secret", forType: .string)
        if case .skipped(.marker) = service.readSnapshot() {} else { XCTFail() }
        board.declareTypes([.init("com.example.private")], owner: nil)
        board.setString("fixture", forType: .init("com.example.private"))
        if case .skipped(.unsupported) = service.readSnapshot() {} else { XCTFail() }
        if case .skipped(.excluded) = service.readSnapshot(source: .init(bundleIdentifier: "safe"), excluded: ["excluded"], previousForegroundID: "excluded") {} else { XCTFail() }
    }
    @MainActor func testBoundsAndClearRace() {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var policy = CapturePolicy(); policy.byteLimit = 1024
        let service = PasteboardService(pasteboard: board, policy: policy)
        board.declareTypes([.string], owner: nil); board.setString(String(repeating: "x", count: 900), forType: .string)
        if case .skipped(.oversized) = service.readSnapshot() {} else { XCTFail("JSON base64 overhead must count") }
        let approved = board.changeCount
        board.clearContents(); board.setString("new copy", forType: .string)
        XCTAssertFalse(service.clear(expectedChangeCount: approved))
        XCTAssertEqual(board.string(forType: .string), "new copy")
        XCTAssertTrue(service.clear(expectedChangeCount: board.changeCount))
    }
    @MainActor func testCompleteRawBudgetPrecedesImageParser() {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var policy = CapturePolicy(); policy.byteLimit = 1024
        let service = PasteboardService(pasteboard: board, policy: policy)
        let item = NSPasteboardItem()
        item.setData(Data("invalid image".utf8), forType: .png)
        item.setData(Data(repeating: 0, count: 900), forType: .tiff)
        XCTAssertTrue(board.writeObjects([item]))
        if case .skipped(.oversized) = service.readSnapshot() {} else { XCTFail("The complete raw budget must reject before the earlier invalid image is parsed") }
    }
    @MainActor func testDerivedRTFTextMustFitFinalSerializedBudget() throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let rich = Data(("{\\rtf1\\ansi " + String(repeating: "x", count: 1000) + "}").utf8)
        let raw = ClipPayload(representations: [.init(type: "public.rtf", data: rich)])
        var policy = CapturePolicy(); policy.byteLimit = try XCTUnwrap(policy.serializedSize(raw)) + 256
        XCTAssertNotNil(policy.plainTextFromSafeRTF(rich))
        let item = NSPasteboardItem(); item.setData(rich, forType: .rtf)
        XCTAssertTrue(board.writeObjects([item]))
        if case .skipped(.oversized) = PasteboardService(pasteboard: board, policy: policy).readSnapshot() {} else { XCTFail("Derived plain text must count in the final serialized payload") }
    }
    @MainActor func testEscapedFileMetadataMustFitFinalSerializedBudget() throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let string = "file:///synthetic/" + String(repeating: "\"", count: 1000)
        let data = Data(string.utf8)
        let raw = ClipPayload(representations: [.init(type: "public.file-url", data: data)])
        var policy = CapturePolicy(); policy.byteLimit = try XCTUnwrap(policy.serializedSize(raw)) + 256
        let url = try XCTUnwrap(URL(string: string))
        let derived = ClipPayload(fileReferences: [.init(urlString: string, displayName: url.lastPathComponent)])
        XCTAssertGreaterThan(try XCTUnwrap(policy.serializedSize(derived)), policy.byteLimit)
        let item = NSPasteboardItem(); item.setData(data, forType: .fileURL)
        XCTAssertTrue(board.writeObjects([item]))
        if case .skipped(.oversized) = PasteboardService(pasteboard: board, policy: policy).readSnapshot() {} else { XCTFail("Escaped URL and display name must count in the final payload") }
    }
    @MainActor func testPauseResumeBaseline() async throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var copies = 0
        let monitor = CaptureMonitor(service: .init(pasteboard: board), onCapture: { _, _ in copies += 1 })
        board.declareTypes([.string], owner: nil); board.setString("before enable", forType: .string)
        monitor.enable(); monitor.poll(); XCTAssertEqual(copies, 0)
        monitor.pause(); board.clearContents(); board.setString("during pause", forType: .string)
        monitor.resume(); monitor.poll(); XCTAssertEqual(copies, 0)
        board.clearContents(); board.setString("after resume", forType: .string)
        monitor.poll(); monitor.poll(); try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(copies, 1)
        monitor.suspend(); board.clearContents(); board.setString("suspended", forType: .string)
        monitor.poll(); monitor.poll(); try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(copies, 1); monitor.stop()
    }
    @MainActor func testLateWorkerCaptureIsDiscardedAfterPause() async throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var copies = 0
        let monitor = CaptureMonitor(service: .init(pasteboard: board), onCapture: { _, _ in copies += 1 })
        monitor.enable()
        board.clearContents(); board.setString("synthetic pending", forType: .string)
        monitor.poll(); monitor.poll()
        monitor.pause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(monitor.state, .paused)
        monitor.stop()
    }
    @MainActor func testRapidCopiesBetweenPollsCaptureOnlyLatestSnapshot() async throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var captured: [String] = []
        let monitor = CaptureMonitor(service: .init(pasteboard: board), onCapture: { payload, _ in captured.append(payload.plainText ?? "") })
        monitor.enable()
        defer { monitor.stop() }
        // Ten real named-pasteboard changes before the polling loop can run.
        // Only the latest is recoverable: this deliberately measures nine missed copies.
        for index in 0..<10 { board.clearContents(); XCTAssertTrue(board.setString("burst-\(index)", forType: .string)) }
        monitor.poll(); monitor.poll()
        let deadline = Date().addingTimeInterval(2)
        while captured.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(captured, ["burst-9"])
        XCTAssertEqual(10 - captured.count, 9)
    }
    @MainActor func testMultipleFilesAreReferencesAndMultipleTextIsSkipped() {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        let entries = ["file:///synthetic/one.txt", "file:///synthetic/two.txt"].map { value in
            let item = NSPasteboardItem(); item.setString(value, forType: .fileURL); return item
        }
        board.clearContents(); XCTAssertTrue(board.writeObjects(entries))
        if case let .captured(payload, _) = service.readSnapshot() {
            XCTAssertEqual(payload.fileReferences.map(\.urlString), ["file:///synthetic/one.txt", "file:///synthetic/two.txt"])
            XCTAssertTrue(payload.representations.isEmpty)
            XCTAssertTrue(payload.fileReferences.allSatisfy { $0.availability == .unknown })
        } else { XCTFail() }
        let texts = ["a", "b"].map { value in let item = NSPasteboardItem(); item.setString(value, forType: .string); return item }
        board.clearContents(); XCTAssertTrue(board.writeObjects(texts))
        if case .skipped(.unsupported) = service.readSnapshot() {} else { XCTFail() }
    }
    @MainActor func testPermissionPreflightWithoutClipboardChange() {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var status: ClipboardAccessStatus = .denied
        var failures: [CaptureSkipReason] = []
        let monitor = CaptureMonitor(service: .init(pasteboard: board), onCapture: { _, _ in XCTFail("No payload should be read") }, onCaptureFailure: { failures.append($0) }, permissionStatus: { status })
        monitor.enable(); XCTAssertEqual(monitor.state, .paused); XCTAssertEqual(failures, [.permissionDenied])
        status = .required; monitor.resume(); XCTAssertEqual(monitor.state, .paused); XCTAssertEqual(failures.last, .permissionRequired)
        status = .allowed; monitor.resume(); XCTAssertEqual(monitor.state, .active)
        status = .denied; monitor.poll(); XCTAssertEqual(monitor.state, .paused); XCTAssertEqual(failures.last, .permissionDenied)
        monitor.stop()
    }
    @MainActor func testRTFOnlyPreservesRichBytesAndDerivesSearchableText() throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        let rich = Data("{\\rtf1\\ansi\\deff0 {\\fonttbl {\\f0 Helvetica;}}\\f0\\fs24 Searchable \\b synthetic \\b0 text\\par second line}".utf8)
        board.declareTypes([.rtf], owner: nil); board.setData(rich, forType: .rtf)
        guard case let .captured(payload, _) = service.readSnapshot() else { return XCTFail("Safe RTF-only should capture") }
        XCTAssertEqual(payload.representations.first { $0.type == "public.rtf" }?.data, rich)
        let text = try XCTUnwrap(payload.plainText)
        XCTAssertTrue(text.contains("Searchable synthetic text")); XCTAssertTrue(text.contains("second line"))
        let item = ClipboardItem(copiedAt: Date(), kind: .richText, textPreview: text, searchText: text, payloadByteCount: payload.byteCount, fingerprint: payload.fingerprint)
        XCTAssertEqual(LibraryState(items: [item]).search("synthetic").map(\.id), [item.id])
        XCTAssertEqual(try Combination.preview([.init(item: item, payload: payload)], format: .newline), text)
    }
    func testRTFExternalResourcesAndAttachmentsRejectedBeforeSystemParser() {
        let policy = CapturePolicy()
        for fixture in [
            "{\\rtf1{\\field{\\*\\fldinst INCLUDEPICTURE \"https://example.invalid/image\"}}}",
            "{\\rtf1{\\object\\objdata 00}}",
            "{\\rtf1{\\pict\\pngblip 00}}",
            "{\\rtf1{\\filetbl file:///synthetic/private.txt}}",
            "{\\rtf1{\\*\\unknownDestination file:///synthetic/private.txt}}"
        ] { XCTAssertNil(policy.plainTextFromSafeRTF(Data(fixture.utf8))) }
        XCTAssertNil(policy.plainTextFromSafeRTF(Data("{\\rtf1".utf8)))
        XCTAssertNil(policy.plainTextFromSafeRTF(Data(("{\\rtf1" + String(repeating: "{", count: 128) + String(repeating: "}", count: 129)).utf8)))
        var small = policy; small.byteLimit = 8
        XCTAssertNil(small.plainTextFromSafeRTF(Data("{\\rtf1 too large}".utf8)))
    }
    @MainActor func testFileOnlyWriteHasExactlyOneMarkedObjectPerReference() throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let service = PasteboardService(pasteboard: board)
        let urls = ["file:///synthetic/one.txt", "file:///synthetic/two.txt"]
        let payload = ClipPayload(fileReferences: urls.map { .init(urlString: $0, displayName: URL(string: $0)!.lastPathComponent) })
        XCTAssertTrue(service.write(payload))
        let items = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.types.contains(PasteboardService.ownMarker) && $0.types.contains(.fileURL) })
        XCTAssertEqual(items.compactMap { $0.string(forType: .fileURL) }, urls)
        let readURLs = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])
        XCTAssertEqual(readURLs.map(\.absoluteString), urls)
        let before = board.changeCount
        XCTAssertFalse(service.write(.init()))
        XCTAssertEqual(board.changeCount, before)
    }
    func testFileReferenceMetadataNeverImportsContents() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-file-metadata-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("fixture.txt")
        try Data("synthetic contents excluded".utf8).write(to: file)
        let reference = FileReference(urlString: file.absoluteString, displayName: "fixture.txt")
        XCTAssertEqual(FileReferenceMetadata.resolve(reference).availability, .available)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(FileReferenceMetadata.resolve(reference).availability, .unavailable)
        XCTAssertEqual(FileReferenceMetadata.resolve(.init(urlString: "relative/path", displayName: "path")).availability, .relative)
        XCTAssertEqual(FileReferenceMetadata.resolve(.init(urlString: "https://example.invalid/private", displayName: "private")).availability, .unavailable)
    }
    func testImageMetadataRejectsInvalidDataAndExcludedTransitions() {
        let policy = CapturePolicy()
        XCTAssertFalse(policy.permitsImage(Data("not an image".utf8)))
        XCTAssertNil(policy.thumbnail(Data("invalid".utf8)))
        XCTAssertFalse(policy.permits(source: nil, previous: "blocked", excluded: ["blocked"]))
        XCTAssertFalse(policy.permits(source: "blocked", previous: "safe", excluded: ["blocked"]))
    }
    func testImageDimensionsAndBoundedThumbnail() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data = bytes as Data
        let policy = CapturePolicy()
        XCTAssertTrue(policy.permitsImage(data)); XCTAssertNotNil(policy.thumbnail(data))
        var restricted = policy; restricted.dimensionLimit = 3
        XCTAssertFalse(restricted.permitsImage(data)); XCTAssertNil(restricted.thumbnail(data))
        restricted = policy; restricted.pixelLimit = 7
        XCTAssertFalse(restricted.permitsImage(data))
        XCTAssertNil(policy.thumbnail(data, maximumDimension: 1024))
        XCTAssertEqual(policy.imageDescriptor(data, type: "public.png"), "PNG image · 4 × 2")
        XCTAssertEqual(policy.imageDescriptor(Data("invalid".utf8), type: "public.jpeg"), "JPEG image")
        XCTAssertNil(policy.imageDescriptor(data, type: "public.heic"))
    }
    @MainActor func testMonitorReportsOversizedCopyButKeepsConcealedCopySilent() async throws {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        var policy = CapturePolicy(); policy.byteLimit = 2_048
        var captured: [String] = []; var skipped: [CaptureSkipReason] = []
        let monitor = CaptureMonitor(service: .init(pasteboard: board, policy: policy), onCapture: { payload, _ in captured.append(payload.plainText ?? "") }, onCaptureSkipped: { skipped.append($0) })
        monitor.enable()
        defer { monitor.stop() }
        func settle(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(2)
            while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        }
        board.clearContents(); XCTAssertTrue(board.setString(String(repeating: "x", count: 4_000), forType: .string))
        monitor.poll(); monitor.poll()
        try await settle { !skipped.isEmpty }
        XCTAssertEqual(skipped, [.oversized]); XCTAssertTrue(captured.isEmpty)
        // An oversized copy that is also marked concealed stays silent.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        board.declareTypes([.string, concealed], owner: nil); board.setString(String(repeating: "s", count: 4_000), forType: .string); board.setData(Data(), forType: concealed)
        monitor.poll(); monitor.poll()
        // Let the concealed read finish before the next change, so it is actually evaluated.
        try await settle { !monitor.hasPendingRead }
        board.clearContents(); XCTAssertTrue(board.setString("synthetic sentinel", forType: .string))
        monitor.poll(); monitor.poll()
        try await settle { !captured.isEmpty }
        XCTAssertEqual(captured, ["synthetic sentinel"])
        XCTAssertEqual(skipped, [.oversized])
    }
    @MainActor func testSkipReportsStaySilentWhenAMarkerIsPresentAtReportTime() {
        let board = NSPasteboard(name: .init("winnel-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("synthetic plain", forType: .string)
        XCTAssertTrue(CaptureMonitor.mayReportSkip(on: board))
        // A provider can add a marker after the size check without a new change count.
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertFalse(CaptureMonitor.mayReportSkip(on: board))
        board.clearContents(); board.declareTypes([.string, .init("org.nspasteboard.TransientType")], owner: nil); board.setString("synthetic transient", forType: .string)
        XCTAssertFalse(CaptureMonitor.mayReportSkip(on: board))
    }
    @MainActor func testModifierWaitRechecksCurrentActionAndCancellation() async throws {
        var stillCurrent = true
        let changedAtReadiness = await PasteTargetService.waitUntilReady(isCurrent: { stillCurrent }, isReady: { stillCurrent = false; return true })
        XCTAssertFalse(changedAtReadiness)
        let wait = Task { await PasteTargetService.waitUntilReady(isCurrent: { true }, isReady: { false }) }
        wait.cancel()
        let cancelled = await wait.value
        XCTAssertFalse(cancelled)
        var ready = false
        let release = Task { try await Task.sleep(for: .milliseconds(30)); ready = true }
        let allowed = await PasteTargetService.waitUntilReady(isCurrent: { true }, isReady: { ready })
        try await release.value
        XCTAssertTrue(allowed)
    }
    @MainActor func testPasteCompatibilityDefaultsClosed() {
        let service = PasteTargetService()
        XCTAssertTrue(service.compatibilityRules.isEmpty)
        XCTAssertNil(service.captureTarget())
    }
}
