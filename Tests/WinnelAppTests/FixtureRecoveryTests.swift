import AppKit
import Foundation
import XCTest
@testable import WinnelApp
import WinnelStorage

final class FixtureRecoveryTests: XCTestCase, @unchecked Sendable {
    @MainActor private func settle(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
    private func ciphertext(_ directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    @MainActor func testDeniedFixtureStartupRetryPreservesEncryptedSavedContentAndDoesNotCapture() async throws {
        let model = AppModel(fixtureMode: true, fixtureRecovery: true)
        let board = model.pasteboardService.pasteboard
        let counter = board.changeCount
        XCTAssertTrue(board.name.rawValue.hasPrefix("org.madeordinary.winnel.fixture.recovery."))
        await model.start()
        let seed = try XCTUnwrap(model.fixtureRecoverySeed)
        XCTAssertTrue(seed.directory.lastPathComponent.hasPrefix("winnel-fixture-recovery-"))
        XCTAssertNotNil(model.recoveryMessage)
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertFalse(model.state.settings.captureEnabled)
        XCTAssertNotEqual(model.captureState, .active)
        XCTAssertEqual(board.changeCount, counter)
        let unavailable = await seed.keys.key(createIfMissing: false)
        XCTAssertNil(unavailable)
        let before = try ciphertext(seed.directory)
        XCTAssertEqual(before.count, 2)
        for bytes in before.values {
            XCTAssertNil(bytes.range(of: Data(FixtureRecovery.sampleText.utf8)))
            XCTAssertNil(bytes.range(of: Data(FixtureRecovery.stackName.utf8)))
        }
        model.requestAccessibility()
        XCTAssertEqual(model.status, "Accessibility requests are disabled in this synthetic recovery fixture.")
        XCTAssertFalse(model.state.settings.directPasteEnabled)
        model.retryStorage()
        try await settle { model.recoveryMessage == nil && model.state.items.count == 1 }
        let item = try XCTUnwrap(model.state.items.first)
        XCTAssertTrue(item.isPinned)
        XCTAssertFalse(item.isRecent)
        XCTAssertEqual(item.textPreview, FixtureRecovery.sampleText)
        XCTAssertEqual(model.state.stacks.first?.name, FixtureRecovery.stackName)
        XCTAssertEqual(model.state.stacks.first?.memberships.map(\.itemID), [item.id])
        XCTAssertEqual(model.state.lastUserCopyID, item.id)
        XCTAssertFalse(model.state.settings.captureEnabled)
        XCTAssertFalse(model.state.settings.directPasteEnabled)
        XCTAssertFalse(model.state.settings.launchAtLogin)
        XCTAssertFalse(model.state.settings.updateChecksEnabled)
        XCTAssertNotEqual(model.captureState, .active)
        XCTAssertEqual(board.changeCount, counter)
        XCTAssertEqual(try ciphertext(seed.directory), before)
        model.selectedIDs = [item.id]; model.selectionOrder = [item.id]
        model.loadPreview(item.id); await model.waitForContentOperations()
        XCTAssertEqual(model.previewPayload?.plainText, FixtureRecovery.sampleText)
        await model.shutdown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: seed.directory.path))
        XCTAssertEqual(board.changeCount, counter)
        board.releaseGlobally()
    }

    func testUnavailableFixtureKeyStillAllowsExactEncryptedRecoveryExport() async throws {
        let seed = try await FixtureRecovery.prepare()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-recovery-export-test-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: seed.directory)
            try? FileManager.default.removeItem(at: destination)
        }
        let before = try ciphertext(seed.directory)
        let repo = try LibraryRepository(directory: seed.directory, provider: seed.keys)
        do { _ = try await repo.load(now: Date()); XCTFail("Withheld fixture key must fail the real load") }
        catch { XCTAssertEqual(error as? VaultError, .keyUnavailable) }
        try await repo.exportRecovery(to: destination)
        XCTAssertEqual(try ciphertext(destination), before)
        XCTAssertEqual(try ciphertext(seed.directory), before)
        let unavailable = await seed.keys.key(createIfMissing: false)
        XCTAssertNil(unavailable, "Encrypted export must not release the synthetic key")
        do { try await repo.exportRecovery(to: destination); XCTFail("Recovery export must not overwrite a destination") }
        catch { XCTAssertEqual(error as? VaultError, .unsafePath) }
        XCTAssertEqual(try ciphertext(destination), before)
    }

    @MainActor func testExplicitFixtureResetRemovesSavedArtifactsAndRetryDoesNotReseed() async throws {
        let model = AppModel(fixtureMode: true, fixtureRecovery: true)
        await model.start()
        let seed = try XCTUnwrap(model.fixtureRecoverySeed)
        let before = try ciphertext(seed.directory)
        XCTAssertNotNil(model.recoveryMessage)
        model.resetStorageAfterConfirmation()
        try await settle { model.recoveryMessage == nil && model.status == "All app content deleted. Capture is paused; resume when ready." }
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertTrue(model.state.stacks.isEmpty)
        XCTAssertEqual(model.state.settings.capturePaused, true)
        XCTAssertFalse(model.state.settings.captureEnabled)
        let reset = try ciphertext(seed.directory)
        XCTAssertEqual(Set(reset.keys), ["manifest.sealed"])
        XCTAssertNotEqual(reset["manifest.sealed"], before["manifest.sealed"])
        model.retryStorage()
        try await settle { model.status == "Storage reopened. Resume capture when ready." }
        XCTAssertTrue(model.state.items.isEmpty)
        XCTAssertTrue(model.state.stacks.isEmpty)
        XCTAssertEqual(try ciphertext(seed.directory), reset)
        await model.shutdown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: seed.directory.path))
        model.pasteboardService.pasteboard.releaseGlobally()
    }
}
