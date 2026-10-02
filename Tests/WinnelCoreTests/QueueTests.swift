import XCTest
@testable import WinnelCore
final class QueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private func entry(_ text: String) -> QueueEntry { .init(item: .init(copiedAt: now, kind: .text, textPreview: text, payloadByteCount: 1, fingerprint: text), payload: .init(representations: [.init(type: "public.utf8-plain-text", data: Data(text.utf8))])) }
    func testFailureDoesNotAdvanceAndBackRetriesSentEntry() {
        let a = entry("a"), b = entry("b"); var queue = PasteQueue(entries: [a, b], mode: .paste, now: now)
        queue.recordDispatch(success: false, now: now.addingTimeInterval(1)); XCTAssertEqual(queue.current?.id, a.id)
        queue.recordDispatch(success: true, now: now.addingTimeInterval(2)); XCTAssertEqual(queue.current?.id, b.id)
        queue.back(now: now.addingTimeInterval(3)); XCTAssertEqual(queue.current?.id, a.id)
        queue.recordDispatch(success: true, now: now.addingTimeInterval(4)); queue.recordDispatch(success: true, now: now.addingTimeInterval(5)); XCTAssertTrue(queue.isComplete)
        queue.back(now: now.addingTimeInterval(6)); XCTAssertEqual(queue.current?.id, b.id)
    }
    func testIdleAndLifecycleReleaseSessionPayloads() {
        var queue = PasteQueue(entries: [entry("a")], now: now)
        queue.recordDispatch(success: true, now: now.addingTimeInterval(300)); XCTAssertEqual(queue.cancellation, .idle); XCTAssertTrue(queue.entries.isEmpty)
        var active = PasteQueue(entries: [entry("b")], now: now); active.cancel(.lock); XCTAssertTrue(active.retainedIDs.isEmpty)
    }
    func testGlobalDeletionCancelsRetainedSnapshot() {
        let a = entry("a"); var queue = PasteQueue(entries: [a], now: now); queue.removeDeletedItems([a.id]); XCTAssertEqual(queue.cancellation, .deleted)
    }
}
