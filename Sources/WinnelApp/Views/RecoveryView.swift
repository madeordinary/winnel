import SwiftUI

struct RecoveryView: View {
    @ObservedObject var model: AppModel
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Your library needs attention", systemImage: "lock.trianglebadge.exclamationmark").font(.title2.bold())
            Text(model.recoveryMessage ?? "Storage is unavailable. Capture and changes are paused while the existing library is protected.")
            Text("Winnel keeps the existing encrypted data and key intact. It will not fall back to plaintext or replace the library automatically. If Keychain access is unavailable, unlock it through macOS and retry.").foregroundStyle(.secondary)
            HStack { Button("Retry safely") { model.retryStorage() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction); Button("Export encrypted recovery copy…") { model.exportRecovery() } }
            HStack { Button("Manage storage in Settings") { model.onShowSettings?() }; Button("Open Saved Stacks") { model.onShowLibrary?() } }
            Divider()
            Text("Reset is a separate destructive choice. Save a recovery copy first if you want to preserve the existing encrypted files.").font(.callout).foregroundStyle(.secondary)
            Button("Reset Winnel data…", role: .destructive) { confirmReset = true }
            if !model.status.isEmpty { Text(model.status).font(.callout).foregroundStyle(.secondary) }
        }.padding(30).frame(minWidth: 520, idealWidth: 580).tint(WinnelStyle.accent)
        .alert("Reset the encrypted library?", isPresented: $confirmReset) { Button("Cancel", role: .cancel) {}; Button("Reset data", role: .destructive) { model.resetStorageAfterConfirmation() } } message: { Text("This removes existing app-managed data, including saved stacks and pins. A recovery export remains outside Winnel. No existing Keychain credentials are changed without this explicit reset.") }
    }
}
