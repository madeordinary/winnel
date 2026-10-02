import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable, Sendable { case text, richText, url, image, files }
public enum SourceConfidence: String, Codable, Sendable { case established, inferred, unknown }
public struct SourceApplication: Codable, Equatable, Sendable {
    public var bundleIdentifier: String?
    public var name: String?
    public var confidence: SourceConfidence
    public init(bundleIdentifier: String? = nil, name: String? = nil, confidence: SourceConfidence = .unknown) { self.bundleIdentifier = bundleIdentifier; self.name = name; self.confidence = confidence }
}
public struct PayloadRepresentation: Codable, Equatable, Sendable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) { self.type = type; self.data = data }
}
public enum FileAvailability: String, Codable, Sendable { case unknown, available, unavailable, relative }
public struct FileReference: Codable, Equatable, Sendable {
    public var urlString: String
    public var displayName: String
    public var availability: FileAvailability
    public init(urlString: String, displayName: String, availability: FileAvailability = .unknown) { self.urlString = urlString; self.displayName = displayName; self.availability = availability }
}
public struct ClipPayload: Codable, Equatable, Sendable {
    public var representations: [PayloadRepresentation]
    public var fileReferences: [FileReference]
    public init(representations: [PayloadRepresentation] = [], fileReferences: [FileReference] = []) { self.representations = representations; self.fileReferences = fileReferences }
    public var plainText: String? {
        for type in ["public.utf8-plain-text", "public.url", "public.text"] {
            if let value = representations.first(where: { $0.type == type }), let text = String(data: value.data, encoding: .utf8) { return text }
        }
        return nil
    }
    /// A bounded display excerpt; Copy and Export continue to use the untouched payload.
    public func boundedPlainText(maximumUTF8Bytes: Int = 65_536) -> (text: String, isTruncated: Bool)? {
        guard maximumUTF8Bytes > 0 else { return nil }
        for type in ["public.utf8-plain-text", "public.url", "public.text"] {
            guard let data = representations.first(where: { $0.type == type })?.data else { continue }
            if data.count <= maximumUTF8Bytes {
                if let text = String(data: data, encoding: .utf8) { return (text, false) }
            } else {
                // A UTF-8 character can straddle the limit by at most three bytes.
                for removed in 0...min(3, maximumUTF8Bytes) {
                    if let text = String(data: data.prefix(maximumUTF8Bytes - removed), encoding: .utf8) { return (text, true) }
                }
            }
        }
        return nil
    }
    public var byteCount: Int { representations.reduce(0) { $0 + $1.data.count + $1.type.utf8.count } + fileReferences.reduce(0) { $0 + $1.urlString.utf8.count + $1.displayName.utf8.count } }
    public var fingerprint: String {
        var bytes = Data()
        func append(_ data: Data) { var length = UInt64(data.count).bigEndian; withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }; bytes.append(data) }
        append(Data("winnel-payload-v1".utf8))
        for representation in representations { append(Data(representation.type.utf8)); append(representation.data) }
        append(Data("file-references".utf8))
        for file in fileReferences { append(Data(file.urlString.utf8)) }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var copiedAt: Date
    public var source: SourceApplication
    public var kind: ClipKind
    public var textPreview: String
    public var searchText: String
    public var payloadByteCount: Int
    public var fingerprint: String
    public var isPinned: Bool
    public var isRecent: Bool
    public init(id: UUID = UUID(), copiedAt: Date, source: SourceApplication = .init(), kind: ClipKind, textPreview: String, searchText: String? = nil, payloadByteCount: Int, fingerprint: String, isPinned: Bool = false, isRecent: Bool = true) {
        self.id = id; self.copiedAt = copiedAt; self.source = source; self.kind = kind; self.textPreview = String(textPreview.prefix(512)); self.searchText = String((searchText ?? textPreview).prefix(16_384)); self.payloadByteCount = max(0, payloadByteCount); self.fingerprint = fingerprint; self.isPinned = isPinned; self.isRecent = isRecent
    }
}
public struct StackMembership: Codable, Equatable, Sendable {
    public var itemID: UUID
    public var associatedURL: String?
    public init(itemID: UUID, associatedURL: String? = nil) { self.itemID = itemID; self.associatedURL = associatedURL }
}
public struct SavedStack: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var memberships: [StackMembership]
    public init(id: UUID = UUID(), name: String, memberships: [StackMembership] = []) { self.id = id; self.name = name; self.memberships = memberships }
}
public enum Retention: String, Codable, CaseIterable, Sendable {
    case oneHour, oneDay, sevenDays, ramOnly
    public var duration: TimeInterval? { switch self { case .oneHour: 3600; case .oneDay: 86400; case .sevenDays: 604800; case .ramOnly: nil } }
}
public enum ItemAction: String, Codable, Sendable { case copy, paste }
public struct Settings: Codable, Equatable, Sendable {
    public var onboardingComplete = false
    public var pauseUntil: Date?
    public var paletteShortcutKeyCode: UInt32 = 49
    public var paletteShortcutModifiers: UInt32 = 768
    public var nextShortcutKeyCode: UInt32 = 45
    public var nextShortcutModifiers: UInt32 = 768
    public var captureEnabled = false
    // Optional preserves decoding of the initial v1 manifest; absent means not paused.
    public var capturePaused: Bool? = nil
    public var retention: Retention = .oneDay
    public var excludedBundleIdentifiers: Set<String> = []
    public var defaultAction: ItemAction = .copy
    public var directPasteEnabled = false
    public var launchAtLogin = false
    public var updateChecksEnabled = false
    public var recentLimit = 200
    public var captureByteLimit = 20 * 1024 * 1024
    public var storageByteLimit = 2 * 1024 * 1024 * 1024
    public init() {}
}
