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
            Text("Export \(model.selectedItems.count) items").font(.title2.bold())
            Picker("Format", selection: $format) { Text("Markdown").tag(ExportFormat.markdown); Text("Versioned JSON").tag(ExportFormat.json) }
            Toggle("Include captured images as separate assets", isOn: $includeImages)
            Text("File entries include metadata and references only. Original file contents are never copied. Missing or relative references remain labeled. Exports are plaintext and are not uploaded or opened automatically.").font(.callout).foregroundStyle(.secondary)
            Text("Next, choose a new destination folder and review the exact included content and assets before writing.").font(.callout)
            List(model.selectedItems) { item in ItemRow(item: item) }.frame(minHeight: 150)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Choose destination…") { model.exportSelection(format: format, includeImages: includeImages, stackID: stackID); dismiss() }.keyboardShortcut(.defaultAction).disabled(model.selectedItems.isEmpty) }
        }.padding(24).frame(minWidth: 500, minHeight: 380)
    }
}
