import SwiftUI

struct RecoveryView: View {
    @ObservedObject var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            WinnelSectionHeader(title: "Your library needs attention", subtitle: "Capture and changes are paused", symbol: "lock.trianglebadge.exclamationmark")

            WinnelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.recoveryMessage ?? "Storage is unavailable. Capture and changes are paused while the existing library is protected.")
                        .font(.headline)
                    Text("Winnel keeps the existing encrypted data and key intact. It will not fall back to plaintext or replace the library automatically. If Keychain access is unavailable, unlock it through macOS and retry.")
                        .foregroundStyle(.secondary)
                    Button("Retry safely") { model.retryStorage() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                WinnelSectionHeader(title: "Preserve and inspect", subtitle: "Save the encrypted files before making further changes.")
                Button("Export encrypted recovery copy…") { model.exportRecovery() }
                HStack {
                    Button("Manage storage in Settings") { model.onShowSettings?() }
                    Button("Open Saved Stacks") { model.onShowLibrary?() }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Reset data").font(.headline)
                Text("Reset is a separate destructive choice. Save a recovery copy first if you want to preserve the existing encrypted files.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Reset Winnel data…", role: .destructive) { confirmReset = true }
            }
            if !model.status.isEmpty {
                Label(model.status, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(30)
        .frame(minWidth: 520, idealWidth: 580)
        .background(WinnelStyle.canvas)
        .tint(WinnelStyle.accent)
        .alert("Reset the encrypted library?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset data", role: .destructive) { model.resetStorageAfterConfirmation() }
        } message: {
            Text("This removes existing app-managed data, including saved stacks and pins. A recovery export remains outside Winnel. No existing Keychain credentials are changed without this explicit reset.")
        }
    }
}
