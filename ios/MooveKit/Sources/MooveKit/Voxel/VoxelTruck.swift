import Foundation

/// A cozy voxel box truck for the Pack screen's 3D view: sage cab with a windshield,
/// headlights and a grille, cream cargo box on a dark chassis, four wheels, and a stepped
/// loading ramp out the back. The cargo box is a dollhouse: no roof and no near (+z) side
/// wall, and the roll-up door is rolled up, so everything inside shows.
///
/// Grid axes (mesh it with `centered: false`): x runs from the ramp (back, -x) to the cab
/// (front, +x), y up, z across with the far wall at z = 0 and the open side toward +z.
/// The cargo floor's inside matches `TruckSize.cargoM`.
public enum VoxelTruck {
    public enum Palette {
        public static let body: VoxelColor = 0xF2ECE0
        public static let bodyShade: VoxelColor = 0xE2D9C8
        public static let inner: VoxelColor = 0xE9E1D2
        public static let rail: VoxelColor = 0xC9A877
        public static let deck: VoxelColor = 0xB98D5E
        public static let deckSeam: VoxelColor = 0xA67C50
        public static let cab: VoxelColor = 0x8B9A7B
        public static let cabShade: VoxelColor = 0x74846A
        public static let stripe: VoxelColor = 0x5E6D50
        public static let chassis: VoxelColor = 0x3A3835
        public static let tire: VoxelColor = 0x2A2826
        public static let hub: VoxelColor = 0xB9BCBF
        public static let ramp: VoxelColor = 0x9AA0A6
        public static let rampEdge: VoxelColor = 0x7E848A
        public static let door: VoxelColor = 0xD7CFC0
        public static let headlight: VoxelColor = 0xFFF3C4
        public static let taillight: VoxelColor = 0xC23B2E
    }

    /// Where the cargo space sits in the grid, in voxels.
    public struct Frame: Sendable, Hashable {
        /// Inside of the back opening (cargo x = length) and the cab wall's inner face (cargo x = 0).
        public var doorX: Int
        public var cabWallX: Int
        /// Top of the cargo floor.
        public var floorY: Int
        /// Inner face of the far wall (cargo z = 0).
        public var farZ: Int
        public var length: Int
        public var width: Int
        public var height: Int
        public var nx: Int
        public var ny: Int
        public var nz: Int
    }

    public static func frame(_ size: TruckSize) -> Frame {
        let c = size.cargoM
        let L = VoxelGrid.count(c.length), W = VoxelGrid.count(c.width), H = VoxelGrid.count(c.height)
        let van = size == .cargoVan
        let ramp = van ? 0 : 16
        let floorY = van ? 9 : 13
        let cab = van ? 26 : 34
        // ramp | door post 1 | cargo L | cab wall 1 | cab
        let doorX = ramp + 1
        let cabWallX = doorX + L
        let nx = cabWallX + 1 + cab
        let ny = floorY + H + 2
        let nz = W + 2
        return Frame(doorX: doorX, cabWallX: cabWallX, floorY: floorY, farZ: 1, length: L, width: W, height: H,
                     nx: nx, ny: ny, nz: nz)
    }

    /// Center of a placement's bounding box in the truck grid's meters (uncentered mesh).
    /// Cargo x = 0 is the cab wall, so cargo x grows toward -x in the grid.
    public static func center(of p: TruckPlacement, in size: TruckSize) -> (x: Double, y: Double, z: Double) {
        let f = frame(size), s = VoxelGrid.voxelSize
        let c = p.center
        return (Double(f.cabWallX) * s - c.x, Double(f.floorY) * s + c.y, Double(f.farZ) * s + c.z)
    }

    /// Center of the cargo space, grid meters: where the camera looks.
    public static func cargoCenter(_ size: TruckSize) -> (x: Double, y: Double, z: Double) {
        let f = frame(size), s = VoxelGrid.voxelSize
        return (Double(f.doorX + f.cabWallX) / 2 * s, Double(f.floorY) * s + Double(f.height) * s / 3,
                Double(f.farZ) * s + Double(f.width) * s / 2)
    }

    public static func build(_ size: TruckSize) -> VoxelGrid {
        let f = frame(size)
        var g = VoxelGrid(nx: f.nx, ny: f.ny, nz: f.nz)
        let P = Palette.self
        let van = size == .cargoVan
        let top = f.floorY + f.height // first layer above the cargo space
        let zNear = f.farZ + f.width // first z past the cargo floor (where the near wall would be)

        // Chassis rails under the cargo box and cab.
        let chassisY = max(3, f.floorY - 6)
        g.fill(x: f.doorX...(f.nx - 3), y: chassisY...(f.floorY - 3), z: 3...(f.nz - 4), P.chassis)
        // Cargo floor: plywood deck with seams every 0.6 m, a dark sill all round.
        g.fill(x: f.doorX...(f.cabWallX - 1), y: (f.floorY - 2)...(f.floorY - 1), z: 0...zNear, P.deck)
        for x in stride(from: f.doorX + 12, to: f.cabWallX, by: 12) {
            g.fill(x: x...x, y: (f.floorY - 1)...(f.floorY - 1), z: f.farZ...(zNear - 1), P.deckSeam)
        }
        g.fill(x: f.doorX...(f.cabWallX - 1), y: (f.floorY - 2)...(f.floorY - 2), z: zNear...zNear, P.stripe)
        // Far wall: cream outside, tie-down rails inside every 0.5 m, a sage stripe on top.
        g.fill(x: (f.doorX - 1)...f.cabWallX, y: f.floorY...top, z: 0...0, P.inner)
        for y in stride(from: f.floorY + 8, to: top - 1, by: 10) {
            g.fill(x: f.doorX...(f.cabWallX - 1), y: y...y, z: 0...0, P.rail)
        }
        g.fill(x: (f.doorX - 1)...f.cabWallX, y: top...(top + 1), z: 0...0, P.stripe)
        // Cab wall: full height and width, with a top beam back to the far wall.
        g.fill(x: f.cabWallX...f.cabWallX, y: f.floorY...top, z: 0...zNear, P.body)
        g.fill(x: f.cabWallX...f.cabWallX, y: top...(top + 1), z: 0...zNear, P.stripe)
        // Door end: two posts, a header with the rolled-up door, tail lights low on the posts.
        let doorPost = f.doorX - 1
        for z in [0, zNear] {
            g.fill(x: doorPost...doorPost, y: (f.floorY - 2)...top, z: z...z, P.bodyShade)
            g.fill(x: doorPost...doorPost, y: f.floorY...(f.floorY + 1), z: z...z, P.taillight)
        }
        g.fill(x: doorPost...doorPost, y: (top - 2)...(top + 1), z: 0...zNear, P.door)
        g.fill(x: doorPost...doorPost, y: (top - 2)...(top - 2), z: 1...(zNear - 1), P.bodyShade)
        // Near corner post at the cab wall, so the box reads as a box with its side cut away.
        g.fill(x: (f.cabWallX - 1)...f.cabWallX, y: f.floorY...top, z: zNear...zNear, P.body)

        // Cab: sage, lower than the box, a hood at the front.
        let cabX0 = f.cabWallX + 1, cabX1 = f.nx - 1
        let cabTop = van ? top - 1 : f.floorY + Int(Double(f.height) * 0.7)
        let hoodX = cabX1 - (van ? 8 : 10)
        let hoodTop = f.floorY + (van ? 5 : 7)
        let cabBottom = chassisY
        g.fill(x: cabX0...hoodX, y: cabBottom...cabTop, z: 0...(f.nz - 1), P.cab)
        g.fill(x: (hoodX + 1)...cabX1, y: cabBottom...hoodTop, z: 0...(f.nz - 1), P.cab)
        g.fill(x: cabX0...hoodX, y: cabTop...cabTop, z: 0...(f.nz - 1), P.cabShade) // roof
        // Windshield (front of the cabin) and side windows.
        let winY0 = hoodTop + 2, winY1 = cabTop - 2
        if winY1 >= winY0 {
            g.fill(x: hoodX...hoodX, y: winY0...winY1, z: 2...(f.nz - 3), VoxelHouse.Palette.glass)
            for z in [0, f.nz - 1] {
                g.fill(x: (hoodX - 9)...(hoodX - 2), y: winY0...winY1, z: z...z, VoxelHouse.Palette.glass)
            }
        }
        // Door seams and a stripe along the cab sides.
        for z in [0, f.nz - 1] {
            g.fill(x: (hoodX - 11)...(hoodX - 11), y: (cabBottom + 2)...(cabTop - 1), z: z...z, P.cabShade)
            g.fill(x: cabX0...cabX1, y: (hoodTop - 1)...(hoodTop - 1), z: z...z, P.stripe)
        }
        // Grille, headlights and bumper on the nose.
        g.fill(x: cabX1...cabX1, y: (cabBottom + 3)...(hoodTop - 1), z: 4...(f.nz - 5), P.chassis)
        for z in [1, f.nz - 4] { g.fill(x: cabX1...cabX1, y: (hoodTop - 3)...(hoodTop - 1), z: z...(z + 2), P.headlight) }
        g.fill(x: cabX1...cabX1, y: cabBottom...(cabBottom + 1), z: 0...(f.nz - 1), P.hub)
        // Over-cab storage on the bigger trucks: the box runs on over the cab roof.
        if !van, size != .ft10 {
            let attic = 14
            g.fill(x: cabX0...min(cabX1, cabX0 + attic), y: (cabTop + 1)...top, z: 0...(f.nz - 1), P.body)
            g.fill(x: cabX0...min(cabX1, cabX0 + attic), y: top...(top + 1), z: 0...(f.nz - 1), P.stripe)
            g.fill(x: min(cabX1, cabX0 + attic)...min(cabX1, cabX0 + attic), y: (cabTop + 1)...top, z: 0...(f.nz - 1), P.bodyShade)
        }

        // Wheels: discs on both sides, rear under the box, front under the cab.
        let r = van ? 5 : 7
        let rearX = f.doorX + max(r + 2, f.length / 4)
        let frontX = cabX0 + (cabX1 - cabX0) / 2 + 2
        for wx in [rearX, frontX] {
            for (z0, z1) in [(0, 2), (f.nz - 3, f.nz - 1)] {
                for dy in -r...r {
                    for dx in -r...r where dx * dx + dy * dy <= r * r {
                        let hub = dx * dx + dy * dy <= (r / 2) * (r / 2)
                        // Behind the body (the wheel well): only empty cells.
                        for z in z0...z1 where g[wx + dx, r + dy, z] == nil { g[wx + dx, r + dy, z] = hub ? P.hub : P.tire }
                    }
                }
            }
        }

        // Loading ramp: steps from the deck down to the ground behind the door.
        if f.doorX > 2 {
            let steps = f.doorX - 1
            for x in 0..<steps {
                let h = max(0, (f.floorY - 1) * (x + 1) / steps)
                let z0 = f.farZ + f.width / 2 - 8, z1 = f.farZ + f.width / 2 + 7
                g.fill(x: x...x, y: 0...h, z: z0...z1, x % 2 == 0 ? P.ramp : P.rampEdge)
            }
        }
        return g
    }
}

/// Moving boxes for the truck view: kraft cardboard (or a grey tote) at the box's real size,
/// packing tape over the flap seam and down both ends, a band of the destination room's tape
/// color (`PackingPalette`) around the sides, and a red FRAGILE label on fragile boxes.
public enum VoxelMovingBox {
    public static let kraft: VoxelColor = 0xC9A06A
    public static let kraftShade: VoxelColor = 0xB38D5B
    public static let tape: VoxelColor = 0xE6D7B5
    public static let tote: VoxelColor = 0xA3AFB8
    public static let toteLid: VoxelColor = 0x8E9BA5
    public static let fragileRed: VoxelColor = 0xB0412E
    public static let label: VoxelColor = 0xF4F1EA

    /// Width along x, depth along z, height up: the box's `dimsM`.
    public static func build(_ size: BoxSize, room: String, fragile: Bool = false) -> VoxelGrid {
        let d = size.dimsM
        let X = VoxelGrid.count(d.w), Y = VoxelGrid.count(d.h), Z = VoxelGrid.count(d.d)
        var g = VoxelGrid(nx: X, ny: Y, nz: Z)
        let roomColor = PackingPalette.color(forRoom: room)
        if size == .tote {
            g.fill(x: 0...(X - 1), y: 0...(Y - 1), z: 0...(Z - 1), tote)
            g.fill(x: 0...(X - 1), y: (Y - 1)...(Y - 1), z: 0...(Z - 1), roomColor) // lid in the room's color
            if Y >= 4 { g.fill(x: 0...(X - 1), y: (Y - 2)...(Y - 2), z: 0...(Z - 1), toteLid) }
            return g
        }
        g.fill(x: 0...(X - 1), y: 0...(Y - 1), z: 0...(Z - 1), kraft)
        // Darker kraft on the two short ends, so the box reads in flat light.
        g.fill(x: 0...0, y: 0...(Y - 1), z: 0...(Z - 1), kraftShade)
        g.fill(x: (X - 1)...(X - 1), y: 0...(Y - 1), z: 0...(Z - 1), kraftShade)
        // Room band around the sides, a third of the way down.
        if Y >= 4 {
            let by = Y - 1 - max(1, Y / 3)
            g.fill(x: 0...(X - 1), y: by...by, z: 0...(Z - 1), roomColor)
        }
        // Tape along the flap seam (along x at the middle of z) and down both ends.
        let tz0 = max(0, Z / 2 - (Z >= 6 ? 1 : 0)), tz1 = min(Z - 1, Z / 2)
        g.fill(x: 0...(X - 1), y: (Y - 1)...(Y - 1), z: tz0...tz1, tape)
        let down = max(1, Y / 4)
        for x in [0, X - 1] { g.fill(x: x...x, y: (Y - 1 - down)...(Y - 1), z: tz0...tz1, tape) }
        // Shipping label on the front (+z); red on fragile boxes.
        if X >= 4 && Y >= 4 {
            let lx = X / 2 - 1, ly = max(1, Y / 3 - 1)
            g.fill(x: lx...(lx + 2), y: ly...(ly + 1), z: (Z - 1)...(Z - 1), fragile ? fragileRed : label)
        }
        return g
    }
}
