import SwiftUI
import MooveKit

/// One box opened up: the big drawing, its label and stamps, and a check-off list of what goes in.
/// When the last line is checked the box seals (tape runs across the top, a "Sealed" stamp lands).
struct BoxDetailView: View {
    var box: MovingBox
    /// Checked lines across all boxes, keyed by `PackChecks.key(box:line:)`.
    @Binding var checked: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var packedCount: Int { box.contents.indices.filter { checked.contains(PackChecks.key(box: box.id, line: $0)) }.count }
    private var sealed: Bool { !box.contents.isEmpty && packedCount == box.contents.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BoxArt(box: box, sealed: sealed, large: true)
                        .frame(maxWidth: 360)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    header
                    contents
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .navigationTitle("Box \(box.numberText)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.monoText(14, weight: .bold, maxScale: 1.5)
                }
            }
            .mooveScreen()
        }
        .sensoryFeedback(.success, trigger: sealed) { _, now in now }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // The title bar already says "Box 04".
                BoxBadge(box: box, sealed: false).accessibilityHidden(true)
                Text(box.roomName).eyebrow()
                if sealed { MonoTag(text: "Sealed", tone: Theme.accentStrong) }
            }
            Text(box.title)
                .monoText(22, weight: .bold, maxScale: 1.6)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(box.size.label) · \(Int(box.weightKg.rounded())) kg · \(box.contents.count) \(box.contents.count == 1 ? "line" : "lines")")
                .monoMeta()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(box.size.label), \(Int(box.weightKg.rounded())) kilograms, \(box.contents.count) \(box.contents.count == 1 ? "item" : "items")")
            if !box.stamps.isEmpty {
                Text(box.stamps.map(\.rawValue).joined(separator: " · "))
                    .monoText(13.5, weight: .bold)
                    .foregroundStyle(box.fragile ? Theme.danger : Theme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint = hint {
                Text(hint).sansText(15).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String? {
        if box.keepWithYou { return "Valuables and papers. This one rides with you, not on the truck." }
        if box.openFirst { return "The first-night box. Load it last so it comes off the truck first." }
        if box.fragile { return "Wrap each piece, fill gaps with paper, and keep it light." }
        return nil
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Contents", count: sealed ? "sealed" : "\(packedCount) of \(box.contents.count) packed") {
                if !box.contents.isEmpty {
                    Button(sealed ? "Unpack all" : "Check all") { setAll(!sealed) }
                        .buttonStyle(.pill(.text, compact: true))
                }
            }
            if box.contents.isEmpty {
                Text("Nothing listed for this box.")
                    .monoMeta()
                    .padding(.top, 12)
            }
            ForEach(Array(box.contents.enumerated()), id: \.offset) { index, line in
                ContentRow(line: line, done: isChecked(index)) { toggle(index) }
            }
            if box.contents.contains(where: { $0.itemId == nil }) {
                Text("Typical: usual contents, not from your scan.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            if sealed {
                Text("Sealed. Number two sides, stack by the door.")
                    .monoMeta()
                    .foregroundStyle(Theme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private func isChecked(_ index: Int) -> Bool { checked.contains(PackChecks.key(box: box.id, line: index)) }

    private func toggle(_ index: Int) {
        let key = PackChecks.key(box: box.id, line: index)
        var next = checked
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        checked = next
    }

    private func setAll(_ on: Bool) {
        var next = checked
        for i in box.contents.indices {
            let key = PackChecks.key(box: box.id, line: i)
            if on { next.insert(key) } else { next.remove(key) }
        }
        checked = next
    }
}

/// A check-off line: square checkbox, item name (with "typical" for lines not from the scan), quantity.
private struct ContentRow: View {
    var line: BoxContent
    var done: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(done ? Theme.accentStrong : Theme.muted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .monoText(14.5, weight: .bold)
                        .foregroundStyle(done ? Theme.muted : Theme.text)
                        .strikethrough(done, color: Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if line.itemId == nil {
                        // "Faint" in spirit; `muted` so it still passes 4.5:1.
                        Text("typical").monoText(12.5).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if line.quantity > 1 {
                    Text("× \(line.quantity)").rowValue()
                }
            }
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .ruled()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.name)\(line.quantity > 1 ? ", \(line.quantity)" : "")\(line.itemId == nil ? ", typical" : "")")
        .accessibilityValue(done ? "Packed" : "Not packed")
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }
}

/// Check-off state keys and their compact storage ("3:0,3:1") for `@AppStorage`.
enum PackChecks {
    static func key(box: Int, line: Int) -> String { "\(box):\(line)" }
    static func decode(_ raw: String) -> Set<String> { Set(raw.split(separator: ",").map(String.init)) }
    static func encode(_ set: Set<String>) -> String { set.sorted().joined(separator: ",") }
}

private struct BoxDetailPreview: View {
    @State private var checked: Set<String> = ["1:0"]
    private let box = PackingPlanner.plan(
        items: DemoFixtures.inventory(owner: "preview").items.filter { $0.disposition == .keep || $0.maybeSentimental }
    ).boxes.first

    var body: some View {
        if let box { BoxDetailView(box: box, checked: $checked) } else { Text("No boxes") }
    }
}

#Preview {
    BoxDetailPreview().environment(MooveStore.preview())
}
