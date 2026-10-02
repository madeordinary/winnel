import Foundation
import XCTest
@testable import WinnelApp
import WinnelCore
import WinnelStorage

private actor RecoverableSchemaKeys: VaultKeyProvider {
    private let bytes = Data(repeating: 0x57, count: 32)
    private var available = true
    func key(createIfMissing: Bool) -> Data? { available ? bytes : nil }
    func setAvailable(_ value: Bool) { available = value }
}

final class SchemaCompatibilityTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-schema-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixture(schemaVersion: Int = 1) -> (LibraryState, ClipPayload) {
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("Synthetic schema fixture".utf8)), .init(type: "public.rtf", data: Data("{\\rtf1 Synthetic schema fixture}".utf8))])
        let item = ClipboardItem(copiedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .init(bundleIdentifier: "synthetic.schema", name: "Synthetic Source", confidence: .inferred), kind: .richText, textPreview: "Synthetic schema fixture", payloadByteCount: payload.byteCount, fingerprint: payload.fingerprint, isPinned: true, isRecent: false)
        var settings = Settings()
        settings.captureEnabled = true
        settings.capturePaused = true
        settings.excludedBundleIdentifiers = ["synthetic.excluded"]
        let stack = SavedStack(name: "Synthetic saved stack", memberships: [.init(itemID: item.id, associatedURL: "https://example.invalid/schema")])
        return (.init(schemaVersion: schemaVersion, items: [item], stacks: [stack], settings: settings, lastUserCopyID: item.id), payload)
    }

    private func initialV1Manifest(_ state: LibraryState) throws -> Data {
        // The initial v1 schema shape predates the optional capturePaused key.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertNotNil(settings.removeValue(forKey: "capturePaused"))
        object["settings"] = settings
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func seed(_ directory: URL, provider: any VaultKeyProvider, state: LibraryState, payload: ClipPayload, manifest: Data) async throws {
        // This helper owns the vault only until it returns, releasing its directory flock
        // before LibraryRepository opens the same fixture. No raw ciphertext is invented.
        let vault = try EncryptedVault(directory: directory, keyProvider: provider)
        try await vault.commit(manifest: manifest, newPayloads: [state.items[0].id: JSONEncoder().encode(payload)], retaining: [state.items[0].id])
    }

    private func ciphertext(_ directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    func testInitialV1WithoutCapturePausedReopensSavedDataWithoutCiphertextRewrite() async throws {
        let url = try directory(), keys = RecoverableSchemaKeys()
        var (expected, payload) = fixture()
        let manifest = try initialV1Manifest(expected)
        expected.settings.capturePaused = nil
        XCTAssertEqual(try JSONDecoder().decode(LibraryState.self, from: manifest), expected)
        try await seed(url, provider: keys, state: expected, payload: payload, manifest: manifest)
        let before = try ciphertext(url)
        do {
            let repo = try LibraryRepository(directory: url, provider: keys)
            let snapshot = try await repo.load(now: Date())
            XCTAssertEqual(snapshot.state, expected)
            XCTAssertNil(snapshot.state.settings.capturePaused)
            XCTAssertTrue(snapshot.state.settings.captureEnabled)
            let restored = try await repo.payload(expected.items[0].id)
            XCTAssertEqual(restored, payload)
            XCTAssertEqual(try ciphertext(url), before)
        }
        let reopened = try LibraryRepository(directory: url, provider: keys)
        let snapshot = try await reopened.load(now: Date())
        XCTAssertEqual(snapshot.state, expected)
        XCTAssertEqual(try ciphertext(url), before)
    }

    func testFutureLibrarySchemaRejectsRepeatedLoadsWithoutRewritingSavedCiphertext() async throws {
        let url = try directory(), keys = RecoverableSchemaKeys()
        let (future, payload) = fixture(schemaVersion: 2)
        try await seed(url, provider: keys, state: future, payload: payload, manifest: JSONEncoder().encode(future))
        let before = try ciphertext(url)
        let repo = try LibraryRepository(directory: url, provider: keys)
        for _ in 0..<2 {
            do { _ = try await repo.load(now: Date()); XCTFail("Unsupported LibraryState version must not load") }
            catch { XCTAssertEqual(error as? VaultError, .unsupportedVersion) }
            XCTAssertEqual(try ciphertext(url), before)
        }
    }

    func testUnavailableKeyRetryLoadsInitialV1WithoutReplacingSavedBytes() async throws {
        let url = try directory(), keys = RecoverableSchemaKeys()
        var (expected, payload) = fixture()
        let manifest = try initialV1Manifest(expected)
        expected.settings.capturePaused = nil
        try await seed(url, provider: keys, state: expected, payload: payload, manifest: manifest)
        let before = try ciphertext(url)
        await keys.setAvailable(false)
        let repo = try LibraryRepository(directory: url, provider: keys)
        do { _ = try await repo.load(now: Date()); XCTFail("Missing existing key must fail closed") }
        catch { XCTAssertEqual(error as? VaultError, .keyUnavailable) }
        XCTAssertEqual(try ciphertext(url), before)
        await keys.setAvailable(true)
        let snapshot = try await repo.load(now: Date())
        let restored = try await repo.payload(expected.items[0].id)
        XCTAssertEqual(snapshot.state, expected)
        XCTAssertEqual(restored, payload)
        XCTAssertEqual(try ciphertext(url), before)
    }
}
