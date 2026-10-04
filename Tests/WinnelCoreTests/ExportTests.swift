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
    func testMixedVersionedJSONPreservesOrderMetadataAndExactOptionalAssets() throws {
        struct Document: Decodable {
            let schemaVersion: Int
            let title: String
            let items: [Entry]
        }
        struct Entry: Decodable {
            let id: UUID
            let kind: ClipKind
            let copiedAt: Date
            let source: SourceApplication
            let text: String?
            let associatedURL: String?
            let files: [FileReference]
            let imageAsset: String?
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-mixed-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("never-created.txt")
        let references: [FileReference] = [
            .init(urlString: missing.absoluteString, displayName: "Missing synthetic file", availability: .unavailable),
            .init(urlString: "relative/never-created.txt", displayName: "Relative synthetic file", availability: .relative)
        ]
        // Captured bytes are opaque to export; no image decoder or referenced-file read is needed.
        let imageBytes = Data((0..<64).map { UInt8($0) })
        let payloads: [ClipPayload] = [
            .init(fileReferences: references),
            .init(representations: [.init(type: "public.png", data: imageBytes)]),
            .init(representations: [.init(type: "public.utf8-plain-text", data: Data("Synthetic \"quoted\" text\nsecond line 🧪".utf8))]),
            .init(representations: [.init(type: "public.url", data: Data("https://example.invalid/synthetic?x=1&y=2".utf8))])
        ]
        let kinds: [ClipKind] = [.files, .image, .text, .url]
        let source = SourceApplication(bundleIdentifier: "synthetic.export", name: "Synthetic Export Source", confidence: .inferred)
        let entries = zip(payloads.indices, payloads).map { index, payload in
            ExportEntry(item: .init(copiedAt: Date(timeIntervalSince1970: Double(100 - index)), source: source, kind: kinds[index], textPreview: "Bounded preview", payloadByteCount: payload.byteCount, fingerprint: payload.fingerprint), payload: payload, associatedURL: index == 2 ? "https://example.invalid/citation" : nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for includeImages in [true, false] {
            let document = try ExportBuilder.make(entries: entries, title: "Synthetic mixed stack", format: .json, includeImages: includeImages)
            let decoded = try decoder.decode(Document.self, from: document.content)
            XCTAssertEqual(decoded.schemaVersion, 1)
            XCTAssertEqual(decoded.title, "Synthetic mixed stack")
            XCTAssertEqual(decoded.items.map(\.id), entries.map { $0.item.id })
            XCTAssertEqual(decoded.items.map(\.kind), kinds)
            XCTAssertEqual(decoded.items.map(\.copiedAt), entries.map { $0.item.copiedAt })
            XCTAssertEqual(decoded.items.map(\.source), Array(repeating: source, count: entries.count))
            XCTAssertEqual(decoded.items.map(\.text), payloads.map(\.plainText))
            XCTAssertEqual(decoded.items.map(\.associatedURL), entries.map(\.associatedURL))
            XCTAssertEqual(decoded.items.map(\.files), payloads.map(\.fileReferences))
            XCTAssertEqual(Data(document.preview.utf8), document.content)
            XCTAssertEqual(document.suggestedFilename, "winnel-export.json")
            let destination = root.appendingPathComponent(includeImages ? "WithImages" : "WithoutImages")
            try ExportWriter.write(document: document, to: destination)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(document.suggestedFilename)), Data(document.preview.utf8))
            if includeImages {
                let assetName = entries[1].item.id.uuidString.lowercased() + ".png"
                XCTAssertEqual(decoded.items.map(\.imageAsset), [nil, "assets/" + assetName, nil, nil])
                XCTAssertEqual(document.assets, [assetName: imageBytes])
                XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("assets").appendingPathComponent(assetName)), imageBytes)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("assets").path), [assetName])
            } else {
                XCTAssertTrue(decoded.items.allSatisfy { $0.imageAsset == nil })
                XCTAssertTrue(document.assets.isEmpty)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [document.suggestedFilename])
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["WithImages", "WithoutImages"])
    }
    func testUnsafeAssetPathRejectedBeforeWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var doc = ExportDocument(suggestedFilename: "winnel-export.json", content: Data(), preview: "", assets: [:])
        doc.assets["../escape"] = Data()
        XCTAssertThrowsError(try ExportWriter.write(document: doc, to: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
