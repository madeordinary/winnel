import XCTest
import AppKit
import WinnelCore
@testable import WinnelPlatform

private final class ChangingProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    enum Change: Sendable { case replace, marker }
    let change: Change
    private let lock = NSLock()
    private var requests = 0
    var requestCount: Int { lock.withLock { requests } }
    init(_ change: Change) { self.change = change }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        lock.withLock { requests += 1 }
        // AppKit may invoke the provider on either its owner thread or the reader.
        // All owner-side AppKit objects are accessed on main, never handed to the actor.
        let supply = {
            item.setData(Data("provider fixture".utf8), forType: type)
            guard let pasteboard else { return }
            switch self.change {
            case .replace:
                pasteboard.clearContents()
                pasteboard.setString("replacement fixture", forType: .string)
            case .marker:
                item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            }
        }
        if Thread.isMainThread { supply() } else { DispatchQueue.main.sync(execute: supply) }
    }
}

final class CaptureRaceTests: XCTestCase {
    @MainActor func testProviderReplacementDuringReadIsDiscarded() async {
        await exerciseProvider(.replace)
    }
    @MainActor func testProviderConcealedMarkerDuringReadIsDiscarded() async {
        await exerciseProvider(.marker)
    }
    @MainActor private func exerciseProvider(_ change: ChangingProvider.Change) async {
        let board = NSPasteboard(name: .init("winnel-provider-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let provider = ChangingProvider(change)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [.string]))
        board.clearContents()
        XCTAssertTrue(board.writeObjects([item]))
        let reader = PasteboardSnapshotReader(name: board.name.rawValue)
        let result = await reader.read(policy: .init(), source: .init(), excluded: [], previousForegroundID: nil)
        XCTAssertGreaterThan(provider.requestCount, 0, "The real provider must have supplied a representation")
        switch result {
        case .skipped(.changed), .skipped(.marker): break
        default: XCTFail("Provider mutation must discard the whole snapshot: \(result)")
        }
        withExtendedLifetime(provider) {}
    }
    @MainActor func testExcludedProviderIsNeverRequested() async {
        let board = NSPasteboard(name: .init("winnel-excluded-provider-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let provider = ChangingProvider(.replace)
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setDataProvider(provider, forTypes: [.string]))
        board.clearContents(); XCTAssertTrue(board.writeObjects([item]))
        let reader = PasteboardSnapshotReader(name: board.name.rawValue)
        let result = await reader.read(policy: .init(), source: .init(bundleIdentifier: "fixture.excluded"), excluded: ["fixture.excluded"], previousForegroundID: nil)
        if case .skipped(.excluded) = result {} else { XCTFail("Excluded source must be skipped") }
        XCTAssertEqual(provider.requestCount, 0)
    }
    @MainActor func testTimedNamedBoardCaptureProbe() async throws {
        for cadence in [50, 250, 1250] {
            let board = NSPasteboard(name: .init("winnel-cadence-\(UUID().uuidString)"))
            var captured: [String] = []
            let monitor = CaptureMonitor(service: .init(pasteboard: board), onCapture: { payload, _ in captured.append(payload.plainText ?? "") })
            monitor.enable()
            let started = Date()
            for index in 0..<20 {
                board.clearContents()
                XCTAssertTrue(board.setString("cadence-\(cadence)-\(index)", forType: .string))
                try await Task.sleep(for: .milliseconds(cadence))
            }
            try await Task.sleep(for: .milliseconds(1800))
            let allowed = Set((0..<20).map { "cadence-\(cadence)-\($0)" })
            XCTAssertTrue(captured.allSatisfy { allowed.contains($0) })
            XCTAssertLessThanOrEqual(captured.count, 20)
            XCTAssertEqual(Set(captured).count, captured.count)
            board.clearContents()
            board.declareTypes([.string, PasteboardService.ownMarker], owner: nil)
            board.setString("forbidden own fixture", forType: .string)
            let beforeForbidden = captured.count
            try await Task.sleep(for: .milliseconds(1500))
            XCTAssertEqual(captured.count, beforeForbidden)
            print("CAPTURE_PROBE cadence_ms=\(cadence) produced=20 captured=\(beforeForbidden) misses=\(20-beforeForbidden) elapsed_s=\(Date().timeIntervalSince(started))")
            monitor.stop()
            board.releaseGlobally()
        }
    }
}
