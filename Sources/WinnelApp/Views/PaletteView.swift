import SwiftUI
import WinnelCore
import WinnelPlatform

struct PaletteView: View {
    @ObservedObject var model: AppModel
    @State private var createStack = false
    @State private var combine = false
    @State private var orderSelection = false
    @State private var export = false
    @State private var deleteItems: [ClipboardItem] = []
    @State private var unpinItem: ClipboardItem?
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("Search clipboard…", text: $model.searchQuery)
                            .textFieldStyle(.plain).font(.title3).focused($searchFocused)
                            .onSubmit { if model.selectedItems.count == 1 { defaultAction() } }
                            .onKeyPress(.downArrow) { model.moveVisibleSelection(by: 1); return .handled }
                            .onKeyPress(.upArrow) { model.moveVisibleSelection(by: -1); return .handled }
                            .accessibilityLabel("Search clipboard library")
                            .accessibilityHint("Up and Down Arrow choose a result. Return uses the selected item.")
                        if !model.searchQuery.isEmpty {
                            Button { model.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel("Clear search")
                        }
                    }.padding(10).background(WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(searchFocused ? WinnelStyle.accent : WinnelStyle.border, lineWidth: searchFocused ? 1 : 0.5))
                    Button { model.onShowLibrary?() } label: { Image(systemName: "square.grid.2x2") }
                        .buttonStyle(.plain).help("Open saved stacks").accessibilityLabel("Saved stacks")
                    Menu {
                        Text(model.captureState.label)
                        Button("Saved stacks") { model.onShowLibrary?() }
                        Button("Settings") { model.onShowSettings?() }
                        Divider()
                        if !model.state.settings.captureEnabled { Button("Turn on capture") { model.enableCapture() } }
                        else if model.isPaused { Button("Resume capture") { model.resumeCaptureFromUser() } }
                        else { Button("Pause capture for 15 minutes") { model.pause(until: Date().addingTimeInterval(900)) }; Button("Pause until I resume") { model.pause(until: nil) } }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Capture, library and settings")
                }
                HStack(spacing: 12) {
                    Picker("Browse (search includes all items)", selection: $model.libraryScope) {
                        Text("Recent").tag(LibraryScope.recent)
                        Text("Pinned").tag(LibraryScope.pinned)
                        Text("All items").tag(LibraryScope.all)
                    }.pickerStyle(.segmented).labelsHidden()
                        .accessibilityLabel("Browse recent, pinned, or all saved and recent items")
                        .help("Search always includes all saved and recent items.")
                    Picker("Content type", selection: $model.kindFilter) {
                        Text("All types").tag(ClipKind?.none)
                        ForEach(ClipKind.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }.labelsHidden().frame(width: 115).accessibilityLabel("Filter content type")
                    Label(model.captureState.label, systemImage: model.captureState == .active ? "circle.fill" : "pause.circle")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize().accessibilityLabel(model.captureState.label)
                }
            }.padding(14)
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
                VStack(alignment: .leading, spacing: 8) {
                    actions
                    if !model.selectedItems.isEmpty && !Combination.canCombine(model.selectedItems) {
                        Text("Combine supports text and links. Images and file references can be saved or exported.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10)
                if model.queue != nil { Divider(); QueueStatusView(model: model).padding(12).background(WinnelStyle.accent.opacity(0.05)) }
            }
            if !model.status.isEmpty { Text(model.status).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 10).accessibilityLabel("Status: \(model.status)") }
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(WinnelStyle.canvas)
        .tint(WinnelStyle.accent)
        .onAppear { model.refreshClipboardAccessStatus(); searchFocused = model.recoveryMessage == nil }
        // The panel and its view persist between openings, so each opening asks for focus again.
        .onChange(of: model.paletteOpenCount) { _, _ in model.refreshClipboardAccessStatus(); searchFocused = model.recoveryMessage == nil }
        .onChange(of: model.recoveryMessage) { _, message in
            if message != nil {
                createStack = false; combine = false; orderSelection = false; export = false; deleteItems = []; unpinItem = nil
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
        .alert(deleteItems.count > 1 ? "Delete \(deleteItems.count) items everywhere?" : "Delete everywhere?", isPresented: Binding(get: { !deleteItems.isEmpty }, set: { if !$0 { deleteItems = [] } })) {
            Button("Cancel", role: .cancel) { deleteItems = [] }
            Button(deleteItems.count > 1 ? "Delete \(deleteItems.count) items" : "Delete everywhere", role: .destructive) { model.deleteEverywhere(deleteItems.map(\.id)); deleteItems = [] }
        } message: {
            let names = Array(Set(deleteItems.flatMap { model.state.affectedStacks(for: $0.id).map(\.name) })).sorted()
            Text("Remove \(deleteItems.count > 1 ? "these \(deleteItems.count) items" : "this item") from recent history, pins\(names.isEmpty ? "" : " and stacks: " + names.joined(separator: ", ")). Original files and the system clipboard remain.")
        }
        .alert("Unpin and remove this item?", isPresented: Binding(get: { unpinItem != nil }, set: { if !$0 { unpinItem = nil } })) {
            Button("Cancel", role: .cancel) { unpinItem = nil }
            Button("Unpin and remove", role: .destructive) { if let item = unpinItem { model.togglePin(item.id) }; unpinItem = nil }
        } message: { Text("It is older than your recent-history window and is not in a stack, so unpinning removes it from Winnel.") }
    }
    @ViewBuilder private var itemList: some View {
        if model.visibleItems.isEmpty {
            if let kind = model.kindFilter {
                VStack {
                    EmptyLibraryView(title: "No \(kind.label.lowercased()) items", description: "No items of this type match the current view. Choose another type or clear the filter.", symbol: kind.symbol)
                    Button("Show all types") { model.kindFilter = nil }.padding(.bottom, 24)
                }
            } else {
                EmptyLibraryView(title: model.searchQuery.isEmpty ? (model.libraryScope == .pinned ? "No pins yet" : "A little room for what you copy") : "No matches", description: model.searchQuery.isEmpty ? (model.libraryScope == .pinned ? "Pin an item to keep it beyond recent retention. Your pins appear here." : "Enable capture in Settings, then copy something. Saved stacks stay until you remove them.") : "Try a word, app name or stack name.", symbol: model.searchQuery.isEmpty ? "clipboard" : "magnifyingglass")
            }
        } else {
            ScrollViewReader { proxy in
                List(model.visibleItems, selection: $model.selectedIDs) { item in
                    ItemRow(item: item, query: model.searchQuery, isSelected: model.selectedIDs.contains(item.id)).tag(item.id).id(item.id).listRowSeparator(.hidden).contextMenu {
                        Button(item.isPinned ? "Unpin" : "Pin") { togglePin(item) }
                        Button("Delete everywhere…", role: .destructive) { deleteItems = [item] }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).padding(.horizontal, 4)
                    .accessibilityLabel("Clipboard items. Hold Command to select several.")
                    .onChange(of: model.selectedItems.first?.id) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
    }
    @ViewBuilder private var detail: some View {
        if let item = model.selectedItems.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(model.selectedItems.count > 1 ? "\(model.selectedItems.count) selected" : "Preview").font(.headline)
                        Spacer()
                        Button { togglePin(item) } label: { Image(systemName: item.isPinned ? "pin.fill" : "pin") }
                            .buttonStyle(.borderless).accessibilityLabel(item.isPinned ? "Unpin item" : "Pin item")
                    }
                    WinnelCard {
                        Label(item.kind.label, systemImage: item.kind.symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        PayloadPreviewView(item: item, payload: model.previewPayload, thumbnailData: model.previewThumbnailData, thumbnailFinished: model.previewThumbnailFinished)
                    }
                    Text("DETAILS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ItemMetadataView(item: item)
                    if model.selectedItems.count > 1 { Text("Previewing the first selected item. Review the order before combining or starting a queue.").font(.callout).foregroundStyle(.secondary) }
                }.padding(18)
            }
        } else { EmptyLibraryView(title: "Choose a copy", description: "Inspect it here, then bring it back. Command-click to collect several items.", symbol: "rectangle.and.hand.point.up.left") }
    }
    private func togglePin(_ item: ClipboardItem) {
        if item.isPinned && model.unpinWouldRemove(item.id) { unpinItem = item } else { model.togglePin(item.id) }
    }
    private var actions: some View {
        HStack(spacing: 10) {
            Text(model.selectedItems.isEmpty ? "\(model.visibleItems.count) \(model.visibleItems.count == 1 ? "item" : "items")" : "\(model.selectedItems.count) selected")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button { createStack = true } label: { Label("Save stack", systemImage: "rectangle.stack.badge.plus") }
                .disabled(model.selectedItems.isEmpty).help("Save selected items as an ordered stack")
            Button("Combine…") { model.prepareCombination(format: .newline); combine = true }
                .disabled(!Combination.canCombine(model.selectedItems))
            Menu("More") {
                Button("Copy") { model.copySelected() }.disabled(model.selectedItems.count != 1)
                if model.directPasteAvailable { Button("Paste") { model.pasteSelected() }.disabled(model.selectedItems.count != 1) }
                Divider()
                Button("Create stack…") { createStack = true }
                Menu("Add to stack") { ForEach(model.state.stacks) { stack in Button(stack.name) { model.addToStack(stack.id) } } }.disabled(model.state.stacks.isEmpty)
                Button("Combine…") { model.prepareCombination(format: .newline); combine = true }
                    .disabled(!Combination.canCombine(model.selectedItems))
                Button("Review selection order…") { orderSelection = true }
                Button("Export selected…") { export = true }
                Divider()
                Button("Start Copy Next queue") { model.startQueue(mode: .copy) }
                if model.directPasteAvailable { Button("Start Paste Next queue") { model.startQueue(mode: .paste) } }
                Button(model.selectedItems.count > 1 ? "Delete \(model.selectedItems.count) items everywhere…" : "Delete everywhere…", role: .destructive) { deleteItems = model.selectedItems }
            }.fixedSize().disabled(model.selectedItems.isEmpty)
            Spacer(minLength: 4)
            Button { defaultAction() } label: {
                HStack(spacing: 8) {
                    Text(model.effectiveDefaultAction == .paste ? "Paste" : "Copy")
                    Text("↩").accessibilityHidden(true)
                }
            }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(model.selectedItems.count != 1)
                .accessibilityLabel(model.effectiveDefaultAction == .paste ? "Paste" : "Copy")
        }.controlSize(.regular)
    }
    private func defaultAction() { if model.effectiveDefaultAction == .paste { model.pasteSelected() } else { model.copySelected() } }
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
                    VStack(alignment: .leading, spacing: 4) { Label(file.displayName, systemImage: "doc"); Text(file.urlString).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true); Text(file.availability.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                }
                Text("File references only. Winnel does not copy the file contents.").font(.callout).foregroundStyle(.secondary)
            } else {
                let excerpt = payload.boundedPlainText()
                if let text = excerpt?.text, excerpt?.isTruncated == false, let swatch = literalColor(text) {
                    HStack { RoundedRectangle(cornerRadius: 12).fill(swatch).frame(width: 64, height: 64).overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.5))).accessibilityLabel("Color swatch for " + text); Text("Recognized hex color").font(.callout).foregroundStyle(.secondary) }
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
    private var nextShortcut: String { ShortcutSpec(keyCode: model.state.settings.nextShortcutKeyCode, modifiers: model.state.settings.nextShortcutModifiers).displayName }
    var body: some View {
        if let queue = model.queue {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(queue.isComplete ? "Queue complete" : "Queue · \(min(queue.position + 1, queue.entries.count)) of \(queue.entries.count)").font(.headline)
                    Text(queue.isComplete ? "All \(queue.entries.count) items sent. Back lets you retry." : WinnelStyle.displayText(queue.current?.item.textPreview ?? "")).font(.callout).lineLimit(1)
                    Text("Next: \(nextShortcut) works from any app. Escape here cancels the queue.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.directPasteAvailable {
                    Picker("Queue mode", selection: Binding(get: { queue.mode }, set: { model.queue?.mode = $0; model.queue?.interact(now: Date()) })) { Text("Copy").tag(ItemAction.copy); Text("Paste").tag(ItemAction.paste) }.labelsHidden().frame(maxWidth: 100).accessibilityLabel("Queue Copy or Paste mode")
                }
                Button("Back") { model.backInQueue() }.disabled(queue.position == 0)
                Button(queue.mode == .copy ? "Copy Next Item" : "Paste Next Item") { model.nextInQueue() }.disabled(queue.current == nil)
                    .accessibilityHint("Shortcut \(nextShortcut)")
                Button("Cancel Queue") { model.cancelQueue() }
            }.accessibilityElement(children: .contain).accessibilityLabel("Sequential queue")
        }
    }
}

struct SelectionOrderSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WinnelSectionHeader(title: "Selection order", subtitle: "Combinations and queues use this order.", symbol: "list.number")
            List { ForEach(Array(model.selectedItems.enumerated()), id: \.element.id) { index, item in
                HStack { Text("\(index + 1)."); Text(item.textPreview).lineLimit(2); Spacer(); Button { move(item.id, -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move item up"); Button { move(item.id, 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == model.selectedItems.count).accessibilityLabel("Move item down") }
            } }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 480, minHeight: 340)
    }
    private func move(_ itemID: UUID, _ offset: Int) {
        var ids = model.selectedItems.map(\.id)
        guard let index = ids.firstIndex(of: itemID), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        model.selectionOrder = ids
    }
}

struct CombinationSheet: View {
    @ObservedObject var model: AppModel
    var stackID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WinnelSectionHeader(title: "Combine \(model.selectedItems.count) \(model.selectedItems.count == 1 ? "item" : "items")", subtitle: "One preview. Exactly what you will copy.", symbol: "text.badge.plus")
            Picker("Format", selection: Binding(get: { model.combinationFormat }, set: { model.prepareCombination(format: $0, stackID: stackID) })) { ForEach(CombinationFormat.allCases, id: \.self) { Text($0.label).tag($0) } }
            Text("Copy, Paste and Export use this exact preview. Original items stay unchanged.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                if model.combinationLoading && model.combinationPreview.isEmpty { ProgressView("Preparing preview…").frame(maxWidth: .infinity).padding(24) }
                else { Text(model.combinationPreview.isEmpty ? "No compatible preview. Select text or links; Markdown links need a copied URL or an explicit stack association." : model.combinationPreview).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
            }.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            HStack { Button("Export preview…") { model.exportCombination() }.disabled(model.combinationPreview.isEmpty); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); if model.directPasteAvailable { Button("Paste preview") { model.pasteCombination(); dismiss() }.disabled(model.combinationPreview.isEmpty) }; Button("Copy preview") { model.copyCombination(); dismiss() }.keyboardShortcut(.defaultAction).disabled(model.combinationPreview.isEmpty) }
        }.padding(24).frame(minWidth: 520, minHeight: 420)
    }
}
