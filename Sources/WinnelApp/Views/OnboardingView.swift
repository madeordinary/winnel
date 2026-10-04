import SwiftUI
import WinnelCore

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @State private var capture = false
    @State private var directPaste = false
    @State private var launchAtLogin = false
    @State private var updates = false
    @State private var practiced = false
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 42)).foregroundStyle(WinnelStyle.accent).accessibilityHidden(true); VStack(alignment: .leading, spacing: 4) { Text("Welcome to Winnel").font(.largeTitle.bold()); Text("by Made Ordinary").foregroundStyle(.secondary) } }
                Text("Copy freely. Bring back exactly what you need.").font(.title2)
                HStack(alignment: .top, spacing: 20) {
                    benefit("Find a recent copy", symbol: "clock.arrow.circlepath")
                    benefit("Save an ordered stack", symbol: "square.stack")
                    benefit("Keep it on this Mac", symbol: "lock.shield")
                }.padding(16).frame(maxWidth: .infinity).background(WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                Text("Winnel keeps a private library on this Mac. Recent copies expire after 24 hours or 200 unsaved items. Pins and saved stacks stay until you remove them. Captured content, previews and search data are encrypted at rest.")
                GroupBox("1. Choose capture") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable clipboard capture", isOn: Binding(get: { capture }, set: { enabled in
                            capture = enabled
                            if enabled { model.enableCapture() } else { model.disableCapture() }
                        }))
                        ClipboardAccessView(model: model)
                        Text("Capture starts only when you choose it. Pause any time. Exclusions help skip selected apps, but cannot guarantee every secret is detected. macOS may separately ask for clipboard access.").font(.callout).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("2. Try three examples") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Open palette", value: ShortcutSpec(keyCode: model.settings.paletteShortcutKeyCode, modifiers: model.settings.paletteShortcutModifiers).displayName)
                        Text("Use this shortcut to find a copy, then press Return to Copy. You can select several items to create a saved stack.")
                        if model.fixtureMode {
                            Button(practiced ? "Examples added" : "Add synthetic practice examples") { model.addPracticeExamples(); practiced = true }.disabled(practiced)
                        } else {
                            Text(model.captureState == .active ? "Capture is ready. Select and copy each practice line with Command-C:" : "Enable capture above and allow clipboard access before copying these lines with Command-C:").font(.callout)
                            Text("First practice copy\nhttps://example.com\nThird practice copy").textSelection(.enabled).font(.system(.body, design: .monospaced))
                        }
                        Text("Practice uses these examples. Your existing clipboard is not imported.").font(.callout).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("3. Optional conveniences") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use direct paste in supported apps", isOn: $directPaste)
                        Text("Direct paste needs Accessibility permission. Winnel validates the intended app and field before sending one paste request. Secure, terminal or uncertain targets use Copy and manual Command-V.").font(.callout).foregroundStyle(.secondary)
                        if directPaste { Button("Open Accessibility permission request") { model.requestAccessibility() }; Text(model.accessibilityGranted ? "Accessibility is available." : "You can continue without Accessibility.").font(.callout).foregroundStyle(.secondary) }
                        Divider()
                        Toggle("Launch Winnel at login", isOn: $launchAtLogin)
                        Toggle("Check for updates", isOn: $updates)
                        Text("Update checks are separate from capture. Core features work offline. No analytics or automatic crash uploads.").font(.callout).foregroundStyle(.secondary)
                    }.padding(6)
                }
                if model.fixtureMode { Label("Fixture mode uses a named test clipboard and temporary storage.", systemImage: "testtube.2").font(.callout).foregroundStyle(.secondary) }

            }.padding(32).frame(maxWidth: 660, alignment: .leading).frame(maxWidth: .infinity)
        }
        Divider()
        HStack {
            Label("You control what stays.", systemImage: "hand.raised")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Get started") { finish() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }.padding(.horizontal, 32).padding(.vertical, 20).background(WinnelStyle.surface)
        }.background(WinnelStyle.canvas).frame(minWidth: 600, minHeight: 600).tint(WinnelStyle.accent)
        .onAppear { capture = model.settings.captureEnabled; model.refreshClipboardAccessStatus() }
    }
    private func benefit(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title3).foregroundStyle(WinnelStyle.accent).accessibilityHidden(true)
            Text(title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func finish() {
        model.finishOnboarding(capture: capture, directPaste: directPaste, launchAtLogin: launchAtLogin, updates: updates)
    }
}
