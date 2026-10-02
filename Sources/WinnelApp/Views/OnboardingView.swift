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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 42)).foregroundStyle(WinnelStyle.accent).accessibilityHidden(true); VStack(alignment: .leading, spacing: 4) { Text("Welcome to Winnel").font(.largeTitle.bold()); Text("by Made Ordinary").foregroundStyle(.secondary) } }
                Text("Copy freely. Bring back exactly what you need.").font(.title2)
                Text("Winnel keeps a private library on this Mac. Recent copies expire after 24 hours or 200 unsaved items. Pins and saved stacks stay until you remove them. Captured content, previews and search data are encrypted at rest.")
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable clipboard capture", isOn: $capture)
                        ClipboardAccessView(model: model)
                        Text("Capture starts only when you choose it. Pause any time. Exclusions help skip selected apps, but cannot guarantee every secret is detected. macOS may separately ask for clipboard access.").font(.callout).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("Optional conveniences") {
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
                GroupBox("Try three examples") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open the palette with your configured shortcut, find a copy, then press Return to Copy. You can select several items to create a saved stack.")
                        if model.fixtureMode {
                            Button(practiced ? "Examples added" : "Add synthetic practice examples") { model.addPracticeExamples(); practiced = true }.disabled(practiced)
                        } else {
                            Text("After enabling capture, select and copy each practice line with Command-C:").font(.callout)
                            Text("First practice copy\nhttps://example.com\nThird practice copy").textSelection(.enabled).font(.system(.body, design: .monospaced))
                        }
                        Text("Practice uses these examples. Your existing clipboard is not imported.").font(.callout).foregroundStyle(.secondary)
                    }.padding(6)
                }
                if model.fixtureMode { Label("Fixture mode uses a named test clipboard and temporary storage.", systemImage: "testtube.2").font(.callout).foregroundStyle(.secondary) }
                HStack { Text("You control what stays.").foregroundStyle(.secondary); Spacer(); Button("Get started") { finish() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }.padding(32).frame(maxWidth: 660)
        }.frame(minWidth: 600, minHeight: 600).tint(WinnelStyle.accent)
        .onAppear { model.refreshClipboardAccessStatus() }
    }
    private func finish() {
        model.finishOnboarding(capture: capture, directPaste: directPaste, launchAtLogin: launchAtLogin, updates: updates)
    }
}
