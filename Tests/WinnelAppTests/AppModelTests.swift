import XCTest
import AppKit
@testable import WinnelApp
import WinnelCore
import WinnelPlatform

final class AppModelTests: XCTestCase, @unchecked Sendable {
    @MainActor private func settle(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
    @MainActor func testFixtureStartupDoesNotEnableCaptureOrReadContent() async throws {
        let model = AppModel(fixtureMode: true)
        await model.start()
        XCTAssertFalse(model.state.settings.captureEnabled)
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertEqual(model.captureState, .disabled)
        XCTAssertEqual(model.usageBytes, 0)
        await model.shutdown()
    }
    @MainActor func testRapidEnableDisableDoesNotReactivateMonitor() async throws {
        let model = AppModel(fixtureMode: true)
        await model.start()
        model.enableCapture(); model.disableCapture()
        try await settle { model.status == "Capture is off." }
        XCTAssertFalse(model.state.settings.captureEnabled)
        XCTAssertEqual(model.captureState, .disabled)
        await model.shutdown()
    }
    @MainActor func testExplicitPauseWinsPendingResume() async throws {
        let model = AppModel(fixtureMode: true)
        await model.start(); model.enableCapture()
        try await settle { model.captureState == .active }
        model.resumeCapture(); model.pause(until: nil)
        try await settle { model.state.settings.capturePaused == true }
        XCTAssertEqual(model.captureState, .paused)
        XCTAssertTrue(model.state.settings.captureEnabled)
        await model.shutdown()
    }
    @MainActor func testSerialOnboardingUsesFinalChoices() async throws {
        let model = AppModel(fixtureMode: true)
        await model.start()
        model.finishOnboarding(capture: false, directPaste: false, launchAtLogin: false, updates: false)
        try await settle { model.state.settings.onboardingComplete }
        XCTAssertFalse(model.state.settings.captureEnabled)
        XCTAssertFalse(model.state.settings.updateChecksEnabled)
        XCTAssertEqual(model.captureState, .disabled)
        await model.shutdown()
    }
}

/// Pauses the actual repository at a chosen await rather than relying on wall-clock races.
private actor OperationBarrier {
    private var armed = false
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var calls = 0
    func arm() { armed = true; entered = false; calls = 0 }
    func intercept() async {
        calls += 1
        guard armed else { return }
        armed = false; entered = true
        for waiter in enteredWaiters { waiter.resume() }; enteredWaiters.removeAll()
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitUntilEntered() async { if entered { return }; await withCheckedContinuation { enteredWaiters.append($0) } }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
    func invocationCount() -> Int { calls }
}

extension AppModelTests {
    @MainActor private func controlledModel(payloadGate: OperationBarrier? = nil, mutationGate: OperationBarrier? = nil) async throws -> (AppModel, LibraryRepository, ClipboardItem) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-controller-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let repo = try LibraryRepository(directory: url, provider: FixtureVaultKeys(), beforePayloadRead: { _ in await payloadGate?.intercept() }, beforeMutation: { await mutationGate?.intercept() })
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("synthetic protected content".utf8))])
        let snapshot = try await repo.ingest(payload, source: .init(), now: Date(), sessionIDs: [])
        let item = try XCTUnwrap(snapshot.state.items.first)
        let model = AppModel(fixtureMode: true, repository: repo, pasteboard: NSPasteboard(name: .init("org.madeordinary.winnel.controller-test." + UUID().uuidString)))
        model.state = snapshot.state; model.selectedIDs = [item.id]; model.selectionOrder = [item.id]
        return (model, repo, item)
    }
    @MainActor func testDeleteAllRevokesPendingQueueAndPlaintextCaches() async throws {
        let gate = OperationBarrier(), (model, repo, item) = try await controlledModel(payloadGate: gate)
        model.previewPayload = .init(representations: [.init(type: "public.utf8-plain-text", data: Data("old preview".utf8))])
        model.combinationPreview = "old combination"
        await gate.arm(); model.startQueue(); await gate.waitUntilEntered()
        model.deleteAllData()
        XCTAssertNil(model.queue); XCTAssertNil(model.previewPayload); XCTAssertTrue(model.combinationPreview.isEmpty)
        await gate.release(); await model.waitForContentOperations()
        try await settle { model.state.items.isEmpty }
        XCTAssertNil(model.queue)
        let remaining = try await repo.mutate { _ in }
        XCTAssertFalse(remaining.state.items.contains { $0.id == item.id })
        await model.shutdown()
    }
    @MainActor func testDeleteEverywhereRevokesPendingPreviewAndCombination() async throws {
        let gate = OperationBarrier(), (model, _, item) = try await controlledModel(payloadGate: gate)
        await gate.arm(); model.loadPreview(item.id); await gate.waitUntilEntered()
        model.prepareCombination(format: .newline)
        model.deleteEverywhere(item.id)
        await gate.release(); await model.waitForContentOperations()
        try await settle { model.state.items.isEmpty }
        XCTAssertNil(model.previewPayload); XCTAssertTrue(model.combinationPreview.isEmpty)
        await model.shutdown()
    }
    @MainActor func testLockRevokesPendingCopyWithoutChangingNewerFixtureClipboard() async throws {
        let gate = OperationBarrier(), (model, _, _) = try await controlledModel(payloadGate: gate)
        let approved = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("new synthetic user copy".utf8))])
        XCTAssertTrue(model.pasteboardService.write(approved))
        let count = model.pasteboardService.changeCount
        await gate.arm(); model.copySelected(); await gate.waitUntilEntered()
        model.handleLifecycleSuspension()
        await gate.release(); await model.waitForContentOperations()
        XCTAssertEqual(model.pasteboardService.changeCount, count)
        XCTAssertEqual(model.pasteboardService.pasteboard.string(forType: .string), "new synthetic user copy")
        XCTAssertEqual(model.captureState, .suspended)
        await model.shutdown()
    }
    @MainActor func testCancelQueueAndRecoveryRevokePendingLoads() async throws {
        let gate = OperationBarrier(), (model, _, _) = try await controlledModel(payloadGate: gate)
        await gate.arm(); model.startQueue(); await gate.waitUntilEntered(); model.cancelQueue()
        await gate.release(); await model.waitForContentOperations(); XCTAssertNil(model.queue)
        await gate.arm(); model.prepareCombination(format: .newline); await gate.waitUntilEntered()
        model.retryStorage()
        await gate.release(); await model.waitForContentOperations()
        XCTAssertTrue(model.combinationPreview.isEmpty)
        try await settle { model.status == "Storage reopened. Resume capture when ready." }
        await model.shutdown()
    }
    @MainActor func testShutdownRevokesPendingQueue() async throws {
        let gate = OperationBarrier(), (model, _, _) = try await controlledModel(payloadGate: gate)
        await gate.arm(); model.startQueue(); await gate.waitUntilEntered()
        let shutdown = Task { await model.shutdown() }
        try await settle { model.isShuttingDown }
        await gate.release(); await shutdown.value; await model.waitForContentOperations()
        XCTAssertNil(model.queue); XCTAssertNil(model.previewPayload); XCTAssertTrue(model.combinationPreview.isEmpty)
    }
    @MainActor func testRapidSettingsMergeRetainsBothChoicesAndFinalToggle() async throws {
        let gate = OperationBarrier(), (model, repo, _) = try await controlledModel(mutationGate: gate)
        await gate.arm()
        var first = model.state.settings; first.retention = .sevenDays; first.updateChecksEnabled = true
        model.updateSettings(first)
        await gate.waitUntilEntered()
        var second = model.state.settings; second.excludedBundleIdentifiers = ["synthetic.excluded"]; second.updateChecksEnabled = false
        model.updateSettings(second)
        await gate.release()
        try await settle { model.state.settings.excludedBundleIdentifiers == ["synthetic.excluded"] }
        let snapshot = try await repo.mutate { _ in }
        XCTAssertEqual(snapshot.state.settings.retention, .sevenDays)
        XCTAssertEqual(snapshot.state.settings.excludedBundleIdentifiers, ["synthetic.excluded"])
        XCTAssertFalse(snapshot.state.settings.updateChecksEnabled)
        await model.shutdown()
    }
    @MainActor func testSettingsAndResumeCannotEnableCaptureWhileSuspended() async throws {
        let (model, _, _) = try await controlledModel()
        model.enableCapture(); try await settle { model.captureState == .active }
        model.handleLifecycleSuspension()
        var settings = model.state.settings; settings.retention = .sevenDays
        model.updateSettings(settings); model.resumeCapture()
        try await settle { model.state.settings.retention == .sevenDays }
        XCTAssertEqual(model.captureState, .suspended)
        model.resumeAfterWake(); try await settle { model.captureState == .active }
        await model.shutdown()
    }
    @MainActor func testPausedCaptureWaitingForRepositoryNeverCommits() async throws {
        let gate = OperationBarrier(), (model, repo, _) = try await controlledModel(mutationGate: gate)
        model.enableCapture(); try await settle { model.captureState == .active }
        await gate.arm()
        let blocker = Task { try await repo.mutate { _ in } }
        await gate.waitUntilEntered()
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("must not persist after pause".utf8))])
        model.monitor.onCapture(payload, .init())
        let deadline = Date().addingTimeInterval(5)
        while await repo.queuedTransactionCount == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let queued = await repo.queuedTransactionCount
        XCTAssertGreaterThan(queued, 0, "The capture must reach the blocked repository transaction before pause")
        model.pause(until: nil)
        await gate.release(); _ = try await blocker.value
        try await settle { model.state.settings.capturePaused == true }
        let snapshot = try await repo.mutate { _ in }
        XCTAssertEqual(snapshot.state.items.count, 1)
        XCTAssertFalse(snapshot.state.items.contains { $0.textPreview == "must not persist after pause" })
        XCTAssertEqual(model.captureState, .paused)
        XCTAssertNotEqual(model.status, "Capture active.")
        await model.shutdown()
    }

    @MainActor func testSelectedPasteCancelsWhenClipboardChangesDuringDismissal() async throws {
        let (model, _, _) = try await controlledModel()
        let board = model.pasteboardService.pasteboard
        model.onDismissPalette = { board.clearContents(); board.setString("newer synthetic copy", forType: .string) }
        model.pasteSelected()
        await model.waitForContentOperations()
        XCTAssertEqual(board.string(forType: .string), "newer synthetic copy")
        XCTAssertTrue(model.status.hasPrefix("Clipboard changed. Paste canceled"))
        await model.shutdown()
    }
    @MainActor func testCombinedPasteCancelsWhenClipboardChangesDuringDismissal() async throws {
        let (model, _, _) = try await controlledModel()
        let board = model.pasteboardService.pasteboard
        model.combinationPreview = "exact synthetic preview"
        model.onDismissPalette = { board.clearContents(); board.setString("newer synthetic copy", forType: .string) }
        model.pasteCombination()
        await model.waitForContentOperations()
        XCTAssertEqual(board.string(forType: .string), "newer synthetic copy")
        XCTAssertTrue(model.status.hasPrefix("Clipboard changed. Paste canceled"))
        await model.shutdown()
    }

    @MainActor private func addSecondSelection(_ model: AppModel, repo: LibraryRepository, first: ClipboardItem) async throws {
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("second synthetic item".utf8))])
        let snapshot = try await repo.ingest(payload, source: .init(), now: Date(), sessionIDs: [])
        let second = try XCTUnwrap(snapshot.state.items.first { $0.id != first.id })
        model.state = snapshot.state
        model.selectedIDs = [first.id, second.id]; model.selectionOrder = [first.id, second.id]
    }

    @MainActor func testRepeatedCombinationRequestsOnlyLoadLatestSelectionAfterBlockedPredecessor() async throws {
        let gate = OperationBarrier(), (model, repo, first) = try await controlledModel(payloadGate: gate)
        try await addSecondSelection(model, repo: repo, first: first)
        await gate.arm(); model.prepareCombination(format: .newline); await gate.waitUntilEntered()
        for _ in 0..<10 { model.prepareCombination(format: .bullets) }
        model.prepareCombination(format: .numbered)
        await gate.release(); await model.waitForContentOperations()
        let reads = await gate.invocationCount()
        XCTAssertEqual(reads, 3, "One canceled in-flight read plus only the latest two-item selection")
        XCTAssertEqual(model.combinationPreview, "1. synthetic protected content\n2. second synthetic item")
        XCTAssertEqual(model.combinationFormat, .numbered)
        await model.shutdown()
    }

    @MainActor func testRepeatedPreviewRequestsDoNotQueueObsoletePayloadLoads() async throws {
        let gate = OperationBarrier(), (model, _, item) = try await controlledModel(payloadGate: gate)
        await gate.arm(); model.loadPreview(item.id); await gate.waitUntilEntered()
        for _ in 0..<10 { model.loadPreview(item.id) }
        await gate.release(); await model.waitForContentOperations()
        let reads = await gate.invocationCount()
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(model.previewPayload?.plainText, "synthetic protected content")
        await model.shutdown()
    }

    @MainActor func testRepeatedQueuePreparationOnlyLoadsLatestModeAndSelection() async throws {
        let gate = OperationBarrier(), (model, repo, first) = try await controlledModel(payloadGate: gate)
        try await addSecondSelection(model, repo: repo, first: first)
        await gate.arm(); model.startQueue(mode: .copy); await gate.waitUntilEntered()
        for _ in 0..<10 { model.startQueue(mode: .copy) }
        model.startQueue(mode: .paste)
        await gate.release(); await model.waitForContentOperations()
        let reads = await gate.invocationCount()
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(model.queue?.mode, .paste)
        XCTAssertEqual(model.queue?.entries.map(\.item.id), model.selectionOrder)
        await model.shutdown()
    }

    @MainActor func testSuspensionStopsRepeatedExportPreparationBeforeAnyChooserOrLaterRead() async throws {
        let gate = OperationBarrier(), (model, repo, first) = try await controlledModel(payloadGate: gate)
        try await addSecondSelection(model, repo: repo, first: first)
        await gate.arm(); model.exportSelection(format: .markdown, includeImages: false); await gate.waitUntilEntered()
        for _ in 0..<10 { model.exportSelection(format: .json, includeImages: false) }
        model.handleLifecycleSuspension()
        let status = model.status
        await gate.release(); await model.waitForContentOperations()
        let reads = await gate.invocationCount()
        XCTAssertEqual(reads, 1, "No canceled export may read the next item or reach a chooser")
        XCTAssertEqual(model.status, status)
        XCTAssertEqual(model.captureState, .suspended)
        await model.shutdown()
    }

}
