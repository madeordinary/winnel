import XCTest
import AppKit
import ImageIO
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
    @MainActor func testIdleQueueIsRemovedAtMaintenanceNextAndBackWithoutWritingClipboard() async throws {
        let (model, repo, item) = try await controlledModel()
        let payload = try await repo.payload(item.id)
        let oldDate = Date().addingTimeInterval(-PasteQueue.idleLimit - 1)
        let count = model.pasteboardService.changeCount
        for action in [0, 1, 2] {
            model.queue = .init(entries: [.init(item: item, payload: payload)], mode: .paste, now: oldDate)
            switch action {
            case 0: model.expireQueue()
            case 1: model.nextInQueue()
            default: model.backInQueue()
            }
            await model.waitForContentOperations()
            XCTAssertNil(model.queue)
            XCTAssertEqual(model.status, "Queue cancelled after five minutes without interaction.")
            XCTAssertEqual(model.pasteboardService.changeCount, count)
        }
        await model.shutdown()
    }

    @MainActor func testIdleExpirationRevokesScheduledQueueDispatchAndClearsAlreadyExpiredQueue() async throws {
        let (model, repo, item) = try await controlledModel()
        let payload = try await repo.payload(item.id)
        let now = Date()
        model.queue = .init(entries: [.init(item: item, payload: payload)], now: now)
        let count = model.pasteboardService.changeCount
        model.nextInQueue()
        // Expire before the scheduled main-actor dispatch gets its first turn.
        XCTAssertTrue(model.expireQueue(now: now.addingTimeInterval(PasteQueue.idleLimit + 1)))
        await model.waitForContentOperations()
        XCTAssertNil(model.queue)
        XCTAssertEqual(model.pasteboardService.changeCount, count)
        XCTAssertEqual(model.status, "Queue cancelled after five minutes without interaction.")

        model.queue = .init(entries: [.init(item: item, payload: payload)], now: now)
        model.queue?.interact(now: now.addingTimeInterval(PasteQueue.idleLimit + 1))
        XCTAssertEqual(model.queue?.cancellation, .idle)
        XCTAssertTrue(model.expireQueue(now: now))
        XCTAssertNil(model.queue)
        await model.shutdown()
    }

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
        XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertTrue(model.selectionOrder.isEmpty)
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
        XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertTrue(model.selectionOrder.isEmpty)
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

    @MainActor func testCaptureBackpressureKeepsOnePendingCopyThenAcceptsLaterCopy() async throws {
        let gate = OperationBarrier(), (model, repo, _) = try await controlledModel(mutationGate: gate)
        model.enableCapture(); try await settle { model.captureState == .active }
        await gate.arm()
        let blocker = Task { try await repo.mutate { _ in } }
        await gate.waitUntilEntered()
        let first = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(("first retained synthetic copy " + String(repeating: "a", count: 1_000_000)).utf8))])
        model.monitor.onCapture(first, .init())
        let deadline = Date().addingTimeInterval(5)
        while await repo.queuedTransactionCount == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        for index in 0..<10 {
            let skipped = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(("skipped synthetic copy \(index) " + String(repeating: "b", count: 1_000_000)).utf8))])
            model.monitor.onCapture(skipped, .init())
        }
        let queued = await repo.queuedTransactionCount
        XCTAssertEqual(queued, 1, "Capture backpressure must not queue another retained payload")
        XCTAssertEqual(model.status, "Skipped a clipboard change while the previous capture is saving.")
        await gate.release(); _ = try await blocker.value
        try await settle { model.state.items.contains { $0.fingerprint == first.fingerprint } }
        let committed = try await repo.mutate { _ in }
        XCTAssertEqual(committed.state.items.count, 2)
        XCTAssertFalse(committed.state.items.contains { $0.textPreview.hasPrefix("skipped synthetic copy") })
        let firstItem = try XCTUnwrap(committed.state.items.first { $0.fingerprint == first.fingerprint })
        let stored = try await repo.payload(firstItem.id)
        XCTAssertEqual(stored, first)
        let later = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("later accepted synthetic copy".utf8))])
        model.monitor.onCapture(later, .init())
        try await settle { model.state.items.contains { $0.fingerprint == later.fingerprint } }
        let finished = try await repo.mutate { _ in }
        XCTAssertEqual(finished.state.items.count, 3)
        XCTAssertEqual(finished.state.lastUserCopyID, finished.state.items.first { $0.fingerprint == later.fingerprint }?.id)
        XCTAssertLessThanOrEqual(firstItem.copiedAt, try XCTUnwrap(finished.state.items.first { $0.fingerprint == later.fingerprint }).copiedAt)
        XCTAssertEqual(model.captureState, .active)
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

    @MainActor func testClearRecentPreservesSavedMembershipButClearsSelectionUntilDeliberateReselect() async throws {
        let (model, repo, item) = try await controlledModel()
        let saved = try await repo.mutate {
            _ = try $0.setPinned(item.id, true, now: Date())
            _ = try $0.createStack(name: "synthetic saved selection", itemIDs: [item.id])
        }
        model.state = saved.state
        model.loadPreview(item.id); await model.waitForContentOperations()
        XCTAssertNotNil(model.previewPayload)
        XCTAssertTrue(model.previewThumbnailFinished)
        model.combinationPreview = "synthetic cached combination"
        model.clearRecent()
        XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertTrue(model.selectionOrder.isEmpty)
        XCTAssertNil(model.previewPayload); XCTAssertNil(model.previewThumbnailData)
        XCTAssertFalse(model.previewThumbnailFinished); XCTAssertTrue(model.combinationPreview.isEmpty)
        try await settle { model.state.recentItems.isEmpty }
        XCTAssertEqual(model.state.items.map(\.id), [item.id])
        XCTAssertTrue(model.state.items[0].isPinned)
        XCTAssertEqual(model.state.stacks.first?.memberships.map(\.itemID), [item.id])
        model.selectedIDs = [item.id]; model.selectionOrder = [item.id]
        model.loadPreview(item.id); await model.waitForContentOperations()
        XCTAssertEqual(model.previewPayload?.plainText, "synthetic protected content")
        await model.shutdown()
    }

    @MainActor func testDeletingUnrelatedItemRevokesSelectionAndCachedPreview() async throws {
        let (model, repo, selected) = try await controlledModel()
        try await addSecondSelection(model, repo: repo, first: selected)
        let unrelated = try XCTUnwrap(model.state.items.first { $0.id != selected.id })
        model.selectedIDs = [selected.id]; model.selectionOrder = [selected.id]
        model.loadPreview(selected.id); await model.waitForContentOperations()
        XCTAssertNotNil(model.previewPayload)
        model.deleteEverywhere(unrelated.id)
        XCTAssertTrue(model.selectedIDs.isEmpty); XCTAssertTrue(model.selectionOrder.isEmpty)
        XCTAssertNil(model.previewPayload); XCTAssertFalse(model.previewThumbnailFinished)
        try await settle { model.state.items.count == 1 }
        XCTAssertEqual(model.state.items.first?.id, selected.id)
        XCTAssertTrue(model.selectedItems.isEmpty)
        await model.shutdown()
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

    @MainActor private func addImageSelection(_ model: AppModel, repo: LibraryRepository, valid: Bool = true) async throws -> ClipboardItem {
        let bytes: Data
        if valid {
            let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 320, bitsPerComponent: 8, bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
            let image = try XCTUnwrap(context.makeImage())
            let output = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            bytes = output as Data
        } else { bytes = Data("synthetic invalid image".utf8) }
        let payload = ClipPayload(representations: [.init(type: "public.png", data: bytes)])
        let snapshot = try await repo.ingest(payload, source: .init(), now: Date(), sessionIDs: [])
        let image = try XCTUnwrap(snapshot.state.items.first { $0.kind == .image })
        model.state = snapshot.state; model.selectedIDs = [image.id]; model.selectionOrder = [image.id]
        return image
    }

    @MainActor func testImagePreviewPublishesBoundedThumbnailAndClearsItWhenLocked() async throws {
        let gate = OperationBarrier(), (model, repo, _) = try await controlledModel(payloadGate: gate)
        let image = try await addImageSelection(model, repo: repo)
        model.loadPreview(image.id); await model.waitForContentOperations()
        let bytes = try XCTUnwrap(model.previewThumbnailData)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let thumbnail = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(thumbnail.width, 256); XCTAssertEqual(thumbnail.height, 128)
        XCTAssertTrue(model.previewThumbnailFinished)
        XCTAssertNotNil(model.previewPayload)
        await gate.arm(); model.loadPreview(image.id); await gate.waitUntilEntered()
        XCTAssertNil(model.previewThumbnailData); XCTAssertFalse(model.previewThumbnailFinished)
        model.handleLifecycleSuspension()
        await gate.release(); await model.waitForContentOperations()
        XCTAssertNil(model.previewThumbnailData); XCTAssertNil(model.previewPayload)
        XCTAssertFalse(model.previewThumbnailFinished)
        await model.shutdown()
    }

    @MainActor func testNewSelectionSupersedesRepeatedImageLoadsWithoutPublishingStaleThumbnail() async throws {
        let gate = OperationBarrier(), (model, repo, text) = try await controlledModel(payloadGate: gate)
        let image = try await addImageSelection(model, repo: repo)
        await gate.arm(); model.loadPreview(image.id); await gate.waitUntilEntered()
        for _ in 0..<10 { model.loadPreview(image.id) }
        model.selectedIDs = [text.id]; model.selectionOrder = [text.id]; model.loadPreview(text.id)
        await gate.release(); await model.waitForContentOperations()
        let reads = await gate.invocationCount()
        XCTAssertEqual(reads, 2, "Canceled image requests must not load more payloads before the latest text selection")
        XCTAssertEqual(model.previewPayload?.plainText, "synthetic protected content")
        XCTAssertNil(model.previewThumbnailData); XCTAssertTrue(model.previewThumbnailFinished)
        await model.shutdown()
    }

    @MainActor func testDeletingImageRevokesPendingThumbnailPublication() async throws {
        let gate = OperationBarrier(), (model, repo, _) = try await controlledModel(payloadGate: gate)
        let image = try await addImageSelection(model, repo: repo)
        await gate.arm(); model.loadPreview(image.id); await gate.waitUntilEntered()
        model.deleteEverywhere(image.id)
        await gate.release(); await model.waitForContentOperations()
        try await settle { !model.state.items.contains { $0.id == image.id } }
        XCTAssertNil(model.previewThumbnailData); XCTAssertNil(model.previewPayload)
        XCTAssertFalse(model.previewThumbnailFinished)
        await model.shutdown()
    }

    @MainActor func testInvalidImageFinishesWithUnavailableThumbnailRatherThanStaleImage() async throws {
        let (model, repo, _) = try await controlledModel()
        let image = try await addImageSelection(model, repo: repo, valid: false)
        model.loadPreview(image.id); await model.waitForContentOperations()
        XCTAssertTrue(model.previewThumbnailFinished)
        XCTAssertNil(model.previewThumbnailData)
        XCTAssertEqual(model.previewPayload?.representations.first?.data, Data("synthetic invalid image".utf8))
        await model.shutdown()
    }

}
