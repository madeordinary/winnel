import XCTest
@testable import WinnelCore

final class ExportTests: XCTestCase {
    func item(_ payload: ClipPayload, kind: ClipKind) -> ClipboardItem { .init(copiedAt: Date(timeIntervalSince1970: 10), kind: kind, textPreview: "Synthetic", payloadByteCount: payload.byteCount, fingerprint: payload.fingerprint) }
    func testPreviewIsExactAndFileReferencesNeverRead() throws {
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("synthetic\ntext".utf8))], fileReferences: [.init(urlString: "relative/never-read.txt", displayName: "never-read.txt", availability: .relative)])
        let result = try ExportBuilder.make(entries: [.init(item: item(payload, kind: .files), payload: payload)], title: "My stack", format: .json)
        XCTAssertEqual(Data(result.preview.utf8), result.content)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: result.content) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertTrue(result.preview.contains("relative/never-read.txt")); XCTAssertTrue(result.assets.isEmpty)
    }
    func testOptionalImageAssetsAndCollisionProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = ClipPayload(representations: [.init(type: "public.png", data: Data([137, 80, 78, 71]))])
        let entry = ExportEntry(item: item(payload, kind: .image), payload: payload)
        XCTAssertTrue(try ExportBuilder.make(entries: [entry], title: "Image", format: .markdown).assets.isEmpty)
        let doc = try ExportBuilder.make(entries: [entry], title: "Image", format: .markdown, includeImages: true)
        let destination = root.appendingPathComponent("Export")
        try ExportWriter.write(document: doc, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(doc.suggestedFilename)), doc.content)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets").appendingPathComponent(doc.assets.keys.first!)), payload.representations[0].data)
        XCTAssertThrowsError(try ExportWriter.write(document: doc, to: destination))
    }
    func testUnsafeAssetPathRejectedBeforeWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var doc = ExportDocument(suggestedFilename: "winnel-export.json", content: Data(), preview: "", assets: [:])
        doc.assets["../escape"] = Data()
        XCTAssertThrowsError(try ExportWriter.write(document: doc, to: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
