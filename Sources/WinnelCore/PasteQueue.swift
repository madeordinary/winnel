import Foundation

public struct QueueEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { item.id }
    public let item: ClipboardItem
    public let payload: ClipPayload
    public init(item: ClipboardItem, payload: ClipPayload) { self.item = item; self.payload = payload }
}
public enum QueueCancellation: String, Sendable { case user, idle, lock, sleep, userSwitch, deleted }
public struct PasteQueue: Sendable {
    public private(set) var entries: [QueueEntry]
    public var mode: ItemAction
    public private(set) var position: Int = 0
    public private(set) var lastInteraction: Date
    public private(set) var cancellation: QueueCancellation?
    public static let idleLimit: TimeInterval = 300
    public init(entries: [QueueEntry], mode: ItemAction = .copy, now: Date) { self.entries = entries; self.mode = mode; self.lastInteraction = now }
    public var current: QueueEntry? { cancellation == nil && position < entries.count ? entries[position] : nil }
    public var retainedIDs: Set<UUID> { cancellation == nil ? Set(entries.map(\.id)) : [] }
    public var isComplete: Bool { cancellation == nil && position == entries.count }
    @discardableResult public mutating func expire(now: Date) -> Bool { if cancellation == nil && now.timeIntervalSince(lastInteraction) >= Self.idleLimit { cancel(.idle); return true }; return false }
    // A successful dispatch means an event was sent, never proof that a destination consumed it.
    public mutating func recordDispatch(success: Bool, now: Date) { guard !expire(now: now), current != nil else { return }; lastInteraction = now; if success { position += 1 } }
    public mutating func back(now: Date) { guard !expire(now: now), cancellation == nil else { return }; lastInteraction = now; position = max(0, position - 1) }
    public mutating func interact(now: Date) { guard !expire(now: now), cancellation == nil else { return }; lastInteraction = now }
    public mutating func cancel(_ reason: QueueCancellation = .user) { cancellation = reason; entries.removeAll(); position = 0 }
    public mutating func removeDeletedItems(_ ids: Set<UUID>) { if entries.contains(where: { ids.contains($0.id) }) { cancel(.deleted) } }
}
