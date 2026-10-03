import Foundation
import WinnelCore
import WinnelStorage

actor FixtureRecoveryKeys: VaultKeyProvider {
    private let bytes = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    private var available = true
    func key(createIfMissing: Bool) -> Data? { available ? bytes : nil }
    func withhold() { available = false }
    func release() { available = true }
}

struct FixtureRecoverySeed: Sendable {
    let directory: URL
    let keys: FixtureRecoveryKeys
}

/// Deliberate synthetic key failure in a new temporary vault. No path/key arguments,
/// Keychain, production library, clipboard access or cross-session persistence.
enum FixtureRecovery {
    static let sampleText = "Winnel synthetic recovery sample. No personal clipboard content is used."
    static let stackName = "Synthetic recovery stack"

    static func prepare() async throws -> FixtureRecoverySeed {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-fixture-recovery-" + UUID().uuidString, isDirectory: true)
        let keys = FixtureRecoveryKeys()
        do {
            try await seed(directory: directory, keys: keys)
            await keys.withhold()
            return .init(directory: directory, keys: keys)
        } catch {
            // This path was generated here and was never supplied by the caller.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func seed(directory: URL, keys: FixtureRecoveryKeys) async throws {
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(sampleText.utf8))])
        let item = ClipboardItem(copiedAt: Date(), source: .init(bundleIdentifier: "org.madeordinary.winnel.fixture", name: "Synthetic recovery fixture", confidence: .established), kind: .text, textPreview: sampleText, payloadByteCount: try JSONEncoder().encode(payload).count, fingerprint: payload.fingerprint, isPinned: true, isRecent: false)
        var settings = Settings()
        settings.onboardingComplete = true
        let state = LibraryState(items: [item], stacks: [.init(name: stackName, memberships: [.init(itemID: item.id)])], settings: settings, lastUserCopyID: item.id)
        let vault = try EncryptedVault(directory: directory, keyProvider: keys)
        try await vault.commit(manifest: JSONEncoder().encode(state), newPayloads: [item.id: JSONEncoder().encode(payload)], retaining: [item.id])
        // Returning releases this vault's flock before the real repository opens it.
    }
}
