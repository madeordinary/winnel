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
    init(model: AppModel, initialStackID: UUID? = nil, initialMemberID: UUID? = nil) {
        self.model = model
        _stackID = State(initialValue: initialStackID)
        _memberID = State(initialValue: initialMemberID)
    }
    private var stack: SavedStack? { model.state.stacks.first { $0.id == stackID } }
    private var stackCanCombine: Bool {
        guard let stack else { return false }
        let items = stack.memberships.compactMap { membership in model.state.items.first { $0.id == membership.itemID } }
        return items.count == stack.memberships.count && Combination.canCombine(items)
    }
    private var selectedMember: ClipboardItem? {
        guard let memberID, model.selectedIDs == [memberID] else { return nil }
        return model.state.items.first { $0.id == memberID }
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.title2).foregroundStyle(WinnelStyle.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Winnel").font(.title2.bold())
                            Text("Saved stacks").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Button { create = true } label: { Label("New stack", systemImage: "plus") }
                        .help("Create an empty named stack")
                }.padding(16)
                Divider()
                List(model.state.stacks, selection: $stackID) { stack in
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack")
                            .foregroundStyle(WinnelStyle.accent).frame(width: 30, height: 30)
                            .background(WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                        Text(stack.name).lineLimit(2).foregroundStyle(Color(nsColor: .labelColor))
                        Spacer(minLength: 4)
                        Text("\(stack.memberships.count)").font(.caption.monospacedDigit())
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .accessibilityLabel("\(stack.memberships.count) \(stack.memberships.count == 1 ? "item" : "items")")
                    }.padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 10).fill(WinnelStyle.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).fill(stackID == stack.id ? WinnelStyle.accent.opacity(0.10) : Color.clear))
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(stackID == stack.id ? WinnelStyle.accent : WinnelStyle.border, lineWidth: stackID == stack.id ? 1.5 : 0.5))
                        .tag(stack.id).accessibilityElement(children: .combine)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }.listStyle(.plain).scrollContentBackground(.hidden).accessibilityLabel("Saved stacks")
                Text("\(model.state.stacks.count) saved \(model.state.stacks.count == 1 ? "stack" : "stacks")")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }.background(WinnelStyle.canvas).frame(minWidth: 220, idealWidth: 250, maxWidth: 280)
            if let stack {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            WinnelSectionHeader(title: stack.name, subtitle: "\(stack.memberships.count) ordered \(stack.memberships.count == 1 ? "item" : "items")", symbol: "square.stack")
                            HStack(spacing: 10) {
                                Button { selectWholeStack(); model.prepareCombination(format: .newline, stackID: stack.id); combine = true } label: {
                                    Label("Combine…", systemImage: "text.badge.plus")
                                }.disabled(!stackCanCombine)
                                Button { selectWholeStack(); export = true } label: {
                                    Label("Export…", systemImage: "square.and.arrow.up")
                                }.disabled(stack.memberships.isEmpty)
                                Spacer()
                                Menu("Stack actions") {
                                    Button("Rename…") { rename = true }
                                    Divider()
                                    Button("Delete stack…", role: .destructive) { confirmDeleteStack = true }
                                }.fixedSize()
                            }
                            if !stack.memberships.isEmpty && !stackCanCombine {
                                Text("Combine supports text and links. This stack includes an unsupported item; you can still export the stack.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(20).background(WinnelStyle.surface)
                        Divider()
                        if stack.memberships.isEmpty { EmptyLibraryView(title: "Ready to collect", description: "Select clipboard items in the palette, then choose Add to stack. An item can belong to several stacks.", symbol: "square.stack") }
                        else {
                            HSplitView {
                                List(selection: $memberID) {
                                    ForEach(Array(stack.memberships.enumerated()), id: \.element.itemID) { index, membership in
                                        if let item = model.state.items.first(where: { $0.id == membership.itemID }) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(alignment: .top, spacing: 10) {
                                                    Text("\(index + 1)").font(.caption.monospacedDigit())
                                                        .foregroundStyle(.secondary).frame(width: 20).padding(.top, 8)
                                                    ItemRow(item: item, isSelected: memberID == item.id)
                                                }
                                                HStack { Button { move(index: index, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move \(item.textPreview) up"); Button { move(index: index, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == stack.memberships.count).accessibilityLabel("Move \(item.textPreview) down"); if membership.associatedURL != nil { Label("Associated link", systemImage: "link").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.borderless)
                                            }.tag(item.id).padding(.vertical, 3)
                                                .listRowSeparator(.hidden)
                                                .listRowBackground(Color.clear)
                                        }
                                    }
                                }.listStyle(.plain).scrollContentBackground(.hidden).frame(minWidth: 280, idealWidth: 320, maxWidth: max(280, geometry.size.width - 261)).accessibilityLabel("Ordered stack items")
                                memberDetail.frame(minWidth: 260, idealWidth: 350, maxWidth: max(260, geometry.size.width - 281))
                            }
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            } else { EmptyLibraryView(title: "Gather what belongs together", description: "Make a named stack of excerpts, links, images or file references. Items are shared, so removing one membership leaves other stacks intact.", symbol: "square.stack.3d.up") }
        }
        .background(WinnelStyle.canvas)
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
                    HStack(spacing: 10) {
                        ClipTypeBadge(kind: item.kind)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Saved item").font(.headline)
                            Text(item.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    WinnelCard {
                        PayloadPreviewView(item: item, payload: model.previewPayload, thumbnailData: model.previewThumbnailData, thumbnailFinished: model.previewThumbnailFinished)
                    }
                    HStack {
                        Button { model.copySelected() } label: { Label("Copy", systemImage: "doc.on.doc") }
                            .buttonStyle(.borderedProminent)
                        Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item.id) }
                        Spacer()
                    }
                    WinnelCard {
                        Text("Details").font(.headline)
                        ItemMetadataView(item: item)
                    }
                    WinnelCard {
                        Text("Source link").font(.headline)
                        if let url = stack?.memberships.first(where: { $0.itemID == item.id })?.associatedURL {
                            Text(url).textSelection(.enabled).font(.callout)
                        } else {
                            Text("No associated URL").font(.callout).foregroundStyle(.secondary)
                        }
                        Button("Associate a URL…") { associate = true }
                        Text("This is an explicit citation for this stack membership. Winnel never discovers a page URL from nearby clips.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Manage membership").font(.headline)
                        Button("Remove from this stack") { if let id = stackID { model.removeFromStack(id, itemID: item.id) }; memberID = nil }
                        Text("Other stack memberships and pins remain.").font(.caption).foregroundStyle(.secondary)
                        Button("Delete everywhere…", role: .destructive) { confirmDeleteItem = true }
                    }
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
            WinnelSectionHeader(title: "Associate a URL", subtitle: "Provide the source link yourself. This association belongs only to this stack membership.", symbol: "link")
            TextField("https://example.com/source", text: $url).textFieldStyle(.roundedBorder).accessibilityLabel("Associated URL")
            if !url.isEmpty && !valid { Text("Enter an HTTP, HTTPS or mailto URL.").font(.callout).foregroundStyle(.red) }
            HStack { Button("Remove association") { save(nil) }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save link") { save(url) }.keyboardShortcut(.defaultAction).disabled(!valid) }
        }.padding(24).frame(minWidth: 450).onAppear { url = model.state.stacks.first { $0.id == stackID }?.memberships.first { $0.itemID == itemID }?.associatedURL ?? "" }
    }
    private func save(_ value: String?) { if let stackID, let itemID { model.associateURL(stackID: stackID, itemID: itemID, url: value) }; dismiss() }
}
