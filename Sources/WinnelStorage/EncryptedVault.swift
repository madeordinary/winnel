import Foundation
import CryptoKit
import Security
import LocalAuthentication
import Darwin

public enum VaultError: Error, Equatable, Sendable {
    case keyUnavailable, invalidKey, corruptData, unsupportedVersion, unsafePath, busy
    case sizeLimit, storageLimit, missingPayload, immutablePayload, ioFailure, garbageCollectionFailed
}

public enum VaultCommitStage: Sendable { case beforePayloads, afterPayloads, beforeManifestRename, afterManifestRename, beforeGarbageCollection }

public protocol VaultKeyProvider: Sendable {
    func key(createIfMissing: Bool) async throws -> Data?
}

public struct KeychainVaultKeyProvider: VaultKeyProvider {
    public let service: String
    public init(service: String = "org.madeordinary.winnel.storage") { self.service = service }
    public func key(createIfMissing: Bool) async throws -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "vault-key",
            kSecAttrSynchronizable as String: false, kSecUseAuthenticationContext as String: context]
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else { throw VaultError.invalidKey }
            return data
        }
        guard status == errSecItemNotFound else { throw VaultError.keyUnavailable }
        guard createIfMissing else { return nil }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw VaultError.keyUnavailable }
        var insert = query
        insert.removeValue(forKey: kSecUseAuthenticationContext as String)
        insert[kSecValueData as String] = bytes
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        if added == errSecDuplicateItem { return try await key(createIfMissing: false) }
        guard added == errSecSuccess else { throw VaultError.keyUnavailable }
        return bytes
    }
}

public struct VaultLimits: Sendable {
    public var payloadBytes: Int
    public var manifestBytes: Int
    public var totalBytes: Int
    public init(payloadBytes: Int = 20 * 1024 * 1024, manifestBytes: Int = 32 * 1024 * 1024,
                totalBytes: Int = 2 * 1024 * 1024 * 1024) {
        self.payloadBytes = payloadBytes; self.manifestBytes = manifestBytes; self.totalBytes = totalBytes
    }
}

/// All files are ciphertext; UUID payloads are immutable. The manifest rename is the transaction boundary.
/// Callers must retain IDs referenced by the manifest. A failed garbage collection means the new manifest committed.
public actor EncryptedVault {
    private let provider: any VaultKeyProvider
    private let limits: VaultLimits
    private let failureInjector: (@Sendable (VaultCommitStage) throws -> Void)?
    private let fd: Int32
    private var operationInProgress = false
    private static let header = Data([0x57, 0x4e, 0x4c, 1])
    private static let overhead = 32

    public init(directory: URL, keyProvider: any VaultKeyProvider = KeychainVaultKeyProvider(), limits: VaultLimits = .init(), failureInjector: (@Sendable (VaultCommitStage) throws -> Void)? = nil) throws {
        guard directory.isFileURL, limits.payloadBytes > 0, limits.payloadBytes <= Int.max - Self.overhead, limits.manifestBytes > 0, limits.manifestBytes <= Int.max - Self.overhead, limits.totalBytes > 0 else { throw VaultError.unsafePath }
        let parent = directory.deletingLastPathComponent().standardizedFileURL
        guard parent.resolvingSymlinksInPath() == parent else { throw VaultError.unsafePath }
        if mkdir(directory.path, 0o700) != 0 && errno != EEXIST { throw VaultError.ioFailure }
        let opened = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard opened >= 0 else { throw VaultError.unsafePath }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else { close(opened); throw VaultError.busy }
        self.fd = opened; self.provider = keyProvider; self.limits = limits; self.failureInjector = failureInjector
    }
    deinit { close(fd) }

    private func names() throws -> [String] {
        // Enumerate the held directory, never a substituted pathname.
        let duplicate = dup(fd)
        guard duplicate >= 0, let stream = fdopendir(duplicate) else { throw VaultError.ioFailure }
        rewinddir(stream)
        defer { closedir(stream) }
        var result: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { result.append(name) }
        }
        return result
    }
    private func size(_ name: String) throws -> Int {
        var info = stat()
        guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw VaultError.ioFailure }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw VaultError.unsafePath }
        guard info.st_size >= 0, info.st_size <= Int.max else { throw VaultError.sizeLimit }
        return Int(info.st_size)
    }
    public func usageBytes() throws -> Int {
        try names().reduce(0) { total, name in
            let bytes = try size(name)
            guard bytes <= Int.max - total else { throw VaultError.storageLimit }
            return total + bytes
        }
    }
    private func key(create: Bool) async throws -> SymmetricKey {
        let existing = try names()
        guard let data = try await provider.key(createIfMissing: create && existing.isEmpty) else { throw VaultError.keyUnavailable }
        guard data.count == 32 else { throw VaultError.invalidKey }
        return SymmetricKey(data: data)
    }
    private func isStageName(_ name: String) -> Bool { name.hasPrefix("stage-") && UUID(uuidString: String(name.dropFirst(6))) != nil }
    private func payloadName(_ id: UUID) -> String { id.uuidString.lowercased() + ".sealed" }
    private func read(_ name: String, bound: Int) throws -> Data {
        let count = try size(name)
        guard count <= bound else { throw VaultError.sizeLimit }
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw VaultError.ioFailure }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size == count else { throw VaultError.unsafePath }
        var data = Data(count: count)
        let success = data.withUnsafeMutableBytes { buffer -> Bool in
            var offset = 0
            while offset < count {
                let n = Darwin.read(file, buffer.baseAddress!.advanced(by: offset), count - offset)
                if n <= 0 { return false }; offset += n
            }
            return true
        }
        guard success else { throw VaultError.ioFailure }
        return data
    }
    private func seal(_ data: Data, role: String, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(data, using: key, authenticating: Self.header + Data(role.utf8))
        guard let combined = box.combined else { throw VaultError.corruptData }
        return Self.header + combined
    }
    private func unseal(_ data: Data, role: String, key: SymmetricKey) throws -> Data {
        guard data.count >= Self.overhead, data.prefix(3) == Self.header.prefix(3) else { throw VaultError.corruptData }
        guard data[3] == 1 else { throw VaultError.unsupportedVersion }
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(4)), using: key, authenticating: Self.header + Data(role.utf8)) }
        catch { throw VaultError.corruptData }
    }
    public func loadManifest() async throws -> Data? {
        guard !operationInProgress else { throw VaultError.busy }; operationInProgress = true
        defer { operationInProgress = false }
        let existing = try names()
        guard !existing.isEmpty else { return nil }
        let secret = try await key(create: false)
        guard existing.contains("manifest.sealed") else { throw VaultError.corruptData }
        return try unseal(read("manifest.sealed", bound: limits.manifestBytes + Self.overhead), role: "manifest", key: secret)
    }
    public func readPayload(id: UUID) async throws -> Data {
        guard !operationInProgress else { throw VaultError.busy }; operationInProgress = true
        defer { operationInProgress = false }
        let secret = try await key(create: false)
        guard try names().contains(payloadName(id)) else { throw VaultError.missingPayload }
        return try unseal(read(payloadName(id), bound: limits.payloadBytes + Self.overhead), role: payloadName(id), key: secret)
    }
    private func write(_ data: Data, name: String) throws {
        let file = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw VaultError.ioFailure }
        defer { close(file) }
        let success = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                if n <= 0 { return false }; offset += n
            }
            // Flush through the device write cache before making the manifest reachable.
            // An unsupported/full-sync failure is a storage error, never a silent weaker write.
            return fsync(file) == 0 && fcntl(file, F_FULLFSYNC) == 0
        }
        guard success else { throw VaultError.ioFailure }
    }
    public func commit(manifest: Data, newPayloads: [UUID: Data], retaining: Set<UUID>, isStillAuthorized: @Sendable () async -> Bool = { true }) async throws {
        guard !operationInProgress else { throw VaultError.busy }; operationInProgress = true
        defer { operationInProgress = false }
        guard manifest.count <= limits.manifestBytes, newPayloads.values.allSatisfy({ $0.count <= limits.payloadBytes }), Set(newPayloads.keys).isSubset(of: retaining) else { throw VaultError.sizeLimit }
        let secret = try await key(create: true)
        guard await isStillAuthorized(), !Task.isCancelled else { throw CancellationError() }
        let before = try names()
        for name in before {
            guard name == "manifest.sealed" || isStageName(name) || (name.hasSuffix(".sealed") && UUID(uuidString: String(name.dropLast(7))) != nil) else { throw VaultError.unsafePath }
            _ = try size(name)
        }
        if !before.isEmpty {
            guard before.contains("manifest.sealed") else { throw VaultError.corruptData }
            _ = try unseal(read("manifest.sealed", bound: limits.manifestBytes + Self.overhead), role: "manifest", key: secret)
        }
        for id in retaining {
            let name = payloadName(id)
            if before.contains(name) {
                let old = try unseal(read(name, bound: limits.payloadBytes + Self.overhead), role: name, key: secret)
                if let replacement = newPayloads[id], replacement != old { throw VaultError.immutablePayload }
            } else if newPayloads[id] == nil { throw VaultError.missingPayload }
        }
        let additions = newPayloads.filter { !before.contains(payloadName($0.key)) }
        var extra = manifest.count + Self.overhead
        for payload in additions.values {
            let bytes = payload.count + Self.overhead
            guard bytes <= limits.totalBytes, extra <= limits.totalBytes - bytes else { throw VaultError.storageLimit }
            extra += bytes
        }
        let current = try usageBytes()
        guard extra <= limits.totalBytes, current <= limits.totalBytes - extra else { throw VaultError.storageLimit }
        // Reserve space for a second copy of the next manifest. Otherwise a nearly full
        // vault could accept growth and later reject a shrinking deletion transaction.
        let manifestBytes = manifest.count + Self.overhead
        var finalBytes = manifestBytes
        for id in retaining {
            let bytes = try additions[id].map { $0.count + Self.overhead } ?? size(payloadName(id))
            guard bytes <= limits.totalBytes, finalBytes <= limits.totalBytes - bytes else { throw VaultError.storageLimit }
            finalBytes += bytes
        }
        guard manifestBytes <= limits.totalBytes, finalBytes <= limits.totalBytes - manifestBytes else { throw VaultError.storageLimit }
        var created: [String] = []
        let stage = "stage-" + UUID().uuidString.lowercased()
        do {
            try failureInjector?(.beforePayloads)
            for (id, data) in additions {
                let name = payloadName(id); created.append(name)
                try write(seal(data, role: name, key: secret), name: name)
            }
            try failureInjector?(.afterPayloads)
            created.append(stage)
            try write(seal(manifest, role: "manifest", key: secret), name: stage)
            try failureInjector?(.beforeManifestRename)
            guard fsync(fd) == 0 else { throw VaultError.ioFailure }
            // Authorization is linearized at this final check; rename follows without suspension.
            guard await isStillAuthorized(), !Task.isCancelled else { throw CancellationError() }
            guard renameat(fd, stage, fd, "manifest.sealed") == 0 else { throw VaultError.ioFailure }
        } catch {
            for name in created { _ = unlinkat(fd, name, 0) }
            throw error
        }
        do { try failureInjector?(.afterManifestRename) } catch { throw VaultError.garbageCollectionFailed }
        guard fsync(fd) == 0 else { throw VaultError.garbageCollectionFailed }
        let keep = Set(retaining.map(payloadName)).union(["manifest.sealed"])
        do {
        try failureInjector?(.beforeGarbageCollection)
        for name in try names() where !keep.contains(name) {
            // Only app-owned artifact names are eligible; unknown files require recovery.
            guard isStageName(name) || (name.hasSuffix(".sealed") && UUID(uuidString: String(name.dropLast(7))) != nil) else { throw VaultError.garbageCollectionFailed }
            _ = try size(name)
            guard unlinkat(fd, name, 0) == 0 else { throw VaultError.garbageCollectionFailed }
        }
        guard fsync(fd) == 0 else { throw VaultError.garbageCollectionFailed }
        } catch { throw VaultError.garbageCollectionFailed }
    }
    /// Copies only encrypted app-owned artifacts; never asks for the unavailable key.
    /// Destination is a new explicit user-selected folder. Bounded record-at-a-time copying.
    public func exportEncryptedRecovery(to directory: URL) throws {
        guard !operationInProgress else { throw VaultError.busy }; operationInProgress = true
        defer { operationInProgress = false }
        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent().standardizedFileURL
        guard directory.isFileURL, parent.resolvingSymlinksInPath() == parent,
              !manager.fileExists(atPath: directory.path) else { throw VaultError.unsafePath }
        let files = try names()
        guard try usageBytes() <= limits.totalBytes else { throw VaultError.storageLimit }
        for name in files {
            guard name == "manifest.sealed" || isStageName(name) || (name.hasSuffix(".sealed") && UUID(uuidString: String(name.dropLast(7))) != nil) else { throw VaultError.unsafePath }
            _ = try size(name)
        }
        let staging = parent.appendingPathComponent(".winnel-recovery-" + UUID().uuidString)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for name in files {
                let bytes = try read(name, bound: max(limits.payloadBytes, limits.manifestBytes) + Self.overhead)
                try bytes.write(to: staging.appendingPathComponent(name), options: .withoutOverwriting)
            }
            try manager.moveItem(at: staging, to: directory)
        } catch { try? manager.removeItem(at: staging); throw error }
    }
    /// Explicit UI-confirmed reset removes active app artifacts, retaining the app key for later capture.
    public func reset() throws {
        guard !operationInProgress else { throw VaultError.busy }; operationInProgress = true
        defer { operationInProgress = false }
        let files = try names()
        for name in files {
            guard name == "manifest.sealed" || isStageName(name) || (name.hasSuffix(".sealed") && UUID(uuidString: String(name.dropLast(7))) != nil) else { throw VaultError.unsafePath }
            _ = try size(name)
        }
        for name in files { guard unlinkat(fd, name, 0) == 0 else { throw VaultError.ioFailure } }
        guard fsync(fd) == 0 else { throw VaultError.ioFailure }
    }
}
