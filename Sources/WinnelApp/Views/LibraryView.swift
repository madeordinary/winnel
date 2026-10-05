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
    @State private var confirmUnpin = false
    @State private var confirmRemoveMember = false
    @State private var combine = false
    @State private var export = false
    @State private var presentation: MemberPresentation
    @State private var inspectorVisible: Bool
    enum MemberPresentation: String, CaseIterable { case cards = "Cards", list = "List" }
    init(model: AppModel, initialStackID: UUID? = nil, initialMemberID: UUID? = nil, initialPresentation: MemberPresentation = .cards) {
        self.model = model
        _stackID = State(initialValue: initialStackID)
        _memberID = State(initialValue: initialMemberID)
        _presentation = State(initialValue: initialPresentation)
        _inspectorVisible = State(initialValue: initialMemberID != nil)
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
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text("Saved stacks").font(.headline)
                    Spacer()
                    Button { create = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help("Create an empty named stack").accessibilityLabel("New stack")
                }.padding(16)
                Divider()
                List(model.state.stacks, selection: $stackID) { stack in
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(stack.name).lineLimit(2).foregroundStyle(Color(nsColor: .labelColor))
                        Spacer(minLength: 4)
                        Text("\(stack.memberships.count)").font(.caption.monospacedDigit())
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .accessibilityLabel("\(stack.memberships.count) items")
                    }.padding(.horizontal, 8).padding(.vertical, 6)
                        .background {
                            if stackID == stack.id {
                                RoundedRectangle(cornerRadius: 6).fill(WinnelStyle.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 6).fill(WinnelStyle.accent.opacity(0.10)))
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(stackID == stack.id ? WinnelStyle.accent.opacity(0.65) : Color.clear, lineWidth: 1))
                        .tag(stack.id).accessibilityElement(children: .combine)
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }.listStyle(.plain).scrollContentBackground(.hidden).accessibilityLabel("Saved stacks")
                Text("\(model.state.stacks.count) saved \(model.state.stacks.count == 1 ? "stack" : "stacks")")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }.background(WinnelStyle.canvas).frame(minWidth: 180, idealWidth: 210, maxWidth: 240)
            if let stack {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            // One row when it fits; the controls wrap below the title in narrow windows.
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { stackTitle(stack); Spacer(minLength: 8); stackActions(stack); presentationControls }
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { stackTitle(stack); Spacer(minLength: 8); presentationControls }
                                    HStack(spacing: 10) { stackActions(stack); Spacer(minLength: 0) }
                                }
                            }
                            if !stack.memberships.isEmpty && !stackCanCombine {
                                Text("Combine supports text and links. This stack includes an unsupported item; you can still export the stack.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 10).background(WinnelStyle.surface)
                        Divider()
                        if stack.memberships.isEmpty { EmptyLibraryView(title: "Ready to collect", description: "Select clipboard items in the palette, then choose Add to stack. An item can belong to several stacks.", symbol: "square.stack") }
                        else {
                            HSplitView {
                                Group {
                                    if presentation == .cards { memberCards(stack) }
                                    else { memberList(stack) }
                                }.frame(minWidth: 280, maxWidth: .infinity)
                                if inspectorVisible {
                                    memberDetail.frame(minWidth: 280, idealWidth: 310, maxWidth: max(280, geometry.size.width - 281))
                                }
                            }
                        }
                        if model.queue != nil { Divider(); QueueStatusView(model: model).padding(12).background(WinnelStyle.accent.opacity(0.05)) }
                    }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            } else if model.state.stacks.isEmpty { EmptyLibraryView(title: "Gather what belongs together", description: "Make a named stack of excerpts, links, images or file references. Items are shared, so removing one membership leaves other stacks intact.", symbol: "square.stack.3d.up") }
            else { EmptyLibraryView(title: "Choose a stack", description: "Select a saved stack on the left to see its items in order.", symbol: "sidebar.left") }
        }
        .background(WinnelStyle.canvas)
        .frame(minWidth: 900, minHeight: 500).tint(WinnelStyle.accent)
        .onAppear { if stackID == nil { stackID = model.state.stacks.first?.id } }
        .onChange(of: model.state.stacks.map(\.id)) { _, ids in if stackID.map({ !ids.contains($0) }) ?? true { stackID = ids.first } }
        .onChange(of: memberID) { _, id in
            guard let item = model.state.items.first(where: { $0.id == id }) else { return }
            model.selectedIDs = [item.id]; model.selectionOrder = [item.id]; model.loadPreview(item.id)
            inspectorVisible = true
        }
        .onChange(of: model.selectedIDs) { _, ids in
            if let memberID, ids != [memberID] { self.memberID = nil }
        }
        .onChange(of: stackID) { _, _ in memberID = nil }
        .sheet(isPresented: $create) { NamedTextSheet(title: "New saved stack", fieldLabel: "Stack name", actionLabel: "Create stack", initialValue: "") { name in model.selectedIDs = []; model.selectionOrder = []; model.createStack(name: name) } }
        .sheet(isPresented: $rename) { NamedTextSheet(title: "Rename stack", fieldLabel: "Stack name", actionLabel: "Save", initialValue: stack?.name ?? "") { if let id = stackID { model.renameStack(id, name: $0) } } }
        .sheet(isPresented: $associate) { AssociationSheet(model: model, stackID: stackID, itemID: memberID) }
        .sheet(isPresented: $combine) { CombinationSheet(model: model, stackID: stackID) }
        .sheet(isPresented: $export) { ExportOptionsSheet(model: model, stackID: stackID) }
        .alert("Delete this stack?", isPresented: $confirmDeleteStack) { Button("Cancel", role: .cancel) {}; Button("Delete stack", role: .destructive) { if let id = stackID { model.deleteStack(id) }; stackID = nil } } message: {
            let removed = stackID.map(model.itemsRemovedByDeletingStack) ?? 0
            Text("Only this stack is removed. Pins, other stack memberships and eligible recent items remain." + (removed > 0 ? " \(removed) \(removed == 1 ? "item has" : "items have") no other saved reference and \(removed == 1 ? "is" : "are") no longer kept in recent history, so \(removed == 1 ? "it" : "they") will be removed from Winnel." : ""))
        }
        .alert("Unpin and remove this item?", isPresented: $confirmUnpin) { Button("Cancel", role: .cancel) {}; Button("Unpin and remove", role: .destructive) { if let id = memberID { model.togglePin(id) } } } message: { Text("It has no other saved reference and is no longer kept in recent history, so unpinning removes it from Winnel.") }
        .alert("Remove from stack and delete?", isPresented: $confirmRemoveMember) { Button("Cancel", role: .cancel) {}; Button("Remove", role: .destructive) { removeSelectedMember() } } message: { Text("This is the item's last saved reference and it is no longer kept in recent history, so it will be removed from Winnel.") }
        .alert("Delete this item everywhere?", isPresented: $confirmDeleteItem) { Button("Cancel", role: .cancel) {}; Button("Delete everywhere", role: .destructive) { if let id = memberID { model.deleteEverywhere(id) }; memberID = nil } } message: { Text("Remove from recent history, pins and all affected stacks: \(memberID.map { model.state.affectedStacks(for: $0).map(\.name).joined(separator: ", ") } ?? ""). Original files and exports remain.") }
    }
    private func memberCards(_ stack: SavedStack) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)], spacing: 12) {
                ForEach(Array(stack.memberships.enumerated()), id: \.element.itemID) { index, membership in
                    if let item = model.state.items.first(where: { $0.id == membership.itemID }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                memberID = item.id
                                inspectorVisible = true
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Label(item.kind.label, systemImage: item.kind.symbol).font(.caption.weight(.medium))
                                        Spacer()
                                        Text("\(index + 1)").font(.caption.monospacedDigit())
                                    }.foregroundStyle(.secondary)
                                    Text(WinnelStyle.displayText(item.textPreview.isEmpty ? item.kind.label : item.textPreview))
                                        .font(.body).lineLimit(5).frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                                    HStack {
                                        Text(item.source.name ?? "Unknown source").lineLimit(1)
                                        if item.source.confidence == .inferred { Text("(inferred)") }
                                        Spacer(minLength: 0)
                                        if item.isPinned { Image(systemName: "pin.fill") }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(Color(nsColor: .labelColor))
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Item \(index + 1), \(item.kind.label): \(WinnelStyle.displayText(item.textPreview))")
                                .accessibilityHint("Select and open the item inspector. This does not copy the item.")
                                .accessibilityAddTraits(memberID == item.id ? .isSelected : [])
                            HStack {
                                reorderButtons(stackID: stack.id, itemID: item.id, index: index, count: stack.memberships.count)
                                Spacer()
                                if membership.associatedURL != nil {
                                    Image(systemName: "link").foregroundStyle(.secondary).accessibilityLabel("Associated link")
                                }
                            }
                        }.padding(14).background(WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(memberID == item.id ? WinnelStyle.accent : WinnelStyle.border, lineWidth: memberID == item.id ? 1.5 : 0.5))
                            .id(item.id)
                    }
                }
            }.padding(16)
        }.accessibilityLabel("Ordered stack cards")
            .accessibilityHint("Select a card to open it in the inspector. Switch to List for arrow-key navigation.")
            .onAppear { if let memberID { proxy.scrollTo(memberID, anchor: .center) } }
            .onChange(of: memberID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: inspectorVisible) { _, _ in if let memberID { proxy.scrollTo(memberID, anchor: .center) } }
        }
    }
    private func memberList(_ stack: SavedStack) -> some View {
        List(selection: $memberID) {
            ForEach(Array(stack.memberships.enumerated()), id: \.element.itemID) { index, membership in
                if let item = model.state.items.first(where: { $0.id == membership.itemID }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20).padding(.top, 8)
                            ItemRow(item: item, isSelected: memberID == item.id)
                        }
                        HStack {
                            reorderButtons(stackID: stack.id, itemID: item.id, index: index, count: stack.memberships.count)
                            if membership.associatedURL != nil { Label("Associated link", systemImage: "link").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.tag(item.id).padding(.vertical, 3).listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).accessibilityLabel("Ordered stack items")
    }
    private func reorderButtons(stackID: UUID, itemID: UUID, index: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            Button { move(stackID: stackID, itemID: itemID, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0).accessibilityLabel("Move item \(index + 1) up")
            Button { move(stackID: stackID, itemID: itemID, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index + 1 == count).accessibilityLabel("Move item \(index + 1) down")
        }.buttonStyle(.borderless)
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
                        Button(item.isPinned ? "Unpin" : "Pin") { if item.isPinned && model.unpinWouldRemove(item.id) { confirmUnpin = true } else { model.togglePin(item.id) } }
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
                        Button("Remove from this stack") { if let id = stackID, model.stackRemovalWouldRemove(stackID: id, itemID: item.id) { confirmRemoveMember = true } else { removeSelectedMember() } }
                        Text("Other stack memberships and pins remain.").font(.caption).foregroundStyle(.secondary)
                        Button("Delete everywhere…", role: .destructive) { confirmDeleteItem = true }
                    }
                }.padding(20)
            }
        } else { EmptyLibraryView(title: "Inspect a saved item", description: "Select an item to copy it, pin it or associate a URL.", symbol: "doc.text.magnifyingglass") }
    }
    private func removeSelectedMember() { if let id = stackID, let itemID = memberID { model.removeFromStack(id, itemID: itemID) }; memberID = nil }
    private func stackTitle(_ stack: SavedStack) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(stack.name).font(.title3.weight(.semibold)).lineLimit(1)
            Text("\(stack.memberships.count) \(stack.memberships.count == 1 ? "item" : "items")").font(.caption).foregroundStyle(.secondary).fixedSize()
        }
    }
    private func stackActions(_ stack: SavedStack) -> some View {
        HStack(spacing: 8) {
            Button { selectWholeStack(); model.prepareCombination(format: .newline, stackID: stack.id); combine = true } label: { Label("Combine…", systemImage: "text.badge.plus") }
                .disabled(!stackCanCombine)
            Button { selectWholeStack(); export = true } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                .disabled(stack.memberships.isEmpty)
            Button { selectWholeStack(); model.startQueue(mode: .copy) } label: { Label("Start Queue", systemImage: "list.number") }
                .disabled(stack.memberships.isEmpty).help("Copy this stack's items one at a time with the Next shortcut")
            Menu { Button("Rename…") { rename = true }; Divider(); Button("Delete stack…", role: .destructive) { confirmDeleteStack = true } } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Stack actions")
        }.fixedSize()
    }
    private var presentationControls: some View {
        HStack(spacing: 8) {
            Picker("View", selection: $presentation) { ForEach(MemberPresentation.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110)
            Toggle(isOn: $inspectorVisible) { Image(systemName: "sidebar.right") }
                .toggleStyle(.button).help("Show or hide item inspector").accessibilityLabel("Item inspector")
        }.fixedSize()
    }
    private func selectWholeStack() { let ids = stack?.memberships.map(\.itemID) ?? []; model.selectedIDs = Set(ids); model.selectionOrder = ids }
    private func move(stackID: UUID, itemID: UUID, by offset: Int) {
        guard let stack, stack.id == stackID else { return }
        var ids = stack.memberships.map(\.itemID)
        guard let index = ids.firstIndex(of: itemID), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        model.reorderStack(stack.id, itemIDs: ids)
    }
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
