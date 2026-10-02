import AppKit
import WinnelCore

public enum CaptureState: String, Sendable { case disabled, active, paused, suspended }
@MainActor public final class CaptureMonitor {
    public private(set) var state: CaptureState = .disabled
    public var exclusions: Set<String> = []
    public var onCapture: (ClipPayload, SourceApplication) -> Void
    public var onCaptureFailure: (CaptureSkipReason) -> Void
    public var onStateChange: (CaptureState) -> Void
    private let reader: PasteboardSnapshotReader
    private var generation = 0
    private var readInFlight = false
    private var readTask: Task<Void, Never>?
    private let permissionStatus: () -> ClipboardAccessStatus
    private let service: PasteboardService
    private var timer: Timer?
    private var lastCount: Int
    private var previousForeground: String?
    private var idleTicks = 0
    private var pendingSource: SourceApplication?
    private var pendingPrevious: String?
    private var observers: [NSObjectProtocol] = []
    public init(service: PasteboardService = .init(), onCapture: @escaping (ClipPayload, SourceApplication) -> Void, onStateChange: @escaping (CaptureState) -> Void = { _ in }, onCaptureFailure: @escaping (CaptureSkipReason) -> Void = { _ in }, permissionStatus: (() -> ClipboardAccessStatus)? = nil) {
        self.service = service; self.reader = PasteboardSnapshotReader(name: service.pasteboard.name.rawValue); self.onCapture = onCapture; self.onStateChange = onStateChange; self.onCaptureFailure = onCaptureFailure; self.permissionStatus = permissionStatus ?? { service.permissionStatus }; lastCount = service.changeCount
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspend() } })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspend() } })
    }
    public func enable() { resume() }
    public func resume() {
        generation += 1; readTask?.cancel()
        lastCount = service.changeCount
        pendingSource = nil; pendingPrevious = nil
        previousForeground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard preflightPermission() else { return }
        idleTicks = 0; setState(.active); schedule()
    }
    public func pause() { generation += 1; readTask?.cancel(); timer?.invalidate(); timer = nil; setState(.paused) }
    public func suspend() { generation += 1; readTask?.cancel(); timer?.invalidate(); timer = nil; setState(.suspended) }
    public func stop() { generation += 1; readTask?.cancel(); timer?.invalidate(); timer = nil; setState(.disabled) }
    private func preflightPermission() -> Bool {
        switch permissionStatus() {
        case .allowed: return true
        case .denied: pause(); onCaptureFailure(.permissionDenied); return false
        case .required: pause(); onCaptureFailure(.permissionRequired); return false
        }
    }
    private func setState(_ new: CaptureState) { state = new; onStateChange(new) }
    private func schedule() {
        timer?.invalidate()
        let delay: TimeInterval = pendingSource != nil ? 0.15 : idleTicks > 30 || !(NSApp?.isActive ?? false) ? 1 : 0.25
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }
    public func poll() {
        guard state == .active, preflightPermission() else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let foreground = app?.bundleIdentifier
        let oldForeground = previousForeground
        if oldForeground != foreground { generation += 1 }
        previousForeground = foreground
        let count = service.changeCount
        if count != lastCount {
            lastCount = count; idleTicks = 0
            pendingSource = SourceApplication(bundleIdentifier: foreground, name: app?.localizedName, confidence: foreground == nil ? .unknown : .inferred)
            pendingPrevious = oldForeground
        } else if let initialSource = pendingSource, !readInFlight {
            pendingSource = nil
            // Let advertised types settle for one bounded poll; recheck all markers in the
            // service as providers can add them without incrementing the change counter.
            if exclusions.contains(initialSource.bundleIdentifier ?? "") || exclusions.contains(foreground ?? "") || exclusions.contains(pendingPrevious ?? "") { schedule(); return }
            let source = initialSource.bundleIdentifier == foreground ? initialSource : SourceApplication()
            let epoch = generation
            let policy = service.policy
            let excluded = exclusions
            let previous = pendingPrevious
            let expectedForeground = foreground
            readInFlight = true
            readTask = Task {
                defer { readInFlight = false }
                guard !Task.isCancelled, state == .active, generation == epoch else { return }
                let result = await reader.read(policy: policy, source: source, excluded: excluded, previousForegroundID: previous)
                guard !Task.isCancelled, state == .active, generation == epoch, exclusions == excluded, service.changeCount == count,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expectedForeground else { return }
                switch result {
                case let .captured(payload, attribution): onCapture(payload, attribution)
                case .skipped(let reason) where reason == .permissionDenied || reason == .permissionRequired: pause(); onCaptureFailure(reason)
                default: break
                }
            }
            pendingPrevious = nil
        } else { idleTicks = min(idleTicks + 1, 100) }
        schedule()
    }
}
