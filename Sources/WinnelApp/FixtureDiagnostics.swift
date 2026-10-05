import AppKit
import SwiftUI
import WinnelCore

/// App-owned rendering diagnostics, not OS screenshots or interactive/AX verification.
/// No repository, general pasteboard, capture monitor, privacy prompt or network is started.
@MainActor enum FixtureDiagnostics {
    enum Failure: Error { case unsafeOutput, renderingFailed }
    static func run(outputDirectory: URL) async throws {
        let directory = outputDirectory.standardizedFileURL
        guard directory.isFileURL, directory.path.hasPrefix(FileManager.default.currentDirectoryPath + "/build/"),
              directory.resolvingSymlinksInPath() == directory else { throw Failure.unsafeOutput }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let model = AppModel(fixtureMode: true)
        model.state = syntheticState()
        model.captureState = .disabled
        model.status = "Synthetic diagnostics: capture is off. No personal clipboard or stored library is loaded."
        model.usageBytes = model.state.managedPayloadBytes
        let item = model.state.recentItems.first(where: { $0.kind == .text })!
        model.selectedIDs = [item.id]; model.selectionOrder = [item.id]
        model.previewPayload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("A deliberately synthetic clipboard example.\nNo private data is used.".utf8))])
        let libraryModel = AppModel(fixtureMode: true)
        libraryModel.state = model.state
        let stack = libraryModel.state.stacks[0]
        let member = libraryModel.state.items.first { $0.id == stack.memberships[3].itemID }!
        libraryModel.selectedIDs = [member.id]; libraryModel.selectionOrder = [member.id]
        libraryModel.previewPayload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(member.textPreview.utf8))])
        let queueModel = AppModel(fixtureMode: true)
        queueModel.state = model.state
        queueModel.selectedIDs = [item.id]; queueModel.selectionOrder = [item.id]
        queueModel.previewPayload = model.previewPayload
        queueModel.queue = .init(entries: [.init(item: item, payload: model.previewPayload!)], now: Date())
        let filteredModel = AppModel(fixtureMode: true)
        filteredModel.state = model.state
        filteredModel.kindFilter = .richText
        let unsupportedModel = AppModel(fixtureMode: true)
        unsupportedModel.state = model.state
        let imageItem = unsupportedModel.state.items.first { $0.kind == .image }!
        unsupportedModel.selectedIDs = [imageItem.id]; unsupportedModel.selectionOrder = [imageItem.id]
        let emptyLibraryModel = AppModel(fixtureMode: true)
        emptyLibraryModel.state = model.state; emptyLibraryModel.state.stacks = []
        // A typed query selects its first match once results publish, as in the palette.
        let searchModel = AppModel(fixtureMode: true)
        searchModel.state = model.state
        searchModel.searchQuery = "entry 1"
        if let first = searchModel.selectedItems.first { searchModel.previewPayload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(first.textPreview.utf8))]) }
        let libraryQueueModel = AppModel(fixtureMode: true)
        libraryQueueModel.state = model.state
        let queued = stack.memberships.prefix(5).compactMap { membership in model.state.items.first { $0.id == membership.itemID } }
        libraryQueueModel.queue = .init(entries: queued.map { .init(item: $0, payload: ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data($0.textPreview.utf8))])) }, now: Date())
        libraryQueueModel.queue?.recordDispatch(success: true, now: Date())
        var captures: [String] = []
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let views: [(String, NSSize, AnyView)] = [
                ("palette", .init(width: 760, height: 660), AnyView(PaletteView(model: model))),
                ("library", .init(width: 1000, height: 720), AnyView(LibraryView(model: libraryModel, initialStackID: stack.id, initialMemberID: member.id))),
                ("library-cards", .init(width: 1000, height: 720), AnyView(LibraryView(model: libraryModel, initialStackID: stack.id))),
                ("library-list", .init(width: 900, height: 500), AnyView(LibraryView(model: libraryModel, initialStackID: stack.id, initialMemberID: member.id, initialPresentation: .list))),
                ("library-empty", .init(width: 900, height: 500), AnyView(LibraryView(model: emptyLibraryModel))),
                ("export", .init(width: 540, height: 760), AnyView(ExportOptionsSheet(model: model))),
                ("combination", .init(width: 560, height: 480), AnyView(CombinationSheet(model: model))),
                ("queue", .init(width: 760, height: 660), AnyView(PaletteView(model: queueModel))),
                ("settings", .init(width: 780, height: 1100), AnyView(SettingsView(model: model))),
                ("onboarding", .init(width: 760, height: 720), AnyView(OnboardingView(model: model))),
                ("recovery", .init(width: 720, height: 600), AnyView(RecoveryView(model: model)))
            ]
            for (viewName, size, view) in views {
                let filename = "\(viewName)-\(name).png"
                try await render(view, size: size, appearance: appearance, destination: directory.appendingPathComponent(filename))
                captures.append(filename)
            }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        let accessibilityPalette = AnyView(PaletteView(model: model)
            .environment(\.dynamicTypeSize, .accessibility1))
        let variants: [(String, NSSize, AnyView)] = [
            ("palette-light-accessibility", .init(width: 620, height: 420), accessibilityPalette),
            ("library-light-minimum", .init(width: 900, height: 500), AnyView(LibraryView(model: libraryModel, initialStackID: stack.id, initialMemberID: member.id))),
            ("library-cards-light-minimum", .init(width: 900, height: 500), AnyView(LibraryView(model: libraryModel, initialStackID: stack.id))),
            ("queue-light-minimum", .init(width: 620, height: 420), AnyView(PaletteView(model: queueModel))),
            ("palette-filter-empty", .init(width: 620, height: 420), AnyView(PaletteView(model: filteredModel))),
            ("palette-combine-unavailable", .init(width: 620, height: 420), AnyView(PaletteView(model: unsupportedModel))),
            ("palette-search", .init(width: 760, height: 660), AnyView(PaletteView(model: searchModel))),
            ("library-queue", .init(width: 1000, height: 720), AnyView(LibraryView(model: libraryQueueModel, initialStackID: stack.id))),
            ("export-light-minimum", .init(width: 500, height: 380), AnyView(ExportOptionsSheet(model: model))),
            ("settings-storage", .init(width: 680, height: 600), AnyView(SettingsView(model: model, initialSection: .storage))),
            ("settings-shortcuts", .init(width: 680, height: 600), AnyView(SettingsView(model: model, initialSection: .shortcuts))),
            ("settings-privacy", .init(width: 680, height: 600), AnyView(SettingsView(model: model, initialSection: .privacy))),
            ("settings-general", .init(width: 680, height: 600), AnyView(SettingsView(model: model, initialSection: .general))),
            ("selection-order", .init(width: 500, height: 400), AnyView(SelectionOrderSheet(model: model))),
            ("onboarding-light-full", .init(width: 760, height: 1400), AnyView(OnboardingView(model: model))),
            ("onboarding-light-minimum", .init(width: 600, height: 600), AnyView(OnboardingView(model: model)))
        ]
        for (name, size, view) in variants {
            let filename = name + ".png"
            let appearance: NSAppearance.Name = name == "palette-light-accessibility" ? .accessibilityHighContrastAqua : .aqua
            NSApp.appearance = NSAppearance(named: appearance)
            try await render(view, size: size, appearance: appearance, destination: directory.appendingPathComponent(filename))
            captures.append(filename)
        }
        let host = NSHostingView(rootView: PaletteView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 660)
        host.layoutSubtreeIfNeeded()
        var layout: [Double] = []
        for _ in 0..<100 {
            let start = ProcessInfo.processInfo.systemUptime
            host.needsLayout = true; host.layoutSubtreeIfNeeded()
            layout.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        var search: [Double] = []; var matched = 0
        let queries = ["synthetic", "example.invalid", "Reference", "entry 199", "missing-query"]
        for index in 0..<100 {
            let start = ProcessInfo.processInfo.systemUptime
            matched += model.state.search(queries[index % queries.count]).count
            search.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        let report: [String: Any] = [
            "schemaVersion": 1, "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "kind": "actual SwiftUI view raster rendering with synthetic in-memory AppModel state",
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "processorCount": ProcessInfo.processInfo.processorCount,
            "dataset": ["total": model.state.items.count, "recent": 200, "saved": 1000, "description": "Synthetic text, URL, image and file-reference metadata; no repository or live capture is loaded."],
            "renderedViews": captures,
            "accessibilityVariant": "620×420 hosting viewport with dynamicTypeSize accessibility1 and high-contrast AppKit appearance; SwiftUI colorSchemeContrast and accessibilityReduceMotion are read-only on this SDK and were not injected. No OS preferences changed; no interaction verified.",
            "rendering": "Native window background drawn by the actual hosting root; explicit SwiftUI color scheme and AppKit appearance; sampled bitmap opacity verified before PNG encoding.",
            "measurements": ["samples": 100, "coreSearchP95Milliseconds": p95(search), "hostingLayoutP95Milliseconds": p95(layout), "searchResultChecksum": matched],
            "diagnosticThresholds": ["coreSearchP95AtMost100ms": p95(search) <= 100, "hostingLayoutP95AtMost100ms": p95(layout) <= 100],
            "unverified": ["Keyboard and VoiceOver interaction", "Arrow keys and Return from the search field", "Edit-menu key equivalents in the nonactivating palette", "Menu-bar status item, queue position and capture symbol", "Lock, sleep and wake suspension", "Real palette opening and shortcut latency", "Cold launch", "30-minute CPU/RSS", "Reference M1 hardware fixture", "Cross-app paste and AX notification behavior", "Encrypted repository search timing"],
            "privacy": "Named fixture pasteboard is configured; no clipboard payloads are read or written. No capture, Keychain, permission prompts or OS screenshot APIs are used."
        ]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic)
    }
    private static func render(_ view: AnyView, size: NSSize, appearance: NSAppearance.Name, destination: URL) async throws {
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isRestorable = false
        window.appearance = NSAppearance(named: appearance)
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let root = view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: root)
        host.appearance = window.appearance
        host.frame = NSRect(origin: .zero, size: size); window.contentView = host
        // Attach to the window server outside visible screens; never activate or make key.
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure.renderingFailed }
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        // A bitmap container may have an alpha channel. Verify that native drawing filled
        // the viewport; do not flatten/recolor pixels after rendering.
        let step = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 32)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent >= 0.99 else { throw Failure.renderingFailed }
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]), !png.isEmpty else { throw Failure.renderingFailed }
        try png.write(to: destination, options: .atomic)
    }
    private static func p95(_ values: [Double]) -> Double { values.sorted()[Int(ceil(Double(values.count) * 0.95)) - 1] }
    private static func syntheticState() -> LibraryState {
        let now = Date()
        var settings = Settings(); settings.captureEnabled = false; settings.onboardingComplete = false
        var items: [ClipboardItem] = []
        for index in 0..<1200 {
            let kind: ClipKind = index % 12 == 0 ? .image : index % 12 == 1 ? .files : index % 12 == 2 ? .url : .text
            let text = kind == .url ? "https://example.invalid/synthetic/\(index)" : kind == .files ? "Reference: synthetic-\(index).txt" : kind == .image ? "PNG image · 1600 × \(900 + index)" : "Synthetic entry \(index): A small example excerpt for local search and saved stacks."
            items.append(.init(copiedAt: now.addingTimeInterval(-Double(index) * 10), source: .init(bundleIdentifier: "org.madeordinary.winnel.fixture", name: "Winnel Synthetic Fixture", confidence: .inferred), kind: kind, textPreview: text, payloadByteCount: 256, fingerprint: "synthetic-\(index)", isRecent: index < 200))
        }
        let stacks = stride(from: 200, to: 1200, by: 50).map { start in SavedStack(name: "Synthetic collection \((start - 200) / 50 + 1)", memberships: items[start..<start + 50].map { .init(itemID: $0.id) }) }
        return LibraryState(items: items, stacks: stacks, settings: settings)
    }
}
