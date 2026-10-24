import MooveKit
import PhotosUI
import SwiftUI
import UIKit

/// "Import from a listing" (#89): paste a listing link (or type an address and facts), optionally
/// attach floor-plan screenshots, and get a floor plan. The address is read from the link itself,
/// never by fetching the page. The worker turns screenshots into rooms with Claude; when it is
/// unreachable or finds no plan, a plan is estimated locally from beds / baths / sqft.
struct ListingImportView: View {
    var onUse: (_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) -> Void

    @State private var linkText = ""
    @State private var address = ""
    /// The address last copied in from the link, so typing over it isn't clobbered.
    @State private var prefilledAddress = ""
    @State private var beds = 2
    @State private var baths = 1.0
    @State private var sqftText = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var shots: [Screenshot] = []
    @State private var loadingShots = false
    @State private var useScraper = false
    @State private var phase: Phase = .idle
    @State private var errorText: String?
    @State private var result: ImportResult?
    @State private var clipboardHasLink = false

    private let client = ListingImportClient()
    private static let maxShots = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "08 — New home",
                    title: "Import a listing",
                    lede: "Paste a Zillow, Redfin or Realtor.com link. Moove reads the address from the link without opening the page."
                )
                .padding(.top, 16)
                .padding(.bottom, 32)

                linkSection
                factsSection.padding(.top, 36)
                screenshotsSection.padding(.top, 36)
                scraperSection.padding(.top, 36)
                buildSection.padding(.top, 32)
                if let result {
                    resultSection(result).padding(.top, 40)
                }
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Import a listing")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .onAppear(perform: refreshClipboard)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshClipboard()
        }
        .onChange(of: linkText) { _, _ in prefillAddress() }
        .onChange(of: link?.isZillow ?? false) { _, isZillow in if !isZillow { useScraper = false } }
        .onChange(of: pickerItems) { _, items in loadShots(items) }
    }

    // MARK: Sections

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ListHeader(title: "Listing link") {
                if clipboardHasLink {
                    Button("Paste", systemImage: "doc.on.clipboard", action: paste)
                        .buttonStyle(.pill(.outline, compact: true))
                }
            }
            ThemedField(placeholder: "https://www.zillow.com/homedetails/…", text: $linkText)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !trimmedLink.isEmpty {
                if let link {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        MonoTag(text: link.siteName ?? "Listing", tone: Theme.accentStrong)
                        Text(link.address ?? "No address in this link — type it below")
                            .monoMeta()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Not a listing link Moove knows. Type the address below.")
                        .monoMeta()
                }
            }
        }
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "The home")
            VStack(alignment: .leading, spacing: 8) {
                Text("Address").monoText(12.5).foregroundStyle(Theme.muted)
                ThemedField(placeholder: "123 Main St, Berkeley, CA", text: $address)
                    .textContentType(.fullStreetAddress)
            }
            .padding(.vertical, 16)
            .ruled()

            Stepper(value: $beds, in: 0...6) {
                factLabel("Beds", beds == 0 ? "Studio" : "\(beds)")
            }
            .padding(.vertical, 12)
            .ruled()

            Stepper(value: $baths, in: 1...4, step: 0.5) {
                factLabel("Baths", baths.formatted(.number.precision(.fractionLength(0...1))))
            }
            .padding(.vertical, 12)
            .ruled()

            HStack(spacing: 16) {
                Text("Square feet").blockTitle()
                Spacer(minLength: 8)
                TextField(sqftPlaceholder, text: $sqftText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monoText(14.5)
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Square feet, optional")
            }
            .padding(.vertical, 16)
            .frame(minHeight: 44)
            .ruled()
        }
    }

    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ListHeader(title: "Floor plan screenshots", count: shots.isEmpty ? nil : "\(shots.count)/\(Self.maxShots)") {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: Self.maxShots, matching: .images) {
                    Label(shots.isEmpty ? "Add" : "Change", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.pill(.outline, compact: true))
            }
            Text("Optional. Moove reads room sizes from them with Claude.")
                .sansText(14)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if loadingShots {
                ProgressView().padding(.vertical, 8)
            } else if !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shots) { shot in
                            Image(uiImage: shot.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1))
                                .accessibilityLabel("Floor plan screenshot")
                        }
                    }
                }
            }
        }
    }

    private var scraperSection: some View {
        let zillow = link?.isZillow ?? false
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $useScraper) {
                Text("Fetch listing details with Apify (Zillow scraper)")
                    .blockTitle()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!zillow)
            Text(zillow ? "Scrapes the listing page; use only for the demo." : "Scrapes the listing page; use only for the demo. Zillow links only.")
                .monoMeta()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .ruled(.top)
        .ruled()
    }

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await build() }
            } label: {
                HStack(spacing: 8) {
                    if phase.isBusy { ProgressView().tint(Theme.accentInk) }
                    Text(phase.isBusy ? phase.label : "Build floor plan")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .disabled(phase.isBusy || loadingShots)

            if let errorText {
                Text(errorText)
                    .sansText(14)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resultSection(_ result: ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeader(title: "Floor plan") {
                HStack(spacing: 6) {
                    MonoTag(text: result.method.label, tone: result.method.tone)
                    if result.simulated { MonoTag(text: "Simulated", tone: Theme.ochreInk) }
                }
            }
            FloorPlanSketch(plan: result.plan)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                .accessibilityLabel("Floor plan sketch, \(result.plan.rooms.count) rooms")
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name).blockTitle().fixedSize(horizontal: false, vertical: true)
                if let address = result.address, address != result.name {
                    Text(address).sansText(14).foregroundStyle(Theme.muted)
                }
                Text(Self.meta(result.plan)).monoMeta()
            }
            .accessibilityElement(children: .combine)
            if !result.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("·").monoText(12.5).foregroundStyle(Theme.faint).accessibilityHidden(true)
                            Text(note).sansText(14).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Button("Use this home") { onUse(result.name, result.source, result.plan) }
                .buttonStyle(.pill)
                .padding(.top, 6)
        }
    }

    private func factLabel(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).blockTitle()
            Spacer(minLength: 8)
            Text(value).rowValue()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Derived

    private var trimmedLink: String { linkText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var link: ParsedLink? {
        guard !trimmedLink.isEmpty, let parsed = ListingLink.parse(trimmedLink) else { return nil }
        return ParsedLink(parsed)
    }

    private var sqft: Double? {
        let digits = sqftText.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value > 0 else { return nil }
        return value
    }

    private var sqftPlaceholder: String {
        "~\(Int(EstimatedFloorPlan.defaultSqft(beds: beds, baths: baths)))"
    }

    private var trimmedAddress: String? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? nil : a
    }

    private static func meta(_ plan: FloorPlan) -> String {
        let n = plan.rooms.count
        let area = Int(plan.totalAreaM2.rounded())
        return "\(n) room\(n == 1 ? "" : "s") · \(area) m²"
    }

    // MARK: Actions

    private func refreshClipboard() {
        let board = UIPasteboard.general
        clipboardHasLink = board.hasURLs || board.hasStrings
    }

    private func paste() {
        let board = UIPasteboard.general
        if let url = board.url {
            linkText = url.absoluteString
        } else if let string = board.string {
            linkText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func prefillAddress() {
        guard let found = link?.address else { return }
        if trimmedAddress == nil || address == prefilledAddress {
            address = found
            prefilledAddress = found
        }
    }

    private func loadShots(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { shots = []; return }
        loadingShots = true
        Task {
            var loaded: [Screenshot] = []
            var failed = 0
            for item in items.prefix(Self.maxShots) {
                if let data = try? await item.loadTransferable(type: Data.self), let shot = Screenshot(data: data) {
                    loaded.append(shot)
                } else {
                    failed += 1
                }
            }
            shots = loaded
            loadingShots = false
            if failed > 0 { errorText = "Couldn't read \(failed) of the screenshots." }
        }
    }

    private func build() async {
        errorText = nil
        var problems: [String] = []
        var response: ListingImportClient.Response?

        if client.isConfigured {
            var imageURLs: [String] = []
            for (i, shot) in shots.enumerated() {
                phase = .uploading(i + 1, shots.count)
                do {
                    imageURLs.append(try await client.upload(imageData: shot.jpeg, contentType: "image/jpeg").absoluteString)
                } catch {
                    problems.append("Couldn't upload a screenshot: \(error.localizedDescription)")
                    break
                }
            }
            phase = .importing
            let request = ListingImportClient.Request(
                url: link != nil ? trimmedLink : nil,
                address: trimmedAddress,
                beds: beds,
                baths: baths,
                sqft: sqft,
                floorPlanImageUrls: imageURLs.isEmpty ? nil : imageURLs,
                useScraper: useScraper && (link?.isZillow ?? false) ? true : nil
            )
            do {
                response = try await client.importHome(request)
            } catch {
                problems.append("Couldn't reach Moove's worker (\(error.localizedDescription)). Built an estimate instead.")
            }
        }

        let estimateNote = client.isConfigured ? nil : "Offline: estimated from beds, baths and size."
        let resolved = resolve(response, extraNote: estimateNote)
        withAnimation { result = resolved }
        errorText = problems.isEmpty ? nil : problems.joined(separator: "\n")
        phase = .idle
    }

    /// The worker's plan when it found one, otherwise a local estimate from the best facts we have.
    private func resolve(_ response: ListingImportClient.Response?, extraNote: String?) -> ImportResult {
        let address = response?.address ?? trimmedAddress ?? link?.address
        let name = response?.name.nilIfBlank ?? address.map(Self.shortName) ?? "New home"
        var notes = response?.notes ?? []
        if let extraNote { notes.append(extraNote) }
        let source: NewHomeSource = link != nil ? .zillow : .manual

        if let response, let plan = response.floorPlan, !plan.rooms.isEmpty {
            let method: ImportResult.Method = switch response.method {
            case .floorplan: .floorPlan
            case .scraper: .scraper
            case .facts: .estimated
            }
            return ImportResult(name: name, address: address, plan: plan, method: method, notes: notes,
                                simulated: response.simulated, source: source)
        }
        let plan = EstimatedFloorPlan.build(
            beds: response?.beds ?? beds,
            baths: response?.baths ?? baths,
            sqft: response?.sqft ?? sqft
        )
        return ImportResult(name: name, address: address, plan: plan, method: .estimated, notes: notes,
                            simulated: response?.simulated ?? false, source: source)
    }

    /// "123 Main St, Berkeley, CA 94704" -> "123 Main St".
    private static func shortName(_ address: String) -> String {
        address.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? address
    }
}

// MARK: Model

private enum Phase: Equatable {
    case idle
    case uploading(Int, Int)
    case importing

    var isBusy: Bool { self != .idle }

    var label: String {
        switch self {
        case .idle: "Build floor plan"
        case let .uploading(i, n): "Uploading \(i) of \(n)…"
        case .importing: "Reading the listing…"
        }
    }
}

private struct ImportResult {
    enum Method {
        case floorPlan, estimated, scraper

        var label: String {
            switch self {
            case .floorPlan: "From floor plan"
            case .estimated: "Estimated"
            case .scraper: "Apify scrape"
            }
        }

        var tone: Color {
            switch self {
            case .floorPlan: Theme.accentStrong
            case .estimated: Theme.ochreInk
            case .scraper: Theme.muted
            }
        }
    }

    var name: String
    var address: String?
    var plan: FloorPlan
    var method: Method
    var notes: [String]
    var simulated: Bool
    var source: NewHomeSource
}

/// A picked screenshot, re-encoded as JPEG (the worker accepts it everywhere) and capped in size.
private struct Screenshot: Identifiable {
    let id = UUID()
    let jpeg: Data
    let thumbnail: UIImage

    @MainActor init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 2048
        let side = max(image.size.width, image.size.height)
        let scaled: UIImage
        if side > maxSide {
            let k = maxSide / side
            let size = CGSize(width: image.size.width * k, height: image.size.height * k)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            scaled = image
        }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        self.jpeg = jpeg
        self.thumbnail = scaled
    }
}

/// What the view shows for a parsed `ListingLink`.
private struct ParsedLink {
    var siteName: String?
    var address: String?
    var isZillow: Bool

    init(_ link: ListingLink) {
        let names = ["zillow": "Zillow", "redfin": "Redfin", "realtor": "Realtor.com",
                     "apartments": "Apartments.com", "streeteasy": "StreetEasy"]
        siteName = names[link.site] ?? (link.site == "other" ? nil : link.site)
        address = link.address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        isZillow = link.site == "zillow"
    }
}

// MARK: Pieces

/// A single-line field on the theme's surface.
private struct ThemedField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .monoText(14)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1))
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

#Preview {
    NavigationStack {
        ListingImportView { _, _, _ in }
    }
}
