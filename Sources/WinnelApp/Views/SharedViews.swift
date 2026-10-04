import SwiftUI
import WinnelCore

/// Native adaptive surfaces keep system contrast, text scaling and VoiceOver behavior.
enum WinnelStyle {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static func displayText(_ text: String) -> String {
        let controls: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
        guard text.unicodeScalars.contains(where: { controls.contains($0.value) }) else { return text }
        var result = String(); result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            // Keep clipboard bytes unchanged; avoid an allocation per character in ordinary text.
            if controls.contains(scalar.value) { result += "⟦U+" + String(scalar.value, radix: 16).uppercased() + "⟧" }
            else { result.unicodeScalars.append(scalar) }
        }
        return result
    }
    static let accent = Color(nsColor: NSColor(name: "WinnelAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.40, green: 0.66, blue: 1.00, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.36, blue: 0.78, alpha: 1)
    })
}

struct WinnelSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(WinnelStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

struct WinnelCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WinnelStyle.border, lineWidth: 0.5))
    }
}

struct ClipTypeBadge: View {
    let kind: ClipKind
    var body: some View {
        Image(systemName: kind.symbol).font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary).frame(width: 32, height: 32)
            .background(WinnelStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

extension ClipKind {
    var label: String {
        switch self { case .text: "Text"; case .richText: "Rich text"; case .url: "Link"; case .image: "Image"; case .files: "Files" }
    }
    var symbol: String {
        switch self { case .text: "text.alignleft"; case .richText: "textformat"; case .url: "link"; case .image: "photo"; case .files: "doc" }
    }
}
extension Retention {
    var label: String { switch self { case .oneHour: "1 hour"; case .oneDay: "24 hours"; case .sevenDays: "7 days"; case .ramOnly: "Clear on quit (RAM only)" } }
}
extension CombinationFormat {
    var label: String { switch self { case .newline: "Newline separated"; case .bullets: "Bullets"; case .numbered: "Numbered list"; case .markdownLinks: "Markdown links"; case .jsonArray: "JSON string array" } }
}

struct ItemRow: View {
    let item: ClipboardItem
    var query = ""
    var isSelected = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ClipTypeBadge(kind: item.kind)
            VStack(alignment: .leading, spacing: 5) {
                Text(highlighted(WinnelStyle.displayText(item.textPreview.isEmpty ? item.kind.label : item.textPreview)))
                    .font(.body.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    Text(sourceLabel).font(.caption).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(item.copiedAt, style: .relative).font(.caption).lineLimit(1)
                    if item.isPinned { Image(systemName: "pin.fill").font(.caption).accessibilityLabel("Pinned") }
                }.foregroundStyle(.secondary)
                Text(item.kind.label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(isSelected ? WinnelStyle.accent.opacity(0.08) : WinnelStyle.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSelected ? WinnelStyle.accent : WinnelStyle.border, lineWidth: isSelected ? 1.5 : 0.5))
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
    private var sourceLabel: String {
        let name = item.source.name ?? "Unknown source"
        return item.source.confidence == .inferred ? "\(name) (inferred)" : name
    }
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: search) {
            if let attributedRange = Range(range, in: result) { result[attributedRange].backgroundColor = WinnelStyle.accent.opacity(0.16); result[attributedRange].font = .body.bold() }
            guard range.upperBound < text.endIndex else { break }; search = range.upperBound..<text.endIndex
        }
        return result
    }
}

struct EmptyLibraryView: View {
    let title: String
    let description: String
    let symbol: String
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(WinnelStyle.accent)
                        .frame(width: 64, height: 64).background(WinnelStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                    Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(description).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360).fixedSize(horizontal: false, vertical: true)
                }.padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
}

struct ItemMetadataView: View {
    let item: ClipboardItem
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow { Text("Type").foregroundStyle(.secondary); Text(item.kind.label) }
            GridRow { Text("Copied").foregroundStyle(.secondary); Text(item.copiedAt.formatted(date: .abbreviated, time: .standard)) }
            GridRow { Text("Source").foregroundStyle(.secondary); Text(item.source.name ?? "Unknown") }
            if item.source.confidence == .inferred { GridRow { Text("Attribution").foregroundStyle(.secondary); Text("Inferred from app activity") } }
            GridRow { Text("Payload").foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: Int64(item.payloadByteCount), countStyle: .file)) }
        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NamedTextSheet: View {
    let title: String
    let fieldLabel: String
    let actionLabel: String
    let initialValue: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.bold())
            TextField(fieldLabel, text: $value).textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button(actionLabel, action: save).keyboardShortcut(.defaultAction).disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(minWidth: 360).onAppear { value = initialValue; focused = true }
    }
    private func save() { let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty else { return }; onSave(trimmed); dismiss() }
}
