import Foundation
import WinnelCore
import WinnelStorage

struct RepositorySnapshot: Sendable {
    var state: LibraryState
    var usage: Int
    var warning: Bool = false
    var revision: Int = 0
}
/// Capacity eviction is its own committed retention transaction. If the subsequent
/// capture fails, callers must adopt this snapshot before reporting the cause.
struct RepositoryTransitionError: Error, Sendable {
    let snapshot: RepositorySnapshot
    let cause: any Error
}
actor FixtureVaultKeys: VaultKeyProvider {
    private let bytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    func key(createIfMissing: Bool) -> Data? { bytes }
}
/// FIFO transaction ownership extends across vault awaits; actor isolation alone would not suffice.
actor LibraryRepository {
    private let vault: EncryptedVault
    private var state = LibraryState()
    private var memoryPayloads: [UUID: ClipPayload] = [:]
    private var revision = 0
    private var hasLoaded = false
    private let beforeMutation: (@Sendable () async -> Void)?
    private let beforePayloadRead: (@Sendable (UUID) async -> Void)?
    var memoryPayloadIDs: Set<UUID> { Set(memoryPayloads.keys) }
    var queuedTransactionCount: Int { waiters.count }
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    static let ramBudget = 64 * 1024 * 1024
    init(directory: URL, provider: any VaultKeyProvider, vaultLimits: VaultLimits = .init(), beforePayloadRead: (@Sendable (UUID) async -> Void)? = nil, beforeMutation: (@Sendable () async -> Void)? = nil) throws { vault = try EncryptedVault(directory: directory, keyProvider: provider, limits: vaultLimits); self.beforePayloadRead = beforePayloadRead; self.beforeMutation = beforeMutation }
    private func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() { if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() } }
    private func payloadUnlocked(_ id: UUID) async throws -> ClipPayload {
        if let payload = memoryPayloads[id] { return payload }
        return try JSONDecoder().decode(ClipPayload.self, from: await vault.readPayload(id: id))
    }
    func payload(_ id: UUID) async throws -> ClipPayload {
        await acquire(); defer { release() }
        try Task.checkCancellation()
        await beforePayloadRead?(id)
        try Task.checkCancellation()
        let payload = try await payloadUnlocked(id)
        try Task.checkCancellation()
        return payload
    }
    func load(now: Date) async throws -> RepositorySnapshot {
        await acquire(); defer { release() }
        let previousState = state
        let previousMemory = memoryPayloads
        do {
            guard let manifest = try await vault.loadManifest() else { hasLoaded = true; return .init(state: state, usage: 0, revision: revision) }
            var loaded = try JSONDecoder().decode(LibraryState.self, from: manifest)
            guard loaded.schemaVersion == LibraryState.currentSchemaVersion else { throw VaultError.unsupportedVersion }
            guard loaded.items.count <= 100_000, Set(loaded.items.map(\.id)).count == loaded.items.count,
                  Set(loaded.stacks.map(\.id)).count == loaded.stacks.count,
                  loaded.items.allSatisfy({ $0.payloadByteCount >= 0 && $0.payloadByteCount <= 20 * 1024 * 1024 }),
                  loaded.stacks.allSatisfy({ stack in Set(stack.memberships.map(\.itemID)).count == stack.memberships.count && stack.memberships.allSatisfy { member in loaded.items.contains { $0.id == member.itemID } } }) else { throw VaultError.corruptData }
            let diskState = loaded
            // Reopening after a recoverable failure is not a new session. Keep RAM-only
            // entries whose payloads still exist in this process; a new repository has none.
            if hasLoaded, previousState.settings.retention == .ramOnly, loaded.settings.retention == .ramOnly {
                let diskIDs = Set(loaded.items.map(\.id))
                loaded.items += previousState.items.filter { !previousState.isSaved($0.id) && previousMemory[$0.id] != nil && !diskIDs.contains($0.id) }
                if let id = previousState.lastUserCopyID, loaded.items.contains(where: { $0.id == id }) { loaded.lastUserCopyID = id }
            }
            loaded.enforceRetention(now: now, endingSession: !hasLoaded && loaded.settings.retention == .ramOnly)
            state = diskState
            let snapshot: RepositorySnapshot
            if loaded != diskState { snapshot = try await save(loaded, additions: [:]) }
            else {
                state = loaded
                let liveIDs = Set(loaded.items.map(\.id)); memoryPayloads = memoryPayloads.filter { liveIDs.contains($0.key) }
                revision += 1; snapshot = .init(state: loaded, usage: try await vault.usageBytes(), revision: revision)
            }
            hasLoaded = true
            return snapshot
        } catch {
            state = previousState; memoryPayloads = previousMemory
            throw error
        }
    }
    private func save(_ candidate: LibraryState, additions: [UUID: ClipPayload], isStillAuthorized: @Sendable () async -> Bool = { true }) async throws -> RepositorySnapshot {
        var candidate = candidate
        if candidate.settings.retention == .ramOnly {
            var bytes = candidate.items.filter { !candidate.isSaved($0.id) }.reduce(0) { $0 + $1.payloadByteCount }
            for item in candidate.items.filter({ !candidate.isSaved($0.id) }).sorted(by: { $0.copiedAt < $1.copiedAt }) where bytes > Self.ramBudget {
                candidate.deleteEverywhere(item.id); bytes -= item.payloadByteCount
            }
        }
        let persisted = candidate.persistentSnapshot()
        let priorIDs = Set(state.persistentSnapshot().items.map(\.id))
        var newPayloads: [UUID: Data] = [:]
        for item in persisted.items where !priorIDs.contains(item.id) {
            let payload: ClipPayload
            if let incoming = additions[item.id] { payload = incoming }
            else { payload = try await payloadUnlocked(item.id) }
            newPayloads[item.id] = try JSONEncoder().encode(payload)
        }
        var nextMemory = memoryPayloads
        let persistentIDs = Set(persisted.items.map(\.id))
        // Release of a final saved reference must move bytes into RAM before GC can unlink them.
        for item in candidate.items where priorIDs.contains(item.id) && !persistentIDs.contains(item.id) {
            nextMemory[item.id] = try await payloadUnlocked(item.id)
        }
        var warning = false
        do { try await vault.commit(manifest: JSONEncoder().encode(persisted), newPayloads: newPayloads, retaining: Set(persisted.items.map(\.id)), isStillAuthorized: isStillAuthorized) }
        catch VaultError.garbageCollectionFailed { warning = true }
        // Publish only once the manifest commit succeeded (including an explicit GC warning).
        for (id, payload) in additions where !persisted.items.contains(where: { $0.id == id }) { nextMemory[id] = payload }
        let memoryIDs = Set(candidate.items.filter { !persistentIDs.contains($0.id) }.map(\.id))
        nextMemory = nextMemory.filter { memoryIDs.contains($0.key) }
        state = candidate; memoryPayloads = nextMemory; hasLoaded = true; revision += 1
        return .init(state: state, usage: (try? await vault.usageBytes()) ?? 0, warning: warning, revision: revision)
    }
    func mutate(_ change: @Sendable (inout LibraryState) throws -> Void) async throws -> RepositorySnapshot {
        await acquire(); defer { release() }
        await beforeMutation?()
        var candidate = state; try change(&candidate)
        if candidate == state { return .init(state: state, usage: try await vault.usageBytes(), revision: revision) }
        // Promote RAM entries before dropping their memory payloads; switching to RAM removes disk recent immediately.
        return try await save(candidate, additions: [:])
    }
    func ingest(_ payload: ClipPayload, source: SourceApplication, now: Date, sessionIDs: Set<UUID>, isStillAuthorized: @Sendable () async -> Bool = { true }) async throws -> RepositorySnapshot {
        await acquire(); defer { release() }
        guard await isStillAuthorized(), !Task.isCancelled else { throw CancellationError() }
        let encoded = try JSONEncoder().encode(payload)
        guard encoded.count <= state.settings.captureByteLimit else { throw LibraryError.captureTooLarge }
        let kind: ClipKind = !payload.fileReferences.isEmpty ? .files : payload.representations.contains(where: { $0.type == "public.url" }) ? .url : payload.representations.contains(where: { ["public.png", "public.tiff", "public.jpeg"].contains($0.type) }) ? .image : payload.representations.contains(where: { $0.type == "public.rtf" }) ? .richText : .text
        let text = payload.plainText ?? payload.fileReferences.map(\.displayName).joined(separator: ", ")
        let preview = kind == .image ? "Image" : text
        let item = ClipboardItem(copiedAt: now, source: source, kind: kind, textPreview: preview, searchText: text, payloadByteCount: encoded.count, fingerprint: payload.fingerprint)
        var candidate = state
        let ingestion = try candidate.ingest(item, now: now, sessionRetainedIDs: sessionIDs)
        if candidate.settings.retention == .ramOnly {
            let unsaved = candidate.items.filter { !candidate.isSaved($0.id) }
            var bytes = unsaved.reduce(0) { $0 + $1.payloadByteCount }
            for old in unsaved.sorted(by: { $0.copiedAt < $1.copiedAt }) where bytes > Self.ramBudget {
                guard !sessionIDs.contains(old.id) else { continue }
                candidate.deleteEverywhere(old.id); bytes -= old.payloadByteCount
            }
            guard bytes <= Self.ramBudget else { throw LibraryError.savedStorageFull }
            // No persistence operation is needed for RAM-only ingestion when saved metadata is unchanged.
            if candidate.persistentSnapshot() == state.persistentSnapshot() {
                guard await isStillAuthorized(), !Task.isCancelled else { throw CancellationError() }
                if candidate.items.contains(where: { $0.id == item.id }) { memoryPayloads[item.id] = payload }
                let keep = Set(candidate.items.map(\.id)); memoryPayloads = memoryPayloads.filter { keep.contains($0.key) }
                state = candidate; hasLoaded = true; revision += 1; return .init(state: state, usage: try await vault.usageBytes(), revision: revision)
            }
        }
        var committedEviction: RepositorySnapshot?
        do {
            while true {
                guard await isStillAuthorized(), !Task.isCancelled else { throw CancellationError() }
                do { return try await save(candidate, additions: [item.id: payload], isStillAuthorized: isStillAuthorized) }
                catch VaultError.storageLimit {
                    // Payload accounting omits metadata, envelopes and transaction reserves.
                    // Free only eligible persisted recent data. A committed eviction is
                    // necessary: staging a replacement cannot spend space not yet reclaimed.
                    let persistentIDs = Set(state.persistentSnapshot().items.map(\.id))
                    let candidateIDs = Set(candidate.items.map(\.id))
                    guard let victim = state.items.filter({
                        ($0.isRecent || !candidateIDs.contains($0.id)) && persistentIDs.contains($0.id) && !state.isSaved($0.id)
                        && !sessionIDs.contains($0.id) && $0.id != ingestion.itemID
                    }).min(by: { $0.copiedAt < $1.copiedAt }) else { throw VaultError.storageLimit }
                    guard await isStillAuthorized(), !Task.isCancelled else { throw CancellationError() }
                    var eviction = state; eviction.deleteEverywhere(victim.id)
                    let snapshot = try await save(eviction, additions: [:], isStillAuthorized: isStillAuthorized)
                    committedEviction = snapshot
                    candidate.deleteEverywhere(victim.id)
                    // A manifest committed but GC failed: no claim that the incoming
                    // capture was accepted, and no further capacity retries until recovery.
                    if snapshot.warning { return snapshot }
                }
            }
        } catch {
            if let snapshot = committedEviction { throw RepositoryTransitionError(snapshot: snapshot, cause: error) }
            throw error
        }
    }
    func search(_ query: String) async throws -> [ClipboardItem] {
        await acquire(); defer { release() }
        try Task.checkCancellation()
        var matches = state.search(query)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return matches }
        var ids = Set(matches.map(\.id))
        for item in state.items where item.searchText.count >= 16_384 && !ids.contains(item.id) {
            try Task.checkCancellation()
            let payload = try await payloadUnlocked(item.id)
            try Task.checkCancellation()
            if let text = payload.plainText, text.localizedCaseInsensitiveContains(query) { matches.append(item); ids.insert(item.id) }
        }
        try Task.checkCancellation()
        return matches.sorted { $0.copiedAt > $1.copiedAt }
    }
    func exportRecovery(to directory: URL) async throws {
        await acquire(); defer { release() }; try await vault.exportEncryptedRecovery(to: directory)
    }
    func reset() async throws -> RepositorySnapshot {
        await acquire(); defer { release() }
        try await vault.reset(); state = LibraryState(settings: state.settings); memoryPayloads.removeAll(); revision += 1
        return .init(state: state, usage: 0, revision: revision)
    }
}
