import SwiftUI
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
    }
    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .capture:
                GroupBox("Capture") {
                    VStack(alignment: .leading, spacing: 12) {
                        ClipboardAccessView(model: model)
                        Toggle("Capture clipboard history", isOn: Binding(get: { model.state.settings.captureEnabled }, set: { if $0 { model.enableCapture() } else { model.disableCapture() } }))
                        Text("Capture: \(model.captureState.rawValue.capitalized)").font(.callout).foregroundStyle(.secondary).accessibilityLabel("Capture status")
                        HStack { Menu("Pause capture") { Button("15 minutes") { model.pause(until: Date().addingTimeInterval(15 * 60)) }; Button("1 hour") { model.pause(until: Date().addingTimeInterval(60 * 60)) }; Button("Until tomorrow") { model.pause(until: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)) }; Button("Until I resume") { model.pause(until: nil) } }; Button("Resume") { model.resumeCapture() } }
                        if let until = model.state.settings.pauseUntil { Text("Scheduled resume: \(until.formatted(date: .abbreviated, time: .shortened))").font(.callout) }
                        Text("Resume starts with the current clipboard counter and does not import copies made during the pause. Capture also stops on lock, sleep and user switch.").font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("App exclusions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Match stable bundle identifiers, for example com.example.app. Source attribution is best effort; Pause stops all capture.").font(.callout).foregroundStyle(.secondary)
                        HStack { TextField("Application bundle identifier", text: $exclusion).textFieldStyle(.roundedBorder).onSubmit(addExclusion); Button("Add", action: addExclusion).disabled(exclusion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                        ForEach(model.state.settings.excludedBundleIdentifiers.sorted(), id: \.self) { identifier in HStack { Text(identifier).textSelection(.enabled); Spacer(); Button { var settings = model.state.settings; settings.excludedBundleIdentifiers.remove(identifier); model.updateSettings(settings) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove exclusion for \(identifier)") } }
                        if model.state.settings.excludedBundleIdentifiers.isEmpty { Text("No excluded apps.").font(.callout).foregroundStyle(.secondary) }
                    }.padding(8)
                }
        case .storage:
                GroupBox("Retention and storage") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Recent retention", selection: setting(\.retention)) { ForEach(Retention.allCases, id: \.self) { Text($0.label).tag($0) } }
                        Text("Up to \(model.state.settings.recentLimit) unsaved recent items. Pins and saved stacks are persistent exceptions. Removing a final saved reference keeps an item only while its actual copy time is eligible.").font(.callout).foregroundStyle(.secondary)
                        LabeledContent("Managed storage", value: ByteCountFormatter.string(fromByteCount: Int64(model.usageBytes), countStyle: .file))
                        LabeledContent("Storage budget", value: ByteCountFormatter.string(fromByteCount: Int64(model.state.settings.storageByteLimit), countStyle: .file))
                        LabeledContent("Capture limit", value: ByteCountFormatter.string(fromByteCount: Int64(model.state.settings.captureByteLimit), countStyle: .file))
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
                        Picker("Return action", selection: setting(\.defaultAction)) { Text("Copy").tag(ItemAction.copy); Text("Paste").tag(ItemAction.paste) }
                        Toggle("Enable direct paste in compatible apps", isOn: setting(\.directPasteEnabled))
                        HStack { Text(model.accessibilityGranted ? "Accessibility available" : "Accessibility unavailable — Copy still works").font(.callout); Spacer(); Button("Accessibility settings…") { model.requestAccessibility() } }
                        Text("Winnel revalidates the app, process, window and focused control. Secure fields, terminals and uncertain targets use manual Copy. Queue Next validates your current target each time and sends no Tab or Return. Ordinary Command-V is unchanged.").font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("Keyboard shortcuts") { VStack(alignment: .leading, spacing: 12) { ShortcutSettingsView(model: model); Button("Test shortcuts") { model.testShortcuts() } }.padding(8) }
        case .privacy:
                GroupBox("Privacy") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your library stays on this Mac. Winnel has no account, cloud sync, analytics, AI or automatic crash uploads. Captured payloads, paths, stack names, metadata, search indexes and previews are encrypted at rest with a Keychain key.")
                        Text("Copy and Paste deliberately replace the system clipboard. Other local apps can observe it. Winnel does not restore an older clipboard later, scrape source pages, fetch remote previews or read arbitrary referenced files. File exports contain references only.")
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
