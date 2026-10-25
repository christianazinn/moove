import SwiftUI
import MooveKit

/// One item: photo, what the vision agent saw, why it was sorted this way,
/// and the comps behind its price.
struct ItemDetailView: View {
    @Environment(MooveStore.self) private var store
    let itemId: UInt64
    @State private var takingPhoto = false
    @State private var photoState: PhotoState = .idle
    /// What the camera's photo is for: another photo, or a reclassify retake.
    @State private var reclassifying = false
    @State private var reclassifyState: PhotoState = .idle

    enum PhotoState: Equatable { case idle, uploading, added, failed(String) }

    var body: some View {
        if let item = store.items.first(where: { $0.id == itemId }) {
            content(item)
        } else {
            ContentUnavailableView("Item removed", systemImage: "shippingbox")
                .foregroundStyle(Theme.muted)
                .mooveScreen()
        }
    }

    private func content(_ item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ItemThumbnail(item: item, size: 200)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                photoAction(item)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name)
                            .monoText(20, weight: .bold, maxScale: 1.6)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if item.maybeSentimental {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.danger)
                                .accessibilityLabel("Possibly sentimental")
                        }
                    }
                    reclassifyAction(item)
                    let listings = store.snapshot.compCounts[item.id] ?? 0
                    let rough = item.saleValueCents != nil && Item.isRoughEstimate(compCount: listings)
                    Text(item.saleValueCents == nil ? item.priceText.capitalizedFirst : rough ? "≈\(item.priceText)" : item.priceText)
                        .monoText(32, weight: .bold, maxScale: 1.6)
                        .tracking(-0.3)
                        .foregroundStyle(item.saleValueCents == nil ? Theme.muted : Theme.text)
                        .accessibilityLabel("Estimated value: \(rough ? "about " : "")\(item.priceText)")
                    if rough {
                        Text("Rough estimate: based on only \(listings) comparable listing\(listings == 1 ? "" : "s").")
                            .monoMeta()
                            .foregroundStyle(Theme.ochreInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("item.roughEstimate")
                    }
                    if item.priceState == .builtIn {
                        Text("Part of the building: not priced or sold.")
                            .monoMeta()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if item.priceState == .unpriced {
                        Text("No price found.")
                            .monoMeta()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DispositionChip(disposition: item.disposition)
                }

                decision(item)
                ItemFixSection(item: item)
                details(item)
                comps(item)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPicker { jpeg in
                takingPhoto = false
                if let jpeg { Task { await (reclassifying ? reclassify(jpeg, item) : addPhoto(jpeg, to: item)) } }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Photo (#5: vision runs again on a new photo)

    /// "Add photo" for items without one (seeded, or added before uploads worked), and
    /// "Add another photo" otherwise. `add_item_photo` re-queues vision, then pricing.
    @ViewBuilder private func photoAction(_ item: Item) -> some View {
        VStack(spacing: 6) {
            Button {
                photoState = .idle
                reclassifying = false
                takingPhoto = true
            } label: {
                Label(photoState == .uploading ? "Uploading…" : item.photoUrls.isEmpty ? "Add photo" : "Add another photo",
                      systemImage: "camera")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .disabled(photoState == .uploading)
            .accessibilityHint("Moove identifies and prices the item from the photo")
            switch photoState {
            case .idle, .uploading:
                if item.photoUrls.isEmpty {
                    Text("No photo yet, so the agents can't identify it.").monoMeta()
                } else if let ask = item.closeupRequest {
                    // #276: vision named one photo that would identify the exact product
                    Text(ask)
                        .monoMeta()
                        .foregroundStyle(Theme.ochreInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("item.closeup")
                }
            case .added:
                Text("Photo added. Moove is identifying it again.").monoMeta()
            case .failed(let why):
                Text("Couldn't add the photo: \(why)").monoMeta().foregroundStyle(Theme.danger)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func addPhoto(_ jpeg: Data, to item: Item) async {
        photoState = .uploading
        let failure = await ItemPhotoUpload.attach(jpeg, to: item, reclassify: false, store: store)
        photoState = failure.map { .failed($0) } ?? .added
    }

    // MARK: Reclassify (a misidentified item, from a new photo)

    /// "Wrong item? Reclassify from a photo", under the name: the retake goes to vision marked
    /// so it identifies the item from that photo, not the scan's category (`ItemReclassify`).
    /// The name and category update when vision answers; meanwhile the status line says so.
    @ViewBuilder private func reclassifyAction(_ item: Item) -> some View {
        let offline = store.backendKind == .fixture
        VStack(alignment: .leading, spacing: 6) {
            if let status = ItemReclassify.status(for: item, offline: offline) {
                HStack(spacing: 8) {
                    if ItemReclassify.isReclassifying(item) && !offline {
                        ProgressView().controlSize(.small)
                    }
                    Text(status)
                        .monoMeta()
                        .foregroundStyle(item.detailsStatus == .failed ? Theme.danger : Theme.ochreInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("item.reclassify.status")
            }
            Button {
                reclassifyState = .idle
                reclassifying = true
                takingPhoto = true
            } label: {
                Label(reclassifyState == .uploading ? "Uploading…" : "Wrong item? Reclassify from a photo",
                      systemImage: "camera.viewfinder")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .disabled(reclassifyState == .uploading)
            .accessibilityHint("Take a photo of it. Moove identifies it again from that photo, not from the scan")
            .accessibilityIdentifier("item.reclassify")
            if case .failed(let why) = reclassifyState {
                Text("Couldn't add the photo: \(why)").monoMeta().foregroundStyle(Theme.danger)
            }
        }
    }

    private func reclassify(_ jpeg: Data, _ item: Item) async {
        reclassifyState = .uploading
        let failure = await ItemPhotoUpload.attach(jpeg, to: item, reclassify: true, store: store)
        reclassifyState = failure.map { .failed($0) } ?? .added
    }

    // MARK: Sections

    @ViewBuilder private func decision(_ item: Item) -> some View {
        ListHeader(title: "Decision").padding(.top, 40)
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { dispositionChoices(item) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 0) {
                    dispositionChoices(item)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Disposition")
            .accessibilityIdentifier("item.disposition")
            if item.disposition == .undecided {
                Text("Undecided. Pick one.").monoMeta()
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        detail("Decided by", item.dispositionSource == .user ? "You" : "Moove (auto)")
        if let reason = item.dispositionReason {
            Text(reason)
                .sansText(15)
                .lineSpacing(3)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled()
        }
        Toggle(isOn: Binding(
            get: { item.maybeSentimental },
            set: { v in Task { await store.setSentimental(v, for: item) } }
        )) {
            Text("Possibly sentimental").monoText(13.5).foregroundStyle(Theme.text)
        }
        .tint(Theme.accentFill)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .ruled()
    }

    /// Same behavior as the old menu picker: choosing the current value does nothing.
    @ViewBuilder private func dispositionChoices(_ item: Item) -> some View {
        ForEach(Disposition.choices, id: \.self) { d in
            ChoiceChip(title: d.label, selected: item.disposition == d) {
                guard item.disposition != d else { return }
                Task { await store.setDisposition(d, for: item) }
            }
        }
    }

    @ViewBuilder private func details(_ item: Item) -> some View {
        ListHeader(title: "Details").padding(.top, 40)
        detail("Estimated value", item.estValueCents?.usd ?? "Pricing…")
        detail("Category", item.category)
        if let material = item.material { detail("Material", material) }
        if let brand = item.brand { detail("Brand", brand) }
        if let condition = item.condition { detail("Condition", "\(condition) / 5") }
        detail("Size", dims(item))
        detail("Found by", foundBy(item))
        if item.fragile {
            Label("Fragile", systemImage: "exclamationmark.triangle")
                .monoText(13.5, weight: .bold)
                .foregroundStyle(Theme.danger)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .ruled()
        }
    }

    @ViewBuilder private func comps(_ item: Item) -> some View {
        let comps = store.snapshot.comps(for: item.id)
        if !comps.isEmpty {
            ListHeader(title: "Comparable listings", count: "\(comps.count)").padding(.top, 40)
            ForEach(comps) { comp in
                if let url = URL(string: comp.url) {
                    Link(destination: url) { compRow(comp, linked: true) }
                        .buttonStyle(.plain)
                } else {
                    compRow(comp, linked: false)
                }
            }
        }
    }

    private func compRow(_ comp: Comp, linked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(comp.title).blockTitle().lineLimit(2)
                Text(comp.source.uppercased()).monoMeta()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(comp.priceCents.usd).rowValue().layoutPriority(1)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .ruled()
        .accessibilityElement(children: .combine)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).monoText(13.5).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).rowValue()
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .ruled()
        .accessibilityElement(children: .combine)
    }

    private func dims(_ item: Item) -> String {
        if item.origin == .photo { return "Not measured" }
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(2))) }
        let size = "\(f(item.widthM)) × \(f(item.depthM)) × \(f(item.heightM)) m"
        return item.origin == .roomPhotos || item.origin == .manual ? "≈ \(size)" : size
    }

    private func foundBy(_ item: Item) -> String {
        switch item.origin {
        case .scan: "LiDAR scan"
        case .roomPhotos: "Room photos (size estimated)"
        case .photo: "Your photo"
        case .manual: "Added by you (typical size)"
        }
    }
}

#Preview {
    NavigationStack { ItemDetailView(itemId: 11) }.environment(MooveStore.preview())
}
