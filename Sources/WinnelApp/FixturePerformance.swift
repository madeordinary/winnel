import AppKit
import SwiftUI
import CoreGraphics
import ImageIO
import Darwin
import WinnelCore
import WinnelStorage

struct PerformanceFixtureSeed {
    let directory: URL
    let keys: FixtureVaultKeys
}

/// Actual app-process measurements with production encrypted storage and timers.
/// Synthetic named clipboard only; no consent request, Keychain access or network.
@MainActor enum FixturePerformance {
    enum Failure: String, Error {
        case unsafeOutput = "unsafe-output"
        case invalidFixture = "invalid-fixture-startup"
        case imageEncoding = "image-encoding-failed"
        case resourceMeasurement = "resource-measurement-failed"
        case idleCaptureInactive = "idle-capture-inactive"
        case idleRecoveryDetected = "idle-recovery-detected"
    }
    private struct Resources: Codable {
        let cpuSeconds: Double
        let residentBytes: UInt64
        let physicalFootprintBytes: UInt64
    }
    private struct Sample: Codable {
        let elapsedSeconds: Double
        let meanCPUPercentOneCore: Double
        let residentBytes: UInt64
        let physicalFootprintBytes: UInt64
        let captureActive: Bool
    }
    private struct Dataset: Codable, Sendable {
        let totalItems: Int
        let recentItems: Int
        let savedItems: Int
        let textItems: Int
        let imageItems: Int
        let rawTextBytesPerItem: Int
        let imageWidth: Int
        let imageHeight: Int
        let serializedPayloadBytes: Int
        let encryptedDiskBytes: Int
        let description: String
    }
    private struct Report: Encodable {
        var schemaVersion = 1
        var phase = "initializing"
        let processID: Int32
        let startedAt: String
        let requestedIdleSeconds: Double
        let os: String
        let hardwareModel: String
        let physicalMemoryBytes: UInt64
        let processorCount: Int
        var dataset: Dataset?
        var seedMilliseconds: Double?
        var modelStartupMilliseconds: Double?
        var repositorySearchMilliseconds: [Double] = []
        var repositorySearchP95Milliseconds: Double?
        var searchResultChecksum = 0
        var paletteLayoutMilliseconds: [Double] = []
        var paletteLayoutP95Milliseconds: Double?
        var samples: [Sample] = []
        var elapsedIdleSeconds: Double = 0
        var finalMeanCPUPercentOneCore: Double?
        var peakResidentBytes: UInt64?
        var meanResidentBytes: Double?
        var completedAt: String?
        var observedThresholds: [String: Bool] = [:]
        var failure: String?
        var captureStateBeforeShutdown: String?
        var recoveryPresentBeforeShutdown: Bool?
        let measurementScope = "Release Winnel process, NSApplication.run, real encrypted repository, active production CaptureMonitor, active 30-second retention timer, retained actual PaletteView hosting tree. No menu-bar delegate or registered global shortcuts in this mode."
        let startupCondition = "First AppModel/repository initialization after same-process encrypted seeding. OS filesystem caches are warm; this is not cold process launch or cold OS-cache timing."
        let cpuDefinition = "getrusage user+system CPU delta / monotonic wall-clock delta * 100; 100% equals one logical core. proc_pid_rusage supplies current resident bytes including loaded frameworks."
        let privacy = "1,200 generated synthetic payloads, unique temporary app-owned vault and named pasteboard; in-memory fixture key only. No general clipboard, Keychain, permission prompts, external files, OS screenshots, accessibility automation or update traffic."
        let unverified = ["Reference M1 MacBook Air 8 GB results", "macOS 14 hardware observations", "External-display and other-device observations", "True cold app launch", "Shortcut-to-visible-palette latency", "Keyboard/VoiceOver interaction", "Cross-app paste reliability"]
    }

    static func run(outputDirectory: URL, idleSeconds: Double) async throws {
        let output = outputDirectory.standardizedFileURL
        guard output.isFileURL, output.path.hasPrefix(FileManager.default.currentDirectoryPath + "/build/"),
              output.resolvingSymlinksInPath() == output, idleSeconds.isFinite, idleSeconds >= 1 else { throw Failure.unsafeOutput }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let started = ISO8601DateFormatter().string(from: Date())
        var report = Report(processID: getpid(), startedAt: started, requestedIdleSeconds: idleSeconds,
                            os: ProcessInfo.processInfo.operatingSystemVersionString, hardwareModel: hardwareModel(),
                            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                            processorCount: ProcessInfo.processInfo.processorCount)
        try write(report, to: output)
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-performance-" + UUID().uuidString, isDirectory: true)
        let keys = FixtureVaultKeys()
        let board = NSPasteboard(name: .init("org.madeordinary.winnel.performance." + UUID().uuidString))
        defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: vault) }
        var model: AppModel?
        do {
            let seedStart = ProcessInfo.processInfo.systemUptime
            report.dataset = try await seed(directory: vault, keys: keys)
            report.seedMilliseconds = (ProcessInfo.processInfo.systemUptime - seedStart) * 1_000
            let startupStart = ProcessInfo.processInfo.systemUptime
            let appModel = AppModel(fixtureMode: true, pasteboard: board, performanceFixture: .init(directory: vault, keys: keys))
            model = appModel
            await appModel.start()
            report.modelStartupMilliseconds = (ProcessInfo.processInfo.systemUptime - startupStart) * 1_000
            guard appModel.recoveryMessage == nil, appModel.captureState == .active,
                  appModel.state.items.count == 1_200, appModel.state.recentItems.count == 200,
                  appModel.state.items.filter({ appModel.state.isSaved($0.id) }).count == 1_000 else { throw Failure.invalidFixture }
            report.phase = "search-and-render"
            try write(report, to: output)
            let queries = ["synthetic performance", "needle-1199", "needle-0199", "fixture source", "not-present-query"]
            for index in 0..<100 {
                let beginning = ProcessInfo.processInfo.systemUptime
                report.searchResultChecksum += try await appModel.performanceSearch(queries[index % queries.count])
                report.repositorySearchMilliseconds.append((ProcessInfo.processInfo.systemUptime - beginning) * 1_000)
            }
            report.repositorySearchP95Milliseconds = p95(report.repositorySearchMilliseconds)
            let host = NSHostingView(rootView: PaletteView(model: appModel))
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 660)
            host.layoutSubtreeIfNeeded()
            for _ in 0..<100 {
                let beginning = ProcessInfo.processInfo.systemUptime
                host.needsLayout = true; host.layoutSubtreeIfNeeded()
                report.paletteLayoutMilliseconds.append((ProcessInfo.processInfo.systemUptime - beginning) * 1_000)
            }
            report.paletteLayoutP95Milliseconds = p95(report.paletteLayoutMilliseconds)
            // Settle transient seed/search allocations before the observed idle interval.
            try await Task.sleep(for: .seconds(2))
            let baseline = try resources()
            let idleStart = ProcessInfo.processInfo.systemUptime
            report.phase = "idle-running"
            report.samples.append(.init(elapsedSeconds: 0, meanCPUPercentOneCore: 0,
                                        residentBytes: baseline.residentBytes, physicalFootprintBytes: baseline.physicalFootprintBytes,
                                        captureActive: appModel.captureState == .active))
            try write(report, to: output)
            try write(report, to: output, filename: "performance-initial.json")
            print("Winnel performance fixture PID \(getpid()); idle interval \(Int(idleSeconds)) seconds started \(ISO8601DateFormatter().string(from: Date())).")
            fflush(stdout)
            while true {
                let elapsed = ProcessInfo.processInfo.systemUptime - idleStart
                guard elapsed < idleSeconds else { break }
                try await Task.sleep(for: .seconds(min(15, idleSeconds - elapsed)))
                let current = try resources()
                let observed = ProcessInfo.processInfo.systemUptime - idleStart
                let cpu = (current.cpuSeconds - baseline.cpuSeconds) / observed * 100
                report.elapsedIdleSeconds = observed
                report.samples.append(.init(elapsedSeconds: observed, meanCPUPercentOneCore: cpu,
                                            residentBytes: current.residentBytes, physicalFootprintBytes: current.physicalFootprintBytes,
                                            captureActive: appModel.captureState == .active))
                try write(report, to: output)
                guard appModel.recoveryMessage == nil else { throw Failure.idleRecoveryDetected }
                guard appModel.captureState == .active else { throw Failure.idleCaptureInactive }
            }
            let last = try resources()
            let elapsed = ProcessInfo.processInfo.systemUptime - idleStart
            report.elapsedIdleSeconds = elapsed
            report.finalMeanCPUPercentOneCore = (last.cpuSeconds - baseline.cpuSeconds) / elapsed * 100
            report.peakResidentBytes = report.samples.map(\.residentBytes).max()
            report.meanResidentBytes = report.samples.reduce(0) { $0 + Double($1.residentBytes) } / Double(report.samples.count)
            report.observedThresholds = [
                "full30MinuteIdleObserved": elapsed >= 1_800,
                "captureActiveThroughoutSampledInterval": report.samples.allSatisfy(\.captureActive),
                "localRepositorySearchP95AtMost100ms": (report.repositorySearchP95Milliseconds ?? .infinity) <= 100,
                "localHostingLayoutP95AtMost100ms": (report.paletteLayoutP95Milliseconds ?? .infinity) <= 100,
                "localMeanIdleCPUAtMost0_5PercentOneCore": (report.finalMeanCPUPercentOneCore ?? .infinity) <= 0.5,
                "localPeakSampledResidentBytesAtMost150MiB": (report.peakResidentBytes ?? .max) <= 150 * 1_024 * 1_024
            ]
            // Keep the actual hosting tree alive through every idle sample.
            withExtendedLifetime(host) {}
            report.captureStateBeforeShutdown = appModel.captureState.rawValue
            report.recoveryPresentBeforeShutdown = appModel.recoveryMessage != nil
            await appModel.shutdown()
            report.phase = "complete"; report.completedAt = ISO8601DateFormatter().string(from: Date())
            try write(report, to: output)
            try write(report, to: output, filename: "performance-final.json")
            print("Winnel isolated performance measurement complete; results in performance.json.")
        } catch {
            if let model {
                report.captureStateBeforeShutdown = model.captureState.rawValue
                report.recoveryPresentBeforeShutdown = model.recoveryMessage != nil
                await model.shutdown()
            }
            report.phase = "failed"
            report.failure = (error as? Failure)?.rawValue ?? (error is CancellationError ? "measurement-cancelled" : "fixture-operation-failed")
            report.completedAt = ISO8601DateFormatter().string(from: Date())
            try? write(report, to: output)
            throw error
        }
    }
    private static func write(_ report: Report, to directory: URL, filename: String = "performance.json") throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(report)
        try bytes.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }
    private static func resources() throws -> Resources {
        var cpu = rusage()
        guard getrusage(RUSAGE_SELF, &cpu) == 0 else { throw Failure.resourceMeasurement }
        let seconds = Double(cpu.ru_utime.tv_sec + cpu.ru_stime.tv_sec) + Double(cpu.ru_utime.tv_usec + cpu.ru_stime.tv_usec) / 1_000_000
        var info = rusage_info_v0()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V0, $0) }
        }
        guard status == 0 else { throw Failure.resourceMeasurement }
        return .init(cpuSeconds: seconds, residentBytes: info.ri_resident_size, physicalFootprintBytes: info.ri_phys_footprint)
    }
    private static func hardwareModel() -> String {
        var length = 0
        guard sysctlbyname("hw.model", nil, &length, nil, 0) == 0, length > 0 else { return "Unavailable" }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname("hw.model", &bytes, &length, nil, 0) == 0 else { return "Unavailable" }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
    private static func p95(_ values: [Double]) -> Double { values.sorted()[Int(ceil(Double(values.count) * 0.95)) - 1] }
    private static func seed(directory: URL, keys: FixtureVaultKeys) async throws -> Dataset {
        try await Task.detached {
            let now = Date()
            var settings = Settings()
            settings.captureEnabled = true; settings.capturePaused = false; settings.onboardingComplete = true
            settings.directPasteEnabled = false; settings.launchAtLogin = false; settings.updateChecksEnabled = false
            settings.retention = .oneDay
            var items: [ClipboardItem] = [], payloads: [UUID: Data] = [:]
            var totalBytes = 0
            let image = try imageData()
            for index in 0..<1_200 {
                let isImage = index % 10 == 0
                let text = String(("Synthetic performance excerpt \(index), needle-\(String(format: "%04d", index)). " + String(repeating: "A bounded offline excerpt for local search. ", count: 40)).prefix(1_024))
                let payload = isImage ? ClipPayload(representations: [.init(type: "public.png", data: image)]) : ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(text.utf8))])
                let encoded = try JSONEncoder().encode(payload)
                let item = ClipboardItem(copiedAt: now.addingTimeInterval(-Double(index)),
                                         source: .init(bundleIdentifier: "org.madeordinary.winnel.performance", name: "Fixture Source", confidence: .established),
                                         kind: isImage ? .image : .text, textPreview: isImage ? "Synthetic 256 × 256 PNG" : text,
                                         searchText: isImage ? "Synthetic generated image" : text,
                                         payloadByteCount: encoded.count, fingerprint: payload.fingerprint, isRecent: index < 200)
                items.append(item); payloads[item.id] = encoded; totalBytes += encoded.count
            }
            let stack = SavedStack(name: "Synthetic Performance Saved Stack", memberships: items.dropFirst(200).map { .init(itemID: $0.id) })
            let state = LibraryState(items: items, stacks: [stack], settings: settings)
            let vault = try EncryptedVault(directory: directory, keyProvider: keys)
            try await vault.commit(manifest: JSONEncoder().encode(state), newPayloads: payloads, retaining: Set(items.map(\.id)))
            let usage = try await vault.usageBytes()
            return Dataset(totalItems: 1_200, recentItems: 200, savedItems: 1_000, textItems: 1_080, imageItems: 120,
                           rawTextBytesPerItem: 1_024, imageWidth: 256, imageHeight: 256,
                           serializedPayloadBytes: totalBytes, encryptedDiskBytes: usage,
                           description: "1080 generated UTF-8 text payloads of 1024 bytes and 120 PNG payloads of 256×256 deterministic RGBA noise (identical fixture bytes stored under independent UUIDs); 20 recent images/180 recent text, 100 saved images/900 saved text; 1000 ordered memberships in one saved stack. No personal content.")
        }.value
    }
    nonisolated private static func imageData() throws -> Data {
        let width = 256, height = 256
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var random: UInt32 = 0x57494e4e
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 { random = 1_664_525 &* random &+ 1_013_904_223; pixels[index + channel] = UInt8(truncatingIfNeeded: random >> 24) }
            pixels[index + 3] = 255
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Failure.imageEncoding }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw Failure.imageEncoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.imageEncoding }
        return output as Data
    }
}
