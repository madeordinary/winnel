import Foundation

public enum CombinationFormat: String, CaseIterable, Codable, Sendable { case newline, bullets, numbered, markdownLinks, jsonArray }
public enum CombinationError: Error, Equatable { case emptySelection, unsupportedSelection, missingLink }
public struct CombinationEntry: Sendable {
    public let item: ClipboardItem
    public let payload: ClipPayload
    public let associatedURL: String?
    public init(item: ClipboardItem, payload: ClipPayload, associatedURL: String? = nil) { self.item = item; self.payload = payload; self.associatedURL = associatedURL }
}
public enum Combination {
    /// Metadata eligibility for presenting Combine. Payload and format validation still happen in preview.
    public static func canCombine(_ items: [ClipboardItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { [.text, .richText, .url].contains($0.kind) }
    }
    public static func preview(_ entries: [CombinationEntry], format: CombinationFormat) throws -> String {
        try Task.checkCancellation()
        guard !entries.isEmpty else { throw CombinationError.emptySelection }
        guard entries.allSatisfy({ [.text, .richText, .url].contains($0.item.kind) && $0.payload.plainText != nil }) else { throw CombinationError.unsupportedSelection }
        let texts = try entries.map { entry in try Task.checkCancellation(); return entry.payload.plainText! }
        switch format {
        case .newline: return texts.joined(separator: "\n")
        case .bullets: return try texts.map { try Task.checkCancellation(); return "- " + $0.replacingOccurrences(of: "\n", with: "\n  ") }.joined(separator: "\n")
        case .numbered: return try texts.enumerated().map { try Task.checkCancellation(); return "\($0.offset + 1). " + $0.element.replacingOccurrences(of: "\n", with: "\n   ") }.joined(separator: "\n")
        case .jsonArray:
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(texts), as: UTF8.self)
        case .markdownLinks:
            return try zip(entries, texts).map { entry, text in
                try Task.checkCancellation()
                let raw = entry.associatedURL ?? (entry.item.kind == .url ? text : nil)
                guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else { throw CombinationError.missingLink }
                let label = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "\n", with: " ")
                let destination = raw.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29").replacingOccurrences(of: "\n", with: "%0A").replacingOccurrences(of: "\r", with: "%0D")
                return "- [\(label)](\(destination))"
            }.joined(separator: "\n")
        }
    }
}
