import Foundation
import XCTest
@testable import WinnelStorage

actor TestKeys: VaultKeyProvider {
    var value: Data? = Data(repeating: 0x42, count: 32)
    func key(createIfMissing: Bool) -> Data? { value }
    func remove() { value = nil }
}
final class EncryptedVaultTests: XCTestCase, @unchecked Sendable {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testRoundTripCiphertextDeletionAndReset() async throws {
        let url = try folder(), keys = TestKeys(), id = UUID()
        let vault = try EncryptedVault(directory: url, keyProvider: keys)
        let payload = Data("private synthetic clipboard fixture".utf8), manifest = Data("secret stack title".utf8)
        try await vault.commit(manifest: manifest, newPayloads: [id: payload], retaining: [id])
        let loaded = try await vault.loadManifest(), content = try await vault.readPayload(id: id)
        XCTAssertEqual(loaded, manifest); XCTAssertEqual(content, payload)
        for file in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: payload)); XCTAssertNil(bytes.range(of: manifest))
        }
        try await vault.commit(manifest: Data("empty".utf8), newPayloads: [:], retaining: [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), ["manifest.sealed"])
        try await vault.reset()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
        try await vault.commit(manifest: manifest, newPayloads: [:], retaining: [])
    }
    func testMissingKeyDoesNotReplaceExistingData() async throws {
        let url = try folder(), keys = TestKeys()
        let vault = try EncryptedVault(directory: url, keyProvider: keys)
        try await vault.commit(manifest: Data("saved".utf8), newPayloads: [:], retaining: [])
        let before = try Data(contentsOf: url.appendingPathComponent("manifest.sealed"))
        await keys.remove()
        do { _ = try await vault.loadManifest(); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .keyUnavailable) }
        do { try await vault.commit(manifest: Data(), newPayloads: [:], retaining: []); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .keyUnavailable) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.sealed")), before)
    }
    func testTamperSwapVersionAndImmutableIDs() async throws {
        let url = try folder(), keys = TestKeys(), a = UUID(), b = UUID()
        let vault = try EncryptedVault(directory: url, keyProvider: keys)
        try await vault.commit(manifest: Data("m".utf8), newPayloads: [a: Data("a".utf8), b: Data("b".utf8)], retaining: [a,b])
        do { try await vault.commit(manifest: Data(), newPayloads: [a: Data("replace".utf8)], retaining: [a,b]); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .immutablePayload) }
        let pathA = url.appendingPathComponent(a.uuidString.lowercased() + ".sealed"), pathB = url.appendingPathComponent(b.uuidString.lowercased() + ".sealed")
        try Data(contentsOf: pathA).write(to: pathB)
        do { _ = try await vault.readPayload(id: b); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .corruptData) }
        var bytes = try Data(contentsOf: pathA); bytes[bytes.count-1] ^= 1; try bytes.write(to: pathA)
        do { _ = try await vault.readPayload(id: a); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .corruptData) }
        let manifestURL = url.appendingPathComponent("manifest.sealed")
        var manifest = try Data(contentsOf: manifestURL); manifest[3] = 2; try manifest.write(to: manifestURL)
        do { try await vault.commit(manifest: Data(), newPayloads: [:], retaining: []); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .unsupportedVersion) }
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifest)
    }
    func testBudgetFailurePreservesManifestAndOrphansRecover() async throws {
        let url = try folder(), keys = TestKeys(), id = UUID()
        let vault = try EncryptedVault(directory: url, keyProvider: keys, limits: .init(payloadBytes: 100, manifestBytes: 100, totalBytes: 150))
        try await vault.commit(manifest: Data("prior".utf8), newPayloads: [:], retaining: [])
        let before = try Data(contentsOf: url.appendingPathComponent("manifest.sealed"))
        do { try await vault.commit(manifest: Data(repeating: 0, count: 90), newPayloads: [id: Data(repeating: 0, count: 50)], retaining: [id]); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .storageLimit) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.sealed")), before)
        try Data([1,2]).write(to: url.appendingPathComponent("stage-11111111-1111-1111-1111-111111111111"))
        try await vault.commit(manifest: Data("next".utf8), newPayloads: [:], retaining: [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), ["manifest.sealed"])
    }
    func testSymlinkAndConcurrentWriterRejected() async throws {
        let url = try folder(), keys = TestKeys()
        let vault = try EncryptedVault(directory: url, keyProvider: keys)
        do { _ = try EncryptedVault(directory: url, keyProvider: keys); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .busy) }
        let outside = try folder().appendingPathComponent("outside")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("manifest.sealed"), withDestinationURL: outside)
        do { _ = try await vault.loadManifest(); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .unsafePath) }
        XCTAssertEqual(try Data(contentsOf: outside), Data("untouched".utf8))
    }
    func testWriteFailurePreservesPreviousState() async throws {
        let url = try folder(), keys = TestKeys(), id = UUID()
        let vault = try EncryptedVault(directory: url, keyProvider: keys)
        try await vault.commit(manifest: Data("prior".utf8), newPayloads: [:], retaining: [])
        let before = try Data(contentsOf: url.appendingPathComponent("manifest.sealed"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        do { try await vault.commit(manifest: Data("next".utf8), newPayloads: [id: Data("new".utf8)], retaining: [id]); XCTFail() }
        catch { XCTAssertEqual(error as? VaultError, .ioFailure) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("manifest.sealed")), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), ["manifest.sealed"])
    }
    func testOrphanWithoutManifestFailsClosedAndSizeBound() async throws {
        let url = try folder(), keys = TestKeys()
        try Data([1]).write(to: url.appendingPathComponent("stage-11111111-1111-1111-1111-111111111111"))
        let vault = try EncryptedVault(directory: url, keyProvider: keys, limits: .init(payloadBytes: 5, manifestBytes: 5, totalBytes: 100))
        do { _ = try await vault.loadManifest(); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .corruptData) }
        do { try await vault.commit(manifest: Data(repeating: 0, count: 6), newPayloads: [:], retaining: []); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .sizeLimit) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("stage-11111111-1111-1111-1111-111111111111").path))
    }
}

private final class FailureSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var point: VaultCommitStage?
    func set(_ value: VaultCommitStage?) { lock.lock(); defer { lock.unlock() }; point = value }
    func check(_ value: VaultCommitStage) throws {
        lock.lock(); defer { lock.unlock() }
        if point == value { throw VaultError.ioFailure }
    }
}
extension EncryptedVaultTests {
    func testInjectedCommitFailuresAndPostCommitErrorMeaning() async throws {
        for stage in [VaultCommitStage.beforePayloads, .afterPayloads, .beforeManifestRename, .afterManifestRename, .beforeGarbageCollection] {
            let directory = try folder(), keys = TestKeys(), faults = FailureSwitch(), id = UUID()
            let vault = try EncryptedVault(directory: directory, keyProvider: keys, failureInjector: { try faults.check($0) })
            try await vault.commit(manifest: Data("prior".utf8), newPayloads: [:], retaining: [])
            faults.set(stage)
            do { try await vault.commit(manifest: Data("next".utf8), newPayloads: [id: Data("fixture".utf8)], retaining: [id]); XCTFail("Fault not reached") }
            catch {
                let committed = stage == .afterManifestRename || stage == .beforeGarbageCollection
                XCTAssertEqual(error as? VaultError, committed ? .garbageCollectionFailed : .ioFailure)
                faults.set(nil)
                let loaded = try await vault.loadManifest()
                XCTAssertEqual(loaded, Data((committed ? "next" : "prior").utf8))
                if committed { let payload = try await vault.readPayload(id: id); XCTAssertEqual(payload, Data("fixture".utf8)) }
                else { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["manifest.sealed"]) }
            }
        }
    }
    func testUnknownStageNamePreservedAndRecoveryNeedsNoKey() async throws {
        let directory = try folder(), keys = TestKeys()
        let vault = try EncryptedVault(directory: directory, keyProvider: keys)
        try await vault.commit(manifest: Data("saved".utf8), newPayloads: [:], retaining: [])
        await keys.remove()
        let destination = try folder().appendingPathComponent("Recovery")
        try await vault.exportEncryptedRecovery(to: destination)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("manifest.sealed")), try Data(contentsOf: destination.appendingPathComponent("manifest.sealed")))
        let unknown = directory.appendingPathComponent("stage-user-file")
        try Data("preserve".utf8).write(to: unknown)
        do { try await vault.reset(); XCTFail() } catch { XCTAssertEqual(error as? VaultError, .unsafePath) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }
}

extension EncryptedVaultTests {
    func testGrowthKeepsHeadroomForShrinkingDeletion() async throws {
        let directory = try folder(), keys = TestKeys(), id = UUID()
        let vault = try EncryptedVault(directory: directory, keyProvider: keys, limits: .init(payloadBytes: 500, manifestBytes: 500, totalBytes: 1000))
        let prior = Data(repeating: 0x61, count: 200)
        try await vault.commit(manifest: prior, newPayloads: [id: Data(repeating: 0x42, count: 400)], retaining: [id])
        do { try await vault.commit(manifest: Data(repeating: 0x62, count: 300), newPayloads: [:], retaining: [id]); XCTFail("Growth consumed deletion headroom") }
        catch { XCTAssertEqual(error as? VaultError, .storageLimit) }
        let loaded = try await vault.loadManifest(); XCTAssertEqual(loaded, prior)
        let smaller = Data(repeating: 0x63, count: 190)
        try await vault.commit(manifest: smaller, newPayloads: [:], retaining: [])
        let reduced = try await vault.loadManifest(); XCTAssertEqual(reduced, smaller)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["manifest.sealed"])
    }
}

private actor CommitKeyBarrier: VaultKeyProvider {
    private var armed = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var blocked = false
    func arm() { armed = true }
    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
    func key(createIfMissing: Bool) async -> Data? {
        if armed {
            armed = false; blocked = true
            await withCheckedContinuation { continuation in
                waiting = continuation; entered?.resume(); entered = nil
            }
        }
        return Data(repeating: 0x63, count: 32)
    }
}
private actor CommitAuthorization {
    var allowed = true
    var calls = 0
    func revoke() { allowed = false }
    func check() -> Bool { allowed }
    func firstCheckOnly() -> Bool { calls += 1; return calls == 1 }
}
extension EncryptedVaultTests {
    func testAuthorizationRevokedDuringKeyWaitPreservesSavedCiphertext() async throws {
        let url = try folder(), keys = CommitKeyBarrier(), saved = UUID(), incoming = UUID()
        let vault = try EncryptedVault(directory: url, keyProvider: keys)
        try await vault.commit(manifest: Data("original".utf8), newPayloads: [saved: Data("saved".utf8)], retaining: [saved])
        let original = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let authorization = CommitAuthorization()
        await keys.arm()
        let capture = Task {
            try await vault.commit(manifest: Data("incoming".utf8), newPayloads: [incoming: Data("new".utf8)], retaining: [saved, incoming], isStillAuthorized: { await authorization.check() })
        }
        await keys.waitUntilBlocked(); await authorization.revoke(); await keys.release()
        do { try await capture.value; XCTFail("Revoked capture must cancel") } catch { XCTAssertTrue(error is CancellationError) }
        let after = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        XCTAssertEqual(after, original)
    }
    func testFinalAuthorizationCheckRemovesStagedCiphertext() async throws {
        let url = try folder(), saved = UUID(), incoming = UUID()
        let vault = try EncryptedVault(directory: url, keyProvider: TestKeys())
        try await vault.commit(manifest: Data("original".utf8), newPayloads: [saved: Data("saved".utf8)], retaining: [saved])
        let original = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let authorization = CommitAuthorization()
        do {
            try await vault.commit(manifest: Data("incoming".utf8), newPayloads: [incoming: Data("new".utf8)], retaining: [saved, incoming], isStillAuthorized: { await authorization.firstCheckOnly() })
            XCTFail("Revocation before rename must cancel")
        } catch { XCTAssertTrue(error is CancellationError) }
        let after = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        XCTAssertEqual(after, original)
    }
    func testCancellationAfterManifestRenameStillReportsCommit() async throws {
        let url = try folder()
        let vault = try EncryptedVault(directory: url, keyProvider: TestKeys(), failureInjector: { phase in
            if case .afterManifestRename = phase { withUnsafeCurrentTask { $0?.cancel() } }
        })
        let capture = Task { try await vault.commit(manifest: Data("committed".utf8), newPayloads: [:], retaining: []) }
        try await capture.value
        let manifest = try await vault.loadManifest()
        XCTAssertEqual(manifest, Data("committed".utf8))
    }
}
