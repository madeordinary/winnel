import SwiftUI
import UniformTypeIdentifiers
import WinnelCore
import WinnelPlatform

enum SettingsSection: String, CaseIterable, Identifiable {
    case capture = "Capture", storage = "Storage", shortcuts = "Shortcuts", privacy = "Privacy", general = "General"
    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .capture: "Choose when copies become history."
        case .storage: "Manage what stays on this Mac."
        case .shortcuts: "Choose how to bring your copies back."
        case .privacy: "Understand and control your local library."
        case .general: "Set your startup and update preferences."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section: SettingsSection
    @State private var exclusion = ""
    init(model: AppModel, initialSection: SettingsSection = .capture) {
        self.model = model
        _section = State(initialValue: initialSection)
    }
    @State private var clearing: ClearAction?
    @State private var pendingRetention: Retention?
    private enum ClearAction: String, Identifiable { case recent, all, clipboard; var id: String { rawValue } }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                WinnelSectionHeader(title: "Settings", subtitle: "Make Winnel fit your workflow.", symbol: "slider.horizontal.3")
                Picker("Settings category", selection: $section) {
                    ForEach(SettingsSection.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.recoveryMessage != nil { GroupBox("Storage recovery") { RecoveryView(model: model) } }
                    WinnelSectionHeader(title: section.rawValue, subtitle: section.subtitle)
                    sectionContent
                    if model.fixtureMode { Label("Fixture mode: named synthetic clipboard and temporary storage.", systemImage: "testtube.2").foregroundStyle(.secondary) }
                    if !model.status.isEmpty { Text(model.status).font(.callout).foregroundStyle(.secondary) }
                }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }.id(section)
        }.background(WinnelStyle.canvas).frame(minWidth: 680, minHeight: 600).tint(WinnelStyle.accent)
        .onAppear { model.refreshClipboardAccessStatus() }
        .alert(clearTitle, isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } })) {
            Button("Cancel", role: .cancel) { clearing = nil }
            Button(clearButton, role: .destructive) { switch clearing { case .recent: model.clearRecent(); case .all: model.deleteAllData(); case .clipboard: model.clearSystemClipboardIfUnchanged(); case nil: break }; clearing = nil }
        } message: { Text(clearMessage) }
        .alert("Shorten recent history?", isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
            Button("Cancel", role: .cancel) { pendingRetention = nil }
            Button("Remove items", role: .destructive) { if let retention = pendingRetention { applyRetention(retention) }; pendingRetention = nil }
        } message: {
            if let retention = pendingRetention { let count = model.itemsRemovedByRetention(retention); Text("Switching to \(retention.label) removes \(count) unsaved recent \(count == 1 ? "item" : "items") now. Pins and saved stacks stay.") }
        }
    }
    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .capture:
                GroupBox("Capture") {
                    VStack(alignment: .leading, spacing: 12) {
                        ClipboardAccessView(model: model)
                        Toggle("Capture clipboard history", isOn: Binding(get: { model.state.settings.captureEnabled }, set: { if $0 { model.enableCapture() } else { model.disableCapture() } }))
                        Text(model.captureState.label).font(.callout).foregroundStyle(.secondary).accessibilityLabel("Capture status: \(model.captureState.label)")
                        HStack {
                            Menu("Pause capture") { Button("15 minutes") { model.pause(until: Date().addingTimeInterval(15 * 60)) }; Button("1 hour") { model.pause(until: Date().addingTimeInterval(60 * 60)) }; Button("Until midnight") { model.pause(until: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)) }; Button("Until I resume") { model.pause(until: nil) } }
                                .fixedSize().disabled(!model.state.settings.captureEnabled || model.captureState == .disabled)
                            Button("Resume") { if model.lifecycleSuspended { model.endSuspensionFromUser() } else { model.resumeCaptureFromUser() } }
                                .disabled(!model.lifecycleSuspended && (!model.state.settings.captureEnabled || model.captureState != .paused))
                        }
                        if let until = model.state.settings.pauseUntil { Text("Scheduled resume: \(until.formatted(date: .abbreviated, time: .shortened))").font(.callout) }
                        Text("Resume starts with the current clipboard counter and does not import copies made during the pause. Capture also stops on lock, sleep and user switch.").font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("App exclusions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Copies made while an excluded app is in front are skipped. Source attribution is best effort; Pause stops all capture.").font(.callout).foregroundStyle(.secondary)
                        HStack { Button("Add App…", action: chooseExcludedApp); TextField("Or type a bundle identifier, e.g. com.example.app", text: $exclusion).textFieldStyle(.roundedBorder).onSubmit(addExclusion); Button("Add", action: addExclusion).disabled(exclusion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                        ForEach(model.state.settings.excludedBundleIdentifiers.sorted(), id: \.self) { identifier in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appName(identifier) ?? identifier)
                                    if appName(identifier) != nil { Text(identifier).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                                Spacer()
                                Button { var settings = model.state.settings; settings.excludedBundleIdentifiers.remove(identifier); model.updateSettings(settings) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove exclusion for \(appName(identifier) ?? identifier)")
                            }
                        }
                        if model.state.settings.excludedBundleIdentifiers.isEmpty { Text("No excluded apps.").font(.callout).foregroundStyle(.secondary) }
                    }.padding(8)
                }
        case .storage:
                GroupBox("Retention and storage") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Recent retention", selection: Binding(get: { model.state.settings.retention }, set: requestRetention)) { ForEach(Retention.allCases, id: \.self) { Text($0.label).tag($0) } }
                        Text("Up to \(model.state.settings.recentLimit) unsaved recent items. Pins and saved stacks are persistent exceptions. Removing a final saved reference keeps an item only while its actual copy time is eligible.").font(.callout).foregroundStyle(.secondary)
                        LabeledContent("Managed storage", value: WinnelStyle.bytes(model.usageBytes))
                        LabeledContent("Storage budget", value: WinnelStyle.bytes(model.state.settings.storageByteLimit))
                        LabeledContent("Capture limit per copy", value: "About " + WinnelStyle.bytes(model.state.settings.captureByteLimit / 4 * 3))
                        Text("All formats of one copy count together, measured after encoding (\(WinnelStyle.bytes(model.state.settings.captureByteLimit))). An app that offers the same content in several formats uses more of the limit.").font(.callout).foregroundStyle(.secondary)
                        Text("Saved content is never silently evicted. If it fills the budget, capture pauses so you can manage it.").font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("Clear controls") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Button("Clear Recent…") { clearing = .recent }; Button("Delete All Data…", role: .destructive) { clearing = .all }; Button("Clear System Clipboard…") { model.requestClearSystemClipboardApproval(); clearing = .clipboard } }
                        Text("History deletion removes active app-managed content and caches. It does not erase the system clipboard, exports, backups, snapshots or original files. No forensic erasure guarantee is made.").font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }
        case .shortcuts:
                GroupBox("Copy and paste") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.directPasteAvailable {
                            Picker("Return action", selection: setting(\.defaultAction)) { Text("Copy").tag(ItemAction.copy); Text("Paste").tag(ItemAction.paste) }
                            Toggle("Enable direct paste in compatible apps", isOn: setting(\.directPasteEnabled))
                            HStack { Text(model.accessibilityGranted ? "Accessibility available" : "Accessibility unavailable — Copy still works").font(.callout); Spacer(); Button("Accessibility settings…") { model.requestAccessibility() } }
                            Text("Winnel revalidates the app, process, window and focused control. Secure fields, terminals and uncertain targets use manual Copy. Queue Next validates your current target each time and sends no Tab or Return. Ordinary Command-V is unchanged.").font(.callout).foregroundStyle(.secondary)
                        } else {
                            LabeledContent("Return action", value: "Copy")
                            Text("Direct paste is not available yet: no app has been verified for it. Return copies the selected item; then press Command-V where you want it. Winnel does not ask for Accessibility permission until direct paste can work.").font(.callout).foregroundStyle(.secondary)
                        }
                    }.padding(8)
                }
                GroupBox("Keyboard shortcuts") { VStack(alignment: .leading, spacing: 12) { ShortcutSettingsView(model: model); Button("Test shortcuts") { model.testShortcuts() } }.padding(8) }
        case .privacy:
                GroupBox("Privacy") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your library stays on this Mac. Winnel has no account, cloud sync, analytics, AI or automatic crash uploads. Captured payloads, paths, stack names, metadata, search indexes and previews are encrypted at rest with a Keychain key.")
                        Text("Copy and Paste deliberately replace the system clipboard. Other local apps can observe it. Winnel does not restore an older clipboard later, scrape source pages, fetch remote previews or read arbitrary referenced files. File exports contain references only.")
                        Text("Copies that macOS marks as arriving through Universal Clipboard from your iPhone, iPad or another Mac are not recorded. Winnel asks macOS to keep items it copies for you on this Mac rather than offering them to your other devices.")
                        Text("Unavailable keys or storage failures pause affected work. Winnel never silently stores plaintext or replaces an existing key or library.")
                    }.font(.callout).padding(8)
                }
        case .general:
                GroupBox("Startup and updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch at login", isOn: setting(\.launchAtLogin))
                        Toggle("Check for updates", isOn: setting(\.updateChecksEnabled))
                        Button("Check now") { model.checkForUpdates() }
                        Text("Both choices are off initially. Core features work offline. Update availability and network behavior are documented before public beta.").font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }
        }
    }
    private func setting<Value>(_ keyPath: WritableKeyPath<WinnelCore.Settings, Value>) -> Binding<Value> { Binding(get: { model.state.settings[keyPath: keyPath] }, set: { value in var settings = model.state.settings; settings[keyPath: keyPath] = value; model.updateSettings(settings) }) }
    private func requestRetention(_ retention: Retention) {
        guard retention != model.state.settings.retention else { return }
        if model.itemsRemovedByRetention(retention) > 0 { pendingRetention = retention } else { applyRetention(retention) }
    }
    private func applyRetention(_ retention: Retention) { var settings = model.state.settings; settings.retention = retention; model.updateSettings(settings) }
    private func appName(_ identifier: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
    private func chooseExcludedApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true); panel.prompt = "Exclude"; panel.message = "Choose apps whose copies Winnel should skip."
        guard panel.runModal() == .OK else { return }
        let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        guard !identifiers.isEmpty else { model.status = "That app has no bundle identifier to exclude."; return }
        var settings = model.state.settings; settings.excludedBundleIdentifiers.formUnion(identifiers); model.updateSettings(settings)
    }
    private func addExclusion() { let identifier = exclusion.trimmingCharacters(in: .whitespacesAndNewlines); guard !identifier.isEmpty else { return }; var settings = model.state.settings; settings.excludedBundleIdentifiers.insert(identifier); model.updateSettings(settings); exclusion = "" }
    private var clearTitle: String { switch clearing { case .recent: "Clear Recent?"; case .all: "Delete all Winnel data?"; case .clipboard: "Clear the current system clipboard?"; case nil: "" } }
    private var clearButton: String { switch clearing { case .recent: "Clear Recent"; case .all: "Delete All Data"; case .clipboard: "Clear clipboard"; case nil: "" } }
    private var clearMessage: String { switch clearing { case .recent: "Clear the recent view and release unsaved content. Pins and saved stacks remain intact."; case .all: "Delete all items, stacks, indexes, previews and pending queues from Winnel. Settings may remain. Exports, backups, original files and the system clipboard remain."; case .clipboard: "Clear only the clipboard version present when you opened this confirmation. A newer copy will remain untouched."; case nil: "" } }
}


/// Reading permission status never requests access; only these explicit buttons can act.
struct ClipboardAccessView: View {
    @ObservedObject var model: AppModel
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.clipboardAccessStatus {
            case .allowed:
                if !compact { Label("Clipboard access available", systemImage: "checkmark.shield").font(.callout) }
            case .required:
                Label("Clipboard access needs your permission", systemImage: "hand.raised").font(.headline)
                Text("macOS requires a separate clipboard choice. Capture stays paused until access is available; Winnel does not import copies made while paused.").font(.callout).foregroundStyle(.secondary)
                Button("Request clipboard access") { model.requestClipboardAccess() }
            case .denied:
                Label("Clipboard access denied — capture paused", systemImage: "hand.raised.slash").font(.headline)
                Text("Review Winnel’s clipboard permission in System Settings if you want to capture new copies. Existing saved content remains available. Winnel cannot grant permission for you.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Open System Settings") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") { NSWorkspace.shared.open(url) }
                    }
                    Button("Recheck access") { model.refreshClipboardAccessStatus() }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("Clipboard permission")
    }
}
