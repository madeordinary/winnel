import AppKit
import SwiftUI
import CoreGraphics
import ImageIO
import Darwin
import WinnelCore
import WinnelStorage

/// Synthetic active-preview measurement. Samples run independently of the UI executor.
@MainActor enum FixturePreviewPerformance {
    enum Failure: String, Error { case unsafeOutput, invalidFixture, imageEncoding, resourceMeasurement }
    private struct Sample: Codable, Sendable {
        let elapsedSeconds: Double
        let residentBytes: UInt64
        let physicalFootprintBytes: UInt64
    }
    private struct Dataset: Codable, Sendable {
        let textID: UUID
        let imageID: UUID
        let textBytes: Int
        let imagePNGBytes: Int
        let imageWidth: Int
        let imageHeight: Int
        let serializedTextBytes: Int
        let serializedImageBytes: Int
        let encryptedDiskBytes: Int
    }
    private struct Stage: Codable {
        let kind: String
        let elapsedMilliseconds: Double
        let baseline: Sample
        let samples: [Sample]
        let peakSampledResidentBytes: UInt64
        let peakSampledPhysicalFootprintBytes: UInt64
        let largestSampleGapSeconds: Double
        let previewReady: Bool
        let thumbnailBytes: Int
        let offscreenBitmapProduced: Bool
    }
    private struct Report: Encodable {
        let schemaVersion = 1
        let startedAt: String
        let processID: Int32
        let os: String
        var phase = "initializing"
        var dataset: Dataset?
        var stages: [Stage] = []
        var failure: String?
        var completedAt: String?
        let sampling = "Detached utility-priority task requests proc_pid_rusage every 10 milliseconds, independent of MainActor. Samples include load/decryption, thumbnail worker, MainActor PaletteView hosting/layout/bitmap, and 250 ms settled retention. Scheduling may delay samples; sampled peaks are lower bounds, not exact instantaneous maxima."
        let conditions = "Release app process; two synthetic encrypted payloads seeded once off MainActor; fresh AppModel using production repository and named pasteboard. Post-seed OS filesystem caches and allocator are warm. One text preview followed by one image preview in the same process; allocator/cache retention may affect the second baseline. Active normal capture and retention timers; no visible window."
        let datasetDescription = "10 MiB repetitive UTF-8 text and a generated solid RGBA 4096×4096 PNG. PNG compression is intentionally high; encoded size is reported separately from decoded 64 MiB pixel geometry."
        let unverified = ["PRD reference-device active-preview threshold", "Instantaneous maximum RSS", "Cold process or cold filesystem-cache behavior", "Interactive visible rendering", "Personal clipboard and cross-app behavior", "Random or adversarial images", "Repeated preview navigation"]
    }
    static func run(outputDirectory: URL) async throws {
        let output = outputDirectory.standardizedFileURL
        guard output.isFileURL, output.path.hasPrefix(FileManager.default.currentDirectoryPath + "/build/"), output.resolvingSymlinksInPath() == output else { throw Failure.unsafeOutput }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var report = Report(startedAt: ISO8601DateFormatter().string(from: Date()), processID: getpid(), os: ProcessInfo.processInfo.operatingSystemVersionString)
        try write(report, output)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-preview-performance-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let board = NSPasteboard(name: .init("org.madeordinary.winnel.performance.preview." + UUID().uuidString))
        let keys = FixtureVaultKeys()
        var model: AppModel?
        defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: directory) }
        do {
            report.dataset = try await seed(directory: directory, keys: keys)
            let appModel = AppModel(fixtureMode: true, pasteboard: board, performanceFixture: .init(directory: directory, keys: keys))
            model = appModel
            await appModel.start()
            guard appModel.recoveryMessage == nil, appModel.captureState == .active, appModel.state.items.count == 2, let dataset = report.dataset else { throw Failure.invalidFixture }
            try await Task.sleep(for: .milliseconds(500))
            for (kind, id) in [("text", dataset.textID), ("image", dataset.imageID)] {
                try Task.checkCancellation()
                report.phase = "loading-" + kind; try write(report, output)
                appModel.selectedIDs = [id]; appModel.selectionOrder = [id]
                let start = ProcessInfo.processInfo.systemUptime
                let baseline = try resources(start: start)
                let sampler = Task.detached(priority: .utility) { () throws -> [Sample] in
                    var samples: [Sample] = []
                    while !Task.isCancelled {
                        samples.append(try resources(start: start))
                        do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
                    }
                    return samples
                }
                let stage: Stage
                do {
                    stage = try await withTaskCancellationHandler {
                        appModel.loadPreview(id)
                        await appModel.waitForContentOperations()
                        try Task.checkCancellation()
                        guard appModel.previewPayload != nil, appModel.previewThumbnailFinished, appModel.recoveryMessage == nil, appModel.captureState == .active,
                              kind != "image" || appModel.previewThumbnailData != nil else { throw Failure.invalidFixture }
                        let host = NSHostingView(rootView: PaletteView(model: appModel))
                        host.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
                        host.layoutSubtreeIfNeeded()
                        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
                        if let bitmap { host.cacheDisplay(in: host.bounds, to: bitmap) }
                        try await Task.sleep(for: .milliseconds(250))
                        withExtendedLifetime(host) {}
                        let end = try resources(start: start)
                        sampler.cancel()
                        let samples = [baseline] + (try await sampler.value) + [end]
                        let ordered = samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
                        let gaps = zip(ordered, ordered.dropFirst()).map { $1.elapsedSeconds - $0.elapsedSeconds }
                        return Stage(kind: kind, elapsedMilliseconds: end.elapsedSeconds * 1_000, baseline: baseline, samples: ordered,
                                     peakSampledResidentBytes: ordered.map(\.residentBytes).max() ?? baseline.residentBytes,
                                     peakSampledPhysicalFootprintBytes: ordered.map(\.physicalFootprintBytes).max() ?? baseline.physicalFootprintBytes,
                                     largestSampleGapSeconds: gaps.max() ?? 0, previewReady: true,
                                     thumbnailBytes: appModel.previewThumbnailData?.count ?? 0, offscreenBitmapProduced: bitmap != nil)
                    } onCancel: { sampler.cancel() }
                } catch {
                    sampler.cancel(); _ = try? await sampler.value
                    throw error
                }
                report.stages.append(stage); try write(report, output)
            }
            await appModel.shutdown()
            report.phase = "complete"; report.completedAt = ISO8601DateFormatter().string(from: Date())
            try write(report, output)
            print("Winnel synthetic active-preview measurements complete; preview-performance.json.")
        } catch {
            if let model { await model.shutdown() }
            report.phase = "failed"; report.failure = (error as? Failure)?.rawValue ?? (error is CancellationError ? "cancelled" : "fixture-operation-failed")
            report.completedAt = ISO8601DateFormatter().string(from: Date())
            try? write(report, output)
            throw error
        }
    }
    private static func write(_ report: Report, _ output: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: output.appendingPathComponent("preview-performance.json"), options: .atomic)
    }
    nonisolated private static func resources(start: Double) throws -> Sample {
        var info = rusage_info_v0()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V0, $0) }
        }
        guard status == 0 else { throw Failure.resourceMeasurement }
        return .init(elapsedSeconds: ProcessInfo.processInfo.systemUptime - start, residentBytes: info.ri_resident_size, physicalFootprintBytes: info.ri_phys_footprint)
    }
    private static func seed(directory: URL, keys: FixtureVaultKeys) async throws -> Dataset {
        try await Task.detached {
            let text = Data(repeating: 0x61, count: 10 * 1_024 * 1_024)
            let png = try imageData()
            let payloads = [ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: text)]), ClipPayload(representations: [.init(type: "public.png", data: png)])]
            let encoded = try payloads.map { try JSONEncoder().encode($0) }
            guard encoded.allSatisfy({ $0.count < 20 * 1_024 * 1_024 }) else { throw Failure.invalidFixture }
            var settings = Settings()
            settings.captureEnabled = true; settings.capturePaused = false; settings.onboardingComplete = true
            settings.directPasteEnabled = false; settings.launchAtLogin = false; settings.updateChecksEnabled = false
            let now = Date()
            let items = payloads.enumerated().map { index, payload in
                ClipboardItem(copiedAt: now.addingTimeInterval(-Double(index)), source: .init(bundleIdentifier: "org.madeordinary.winnel.performance", name: "Synthetic Preview Fixture", confidence: .established), kind: index == 0 ? .text : .image, textPreview: index == 0 ? "Synthetic repetitive 10 MiB text" : "Synthetic solid 4096 × 4096 PNG", searchText: "Synthetic preview resource fixture", payloadByteCount: encoded[index].count, fingerprint: payload.fingerprint)
            }
            let state = LibraryState(items: items, settings: settings)
            let vault = try EncryptedVault(directory: directory, keyProvider: keys)
            try await vault.commit(manifest: JSONEncoder().encode(state), newPayloads: Dictionary(uniqueKeysWithValues: zip(items.map(\.id), encoded)), retaining: Set(items.map(\.id)))
            return Dataset(textID: items[0].id, imageID: items[1].id, textBytes: text.count, imagePNGBytes: png.count, imageWidth: 4096, imageHeight: 4096, serializedTextBytes: encoded[0].count, serializedImageBytes: encoded[1].count, encryptedDiskBytes: try await vault.usageBytes())
        }.value
    }
    nonisolated private static func imageData() throws -> Data {
        let width = 4096, height = 4096
        let pixels = Data(repeating: 0xff, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Failure.imageEncoding }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw Failure.imageEncoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.imageEncoding }
        return output as Data
    }
}
