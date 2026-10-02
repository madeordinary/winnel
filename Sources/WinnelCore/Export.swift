import Foundation

public enum ExportFormat: String, CaseIterable, Sendable { case markdown, json }
public struct ExportEntry: Sendable {
    public var item: ClipboardItem
    public var payload: ClipPayload
    public var associatedURL: String?
    public init(item: ClipboardItem, payload: ClipPayload, associatedURL: String? = nil) {
        self.item = item; self.payload = payload; self.associatedURL = associatedURL
    }
}
public struct ExportDocument: Sendable {
    public var suggestedFilename: String
    public var content: Data
    public var preview: String
    public var assets: [String: Data]
}
public enum ExportError: Error, Equatable { case emptySelection, unsafeDestination, destinationExists, unsupportedImage, tooLarge }
public enum ExportBuilder {
    private struct JSONDocument: Encodable { let schemaVersion: Int; let title: String; let items: [JSONItem] }
    private struct JSONItem: Encodable {
        let id: UUID; let kind: ClipKind; let copiedAt: Date; let source: SourceApplication
        let text: String?; let associatedURL: String?; let files: [FileReference]; let imageAsset: String?
    }
    public static func make(entries: [ExportEntry], title: String, format: ExportFormat, includeImages: Bool = false) throws -> ExportDocument {
        try Task.checkCancellation()
        guard !entries.isEmpty else { throw ExportError.emptySelection }
        var assets: [String: Data] = [:]
        var jsonItems: [JSONItem] = []
        var markdown = "# " + title.replacingOccurrences(of: "\n", with: " ") + "\n\n"
        for entry in entries {
            try Task.checkCancellation()
            var imageAsset: String?
            if includeImages, entry.item.kind == .image {
                let choices = [("public.png", "png"), ("public.jpeg", "jpg"), ("public.tiff", "tiff")]
                guard let choice = choices.first(where: { type, _ in entry.payload.representations.contains { $0.type == type } }), let data = entry.payload.representations.first(where: { $0.type == choice.0 })?.data else { throw ExportError.unsupportedImage }
                let name = entry.item.id.uuidString.lowercased() + "." + choice.1
                assets[name] = data; imageAsset = "assets/" + name
            }
            jsonItems.append(.init(id: entry.item.id, kind: entry.item.kind, copiedAt: entry.item.copiedAt, source: entry.item.source,
                                   text: entry.payload.plainText, associatedURL: entry.associatedURL, files: entry.payload.fileReferences, imageAsset: imageAsset))
            if let text = entry.payload.plainText { markdown += text + "\n\n" }
            else if entry.item.kind == .richText { markdown += "Rich text (no plain-text representation)\n\n" }
            if let imageAsset { markdown += "![Saved image](" + imageAsset + ")\n\n" }
            else if entry.item.kind == .image { markdown += "Image (asset not included)\n\n" }
            if let link = entry.associatedURL { markdown += "Associated URL: " + link + "\n\n" }
            for file in entry.payload.fileReferences {
                markdown += "- File reference: `" + file.urlString.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "\n", with: "\\n") + "` — " + file.availability.rawValue + "; contents not included\n"
            }
            if !entry.payload.fileReferences.isEmpty { markdown += "\n" }
            markdown += "---\n\n"
        }
        try Task.checkCancellation()
        let data: Data
        if format == .json {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(JSONDocument(schemaVersion: 1, title: title, items: jsonItems))
        } else { data = Data(markdown.utf8) }
        guard data.count <= 64 * 1024 * 1024, assets.values.reduce(Int64(0), { $0 + Int64($1.count) }) <= 2 * 1024 * 1024 * 1024 else { throw ExportError.tooLarge }
        return .init(suggestedFilename: "winnel-export." + (format == .json ? "json" : "md"), content: data, preview: String(decoding: data, as: UTF8.self), assets: assets)
    }
}

/// Writes exactly the previewed document and asset list into a new user-selected folder.
/// Existing paths are never overwritten. Only caller-supplied captured bytes are written.
public enum ExportWriter {
    public static func write(document: ExportDocument, to directory: URL) throws {
        try Task.checkCancellation()
        let fm = FileManager.default
        guard directory.isFileURL, directory.lastPathComponent != ".", directory.lastPathComponent != "..",
              directory.deletingLastPathComponent().resolvingSymlinksInPath() == directory.deletingLastPathComponent().standardizedFileURL,
              document.suggestedFilename == "winnel-export.md" || document.suggestedFilename == "winnel-export.json",
              document.assets.keys.allSatisfy({ !$0.contains("/") && !$0.contains("\\") && $0 != "." && $0 != ".." }) else { throw ExportError.unsafeDestination }
        guard !fm.fileExists(atPath: directory.path) else { throw ExportError.destinationExists }
        let staging = directory.deletingLastPathComponent().appendingPathComponent(".winnel-export-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try document.content.write(to: staging.appendingPathComponent(document.suggestedFilename), options: .withoutOverwriting)
            if !document.assets.isEmpty {
                let assets = staging.appendingPathComponent("assets"); try fm.createDirectory(at: assets, withIntermediateDirectories: false)
                for (name, data) in document.assets { try Task.checkCancellation(); try data.write(to: assets.appendingPathComponent(name), options: .withoutOverwriting) }
            }
            try Task.checkCancellation()
            try fm.moveItem(at: staging, to: directory)
        } catch { try? fm.removeItem(at: staging); throw error }
    }
}
