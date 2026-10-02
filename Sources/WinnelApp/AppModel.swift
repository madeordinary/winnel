import AppKit
import Combine
import ServiceManagement
import WinnelCore
import WinnelPlatform
import WinnelStorage

enum LibraryScope: String, CaseIterable { case recent, pinned, all }

@MainActor final class AppModel: ObservableObject {
    @Published var state = LibraryState()
    @Published var searchQuery = "" { didSet { refreshSearch() } }
    @Published var libraryScope: LibraryScope = .recent
    @Published var selectedIDs: Set<UUID> = []
    @Published var selectionOrder: [UUID] = []
    @Published var queue: PasteQueue?
    @Published var status = "Capture is off. Enable it when you are ready."
    @Published var recoveryMessage: String?
    @Published var captureState: CaptureState = .disabled
    @Published private(set) var clipboardAccessStatus: ClipboardAccessStatus = .allowed
    @Published var usageBytes = 0
    @Published var combinationPreview = ""
    @Published var combinationFormat: CombinationFormat = .newline
    @Published var previewPayload: ClipPayload?
    @Published private(set) var previewThumbnailData: Data?
    @Published private(set) var previewThumbnailFinished = false
    @Published private var searchResults: [ClipboardItem] = []
    let fixtureMode: Bool
    let pasteboardService: PasteboardService
    let targetService = PasteTargetService()
    var onDismissPalette: (() -> Void)?
    var onDismissOnboarding: (() -> Void)?
    var onShowLibrary: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onSettingsChanged: ((Settings) -> Void)?
    var onTestShortcuts: (() -> Void)?
    private var repository: LibraryRepository?
    private let performanceFixture: PerformanceFixtureSeed?
    private var vaultDirectory: URL?
    private var paletteTarget: WinnelPlatform.PasteTarget?
    private var retentionTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var combinationGeneration = 0
    private var previewGeneration = 0
    private var captureControlGeneration = 0
    private var contentGeneration = 0
    private var queueGeneration = 0
    private var queueDispatchPending = false
    private var lifecycleSuspended = false
    private var contentTasks: [UUID: Task<Void, Never>] = [:]
    private enum ContentOperationKind: Hashable { case preview, combination, queuePreparation, queueDispatch, clipboard, exportPreparation }
    private var contentSlots: [ContentOperationKind: (id: UUID, task: Task<Void, Never>)] = [:]
    private var clearClipboardCount: Int?
    private var appliedRevision = -1
    private var lastCommittedSettings = Settings()
    private var startupComplete = false
    private var shuttingDown = false
    private var explicitPause = false
    private var settingsWriteTask: Task<Void, Never>?
    lazy var monitor = CaptureMonitor(service: pasteboardService, onCapture: { [weak self] payload, source in
        self?.capture(payload, source: source)
    }, onStateChange: { [weak self] new in
        self?.captureState = new
        if new == .suspended {
            self?.lifecycleSuspended = true
            self?.captureControlGeneration += 1
            self?.invalidateContentOperations()
        }
    }, onCaptureFailure: { [weak self] reason in
        guard let self else { return }
        self.refreshClipboardAccessStatus()
        if reason == .permissionDenied { self.status = "Capture paused: clipboard access is denied in macOS. Review access in Settings." }
        else if reason == .permissionRequired { self.status = "Capture paused: clipboard access needs your choice. Request access in Settings." }
    })
    init(fixtureMode: Bool = false, repository: LibraryRepository? = nil, pasteboard: NSPasteboard? = nil, performanceFixture: PerformanceFixtureSeed? = nil) {
        precondition(performanceFixture == nil || (fixtureMode && pasteboard?.name.rawValue.hasPrefix("org.madeordinary.winnel.performance.") == true), "Performance data requires its isolated named pasteboard")
        self.performanceFixture = performanceFixture
        self.fixtureMode = fixtureMode
        self.repository = repository
        self.startupComplete = repository != nil
        pasteboardService = PasteboardService(pasteboard: pasteboard ?? (fixtureMode ? NSPasteboard(name: .init("org.madeordinary.winnel.fixture")) : .general))
        clipboardAccessStatus = pasteboardService.permissionStatus
    }
    var visibleItems: [ClipboardItem] {
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return searchResults }
        switch libraryScope {
        case .recent: return state.recentItems
        case .pinned: return state.items.filter(\.isPinned).sorted { $0.copiedAt > $1.copiedAt }
        case .all: return state.items.sorted { $0.copiedAt > $1.copiedAt }
        }
    }
    var selectedItems: [ClipboardItem] {
        let ordered = selectionOrder.filter { selectedIDs.contains($0) }
        let rest = state.items.filter { selectedIDs.contains($0.id) && !ordered.contains($0.id) }.sorted { $0.copiedAt > $1.copiedAt }.map(\.id)
        return (ordered + rest).compactMap { id in state.items.first { $0.id == id } }
    }
    var accessibilityGranted: Bool { targetService.hasPermission }
    var settings: Settings { state.settings }
    var isShuttingDown: Bool { shuttingDown }
    var isPaused: Bool { captureState == .paused || captureState == .suspended }
    func start() async {
        guard !startupComplete else { return }
        startupComplete = true
        do {
            let directory: URL
            if let performanceFixture { directory = performanceFixture.directory }
            else if fixtureMode { directory = FileManager.default.temporaryDirectory.appendingPathComponent("winnel-fixture-" + UUID().uuidString) }
            else {
                let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let parent = support.appendingPathComponent("org.madeordinary.winnel", isDirectory: true)
                guard parent.deletingLastPathComponent().resolvingSymlinksInPath() == parent.deletingLastPathComponent().standardizedFileURL else { throw VaultError.unsafePath }
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                directory = parent.appendingPathComponent("vault", isDirectory: true)
            }
            vaultDirectory = directory
            let provider: any VaultKeyProvider = performanceFixture?.keys ?? (fixtureMode ? FixtureVaultKeys() : KeychainVaultKeyProvider())
            let repo = try LibraryRepository(directory: directory, provider: provider)
            repository = repo
            apply(try await repo.load(now: Date()))
            onSettingsChanged?(state.settings)
            explicitPause = state.settings.capturePaused == true && state.settings.pauseUntil == nil
            resumeIfPermitted()
            if state.settings.updateChecksEnabled { checkForUpdates(automatic: true) }
        } catch { fail(error) }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    /// Only the isolated performance mode calls this. It measures the production
    /// repository search instead of replacing it with a metadata-only mock.
    func performanceSearch(_ query: String) async throws -> Int {
        guard fixtureMode, performanceFixture != nil, let repository else { throw FixturePerformance.Failure.invalidFixture }
        return try await repository.search(query).count
    }
    /// A deletion, recovery, lock or shutdown revokes every pending plaintext operation.
    private func invalidateContentOperations() {
        contentGeneration += 1; queueGeneration += 1; queueDispatchPending = false
        previewGeneration += 1; combinationGeneration += 1
        for task in contentTasks.values { task.cancel() }
        queue?.cancel(); queue = nil
        previewPayload = nil; previewThumbnailData = nil; previewThumbnailFinished = false; combinationPreview = ""
        searchTask?.cancel(); searchResults = []
    }
    private func contentOperationIsCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == contentGeneration && !shuttingDown && !lifecycleSuspended && recoveryMessage == nil
    }
    private func runContentOperation(kind: ContentOperationKind, _ action: @escaping @MainActor (Int) async -> Void) {
        let generation = contentGeneration
        guard contentOperationIsCurrent(generation) else { return }
        let predecessor = contentSlots[kind]?.task
        predecessor?.cancel()
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.contentTasks.removeValue(forKey: id)
                if self.contentSlots[kind]?.id == id { self.contentSlots.removeValue(forKey: kind) }
            }
            // Cancellation is cooperative. Wait for the preceding worker to release
            // its plaintext before allowing this kind to load another selection.
            await predecessor?.value
            guard self.contentOperationIsCurrent(generation) else { return }
            await action(generation)
        }
        contentTasks[id] = task
        contentSlots[kind] = (id, task)
    }
    private func detachedContent<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached {
            try Task.checkCancellation()
            return try action()
        }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: { task.cancel() }
    }
    // Joins tracked work during deterministic fixture verification without polling/sleeps.
    func waitForContentOperations() async {
        let tasks = Array(contentTasks.values)
        for task in tasks { await task.value }
    }
    private func apply(_ snapshot: RepositorySnapshot) {
        guard snapshot.revision >= appliedRevision else { return }
        appliedRevision = snapshot.revision
        lastCommittedSettings = snapshot.state.settings
        state = snapshot.state; usageBytes = snapshot.usage
        selectedIDs.formIntersection(state.items.map(\.id)); selectionOrder.removeAll { !selectedIDs.contains($0) }
        if snapshot.warning { fail(VaultError.garbageCollectionFailed) }
        refreshSearch()
    }
    private func fail(_ error: Error) {
        captureControlGeneration += 1
        invalidateContentOperations()
        state.settings = lastCommittedSettings
        monitor.pause()
        if (error as? VaultError) == .storageLimit || (error as? LibraryError) == .savedStorageFull {
            recoveryMessage = "The managed storage budget is full, including encrypted metadata and transaction space. Pins and stacks have been preserved. Open Settings to clear recent history or Saved Stacks to remove items you no longer need, then retry capture."
        } else {
            recoveryMessage = error is VaultError ? "Encrypted storage is unavailable or needs recovery. Existing saved content has been preserved. Retry, export the encrypted recovery files, or explicitly reset app data." : "The action could not finish. Existing content is preserved. Check storage and try again."
        }
        status = "Capture paused: action or storage failed."
    }
    private func perform(_ change: @escaping @Sendable (inout LibraryState) throws -> Void, success: String? = nil) {
        guard !shuttingDown else { return }
        Task {
            guard let repository else { status = "Storage is not ready."; return }
            do { let snapshot = try await repository.mutate(change); apply(snapshot); if !snapshot.warning, let success { status = success } }
            catch { fail(error) }
        }
    }
    private func capture(_ payload: ClipPayload, source: SourceApplication) {
        guard state.settings.captureEnabled, recoveryMessage == nil, captureState == .active, !shuttingDown else { return }
        guard captureTask == nil else {
            status = "Skipped a clipboard change while the previous capture is saving."
            return
        }
        let ids = queue?.retainedIDs ?? []
        let generation = captureControlGeneration
        captureTask = Task {
            defer { captureTask = nil }
            guard generation == captureControlGeneration, captureState == .active, let repository else { return }
            do {
                let snapshot = try await repository.ingest(payload, source: source, now: Date(), sessionIDs: ids, isStillAuthorized: { [weak self] in
                    await MainActor.run { guard let self else { return false }; return generation == self.captureControlGeneration && self.captureState == .active && !self.lifecycleSuspended && !self.shuttingDown && self.recoveryMessage == nil }
                })
                apply(snapshot)
                if !snapshot.warning, generation == captureControlGeneration, captureState == .active { status = "Capture active." }
            } catch let transition as RepositoryTransitionError {
                apply(transition.snapshot)
                if !(transition.cause is CancellationError) { fail(transition.cause) }
            } catch is CancellationError { }
            catch { fail(error) }
        }
    }
    private func refreshSearch() {
        searchTask?.cancel()
        let query = searchQuery
        guard !lifecycleSuspended, !shuttingDown, recoveryMessage == nil else { searchResults = []; return }
        guard !query.isEmpty, let repository else { searchResults = state.search(query); return }
        searchTask = Task {
            do { let result = try await repository.search(query); guard !Task.isCancelled, searchQuery == query else { return }; searchResults = result }
            catch { guard !Task.isCancelled else { return }; fail(error) }
        }
    }
    func enableCapture() {
        guard recoveryMessage == nil else { status = "Resolve storage recovery before enabling capture."; return }
        captureControlGeneration += 1
        let generation = captureControlGeneration
        Task {
            guard let repository else { return }
            do {
                apply(try await repository.mutate { $0.settings.captureEnabled = true; $0.settings.pauseUntil = nil; $0.settings.capturePaused = false })
                guard recoveryMessage == nil, generation == captureControlGeneration else { return }; explicitPause = false; resumeIfPermitted()
                if captureState == .active { status = "Capture active. Earlier clipboard contents were not imported." }
            } catch { fail(error) }
        }
    }
    func disableCapture() { captureControlGeneration += 1; monitor.stop(); perform({ $0.settings.captureEnabled = false; $0.settings.capturePaused = false }, success: "Capture is off.") }
    func pause(until: Date? = nil) {
        captureControlGeneration += 1; explicitPause = true; monitor.pause()
        perform({ $0.settings.pauseUntil = until; $0.settings.capturePaused = true }, success: until.map { "Paused until \($0.formatted(date: .abbreviated, time: .shortened))." } ?? "Paused until you resume.")
    }
    func resumeCapture() {
        guard recoveryMessage == nil, state.settings.captureEnabled else { return }
        captureControlGeneration += 1; let generation = captureControlGeneration
        explicitPause = false
        Task {
            guard let repository else { return }
            do { apply(try await repository.mutate { $0.settings.pauseUntil = nil; $0.settings.capturePaused = false }); if generation == captureControlGeneration { resumeIfPermitted() } }
            catch { fail(error) }
        }
    }
    private func resumeIfPermitted() {
        monitor.exclusions = state.settings.excludedBundleIdentifiers
        guard !lifecycleSuspended else { monitor.suspend(); return }
        guard state.settings.captureEnabled, recoveryMessage == nil, !explicitPause, !shuttingDown else { monitor.stop(); return }
        if state.settings.capturePaused == true && state.settings.pauseUntil == nil { monitor.pause(); status = "Capture paused until you resume." }
        else if let deadline = state.settings.pauseUntil, deadline > Date() { monitor.pause() }
        else { monitor.resume(); refreshClipboardAccessStatus(); if captureState == .active { status = "Capture active." } }
    }
    func refreshClipboardAccessStatus() { clipboardAccessStatus = pasteboardService.permissionStatus }
    /// Called only by the visible Request clipboard access button. The probe is discarded.
    func requestClipboardAccess() {
        clipboardAccessStatus = pasteboardService.requestAccessFromUserAction()
        if clipboardAccessStatus == .allowed {
            resumeIfPermitted()
            if !state.settings.captureEnabled { status = "Clipboard access is available. Capture stays off until you enable it." }
        } else {
            monitor.pause()
            status = clipboardAccessStatus == .denied ? "Clipboard access was not granted. Capture remains paused." : "Choose Allow in macOS for automatic capture, then recheck access. Capture remains paused."
        }
    }
    func updateSettings(_ transform: (inout Settings) -> Void) {
        var settings = state.settings; transform(&settings); updateSettings(settings)
    }
    private func loginChoice(_ enabled: Bool, previous: Bool) -> Bool {
        guard enabled != previous else { return enabled }
        guard !fixtureMode else { return false }
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; return enabled }
        catch { status = "Launch at login could not be changed. Use a packaged app and review macOS Login Items."; return previous }
    }
    func updateSettings(_ requested: Settings) {
        let baseline = state.settings
        var settings = requested
        settings.launchAtLogin = loginChoice(requested.launchAtLogin, previous: state.settings.launchAtLogin)
        let committedSettings = settings
        state.settings = settings
        captureControlGeneration += 1; let generation = captureControlGeneration
        if lifecycleSuspended { monitor.suspend() } else { monitor.pause() }
        settingsWriteTask = Task {
            guard let repository else { return }
            do {
                let snapshot = try await repository.mutate { state in
                    let previous = state.settings.retention
                    state.settings = Self.mergeSettings(requested: committedSettings, baseline: baseline, current: state.settings)
                    if previous != .ramOnly && state.settings.retention == .ramOnly { _ = state.clearRecent() }
                    _ = state.enforceRetention(now: Date())
                }
                apply(snapshot)
                guard recoveryMessage == nil else { return }
                onSettingsChanged?(state.settings); if generation == captureControlGeneration { resumeIfPermitted() }
                if state.settings.updateChecksEnabled { checkForUpdates(automatic: true) }
            } catch { fail(error) }
        }
    }
    nonisolated private static func mergeSettings(requested: Settings, baseline: Settings, current: Settings) -> Settings {
        var result = current
        if requested.onboardingComplete != baseline.onboardingComplete { result.onboardingComplete = requested.onboardingComplete }
        if requested.captureEnabled != baseline.captureEnabled { result.captureEnabled = requested.captureEnabled }
        if requested.capturePaused != baseline.capturePaused { result.capturePaused = requested.capturePaused }
        if requested.pauseUntil != baseline.pauseUntil { result.pauseUntil = requested.pauseUntil }
        if requested.retention != baseline.retention { result.retention = requested.retention }
        if requested.excludedBundleIdentifiers != baseline.excludedBundleIdentifiers { result.excludedBundleIdentifiers = requested.excludedBundleIdentifiers }
        if requested.defaultAction != baseline.defaultAction { result.defaultAction = requested.defaultAction }
        if requested.directPasteEnabled != baseline.directPasteEnabled { result.directPasteEnabled = requested.directPasteEnabled }
        if requested.launchAtLogin != baseline.launchAtLogin { result.launchAtLogin = requested.launchAtLogin }
        if requested.updateChecksEnabled != baseline.updateChecksEnabled { result.updateChecksEnabled = requested.updateChecksEnabled }
        if requested.paletteShortcutKeyCode != baseline.paletteShortcutKeyCode { result.paletteShortcutKeyCode = requested.paletteShortcutKeyCode }
        if requested.paletteShortcutModifiers != baseline.paletteShortcutModifiers { result.paletteShortcutModifiers = requested.paletteShortcutModifiers }
        if requested.nextShortcutKeyCode != baseline.nextShortcutKeyCode { result.nextShortcutKeyCode = requested.nextShortcutKeyCode }
        if requested.nextShortcutModifiers != baseline.nextShortcutModifiers { result.nextShortcutModifiers = requested.nextShortcutModifiers }
        if requested.recentLimit != baseline.recentLimit { result.recentLimit = requested.recentLimit }
        if requested.captureByteLimit != baseline.captureByteLimit { result.captureByteLimit = requested.captureByteLimit }
        if requested.storageByteLimit != baseline.storageByteLimit { result.storageByteLimit = requested.storageByteLimit }
        return result
    }
    func finishOnboarding(capture: Bool, directPaste: Bool, launchAtLogin: Bool, updates: Bool) {
        captureControlGeneration += 1; let generation = captureControlGeneration
        monitor.stop()
        let login = loginChoice(launchAtLogin, previous: state.settings.launchAtLogin)
        Task { do {
            guard let repository else { status = "Resolve storage recovery before finishing onboarding."; return }
            let snapshot = try await repository.mutate {
                $0.settings.onboardingComplete = true; $0.settings.captureEnabled = capture
                $0.settings.directPasteEnabled = directPaste; $0.settings.launchAtLogin = login
                $0.settings.updateChecksEnabled = updates; $0.settings.pauseUntil = nil; $0.settings.capturePaused = false
            }
            apply(snapshot); guard recoveryMessage == nil else { return }
            explicitPause = false; onSettingsChanged?(state.settings); if generation == captureControlGeneration { resumeIfPermitted() }; onDismissOnboarding?()
            if updates { checkForUpdates(automatic: true) }
        } catch { fail(error) } }
    }
    func completeOnboarding() { perform({ $0.settings.onboardingComplete = true }, success: "Ready. Capture starts when you enable it.") }
    func requestAccessibility() {
        let granted = targetService.requestPermissionFromUserAction()
        var settings = state.settings; settings.directPasteEnabled = granted; updateSettings(settings)
        status = granted ? "Accessibility is available. Paste remains limited to validated apps." : "Accessibility has not been granted. Copy remains available."
    }
    func capturePaletteTarget() { paletteTarget = targetService.captureTarget() }
    func loadPreview(_ id: UUID) {
        previewPayload = nil; previewThumbnailData = nil; previewThumbnailFinished = false; previewGeneration += 1
        let generation = previewGeneration
        let isImage = state.items.first { $0.id == id }?.kind == .image
        runContentOperation(kind: .preview) { operation in
            do {
                guard self.contentOperationIsCurrent(operation), self.previewGeneration == generation else { return }
                guard let payload = try await self.repository?.payload(id) else { return }
                guard self.contentOperationIsCurrent(operation), self.previewGeneration == generation else { return }
                let (preview, thumbnail) = try await self.detachedContent {
                    let preview = Self.resolvingFileMetadata(payload)
                    try Task.checkCancellation()
                    let bytes = isImage ? payload.representations.first { ["public.png", "public.tiff", "public.jpeg"].contains($0.type) }?.data : nil
                    // ImageIO work cannot be interrupted mid-decode. The preview slot
                    // waits for this worker to finish before loading another payload.
                    let thumbnail = bytes.flatMap { CapturePolicy().thumbnail($0) }
                    try Task.checkCancellation()
                    return (preview, thumbnail)
                }
                guard self.contentOperationIsCurrent(operation), self.previewGeneration == generation, self.selectedItems.first?.id == id else { return }
                self.previewThumbnailData = thumbnail; self.previewThumbnailFinished = true; self.previewPayload = preview
            }
            catch { if self.contentOperationIsCurrent(operation) { self.fail(error) } }
        }
    }
    func copySelected() { useSelected(paste: false) }
    func pasteSelected() { useSelected(paste: true) }
    private func useSelected(paste: Bool) {
        guard let item = selectedItems.first else { return }
        let expected = paletteTarget
        runContentOperation(kind: .clipboard) { [self] operation in
            do {
                guard let payload = try await repository?.payload(item.id) else { return }
                guard contentOperationIsCurrent(operation) else { return }
                guard pasteboardService.write(payload) else { status = "Clipboard write failed."; return }
                let writtenCount = pasteboardService.changeCount
                onDismissPalette?()
                if paste, pasteboardService.changeCount != writtenCount { status = "Clipboard changed. Paste canceled; copy the selected item again when ready."; return }
                if paste, state.settings.directPasteEnabled, let expected {
                    let result = await targetService.waitForModifiersThenDispatch(to: expected, isCurrent: { [self] in
                        contentOperationIsCurrent(operation) && state.settings.directPasteEnabled && pasteboardService.changeCount == writtenCount
                    })
                    guard contentOperationIsCurrent(operation) else { return }
                    guard pasteboardService.changeCount == writtenCount else { status = "Clipboard changed. Paste canceled; copy the selected item again when ready."; return }
                    status = result == .dispatched ? "Paste request sent. Destination consumption is unconfirmed." : "Copied. Press Command-V in your destination."
                } else { status = paste ? "Copied. Press Command-V in your destination." : "Copied." }
            } catch { if contentOperationIsCurrent(operation) { fail(error) } }
        }
    }
    func togglePin(_ id: UUID) { perform({ state in guard let item = state.items.first(where: { $0.id == id }) else { throw LibraryError.missingItem }; _ = try state.setPinned(id, !item.isPinned, now: Date()) }) }
    func createStack(name: String) { let ids = selectedItems.map(\.id); perform({ _ = try $0.createStack(name: name, itemIDs: ids) }, success: "Stack saved.") }
    func renameStack(_ id: UUID, name: String) { perform { try $0.renameStack(id, name: name) } }
    func reorderStack(_ id: UUID, itemIDs: [UUID]) { perform { try $0.reorderStack(id, itemIDs: itemIDs) } }
    func deleteStack(_ id: UUID) { perform { _ = $0.deleteStack(id, now: Date()) } }
    func addToStack(_ id: UUID) {
        let ids = selectedItems.map(\.id)
        perform { state in
            guard let stack = state.stacks.first(where: { $0.id == id }) else { throw LibraryError.missingStack }
            var members = stack.memberships
            for itemID in ids where !members.contains(where: { $0.itemID == itemID }) { members.append(.init(itemID: itemID)) }
            _ = try state.setMemberships(id, memberships: members, now: Date())
        }
    }
    func removeFromStack(_ id: UUID, itemID: UUID) { perform { state in guard let stack = state.stacks.first(where: { $0.id == id }) else { throw LibraryError.missingStack }; _ = try state.setMemberships(id, memberships: stack.memberships.filter { $0.itemID != itemID }, now: Date()) } }
    func associateURL(stackID: UUID, itemID: UUID, url: String?) {
        if let url, !(URL(string: url)?.scheme.map { ["http", "https", "mailto"].contains($0.lowercased()) } ?? false) { status = "Use an absolute HTTP, HTTPS or mailto URL."; return }
        perform { state in guard let stack = state.stacks.first(where: { $0.id == stackID }) else { throw LibraryError.missingStack }; var members = stack.memberships; guard let index = members.firstIndex(where: { $0.itemID == itemID }) else { throw LibraryError.missingItem }; members[index].associatedURL = url; _ = try state.setMemberships(stackID, memberships: members, now: Date()) }
    }
    func deleteEverywhere(_ id: UUID) { invalidateContentOperations(); perform({ $0.deleteEverywhere(id) }, success: "Deleted from all app locations.") }
    func clearRecent() { invalidateContentOperations(); perform({ _ = $0.clearRecent() }, success: "Recent history cleared. Saved items remain.") }
    func resetStorageAfterConfirmation() { deleteAllData() }
    func deleteAllData() {
        captureControlGeneration += 1; invalidateContentOperations(); monitor.pause()
        Task { do { guard let repository else { status = "The storage directory cannot safely be opened. Close other Winnel instances or restore directory access, then retry."; return }; apply(try await repository.reset()); recoveryMessage = nil; status = "All app content deleted. Capture is paused; resume when ready."; explicitPause = true; _ = try await repository.mutate { $0.settings.capturePaused = true } } catch { fail(error) } }
    }
    func startQueue(mode: ItemAction = .copy) {
        let items = selectedItems
        queueGeneration += 1; let generation = queueGeneration
        runContentOperation(kind: .queuePreparation) { [self] operation in do { guard let repository else { return }; var entries: [QueueEntry] = []; var bytes = 0
            for item in items {
                guard contentOperationIsCurrent(operation), queueGeneration == generation else { return }
                bytes += item.payloadByteCount; guard bytes <= LibraryRepository.ramBudget else { status = "Queue exceeds the 64 MiB session limit."; return }
                let payload = try await repository.payload(item.id)
                guard contentOperationIsCurrent(operation), queueGeneration == generation else { return }
                entries.append(.init(item: item, payload: payload))
            }
            guard contentOperationIsCurrent(operation), queueGeneration == generation, !entries.isEmpty else { return }; queue = .init(entries: entries, mode: mode, now: Date()); status = "Queue ready. Next copies or sends one paste request."
        } catch { if contentOperationIsCurrent(operation), queueGeneration == generation { fail(error) } } }
    }
    func nextInQueue() {
        guard !queueDispatchPending, queue?.expire(now: Date()) != true, let entry = queue?.current else { return }
        let mode = queue!.mode, position = queue!.position, generation = queueGeneration
        let target = mode == .paste ? targetService.captureTarget() : nil
        runContentOperation(kind: .queueDispatch) { [self] operation in
            guard !queueDispatchPending, queueGeneration == generation, queue?.current?.id == entry.id, queue?.position == position else { return }
            queueDispatchPending = true
            defer { if queueGeneration == generation { queueDispatchPending = false } }
            guard pasteboardService.write(entry.payload) else { queue?.recordDispatch(success: false, now: Date()); status = "Clipboard write failed. Queue did not advance."; return }
            let writtenCount = pasteboardService.changeCount
            if mode == .paste {
                guard state.settings.directPasteEnabled, let target else { queue?.recordDispatch(success: false, now: Date()); status = "Copied for manual paste. Queue did not advance; switch to Copy Next or retry."; return }
                let result = await targetService.waitForModifiersThenDispatch(to: target, isCurrent: { [self] in
                    contentOperationIsCurrent(operation) && queueGeneration == generation && queue?.position == position && queue?.current?.id == entry.id && queue?.mode == mode && state.settings.directPasteEnabled && pasteboardService.changeCount == writtenCount
                })
                guard contentOperationIsCurrent(operation), queueGeneration == generation, queue?.position == position, queue?.current?.id == entry.id else { return }
                guard result == .dispatched else {
                    queue?.recordDispatch(success: false, now: Date())
                    status = pasteboardService.changeCount == writtenCount ? "Copied for manual paste. Queue did not advance; switch to Copy Next or retry." : "Clipboard changed. Queue did not advance; use Next to copy this item again."
                    return
                }
                status = "Paste request sent. Destination consumption is unconfirmed."
            } else { status = "Copied queue item. Press Command-V in your destination." }
            queue?.recordDispatch(success: true, now: Date())
        }
    }
    func backInQueue() { queueGeneration += 1; queueDispatchPending = false; queue?.back(now: Date()) }
    func cancelQueue() { queueGeneration += 1; queueDispatchPending = false; queue?.cancel(); queue = nil }
    func moveSelection(_ id: UUID, offset: Int) {
        var ids = selectedItems.map(\.id); guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }; ids.swapAt(index, index + offset); selectionOrder = ids
    }
    func prepareCombination(format: CombinationFormat, stackID: UUID? = nil) {
        combinationFormat = format; combinationPreview = ""; combinationGeneration += 1
        let generation = combinationGeneration
        let stack = state.stacks.first { $0.id == stackID }
        let items = selectedItems
        runContentOperation(kind: .combination) { [self] operation in do { guard let repository else { return }; var entries: [CombinationEntry] = []; var bytes = 0
            for item in items {
                guard contentOperationIsCurrent(operation), generation == combinationGeneration else { return }
                bytes += item.payloadByteCount; guard bytes <= LibraryRepository.ramBudget else { status = "Combination exceeds the 64 MiB preview limit."; return }
                let payload = try await repository.payload(item.id)
                guard contentOperationIsCurrent(operation), generation == combinationGeneration else { return }
                entries.append(.init(item: item, payload: payload, associatedURL: stack?.memberships.first(where: { $0.itemID == item.id })?.associatedURL))
            }
            guard contentOperationIsCurrent(operation), generation == combinationGeneration else { return }
            let capturedEntries = entries
            let preview = try await detachedContent { try Combination.preview(capturedEntries, format: format) }
            guard contentOperationIsCurrent(operation), generation == combinationGeneration else { return }; combinationPreview = preview
        } catch { guard contentOperationIsCurrent(operation), generation == combinationGeneration else { return }; combinationPreview = ""; status = "This selection cannot use that combination format." } }
    }
    func copyCombination() {
        guard contentOperationIsCurrent(contentGeneration), !combinationPreview.isEmpty else { return }
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(combinationPreview.utf8))])
        status = pasteboardService.write(payload) ? "Exact preview copied." : "Preview exceeds the clipboard limit."
    }
    func pasteCombination() {
        guard contentOperationIsCurrent(contentGeneration), !combinationPreview.isEmpty else { return }
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(combinationPreview.utf8))])
        guard pasteboardService.write(payload) else { status = "Preview exceeds the clipboard limit."; return }
        let writtenCount = pasteboardService.changeCount
        let target = paletteTarget; onDismissPalette?()
        runContentOperation(kind: .clipboard) { [self] operation in await Task.yield()
            guard contentOperationIsCurrent(operation) else { return }
            guard pasteboardService.changeCount == writtenCount else { status = "Clipboard changed. Paste canceled; copy the preview again when ready."; return }
            if state.settings.directPasteEnabled, let target {
                let result = await targetService.waitForModifiersThenDispatch(to: target, isCurrent: { [self] in
                    contentOperationIsCurrent(operation) && state.settings.directPasteEnabled && pasteboardService.changeCount == writtenCount
                })
                guard contentOperationIsCurrent(operation) else { return }
                guard pasteboardService.changeCount == writtenCount else { status = "Clipboard changed. Paste canceled; copy the preview again when ready."; return }
                status = result == .dispatched ? "Exact preview paste request sent. Consumption is unconfirmed." : "Exact preview copied. Press Command-V in your destination."
            } else { status = "Exact preview copied. Press Command-V in your destination." }
        }
    }
    func exportCombination() {
        guard contentOperationIsCurrent(contentGeneration), !combinationPreview.isEmpty else { return }
        let preview = combinationPreview
        runContentOperation(kind: .exportPreparation) { [self] operation in
            let panel = NSSavePanel(); panel.nameFieldStringValue = "winnel-combination.txt"; panel.message = "Export the exact combination preview."
            guard panel.runModal() == .OK, let url = panel.url, contentOperationIsCurrent(operation) else { return }
            do {
                try await detachedContent {
                    let bytes = Data(preview.utf8)
                    try Task.checkCancellation()
                    try bytes.write(to: url, options: .atomic)
                }
                guard contentOperationIsCurrent(operation) else { return }
                status = "Combination exported."
            } catch { if contentOperationIsCurrent(operation) { status = "Export failed." } }
        }
    }
    func exportSelected() { exportSelection(format: .markdown, includeImages: false) }
    nonisolated private static func resolvingFileMetadata(_ payload: ClipPayload) -> ClipPayload {
        var result = payload
        result.fileReferences = payload.fileReferences.map(FileReferenceMetadata.resolve)
        return result
    }
    func exportSelection(format: ExportFormat, includeImages: Bool, stackID: UUID? = nil) {
        let stack = state.stacks.first { $0.id == stackID }
        let title = stack?.name ?? "Winnel Export"
        let items = selectedItems
        runContentOperation(kind: .exportPreparation) { [self] operation in do { guard let repository else { return }; var entries: [ExportEntry] = []; var bytes = 0
            for item in items {
                guard contentOperationIsCurrent(operation) else { return }
                bytes += item.payloadByteCount; guard bytes <= LibraryRepository.ramBudget else { status = "Export selection exceeds the 64 MiB preview limit."; return }
                let payload = try await repository.payload(item.id)
                guard contentOperationIsCurrent(operation) else { return }
                entries.append(.init(item: item, payload: payload, associatedURL: stack?.memberships.first(where: { $0.itemID == item.id })?.associatedURL))
            }
            guard contentOperationIsCurrent(operation) else { return }
            let capturedEntries = entries
            let document = try await detachedContent {
                let resolved = capturedEntries.map { entry in ExportEntry(item: entry.item, payload: Self.resolvingFileMetadata(entry.payload), associatedURL: entry.associatedURL) }
                return try ExportBuilder.make(entries: resolved, title: title, format: format, includeImages: includeImages)
            }
            guard contentOperationIsCurrent(operation) else { return }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "Winnel Export"; panel.message = "Export \(entries.count) selected items and \(document.assets.count) image assets into a new folder."
            guard panel.runModal() == .OK, let url = panel.url, contentOperationIsCurrent(operation) else { return }
            let confirmation = NSAlert(); confirmation.messageText = "Export this preview?"; confirmation.informativeText = "Destination: " + url.path + "\nAssets: " + document.assets.keys.sorted().joined(separator: ", ")
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 360)); scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.string = document.preview; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
            scroll.documentView = text; confirmation.accessoryView = scroll
            confirmation.addButton(withTitle: "Export"); confirmation.addButton(withTitle: "Cancel")
            guard confirmation.runModal() == .alertFirstButtonReturn, contentOperationIsCurrent(operation) else { return }
            try await detachedContent { try ExportWriter.write(document: document, to: url) }
            guard contentOperationIsCurrent(operation) else { return }; status = "Selected content exported."
        } catch { if contentOperationIsCurrent(operation) { status = "Export failed. No referenced file contents were read." } } }
    }
    func requestClearSystemClipboardApproval() { clearClipboardCount = pasteboardService.changeCount }
    func clearSystemClipboardIfUnchanged() {
        guard let count = clearClipboardCount else { return }; clearClipboardCount = nil
        status = pasteboardService.clear(expectedChangeCount: count) ? "System clipboard cleared." : "Clipboard changed; the newer copy was preserved."
    }
    func checkForUpdates(automatic: Bool = false) {
        guard !fixtureMode else { status = "Update checks are disabled in fixture mode."; return }
        if automatic {
            guard state.settings.updateChecksEnabled else { return }
            if let last = UserDefaults.standard.object(forKey: "winnel.lastUpdateCheck") as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        }
        UserDefaults.standard.set(Date(), forKey: "winnel.lastUpdateCheck")
        Task { do {
            switch try await UpdateChecker().check(currentVersion: "0.1.0") {
            case .current: status = "Winnel is up to date."
            case .notPublished: status = "No public release is available yet."
            case .available(let update): status = "Winnel \(update.version) is available. Release page: \(update.releaseURL.absoluteString)"
            }
        } catch { status = "Update check failed. Core features remain available offline." } }
    }
    func testShortcuts() { onTestShortcuts?(); status = "Press your palette and Next shortcuts to test them." }
    func addPracticeExamples() {
        guard fixtureMode else { status = "Copy the three practice examples yourself after enabling capture."; return }
        Task { do { guard let repository else { return }
            for text in ["Winnel synthetic practice: first copy", "https://example.com/winnel-fixture", "Winnel synthetic practice: third copy"] {
                let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(text.utf8))])
                apply(try await repository.ingest(payload, source: .init(bundleIdentifier: "org.madeordinary.winnel.fixture", name: "Synthetic fixture", confidence: .established), now: Date(), sessionIDs: []))
            }
            status = "Three synthetic examples added to the isolated fixture store."
        } catch { fail(error) } }
    }
    func retryStorage() {
        invalidateContentOperations()
        Task { do { guard let repository else { startupComplete = false; recoveryMessage = nil; await start(); return }; let snapshot = try await repository.load(now: Date()); recoveryMessage = nil; apply(snapshot); explicitPause = true; monitor.pause(); status = "Storage reopened. Resume capture when ready." } catch { fail(error) } }
    }
    func exportRecovery() {
        guard vaultDirectory != nil else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Winnel Encrypted Recovery"; panel.message = "Copy encrypted app storage for recovery. This includes no decrypted preview."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { do {
            guard let repository else { status = "Storage must be safely reopened before recovery export."; return }
            try await repository.exportRecovery(to: destination)
            status = "Encrypted recovery files exported. The original key is still required."
        } catch { status = "Encrypted recovery export failed." } }
    }
    func handleLifecycleSuspension() { lifecycleSuspended = true; captureControlGeneration += 1; invalidateContentOperations(); monitor.suspend() }
    func resumeAfterWake() {
        lifecycleSuspended = false
        let generation = captureControlGeneration
        Task { do { guard let repository else { return }; apply(try await repository.mutate { _ = $0.enforceRetention(now: Date()) }); if generation == captureControlGeneration { resumeIfPermitted() } } catch { fail(error) } }
    }
    private func tick() {
        if queue?.expire(now: Date()) == true { status = "Queue cancelled after five minutes without interaction." }
        if let until = state.settings.pauseUntil, until <= Date(), recoveryMessage == nil { explicitPause = false; resumeCapture() }
        let ids = queue?.retainedIDs ?? []
        perform { _ = $0.enforceRetention(now: Date(), sessionRetainedIDs: ids) }
    }
    func shutdown() async {
        captureControlGeneration += 1; shuttingDown = true; invalidateContentOperations(); monitor.stop(); retentionTimer?.invalidate(); searchTask?.cancel()
        do { if let repository { apply(try await repository.mutate { _ = $0.enforceRetention(now: Date(), endingSession: true) }) } } catch { fail(error) }
        if fixtureMode, let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
    }
}
