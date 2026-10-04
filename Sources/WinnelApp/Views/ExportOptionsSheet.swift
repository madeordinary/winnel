import SwiftUI
import WinnelCore

struct ExportOptionsSheet: View {
    @ObservedObject var model: AppModel
    var stackID: UUID? = nil
    @State private var format: ExportFormat = .markdown
    @State private var includeImages = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WinnelSectionHeader(title: "Export selected items", subtitle: "\(model.selectedItems.count) \(model.selectedItems.count == 1 ? "item" : "items") · Review before writing", symbol: "square.and.arrow.up")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WinnelCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Export options").font(.headline)
                            Picker("Format", selection: $format) {
                                Text("Markdown").tag(ExportFormat.markdown)
                                Text("Versioned JSON").tag(ExportFormat.json)
                            }
                            .pickerStyle(.radioGroup)
                            Text(format == .markdown ? "A readable document for notes and sharing." : "Structured, versioned data for reuse outside Winnel.")
                                .font(.callout).foregroundStyle(.secondary)
                            Divider()
                            Toggle("Include captured images as separate assets", isOn: $includeImages)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected content").font(.headline)
                        List(model.selectedItems) { item in ItemRow(item: item) }
                            .frame(height: 150)
                            .scrollContentBackground(.hidden)
                            .background(WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    }

                    WinnelCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Choose a destination, then review", systemImage: "folder").font(.headline)
                            Text("Next, choose a new destination folder and review the exact included content and assets before writing.")
                            Text("File entries include metadata and references only. Original file contents are never copied. Missing or relative references remain labeled. Exports are plaintext and are not uploaded or opened automatically.")
                                .foregroundStyle(.secondary)
                        }.font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Choose destination…") {
                    model.exportSelection(format: format, includeImages: includeImages, stackID: stackID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedItems.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 380, idealHeight: 600)
        .background(WinnelStyle.canvas)
        .tint(WinnelStyle.accent)
    }
}
