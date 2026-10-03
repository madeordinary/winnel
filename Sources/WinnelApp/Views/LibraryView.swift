import SwiftUI
import WinnelCore

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @State private var stackID: UUID?
    @State private var memberID: UUID?
    @State private var create = false
    @State private var rename = false
    @State private var associate = false
    @State private var confirmDeleteStack = false
    @State private var confirmDeleteItem = false
    @State private var combine = false
    @State private var export = false
    private var stack: SavedStack? { model.state.stacks.first { $0.id == stackID } }
    private var selectedMember: ClipboardItem? {
        guard let memberID, model.selectedIDs == [memberID] else { return nil }
        return model.state.items.first { $0.id == memberID }
    }
    var body: some View {
        NavigationSplitView {
            List(model.state.stacks, selection: $stackID) { stack in
                VStack(alignment: .leading, spacing: 4) { Text(stack.name).lineLimit(2); Text("\(stack.memberships.count) items").font(.caption).foregroundStyle(.secondary) }.tag(stack.id).accessibilityElement(children: .combine)
            }.navigationTitle("Saved stacks")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
            .toolbar { Button { create = true } label: { Label("New stack", systemImage: "plus") }.help("Create an empty named stack") }
        } detail: {
            if let stack {
                GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(stack.name).font(.title2.bold()).lineLimit(2); Text("\(stack.memberships.count) ordered items").foregroundStyle(.secondary) }; Spacer(); Menu("Stack actions") { Button("Rename…") { rename = true }; Button("Export stack…") { selectWholeStack(); export = true }; Button("Combine stack…") { selectWholeStack(); model.prepareCombination(format: .newline, stackID: stack.id); combine = true }; Divider(); Button("Delete stack…", role: .destructive) { confirmDeleteStack = true } } }.padding(20)
                    Divider()
                    if stack.memberships.isEmpty { EmptyLibraryView(title: "Ready to collect", description: "Select clipboard items in the palette, then choose Add to stack. An item can belong to several stacks.", symbol: "square.stack") }
                    else {
                        HSplitView {
                            List(selection: $memberID) {
                                ForEach(Array(stack.memberships.enumerated()), id: \.element.itemID) { index, membership in
                                    if let item = model.state.items.first(where: { $0.id == membership.itemID }) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack { Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary); ItemRow(item: item); Spacer() }
                                            HStack { Button { move(index: index, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move \(item.textPreview) up"); Button { move(index: index, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == stack.memberships.count).accessibilityLabel("Move \(item.textPreview) down"); if membership.associatedURL != nil { Label("Associated link", systemImage: "link").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.borderless)
                                        }.tag(item.id).padding(.vertical, 3)
                                    }
                                }
                            }.frame(minWidth: 280, idealWidth: 320, maxWidth: max(280, geometry.size.width - 261))
                            memberDetail.frame(minWidth: 260, idealWidth: 350, maxWidth: max(260, geometry.size.width - 281))
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
                }.navigationTitle(stack.name)
            } else { EmptyLibraryView(title: "Gather what belongs together", description: "Make a named stack of excerpts, links, images or file references. Items are shared, so removing one membership leaves other stacks intact.", symbol: "square.stack.3d.up") }
        }
        .frame(minWidth: 900, minHeight: 500).tint(WinnelStyle.accent)
        .onChange(of: memberID) { _, id in if let item = model.state.items.first(where: { $0.id == id }) { model.selectedIDs = [item.id]; model.selectionOrder = [item.id]; model.loadPreview(item.id) } }
        .onChange(of: model.selectedIDs) { _, ids in
            if let memberID, ids != [memberID] { self.memberID = nil }
        }
        .onChange(of: stackID) { _, _ in memberID = nil }
        .sheet(isPresented: $create) { NamedTextSheet(title: "New saved stack", fieldLabel: "Stack name", actionLabel: "Create stack", initialValue: "") { name in model.selectedIDs = []; model.selectionOrder = []; model.createStack(name: name) } }
        .sheet(isPresented: $rename) { NamedTextSheet(title: "Rename stack", fieldLabel: "Stack name", actionLabel: "Save", initialValue: stack?.name ?? "") { if let id = stackID { model.renameStack(id, name: $0) } } }
        .sheet(isPresented: $associate) { AssociationSheet(model: model, stackID: stackID, itemID: memberID) }
        .sheet(isPresented: $combine) { CombinationSheet(model: model, stackID: stackID) }
        .sheet(isPresented: $export) { ExportOptionsSheet(model: model, stackID: stackID) }
        .alert("Delete this stack?", isPresented: $confirmDeleteStack) { Button("Cancel", role: .cancel) {}; Button("Delete stack", role: .destructive) { if let id = stackID { model.deleteStack(id) }; stackID = nil } } message: { Text("Only this stack is removed. Pins, other stack memberships and eligible recent items remain. Items past retention with no remaining saved reference are released.") }
        .alert("Delete this item everywhere?", isPresented: $confirmDeleteItem) { Button("Cancel", role: .cancel) {}; Button("Delete everywhere", role: .destructive) { if let id = memberID { model.deleteEverywhere(id) }; memberID = nil } } message: { Text("Remove from recent history, pins and all affected stacks: \(memberID.map { model.state.affectedStacks(for: $0).map(\.name).joined(separator: ", ") } ?? ""). Original files and exports remain.") }
    }
    @ViewBuilder private var memberDetail: some View {
        if let item = selectedMember {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PayloadPreviewView(item: item, payload: model.previewPayload, thumbnailData: model.previewThumbnailData, thumbnailFinished: model.previewThumbnailFinished); Divider(); ItemMetadataView(item: item)
                    if let url = stack?.memberships.first(where: { $0.itemID == item.id })?.associatedURL { Text("Associated URL").font(.headline); Text(url).textSelection(.enabled).font(.callout) }
                    HStack { Button("Copy") { model.copySelected() }; Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item.id) } }
                    Button("Associate a URL…") { associate = true }
                    Text("This is an explicit citation for this stack membership. Winnel never discovers a page URL from nearby clips.").font(.callout).foregroundStyle(.secondary)
                    Button("Remove from this stack") { if let id = stackID { model.removeFromStack(id, itemID: item.id) }; memberID = nil }
                    Button("Delete everywhere…", role: .destructive) { confirmDeleteItem = true }
                }.padding(20)
            }
        } else { EmptyLibraryView(title: "Inspect a saved item", description: "Select an item to copy it, pin it or associate a URL.", symbol: "doc.text.magnifyingglass") }
    }
    private func selectWholeStack() { let ids = stack?.memberships.map(\.itemID) ?? []; model.selectedIDs = Set(ids); model.selectionOrder = ids }
    private func move(index: Int, by offset: Int) { guard let stack else { return }; var ids = stack.memberships.map(\.itemID); ids.swapAt(index, index + offset); model.reorderStack(stack.id, itemIDs: ids) }
}

struct AssociationSheet: View {
    @ObservedObject var model: AppModel
    let stackID: UUID?
    let itemID: UUID?
    @State private var url = ""
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool { guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else { return false }; return ["http", "https", "mailto"].contains(scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Associate a URL").font(.title2.bold())
            Text("Provide the source link yourself. This association belongs only to this stack membership.").foregroundStyle(.secondary)
            TextField("https://example.com/source", text: $url).textFieldStyle(.roundedBorder).accessibilityLabel("Associated URL")
            if !url.isEmpty && !valid { Text("Enter an HTTP, HTTPS or mailto URL.").font(.callout).foregroundStyle(.red) }
            HStack { Button("Remove association") { save(nil) }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save link") { save(url) }.keyboardShortcut(.defaultAction).disabled(!valid) }
        }.padding(24).frame(minWidth: 450).onAppear { url = model.state.stacks.first { $0.id == stackID }?.memberships.first { $0.itemID == itemID }?.associatedURL ?? "" }
    }
    private func save(_ value: String?) { if let stackID, let itemID { model.associateURL(stackID: stackID, itemID: itemID, url: value) }; dismiss() }
}
