import SwiftUI
import UniformTypeIdentifiers
import MooveKit

/// What a room shot shows; a new layout (style switch, re-solve) or new items make a new key, so
/// shots are cached per layout and retaken only for rooms that changed.
struct RoomShotKey: Hashable {
    var room: String
    var plan: FloorPlan?
    var placements: [Placement]
    var items: [LayoutItem]

    init(room: String, plan: FloorPlan, placements: [Placement], items: [LayoutItem]) {
        self.room = room
        self.plan = plan.isolating(room)
        self.placements = RoomShot.placements(placements, in: room)
        let ids = Set(self.placements.map(\.itemId))
        self.items = items.filter { ids.contains($0.id) }
    }
}

/// A room shot as a PNG for the share sheet (Save Image, AirDrop, Messages).
struct RoomPhoto: Transferable, Sendable {
    var image: UIImage
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { photo in photo.image.pngData() ?? Data() }
            .suggestedFileName("Moove room.png")
    }
}

/// New Home's "Room shots": each furnished room on its own, framed like an interior photo.
/// Cards render one room at a time (a single offscreen-sized ARView, snapshotted after the main
/// stage's fly-in), so the gallery is plain images; tap one for the full-screen viewer.
struct RoomShotsSection: View {
    var homeName: String
    var plan: FloorPlan
    var items: [LayoutItem]
    var placements: [Placement]
    /// True once the main stage's fly-in has started; shots wait for it to finish.
    var ready: Bool

    @State private var shots: [RoomShotKey: UIImage] = [:]
    @State private var failed: Set<RoomShotKey> = []
    @State private var started = false
    @State private var viewing: ViewedRoom?

    struct ViewedRoom: Identifiable { var name: String; var id: String { name } }

    static let cardSize = CGSize(width: 264, height: 198)

    private var rooms: [FloorPlanRoom] {
        plan.rooms.filter { room in room.kind != .hallway && placements.contains { $0.room == room.name } }
    }

    private func key(_ room: String) -> RoomShotKey {
        RoomShotKey(room: room, plan: plan, placements: placements, items: items)
    }

    /// The next room to render, one at a time.
    private var capturing: String? {
        guard started else { return nil }
        return rooms.first { shots[key($0.name)] == nil && !failed.contains(key($0.name)) }?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Room shots", count: "\(rooms.count)")
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rooms) { card($0) }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 16)
        }
        .task(id: ready) {
            guard ready else { started = false; return }
            // Let the main stage's fly-in play first.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            started = true
        }
        .task(id: capturing.map(key)) {
            // A snapshot that never comes back (no GPU, backgrounded) doesn't hold up the rest.
            guard let room = capturing else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            let k = key(room)
            if shots[k] == nil { failed.insert(k) }
        }
        .fullScreenCover(item: $viewing) { room in
            RoomShotViewer(homeName: homeName, plan: plan, items: items, placements: placements,
                           rooms: rooms.map(\.name), shots: $shots, selection: room.name)
        }
    }

    private func card(_ room: FloorPlanRoom) -> some View {
        let k = key(room.name)
        let count = k.placements.count
        let pieces = "\(count) piece\(count == 1 ? "" : "s")"
        let size = Self.cardSize
        return Button { viewing = ViewedRoom(name: room.name) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Color(uiColor: FloorPlan3DView.sceneBackground)
                    if let image = shots[k] {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if capturing == room.name {
                        // Rendered at twice the card size for a sharper photo, shown scaled down.
                        FloorPlan3DView(plan: plan, items: items, placements: placements, interactive: false,
                                        isolatedRoom: room.name, onSnapshot: { shots[k] = $0 })
                            .frame(width: size.width * 2, height: size.height * 2)
                            .scaleEffect(0.5)
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                    } else if failed.contains(k) {
                        Image(systemName: "cube.transparent").font(.title2).foregroundStyle(Theme.muted)
                    } else {
                        ProgressView().tint(Theme.muted)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name).blockTitle().lineLimit(1)
                    Text(pieces).monoMeta()
                }
            }
            .frame(width: size.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel("\(room.name), \(pieces), photo")
        .accessibilityHint("Opens the room shot to share or save")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("newhome.roomShot.\(room.name)")
    }
}

/// Full-screen room shots: swipe between rooms, Orbit to look around (Use this angle retakes the
/// photo from there), Share to save to Photos or AirDrop.
struct RoomShotViewer: View {
    var homeName: String
    var plan: FloorPlan
    var items: [LayoutItem]
    var placements: [Placement]
    var rooms: [String]
    @Binding var shots: [RoomShotKey: UIImage]
    @State var selection: String
    @State private var orbiting = false
    @State private var angleToken = 0
    @State private var awaitingAngle = false
    @Environment(\.dismiss) private var dismiss

    private func key(_ room: String) -> RoomShotKey {
        RoomShotKey(room: room, plan: plan, placements: placements, items: items)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selection).blockTitle().lineLimit(1).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .buttonStyle(.pill(.text, compact: true))
                    .accessibilityIdentifier("newhome.roomShot.done")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)

            TabView(selection: $selection) {
                ForEach(rooms, id: \.self) { room in
                    page(room).tag(room)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: rooms.count > 1 ? .always : .never))
            .onChange(of: selection) { orbiting = false; awaitingAngle = false }

            controls
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
        }
        .background(Color(uiColor: FloorPlan3DView.sceneBackground).ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .tint(Theme.accentStrong)
    }

    @ViewBuilder
    private func page(_ room: String) -> some View {
        let k = key(room)
        if room == selection, orbiting || shots[k] == nil {
            FloorPlan3DView(plan: plan, items: items, placements: placements, interactive: orbiting,
                            isolatedRoom: room, onSnapshot: { image in
                                shots[k] = image
                                if awaitingAngle { awaitingAngle = false; orbiting = false }
                            }, snapshotToken: angleToken)
                .accessibilityElement()
                .accessibilityLabel("3D view of \(room)")
                .accessibilityHint(orbiting ? "Drag to orbit, pinch to zoom, double-tap to reset" : "")
        } else if let image = shots[k] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("\(room), photo")
        } else {
            Image(systemName: "cube.transparent").font(.largeTitle).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                awaitingAngle = false
                orbiting.toggle()
            } label: {
                Label(orbiting ? "Cancel" : "Orbit", systemImage: orbiting ? "xmark" : "rotate.3d")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityLabel(orbiting ? "Stop orbiting" : "Orbit \(selection) in 3D")
            if orbiting {
                Button("Use this angle") {
                    awaitingAngle = true
                    angleToken += 1
                }
                .buttonStyle(.pill(.outline, compact: true))
                .disabled(awaitingAngle)
                .accessibilityHint("Retakes the photo from this view")
            }
            Spacer(minLength: 0)
            if let image = shots[key(selection)] {
                let name = "\(selection) · \(homeName)"
                ShareLink(item: RoomPhoto(image: image, name: selection),
                          preview: SharePreview(name, image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.pill(.primary, compact: true))
                .accessibilityLabel("Share or save \(selection) photo")
                .accessibilityIdentifier("newhome.roomShot.share")
            }
        }
    }
}
