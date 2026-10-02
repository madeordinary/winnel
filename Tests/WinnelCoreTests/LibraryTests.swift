import XCTest
@testable import WinnelCore

final class LibraryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100_000)
    private func item(_ text: String, age: TimeInterval = 0, bytes: Int = 10) -> ClipboardItem { .init(copiedAt: now.addingTimeInterval(-age), kind: .text, textPreview: text, payloadByteCount: bytes, fingerprint: text) }
    func testSharedMembershipAndExpiredFinalReference() throws {
        let clip = item("saved", age: 90_000)
        var state = LibraryState(items: [clip])
        let first = try state.createStack(name: "First", itemIDs: [clip.id]); let second = try state.createStack(name: "Second", itemIDs: [clip.id])
        XCTAssertTrue(state.enforceRetention(now: now).isEmpty)
        XCTAssertFalse(state.items[0].isRecent)
        XCTAssertTrue(state.deleteStack(first, now: now).isEmpty)
        XCTAssertEqual(state.deleteStack(second, now: now), [clip.id])
        XCTAssertTrue(state.items.isEmpty)
    }
    func testClearRecentKeepsSavedAndGlobalDeletionRemovesAllMemberships() throws {
        let saved = item("saved"), recent = item("recent")
        var state = LibraryState(items: [saved, recent]); _ = try state.createStack(name: "One", itemIDs: [saved.id]); _ = try state.createStack(name: "Two", itemIDs: [saved.id])
        XCTAssertEqual(state.clearRecent(), [recent.id]); XCTAssertEqual(state.items.map(\.id), [saved.id]); XCTAssertTrue(state.recentItems.isEmpty)
        state.deleteEverywhere(saved.id); XCTAssertTrue(state.stacks.allSatisfy { $0.memberships.isEmpty })
    }
    func testCountAndBudgetNeverEvictSavedAndRejectionIsTransactional() throws {
        let saved = item("saved", age: 100, bytes: 80), old = item("old", age: 30), new = item("new")
        var settings = Settings(); settings.recentLimit = 1; settings.storageByteLimit = 100
        var state = LibraryState(items: [saved, old, new], settings: settings); try state.setPinned(saved.id, true, now: now)
        XCTAssertTrue(state.items.contains { $0.id == saved.id }); XCTAssertFalse(state.items.contains { $0.id == old.id })
        let before = state
        XCTAssertThrowsError(try state.ingest(item("too much", bytes: 30), now: now)) { XCTAssertEqual($0 as? LibraryError, .savedStorageFull) }
        XCTAssertEqual(state, before)
    }
    func testConsecutiveDedupLatestActualCopyAndRepresentationIdentity() throws {
        let clip = item("same", age: 100)
        var state = LibraryState(items: [clip], lastUserCopyID: clip.id)
        let result = try state.ingest(item("same"), now: now)
        XCTAssertFalse(result.inserted); XCTAssertEqual(result.itemID, clip.id); XCTAssertEqual(state.items[0].copiedAt, now)
        let plain = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("hello".utf8))])
        let rich = ClipPayload(representations: plain.representations + [.init(type: "public.rtf", data: Data("rich".utf8))])
        XCTAssertNotEqual(plain.fingerprint, rich.fingerprint)
        XCTAssertNotEqual(ClipPayload(fileReferences: [.init(urlString: "file:///one", displayName: "same")]).fingerprint, ClipPayload(fileReferences: [.init(urlString: "file:///two", displayName: "same")]).fingerprint)
    }
    func testRAMOnlySnapshotAndQueueRetentionDoNotBecomePersistent() throws {
        let saved = item("saved"), queued = item("queued")
        var settings = Settings(); settings.retention = .ramOnly
        var state = LibraryState(items: [saved, queued], settings: settings); try state.setPinned(saved.id, true, now: now)
        XCTAssertEqual(state.persistentSnapshot().items.map(\.id), [saved.id])
        XCTAssertTrue(state.enforceRetention(now: now, sessionRetainedIDs: [queued.id], endingSession: true).isEmpty)
        XCTAssertEqual(state.enforceRetention(now: now, endingSession: true), [queued.id])
    }
    func testAgeBoundaryUsesCopyTimeAndSevenDayOption() {
        let boundary = item("boundary", age: 3600), younger = item("young", age: 3599)
        var settings = Settings(); settings.retention = .oneHour
        var state = LibraryState(items: [boundary, younger], settings: settings)
        XCTAssertEqual(state.enforceRetention(now: now), [boundary.id])
        XCTAssertEqual(state.search("young").map(\.id), [younger.id])
        XCTAssertEqual(state.enforceRetention(now: now.addingTimeInterval(1)), [younger.id])
        settings.retention = .sevenDays
        state = LibraryState(items: [item("day old", age: 86400)], settings: settings)
        XCTAssertTrue(state.enforceRetention(now: now).isEmpty)
    }
    func testReorderPreservesAssociatedURLAndRejectsInvalidPermutation() throws {
        let a = item("a"), b = item("b"); var state = LibraryState(items: [a, b])
        let stack = try state.createStack(name: "ordered", itemIDs: [a.id, b.id])
        _ = try state.setMemberships(stack, memberships: [.init(itemID: a.id, associatedURL: "https://example.com"), .init(itemID: b.id)], now: now)
        try state.reorderStack(stack, itemIDs: [b.id, a.id])
        XCTAssertEqual(state.stacks[0].memberships[1].associatedURL, "https://example.com")
        XCTAssertThrowsError(try state.reorderStack(stack, itemIDs: [a.id, a.id]))
    }
    func testUnsaveReturnsStillYoungClearedItemToRecent() throws {
        let clip = item("young"); var state = LibraryState(items: [clip]); try state.setPinned(clip.id, true, now: now); state.clearRecent(); try state.setPinned(clip.id, false, now: now)
        XCTAssertEqual(state.recentItems.map(\.id), [clip.id])
    }
}
