import SwiftUI
import WinnelCore
import WinnelPlatform

struct PaletteView: View {
    @ObservedObject var model: AppModel
    @State private var createStack = false
    @State private var combine = false
    @State private var orderSelection = false
    @State private var export = false
    @State private var deleteItem: ClipboardItem?
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search text, sources and stacks", text: $model.searchQuery).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search clipboard library")
                if !model.searchQuery.isEmpty { Button { model.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                Menu {
                    Button("Saved stacks") { model.onShowLibrary?() }
                    Button("Settings") { model.onShowSettings?() }
                    Divider()
                    if model.isPaused { Button("Resume capture") { model.resumeCapture() } }
                    else { Button("Pause capture for 15 minutes") { model.pause(until: Date().addingTimeInterval(900)) }; Button("Pause until I resume") { model.pause(until: nil) } }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Library and settings")
            }.padding(16)
            Picker("Browse (search includes all items)", selection: $model.libraryScope) {
                Text("Recent").tag(LibraryScope.recent)
                Text("Pinned").tag(LibraryScope.pinned)
                Text("All saved and recent").tag(LibraryScope.all)
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Browse recent, pinned, or all saved and recent items").help("Search always includes all saved and recent items.").padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            if model.recoveryMessage != nil {
                ScrollView { RecoveryView(model: model).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                if model.clipboardAccessStatus != .allowed { ClipboardAccessView(model: model, compact: true).padding(16); Divider() }
                HSplitView {
                    itemList.frame(minWidth: 240, idealWidth: 330)
                    detail.frame(minWidth: 230, idealWidth: 290)
                }
                Divider()
                actions.padding(12)
                if model.queue != nil { Divider(); QueueStatusView(model: model).padding(12) }
            }
            if !model.status.isEmpty { Text(model.status).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 10).accessibilityLabel("Status: \(model.status)") }
        }
        .frame(minWidth: 620, minHeight: 420)
        .tint(WinnelStyle.accent)
        .onAppear { model.refreshClipboardAccessStatus(); searchFocused = model.recoveryMessage == nil }
        .onChange(of: model.recoveryMessage) { _, message in
            if message != nil {
                createStack = false; combine = false; orderSelection = false; export = false; deleteItem = nil
                searchFocused = false
            }
        }
        .onChange(of: model.selectedIDs) { old, new in
            model.selectionOrder = model.selectionOrder.filter { new.contains($0) } + model.visibleItems.filter { new.contains($0.id) && !old.contains($0.id) && !model.selectionOrder.contains($0.id) }.map(\.id)
        }
        .onChange(of: model.selectedItems.first?.id) { _, id in
            if let id { model.loadPreview(id) }
        }
        .onExitCommand { model.cancelQueue(); model.onDismissPalette?() }
        .sheet(isPresented: $createStack) { NamedTextSheet(title: "Create a saved stack", fieldLabel: "Stack name", actionLabel: "Create stack", initialValue: "") { model.createStack(name: $0) } }
        .sheet(isPresented: $combine) { CombinationSheet(model: model) }
        .sheet(isPresented: $orderSelection) { SelectionOrderSheet(model: model) }
        .sheet(isPresented: $export) { ExportOptionsSheet(model: model) }
        .alert("Delete everywhere?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } })) {
            Button("Cancel", role: .cancel) { deleteItem = nil }
            Button("Delete everywhere", role: .destructive) { if let item = deleteItem { model.deleteEverywhere(item.id) }; deleteItem = nil }
        } message: {
            if let item = deleteItem { let names = model.state.affectedStacks(for: item.id).map(\.name); Text("Remove this item from recent history, pins\(names.isEmpty ? "" : " and stacks: " + names.joined(separator: ", ")). Original files and the system clipboard remain.") }
        }
    }
    @ViewBuilder private var itemList: some View {
        if model.visibleItems.isEmpty {
            EmptyLibraryView(title: model.searchQuery.isEmpty ? (model.libraryScope == .pinned ? "No pins yet" : "A little room for what you copy") : "No matches", description: model.searchQuery.isEmpty ? (model.libraryScope == .pinned ? "Pin an item to keep it beyond recent retention. Your pins appear here." : "Enable capture in Settings, then copy something. Saved stacks stay until you remove them.") : "Try a word, app name or stack name.", symbol: model.searchQuery.isEmpty ? "clipboard" : "magnifyingglass")
        } else {
            List(model.visibleItems, selection: $model.selectedIDs) { item in
                ItemRow(item: item, query: model.searchQuery).tag(item.id).contextMenu {
                    Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item.id) }
                    Button("Delete everywhere…", role: .destructive) { deleteItem = item }
                }
            }.listStyle(.inset).accessibilityLabel("Clipboard items. Hold Command to select several.")
        }
    }
    @ViewBuilder private var detail: some View {
        if let item = model.selectedItems.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text(model.selectedItems.count > 1 ? "\(model.selectedItems.count) selected" : "Preview").font(.headline); Spacer(); Button { model.togglePin(item.id) } label: { Image(systemName: item.isPinned ? "pin.fill" : "pin") }.accessibilityLabel(item.isPinned ? "Unpin item" : "Pin item") }
                    PayloadPreviewView(item: item, payload: model.previewPayload, thumbnailData: model.previewThumbnailData, thumbnailFinished: model.previewThumbnailFinished)
                    Divider(); ItemMetadataView(item: item)
                    if model.selectedItems.count > 1 { Text("The first selected item is shown. Review the order before combining or starting a queue.").font(.callout).foregroundStyle(.secondary) }
                }.padding(18)
            }
        } else { EmptyLibraryView(title: "Choose a copy", description: "Select an item to inspect it. Command-click selects several for a stack, combination or queue.", symbol: "rectangle.and.hand.point.up.left") }
    }
    private var actions: some View {
        HStack {
            Button(model.state.settings.defaultAction == .paste ? "Paste" : "Copy") { defaultAction() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(model.selectedItems.count != 1)
            Menu("More") {
                Button("Copy") { model.copySelected() }.disabled(model.selectedItems.count != 1)
                Button("Paste") { model.pasteSelected() }.disabled(model.selectedItems.count != 1)
                Divider()
                Button("Create stack…") { createStack = true }
                Menu("Add to stack") { ForEach(model.state.stacks) { stack in Button(stack.name) { model.addToStack(stack.id) } } }.disabled(model.state.stacks.isEmpty)
                Button("Combine…") { model.prepareCombination(format: .newline); combine = true }
                Button("Review selection order…") { orderSelection = true }
                Button("Export selected…") { export = true }
                Divider()
                Button("Start Copy Next queue") { model.startQueue(mode: .copy) }
                Button("Start Paste Next queue") { model.startQueue(mode: .paste) }
                if let first = model.selectedItems.first { Button("Delete everywhere…", role: .destructive) { deleteItem = first } }
            }.fixedSize().disabled(model.selectedItems.isEmpty)
            Spacer()
            Text("\(model.visibleItems.count) items").font(.callout).foregroundStyle(.secondary)
        }
    }
    private func defaultAction() { if model.state.settings.defaultAction == .paste { model.pasteSelected() } else { model.copySelected() } }
}

struct PayloadPreviewView: View {
    let item: ClipboardItem
    let payload: ClipPayload?
    let thumbnailData: Data?
    let thumbnailFinished: Bool
    var body: some View {
        if let payload {
            if item.kind == .image {
                Group {
                    if let thumbnailData, let image = NSImage(data: thumbnailData) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260).accessibilityLabel("Bounded captured image preview") }
                    else if thumbnailFinished { Label("Image preview unavailable", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                    else { ProgressView("Preparing bounded image preview…") }
                }
            } else if item.kind == .files {
                ForEach(Array(payload.fileReferences.enumerated()), id: \.offset) { _, file in
                    VStack(alignment: .leading, spacing: 4) { Label(file.displayName, systemImage: "doc"); Text(file.urlString).font(.callout).textSelection(.enabled); Text(file.availability.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                }
                Text("File references only. Winnel does not copy the file contents.").font(.callout).foregroundStyle(.secondary)
            } else {
                let excerpt = payload.boundedPlainText()
                if let text = excerpt?.text, excerpt?.isTruncated == false, let swatch = literalColor(text) {
                    HStack { RoundedRectangle(cornerRadius: 8).fill(swatch).frame(width: 48, height: 48).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.5))).accessibilityLabel("Color swatch for " + text); Text("Recognized hex color").font(.callout).foregroundStyle(.secondary) }
                }
                Text(WinnelStyle.displayText(excerpt?.text ?? item.textPreview)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if excerpt?.isTruncated == true { Text("Showing a bounded text excerpt. Copy and Export still use the complete captured content.").font(.callout).foregroundStyle(.secondary) }
            }
        } else { ProgressView("Loading preview…") }
    }
    private func literalColor(_ text: String) -> Color? {
        guard let color = ColorLiteral(hexLiteral: text) else { return nil }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

struct QueueStatusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let queue = model.queue {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(queue.mode == .copy ? "Copy Next queue" : "Paste Next queue").font(.headline)
                    Text(queue.isComplete ? "All \(queue.entries.count) dispatched. Back lets you retry." : "\(min(queue.position + 1, queue.entries.count)) of \(queue.entries.count): \(queue.current?.item.textPreview ?? "")").font(.callout).lineLimit(1)
                }
                Spacer()
                Picker("Queue mode", selection: Binding(get: { queue.mode }, set: { model.queue?.mode = $0; model.queue?.interact(now: Date()) })) { Text("Copy Next").tag(ItemAction.copy); Text("Paste Next").tag(ItemAction.paste) }.labelsHidden().frame(maxWidth: 130).accessibilityLabel("Queue Copy or Paste mode")
                Button("Back") { model.backInQueue() }.disabled(queue.position == 0)
                Button(queue.mode == .copy ? "Copy Next" : "Paste Next") { model.nextInQueue() }.disabled(queue.current == nil)
                Button("Cancel") { model.cancelQueue() }
            }.accessibilityElement(children: .contain).accessibilityLabel("Sequential queue")
        }
    }
}

struct SelectionOrderSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Selection order").font(.title2.bold())
            Text("Combinations and queues use this order.").foregroundStyle(.secondary)
            List { ForEach(Array(model.selectedItems.enumerated()), id: \.element.id) { index, item in
                HStack { Text("\(index + 1)."); Text(item.textPreview).lineLimit(2); Spacer(); Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move item up"); Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == model.selectedItems.count).accessibilityLabel("Move item down") }
            } }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 480, minHeight: 340)
    }
    private func move(_ index: Int, _ offset: Int) { var ids = model.selectedItems.map(\.id); ids.swapAt(index, index + offset); model.selectionOrder = ids }
}

struct CombinationSheet: View {
    @ObservedObject var model: AppModel
    var stackID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Combine \(model.selectedItems.count) items").font(.title2.bold())
            Picker("Format", selection: Binding(get: { model.combinationFormat }, set: { model.prepareCombination(format: $0, stackID: stackID) })) { ForEach(CombinationFormat.allCases, id: \.self) { Text($0.label).tag($0) } }
            Text("Copy, Paste and Export use this exact preview. Original items stay unchanged.").font(.callout).foregroundStyle(.secondary)
            ScrollView { Text(model.combinationPreview.isEmpty ? "No compatible preview. Select text or links; Markdown links need a copied URL or an explicit stack association." : model.combinationPreview).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            HStack { Button("Export preview…") { model.exportCombination() }.disabled(model.combinationPreview.isEmpty); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Paste preview") { model.pasteCombination(); dismiss() }.disabled(model.combinationPreview.isEmpty); Button("Copy preview") { model.copyCombination(); dismiss() }.keyboardShortcut(.defaultAction).disabled(model.combinationPreview.isEmpty) }
        }.padding(24).frame(minWidth: 520, minHeight: 420)
    }
}
