import Foundation

public enum LibraryError: Error, Equatable { case captureTooLarge, savedStorageFull, missingItem, missingStack, invalidOrder }
public struct IngestResult: Equatable, Sendable {
    public let itemID: UUID
    public let inserted: Bool
    public let removedIDs: Set<UUID>
}
public struct LibraryState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var items: [ClipboardItem]
    public var stacks: [SavedStack]
    public var settings: Settings
    // Latest actual user copy, including saved items. Viewing and app writes never update this.
    public var lastUserCopyID: UUID?
    public init(schemaVersion: Int = currentSchemaVersion, items: [ClipboardItem] = [], stacks: [SavedStack] = [], settings: Settings = .init(), lastUserCopyID: UUID? = nil) { self.schemaVersion = schemaVersion; self.items = items; self.stacks = stacks; self.settings = settings; self.lastUserCopyID = lastUserCopyID }
    public func isSaved(_ id: UUID) -> Bool { items.contains { $0.id == id && $0.isPinned } || stacks.contains { $0.memberships.contains { $0.itemID == id } } }
    public var managedPayloadBytes: Int { items.reduce(0) { $0 + $1.payloadByteCount } }
    public var recentItems: [ClipboardItem] { items.filter(\.isRecent).sorted { $0.copiedAt > $1.copiedAt } }
    public func affectedStacks(for id: UUID) -> [SavedStack] { stacks.filter { $0.memberships.contains { $0.itemID == id } } }
    public func search(_ query: String) -> [ClipboardItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return recentItems }
        let stackIDs = Set(stacks.filter { $0.name.localizedCaseInsensitiveContains(query) }.flatMap { $0.memberships.map(\.itemID) })
        return items.filter { stackIDs.contains($0.id) || $0.searchText.localizedCaseInsensitiveContains(query) || ($0.source.name ?? "").localizedCaseInsensitiveContains(query) || ($0.source.bundleIdentifier ?? "").localizedCaseInsensitiveContains(query) || $0.kind.rawValue.localizedCaseInsensitiveContains(query) }.sorted { $0.copiedAt > $1.copiedAt }
    }
    public mutating func ingest(_ incoming: ClipboardItem, now: Date, sessionRetainedIDs: Set<UUID> = []) throws -> IngestResult {
        guard incoming.payloadByteCount <= settings.captureByteLimit else { throw LibraryError.captureTooLarge }
        var candidate = self
        var removed = candidate.enforceRetention(now: now, sessionRetainedIDs: sessionRetainedIDs)
        if let previousID = lastUserCopyID, let index = candidate.items.firstIndex(where: { $0.id == previousID && $0.fingerprint == incoming.fingerprint }) {
            candidate.items[index].copiedAt = incoming.copiedAt
            candidate.items[index].source = incoming.source
            candidate.items[index].isRecent = true
            removed.formUnion(candidate.enforceRetention(now: now, sessionRetainedIDs: sessionRetainedIDs))
            self = candidate
            return .init(itemID: previousID, inserted: false, removedIDs: removed)
        }
        // Make space before insertion; deliberate saved items and active queue snapshots are protected.
        for item in candidate.items.sorted(by: { $0.copiedAt < $1.copiedAt }) where candidate.managedPayloadBytes + incoming.payloadByteCount > settings.storageByteLimit {
            if !candidate.isSaved(item.id) && !sessionRetainedIDs.contains(item.id) { candidate.items.removeAll { $0.id == item.id }; removed.insert(item.id) }
        }
        guard candidate.managedPayloadBytes + incoming.payloadByteCount <= settings.storageByteLimit else { throw LibraryError.savedStorageFull }
        candidate.items.append(incoming)
        candidate.lastUserCopyID = incoming.id
        removed.formUnion(candidate.enforceRetention(now: now, sessionRetainedIDs: sessionRetainedIDs))
        self = candidate
        return .init(itemID: incoming.id, inserted: true, removedIDs: removed)
    }
    @discardableResult public mutating func enforceRetention(now: Date, sessionRetainedIDs: Set<UUID> = [], endingSession: Bool = false) -> Set<UUID> {
        for index in items.indices {
            let expired = settings.retention.duration.map { now.timeIntervalSince(items[index].copiedAt) >= $0 } ?? endingSession
            if expired { items[index].isRecent = false }
        }
        let eligible = items.filter { $0.isRecent && !isSaved($0.id) }.sorted { $0.copiedAt > $1.copiedAt }
        let excess = Set(eligible.dropFirst(max(0, settings.recentLimit)).map(\.id))
        for index in items.indices where excess.contains(items[index].id) { items[index].isRecent = false }
        var removed = Set(items.filter { !$0.isRecent && !isSaved($0.id) && !sessionRetainedIDs.contains($0.id) }.map(\.id))
        items.removeAll { removed.contains($0.id) }
        for item in items.sorted(by: { $0.copiedAt < $1.copiedAt }) where managedPayloadBytes > settings.storageByteLimit {
            if !isSaved(item.id) && !sessionRetainedIDs.contains(item.id) { items.removeAll { $0.id == item.id }; removed.insert(item.id) }
        }
        return removed
    }
    @discardableResult public mutating func setPinned(_ id: UUID, _ pinned: Bool, now: Date) throws -> Set<UUID> {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingItem }
        items[index].isPinned = pinned
        var removed = reconcileReleased(id, now: now)
        removed.formUnion(enforceRetention(now: now))
        return removed
    }
    @discardableResult public mutating func createStack(name: String, itemIDs: [UUID]) throws -> UUID {
        guard itemIDs.allSatisfy({ id in items.contains { $0.id == id } }) else { throw LibraryError.missingItem }
        guard Set(itemIDs).count == itemIDs.count else { throw LibraryError.invalidOrder }
        let stack = SavedStack(name: name, memberships: itemIDs.map { .init(itemID: $0) }); stacks.append(stack); return stack.id
    }
    public mutating func renameStack(_ id: UUID, name: String) throws { guard let index = stacks.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingStack }; stacks[index].name = name }
    public mutating func reorderStack(_ id: UUID, itemIDs: [UUID]) throws {
        guard let index = stacks.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingStack }
        let existing = stacks[index].memberships
        guard itemIDs.count == existing.count, Set(itemIDs) == Set(existing.map(\.itemID)), Set(itemIDs).count == itemIDs.count else { throw LibraryError.invalidOrder }
        stacks[index].memberships = itemIDs.map { id in existing.first { $0.itemID == id }! }
    }
    public mutating func setMemberships(_ id: UUID, memberships: [StackMembership], now: Date) throws -> Set<UUID> {
        guard let index = stacks.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingStack }
        guard Set(memberships.map(\.itemID)).count == memberships.count else { throw LibraryError.invalidOrder }
        guard memberships.allSatisfy({ member in items.contains { $0.id == member.itemID } }) else { throw LibraryError.missingItem }
        let oldIDs = Set(stacks[index].memberships.map(\.itemID)); stacks[index].memberships = memberships
        var removed = Set<UUID>(); for id in oldIDs.subtracting(memberships.map(\.itemID)) { removed.formUnion(reconcileReleased(id, now: now)) }; return removed
    }
    @discardableResult public mutating func deleteStack(_ id: UUID, now: Date) -> Set<UUID> {
        let ids = affectedItemIDs(stack: id); stacks.removeAll { $0.id == id }
        var removed = Set<UUID>(); for itemID in ids { removed.formUnion(reconcileReleased(itemID, now: now)) }; return removed
    }
    private func affectedItemIDs(stack id: UUID) -> [UUID] { stacks.first { $0.id == id }?.memberships.map(\.itemID) ?? [] }
    private mutating func reconcileReleased(_ id: UUID, now: Date) -> Set<UUID> {
        guard !isSaved(id), let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        let alive = settings.retention.duration.map { now.timeIntervalSince(items[index].copiedAt) < $0 } ?? true
        items[index].isRecent = alive
        return enforceRetention(now: now)
    }
    @discardableResult public mutating func clearRecent(sessionRetainedIDs: Set<UUID> = []) -> Set<UUID> {
        for index in items.indices { items[index].isRecent = false }
        let removed = Set(items.filter { !isSaved($0.id) && !sessionRetainedIDs.contains($0.id) }.map(\.id)); items.removeAll { removed.contains($0.id) }; return removed
    }
    /// RAM-only history keeps unsaved payloads within the session memory budget, oldest first.
    @discardableResult public mutating func trimUnsavedRAM(budget: Int) -> Set<UUID> {
        let unsaved = items.filter { !isSaved($0.id) }
        var bytes = unsaved.reduce(0) { $0 + $1.payloadByteCount }
        var removed = Set<UUID>()
        for item in unsaved.sorted(by: { $0.copiedAt < $1.copiedAt }) where bytes > budget {
            deleteEverywhere(item.id); bytes -= item.payloadByteCount; removed.insert(item.id)
        }
        return removed
    }
    public mutating func deleteEverywhere(_ id: UUID) {
        items.removeAll { $0.id == id }; for index in stacks.indices { stacks[index].memberships.removeAll { $0.itemID == id } }; if lastUserCopyID == id { lastUserCopyID = nil }
    }
    @discardableResult public mutating func deleteAll() -> Set<UUID> { let ids = Set(items.map(\.id)); items.removeAll(); stacks.removeAll(); lastUserCopyID = nil; return ids }
    public func persistentSnapshot() -> LibraryState {
        var snapshot = self
        if settings.retention == .ramOnly { snapshot.items = items.filter { isSaved($0.id) }; for index in snapshot.items.indices { snapshot.items[index].isRecent = false }; snapshot.lastUserCopyID = nil }
        return snapshot
    }
}
