import XCTest
import Foundation
@testable import WinnelApp
import WinnelCore
import WinnelStorage

final class LibraryRepositoryTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-repository-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func text(_ value: String) -> ClipPayload { .init(representations: [.init(type: "public.utf8-plain-text", data: Data(value.utf8))]) }
    func testRAMRecentDoesNotReachDiskAndPinPromotesBeforeUnpin() async throws {
        let url = try directory(), keys = FixtureVaultKeys()
        let repo = try LibraryRepository(directory: url, provider: keys)
        _ = try await repo.mutate { $0.settings.retention = .ramOnly }
        let payload = text("synthetic RAM recent secret")
        let snapshot = try await repo.ingest(payload, source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(snapshot.state.items.first?.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), ["manifest.sealed"])
        _ = try await repo.mutate { _ = try $0.setPinned(id, true, now: Date()) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent(id.uuidString.lowercased() + ".sealed").path))
        let promotedMemoryIDs = await repo.memoryPayloadIDs
        XCTAssertFalse(promotedMemoryIDs.contains(id), "Promoted saved payloads must leave the RAM-only cache")
        _ = try await repo.mutate { _ = try $0.setPinned(id, false, now: Date()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent(id.uuidString.lowercased() + ".sealed").path))
        let released = try await repo.payload(id)
        XCTAssertEqual(released, payload)
        let releasedMemoryIDs = await repo.memoryPayloadIDs
        XCTAssertTrue(releasedMemoryIDs.contains(id))
    }
    func testFinalStackReleaseMovesPayloadToRAM() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys())
        _ = try await repo.mutate { $0.settings.retention = .ramOnly }
        let snapshot = try await repo.ingest(text("stack release fixture"), source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(snapshot.state.items.first?.id)
        let saved = try await repo.mutate { _ = try $0.createStack(name: "fixture stack", itemIDs: [id]) }
        let stack = try XCTUnwrap(saved.state.stacks.first?.id)
        _ = try await repo.mutate { _ = $0.deleteStack(stack, now: Date()) }
        let released = try await repo.payload(id)
        XCTAssertEqual(released.plainText, "stack release fixture")
    }
    func testSwitchFromRAMToDiskAndBackPurgesUnsaved() async throws {
        let url = try directory(), repo = try LibraryRepository(directory: url, provider: FixtureVaultKeys())
        _ = try await repo.mutate { $0.settings.retention = .ramOnly }
        let snapshot = try await repo.ingest(text("transition fixture"), source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(snapshot.state.items.first?.id), filename = id.uuidString.lowercased() + ".sealed"
        _ = try await repo.mutate { $0.settings.retention = .oneDay }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent(filename).path))
        _ = try await repo.mutate { $0.settings.retention = .ramOnly; _ = $0.clearRecent() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent(filename).path))
    }
    func testConcurrentMutationsNeverLoseSavedChanges() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys())
        _ = try await repo.load(now: Date())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 { group.addTask { _ = try await repo.mutate { _ = try $0.createStack(name: "fixture \(index)", itemIDs: []) } } }
            try await group.waitForAll()
        }
        let snapshot = try await repo.mutate { _ in }
        XCTAssertEqual(snapshot.state.stacks.count, 30)
        XCTAssertEqual(Set(snapshot.state.stacks.map(\.name)).count, 30)
    }
    func testSearchMatchesTextAfterMetadataTruncation() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys())
        let payload = text(String(repeating: "a", count: 20_000) + " tailneedle")
        _ = try await repo.ingest(payload, source: .init(), now: Date(), sessionIDs: [])
        let matches = try await repo.search("tailneedle")
        XCTAssertEqual(matches.count, 1)
        XCTAssertFalse(matches[0].searchText.contains("tailneedle"))
    }
    func testStartupExpirationHappensBeforeResults() async throws {
        let url = try directory(), keys = FixtureVaultKeys()
        let now = Date()
        do {
            let repo = try LibraryRepository(directory: url, provider: keys)
            _ = try await repo.ingest(text("old fixture"), source: .init(), now: now.addingTimeInterval(-3_600), sessionIDs: [])
            _ = try await repo.mutate { $0.settings.retention = .oneHour }
        }
        let reopened = try LibraryRepository(directory: url, provider: keys)
        let snapshot = try await reopened.load(now: now)
        XCTAssertTrue(snapshot.state.items.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), ["manifest.sealed"])
    }
    func testRAMRecentCannotReviveAfterReopen() async throws {
        let url = try directory(), keys = FixtureVaultKeys()
        do {
            let repo = try LibraryRepository(directory: url, provider: keys)
            _ = try await repo.mutate { $0.settings.retention = .ramOnly }
            _ = try await repo.ingest(text("ephemeral fixture"), source: .init(), now: Date(), sessionIDs: [])
        }
        let reopened = try LibraryRepository(directory: url, provider: keys)
        let snapshot = try await reopened.load(now: Date())
        XCTAssertTrue(snapshot.state.items.isEmpty)
    }
    func testRecoveryReloadKeepsCurrentSessionRAMHistoryAndPayload() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys())
        _ = try await repo.load(now: Date())
        _ = try await repo.mutate { $0.settings.retention = .ramOnly }
        let payload = text("recovery RAM fixture")
        let captured = try await repo.ingest(payload, source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(captured.state.items.first?.id)
        let reopened = try await repo.load(now: Date())
        XCTAssertEqual(reopened.state.recentItems.map(\.id), [id])
        let restored = try await repo.payload(id)
        XCTAssertEqual(restored, payload)
        let memoryIDs = await repo.memoryPayloadIDs
        XCTAssertEqual(memoryIDs, [id])
    }

}

private actor CaptureAuthorizationCounter {
    private var calls = 0
    func allowsThroughEvictionCommitChecks() -> Bool { calls += 1; return calls <= 6 }
}
extension LibraryRepositoryTests {
    func testActualEncryptedCapacityEvictsOldestEligibleRecentAndRetries() async throws {
        let url = try directory()
        let repo = try LibraryRepository(directory: url, provider: FixtureVaultKeys(), vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        let first = try await repo.ingest(text(String(repeating: "a", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let firstID = try XCTUnwrap(first.state.items.first?.id)
        let second = try await repo.ingest(text(String(repeating: "b", count: 1_500)), source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        let secondID = try XCTUnwrap(second.state.items.first { $0.id != firstID }?.id)
        let third = try await repo.ingest(text(String(repeating: "c", count: 1_500)), source: .init(), now: now.addingTimeInterval(2), sessionIDs: [])
        XCTAssertFalse(third.warning)
        XCTAssertEqual(third.state.items.count, 2)
        XCTAssertFalse(third.state.items.contains { $0.id == firstID })
        XCTAssertTrue(third.state.items.contains { $0.id == secondID })
        XCTAssertTrue(third.state.items.contains { $0.searchText.hasPrefix("ccc") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent(firstID.uuidString.lowercased() + ".sealed").path))
        for item in third.state.items { _ = try await repo.payload(item.id) }
        XCTAssertLessThanOrEqual(third.usage, 16 * 1024)
    }
    func testCapacityEvictionNeverDeletesPinOrSessionProtectedItem() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys(), vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        let first = try await repo.ingest(text(String(repeating: "p", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let pinnedID = try XCTUnwrap(first.state.items.first?.id)
        _ = try await repo.mutate { _ = try $0.setPinned(pinnedID, true, now: now) }
        let second = try await repo.ingest(text(String(repeating: "q", count: 1_500)), source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        let protectedID = try XCTUnwrap(second.state.items.first { $0.id != pinnedID }?.id)
        do {
            _ = try await repo.ingest(text(String(repeating: "r", count: 1_500)), source: .init(), now: now.addingTimeInterval(2), sessionIDs: [protectedID])
            XCTFail("Saved and session-protected data must not be silently evicted")
        } catch { XCTAssertEqual(error as? VaultError, .storageLimit) }
        let unchanged = try await repo.mutate { _ in }
        XCTAssertEqual(unchanged.state, second.state)
        _ = try await repo.payload(pinnedID); _ = try await repo.payload(protectedID)
        let captured = try await repo.ingest(text(String(repeating: "r", count: 1_500)), source: .init(), now: now.addingTimeInterval(2), sessionIDs: [])
        XCTAssertTrue(captured.state.items.contains { $0.id == pinnedID && $0.isPinned })
        XCTAssertFalse(captured.state.items.contains { $0.id == protectedID })
    }
    func testCaptureFailureAfterCommittedEvictionReturnsAuthoritativeSnapshot() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys(), vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        let first = try await repo.ingest(text(String(repeating: "p", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let pinnedID = try XCTUnwrap(first.state.items.first?.id)
        _ = try await repo.mutate { _ = try $0.setPinned(pinnedID, true, now: now) }
        let second = try await repo.ingest(text(String(repeating: "q", count: 1_500)), source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        do {
            _ = try await repo.ingest(text(String(repeating: "r", count: 4_000)), source: .init(), now: now.addingTimeInterval(2), sessionIDs: [])
            XCTFail("Incoming data cannot fit beside retained saved data")
        } catch let transition as RepositoryTransitionError {
            XCTAssertEqual(transition.cause as? VaultError, .storageLimit)
            XCTAssertGreaterThan(transition.snapshot.revision, second.revision)
            XCTAssertEqual(transition.snapshot.state.items.map(\.id), [pinnedID])
            XCTAssertTrue(transition.snapshot.state.isSaved(pinnedID))
            let current = try await repo.mutate { _ in }
            XCTAssertEqual(current.state, transition.snapshot.state)
            XCTAssertEqual(current.revision, transition.snapshot.revision)
        }
        let saved = try await repo.payload(pinnedID)
        XCTAssertEqual(saved.plainText, String(repeating: "p", count: 1_500))
    }
    func testAuthorizationLossAfterCapacityEvictionDoesNotCaptureIncoming() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys(), vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        _ = try await repo.ingest(text(String(repeating: "a", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let second = try await repo.ingest(text(String(repeating: "b", count: 1_500)), source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        let authorization = CaptureAuthorizationCounter()
        do {
            _ = try await repo.ingest(text(String(repeating: "c", count: 1_500)), source: .init(), now: now.addingTimeInterval(2), sessionIDs: [], isStillAuthorized: { await authorization.allowsThroughEvictionCommitChecks() })
            XCTFail("Authorization revoked after eviction must stop capture")
        } catch let transition as RepositoryTransitionError {
            XCTAssertTrue(transition.cause is CancellationError)
            XCTAssertEqual(transition.snapshot.state.items.count, 1)
            XCTAssertTrue(transition.snapshot.state.items.allSatisfy { $0.searchText.hasPrefix("bbb") })
            XCTAssertGreaterThan(transition.snapshot.revision, second.revision)
            let current = try await repo.mutate { _ in }
            XCTAssertEqual(current.state, transition.snapshot.state)
        }
    }
}
extension LibraryRepositoryTests {
    func testCapacityRetryNeverEvictsConsecutiveDeduplicatedItem() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys(), vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        _ = try await repo.ingest(text(String(repeating: "a", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let existingPayload = text(String(repeating: "b", count: 1_500))
        let second = try await repo.ingest(existingPayload, source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        let dedupID = try XCTUnwrap(second.state.lastUserCopyID)
        do {
            _ = try await repo.ingest(existingPayload, source: .init(name: String(repeating: "source", count: 1_500)), now: now.addingTimeInterval(2), sessionIDs: [])
            XCTFail("Oversized metadata cannot fit even after eligible eviction")
        } catch let transition as RepositoryTransitionError {
            XCTAssertEqual(transition.cause as? VaultError, .storageLimit)
            XCTAssertEqual(transition.snapshot.state.items.map(\.id), [dedupID])
            XCTAssertEqual(transition.snapshot.state.items.first?.copiedAt, now.addingTimeInterval(1))
        }
        let preserved = try await repo.payload(dedupID)
        XCTAssertEqual(preserved, existingPayload)
    }
}

extension LibraryRepositoryTests {
    func testExpiredFormerQueueReferencesCanFreeCapacityAfterSessionRelease() async throws {
        let repo = try LibraryRepository(directory: directory(), provider: FixtureVaultKeys(), vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        _ = try await repo.mutate { $0.settings.retention = .oneHour }
        _ = try await repo.ingest(text(String(repeating: "a", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let second = try await repo.ingest(text(String(repeating: "b", count: 1_500)), source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        let queueIDs = Set(second.state.items.map(\.id))
        let expired = try await repo.mutate { _ = $0.enforceRetention(now: now.addingTimeInterval(3_602), sessionRetainedIDs: queueIDs) }
        XCTAssertTrue(expired.state.items.allSatisfy { !$0.isRecent })
        let captured = try await repo.ingest(text(String(repeating: "c", count: 3_000)), source: .init(), now: now.addingTimeInterval(3_603), sessionIDs: [])
        XCTAssertEqual(captured.state.items.count, 1)
        XCTAssertTrue(captured.state.items[0].searchText.hasPrefix("ccc"))
        XCTAssertTrue(queueIDs.isDisjoint(with: captured.state.items.map(\.id)))
        _ = try await repo.payload(captured.state.items[0].id)
    }
}

private actor RepositoryKeyBarrier: VaultKeyProvider {
    private var calls = 0
    func callCount() -> Int { calls }
    private var remaining: Int?
    private var waiting: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var blocked = false
    func arm(skipping: Int = 0) { remaining = skipping }
    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
    func key(createIfMissing: Bool) async -> Data? {
        calls += 1
        if let count = remaining {
            if count > 0 { remaining = count - 1 }
            else {
                remaining = nil; blocked = true
                await withCheckedContinuation { continuation in
                    waiting = continuation; entered?.resume(); entered = nil
                }
            }
        }
        return Data(repeating: 0x64, count: 32)
    }
}
private actor RepositoryCaptureAuthorization {
    private var allowed = true
    func revoke() { allowed = false }
    func check() -> Bool { allowed }
}
extension LibraryRepositoryTests {
    func testRAMCaptureRevokedAfterInitialCheckDoesNotPublish() async throws {
        actor RevokedAfterFirstCheck {
            private var allowed = true
            func check() -> Bool { defer { allowed = false }; return allowed }
        }
        let url = try directory(), repo = try LibraryRepository(directory: url, provider: FixtureVaultKeys())
        _ = try await repo.mutate { $0.settings.retention = .ramOnly }
        let original = try await repo.ingest(text("existing synthetic RAM item"), source: .init(), now: Date(), sessionIDs: [])
        let beforeIDs = await repo.memoryPayloadIDs
        let manifest = try Data(contentsOf: url.appendingPathComponent("manifest.sealed"))
        let authorization = RevokedAfterFirstCheck()
        do {
            _ = try await repo.ingest(text("revoked synthetic RAM capture"), source: .init(), now: Date(), sessionIDs: [], isStillAuthorized: { await authorization.check() })
            XCTFail("Authorization lost during ingestion must prevent RAM publication")
        } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await repo.mutate { _ in }
        let afterIDs = await repo.memoryPayloadIDs
        XCTAssertEqual(current.state, original.state)
        XCTAssertEqual(current.revision, original.revision)
        XCTAssertEqual(afterIDs, beforeIDs)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.sealed")), manifest)
    }
    func testCaptureRevokedDuringKeyWaitDoesNotPublishOrWriteIncoming() async throws {
        let url = try directory(), keys = RepositoryKeyBarrier()
        let repo = try LibraryRepository(directory: url, provider: keys)
        let saved = try await repo.ingest(text("synthetic saved"), source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(saved.state.items.first?.id)
        let original = try await repo.mutate { _ = try $0.setPinned(id, true, now: Date()) }
        let bytes = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let authorization = RepositoryCaptureAuthorization()
        await keys.arm()
        let capture = Task { try await repo.ingest(self.text("synthetic incoming"), source: .init(), now: Date(), sessionIDs: [], isStillAuthorized: { await authorization.check() }) }
        await keys.waitUntilBlocked(); await authorization.revoke(); await keys.release()
        do { _ = try await capture.value; XCTFail("Revoked capture must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await repo.mutate { _ in }
        XCTAssertEqual(current.state, original.state); XCTAssertEqual(current.revision, original.revision)
        let after = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        XCTAssertEqual(after, bytes)
    }
    func testCapacityEvictionChecksAuthorizationAfterItsKeyWait() async throws {
        let url = try directory(), keys = RepositoryKeyBarrier()
        let repo = try LibraryRepository(directory: url, provider: keys, vaultLimits: .init(payloadBytes: 64 * 1024, manifestBytes: 64 * 1024, totalBytes: 16 * 1024))
        let now = Date()
        _ = try await repo.ingest(text(String(repeating: "a", count: 1_500)), source: .init(), now: now, sessionIDs: [])
        let original = try await repo.ingest(text(String(repeating: "b", count: 1_500)), source: .init(), now: now.addingTimeInterval(1), sessionIDs: [])
        let bytes = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let authorization = RepositoryCaptureAuthorization()
        await keys.arm(skipping: 1) // Incoming attempt reaches capacity; block the eviction transaction's key read.
        let capture = Task { try await repo.ingest(self.text(String(repeating: "c", count: 1_500)), source: .init(), now: now.addingTimeInterval(2), sessionIDs: [], isStillAuthorized: { await authorization.check() }) }
        await keys.waitUntilBlocked(); await authorization.revoke(); await keys.release()
        do { _ = try await capture.value; XCTFail("Revoked eviction must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let current = try await repo.mutate { _ in }
        XCTAssertEqual(current.state, original.state); XCTAssertEqual(current.revision, original.revision)
        let after = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        XCTAssertEqual(after, bytes)
    }
}

extension LibraryRepositoryTests {
    func testCancelledQueuedSearchDoesNotDecryptLongText() async throws {
        let keys = RepositoryKeyBarrier()
        let repo = try LibraryRepository(directory: directory(), provider: keys)
        let original = try await repo.ingest(text(String(repeating: "x", count: 20_000) + "needle"), source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(original.state.items.first?.id)
        let before = await keys.callCount()
        await keys.arm()
        let read = Task { try await repo.payload(id) }
        await keys.waitUntilBlocked()
        let search = Task { try await repo.search("needle") }
        search.cancel()
        await keys.release()
        _ = try await read.value
        do { _ = try await search.value; XCTFail("Cancelled queued search must stop") } catch { XCTAssertTrue(error is CancellationError) }
        let after = await keys.callCount()
        XCTAssertEqual(after, before + 1, "Only the preceding payload read may request the vault key")
    }
    func testCancelledPayloadReadDoesNotReturnStaleResult() async throws {
        let keys = RepositoryKeyBarrier()
        let repo = try LibraryRepository(directory: directory(), provider: keys)
        let original = try await repo.ingest(text("synthetic payload"), source: .init(), now: Date(), sessionIDs: [])
        let id = try XCTUnwrap(original.state.items.first?.id)
        await keys.arm()
        let read = Task { try await repo.payload(id) }
        await keys.waitUntilBlocked(); read.cancel(); await keys.release()
        do { _ = try await read.value; XCTFail("Cancelled read must not return stale payload") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
