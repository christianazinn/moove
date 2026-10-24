import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// The room model's "look": warm image-based lighting, soft contact shadows
/// under furniture, and the selection pop. Every resource here is drawn at
/// runtime with CoreGraphics (no bundled images or HDRIs) and built once.
@available(iOS 18.0, *)
extension RoomScene {
    /// Builds the shared look resources. Await it before `make` so objects get
    /// contact shadows; cheap after the first call. Anything that fails is
    /// skipped and the scene falls back to the plain sun-only lighting.
    static func prepareLook() async {
        if !popRegistered {
            SelectionPopComponent.registerComponent()
            popRegistered = true
        }
        if shadowMaterial == nil, let image = contactShadowImage(size: 64),
           let texture = try? await TextureResource(image: image, withName: "moove.contactShadow", options: .init(semantic: .color)) {
            var shadow = UnlitMaterial()
            shadow.color = .init(tint: .white, texture: .init(texture))
            shadow.blending = .transparent(opacity: .init(floatLiteral: 1))
            shadow.writesDepth = false  // overlapping shadows blend instead of cutting each other
            shadowMaterial = shadow
        }
        if environment == nil, let image = environmentImage(width: 256, height: 128) {
            environment = try? await EnvironmentResource(equirectangular: image, withName: "moove.warmRoom")
        }
    }

    // MARK: Image-based light

    /// Lights `room` with the warm generated environment (if `prepareLook`
    /// built one) and dims the sun a little so the two don't blow out.
    static func addEnvironmentLight(to room: Entity) {
        guard let environment, room.findEntity(named: "environment") == nil else { return }
        let light = Entity()
        light.name = "environment"
        var ibl = ImageBasedLightComponent(source: .single(environment), intensityExponent: iblExponent)
        ibl.inheritsRotation = true  // the sky stays above the room's floor however the stage tilts it
        light.components.set(ibl)
        room.addChild(light)
        room.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        receiveLight(room, from: light)
        if let sun = room.findEntity(named: "sun") as? DirectionalLight {
            sun.light.intensity = sunIntensityWithIBL
        }
    }

    /// Receivers are set on the root and on every model already in the room;
    /// models attached later rely on the root's receiver.
    private static func receiveLight(_ entity: Entity, from light: Entity) {
        for child in entity.children where child !== light {
            if child.components.has(ModelComponent.self) {
                child.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
            receiveLight(child, from: light)
        }
    }

    /// Equirectangular gradient: warm pale sky, warm-white horizon, darker
    /// warm floor, plus a soft bright patch up high for a gentle highlight.
    private static func environmentImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))] = [
            (0.00, (0.96, 0.93, 0.88)),  // zenith
            (0.42, (1.00, 0.97, 0.92)),  // just above the horizon
            (0.50, (0.93, 0.87, 0.79)),  // horizon
            (0.62, (0.62, 0.53, 0.45)),
            (1.00, (0.40, 0.33, 0.27)),  // floor
        ]
        let colors = stops.map { CGColor(colorSpace: space, components: [$0.1.0, $0.1.1, $0.1.2, 1])! } as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: stops.map { $0.0 }) else { return nil }
        // Bitmap row 0 is the top of the image, which is y = height in CG coordinates.
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])

        let glow = [CGColor(colorSpace: space, components: [1, 0.99, 0.95, 0.9])!,
                    CGColor(colorSpace: space, components: [1, 0.99, 0.95, 0])!] as CFArray
        if let spot = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            let center = CGPoint(x: CGFloat(width) * 0.62, y: CGFloat(height) * 0.78)
            context.drawRadialGradient(spot, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: CGFloat(height) * 0.22, options: [])
        }
        return context.makeImage()
    }

    // MARK: Contact shadows

    /// A soft dark patch on the floor under an object of size `size`, centered
    /// in the object's container. Nil until `prepareLook` has run.
    static func contactShadow(for size: SIMD3<Float>) -> Entity? {
        guard let shadowMaterial else { return nil }
        // The texture is fully dark out to ~60% of its half-width and fades to
        // nothing at the edge, so the footprint sits inside the dark part.
        let width = size.x * 1.3 + 0.08, depth = size.z * 1.3 + 0.08
        let plane = ModelEntity(mesh: .generatePlane(width: width, depth: depth), materials: [shadowMaterial])
        plane.name = "shadow"
        plane.position = SIMD3(0, -size.y / 2 + 0.004, 0)  // just above the floor, no z-fighting
        return plane
    }

    /// Black with a soft rounded-rectangle alpha falloff (separable smoothstep).
    private static func contactShadowImage(size: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let maxAlpha: Float = 0.5
        func falloff(_ i: Int) -> Float {
            let u = abs((Float(i) + 0.5) / Float(size) * 2 - 1)  // 0 at center, 1 at edge
            let t = min(max((u - 0.6) / 0.4, 0), 1)
            return 1 - t * t * (3 - 2 * t)
        }
        for y in 0..<size {
            for x in 0..<size {
                // RGB stays 0 (black), so premultiplied alpha needs no extra care.
                pixels[(y * size + x) * 4 + 3] = UInt8(maxAlpha * falloff(x) * falloff(y) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Selection pop

    /// Scales an object's visible body up when selected (1.0 → 1.09 → 1.06) and
    /// back down when deselected, with a short overshoot. Safe to call on every
    /// update: it only animates when the selection actually changes, and a
    /// rapid toggle restarts from wherever the body currently is.
    static func setSelected(_ body: Entity, selected: Bool) {
        if !popRegistered {
            SelectionPopComponent.registerComponent()
            popRegistered = true
        }
        let previous = body.components[SelectionPopComponent.self]
        if previous?.selected == selected { return }
        let base = previous?.baseScale ?? body.scale
        body.components.set(SelectionPopComponent(selected: selected, baseScale: base))

        body.stopAllAnimations(recursive: false)
        let start = body.transform
        var end = start
        end.scale = base * (selected ? selectedScale : 1)
        body.transform = end  // the resting value, whether or not the animation runs or holds its end
        // First sight of an unselected body, or reduced motion: no animation.
        guard previous != nil || selected, !UIAccessibility.isReduceMotionEnabled else { return }

        var overshoot = end
        overshoot.scale = end.scale + (end.scale - start.scale) * 0.5
        let rise = FromToByAnimation<RealityKit.Transform>(from: start, to: overshoot, duration: 0.12, timing: .easeOut, bindTarget: .transform)
        let settle = FromToByAnimation<RealityKit.Transform>(from: overshoot, to: end, duration: 0.14, timing: .easeInOut, bindTarget: .transform)
        guard let a = try? AnimationResource.generate(with: rise),
              let b = try? AnimationResource.generate(with: settle),
              let pop = try? AnimationResource.sequence(with: [a, b]) else { return }
        body.playAnimation(pop, transitionDuration: 0, startsPaused: false)
    }

    // MARK: Cache and knobs

    private static var popRegistered = false
    private static var shadowMaterial: UnlitMaterial?
    private static var environment: EnvironmentResource?

    static let selectedScale: Float = 1.06

    /// IBL brightness as a power of two (0 = the image as drawn). MOOVE_IBL_EXPONENT overrides.
    static var iblExponent: Float {
        Float(ProcessInfo.processInfo.environment["MOOVE_IBL_EXPONENT"].flatMap(Double.init) ?? 0)
    }
    /// Sun intensity (lux) once the environment light is on. MOOVE_SUN_IBL overrides.
    static var sunIntensityWithIBL: Float {
        Float(ProcessInfo.processInfo.environment["MOOVE_SUN_IBL"].flatMap(Double.init) ?? 2100)
    }
}

/// Remembers a body's selection state and unscaled size so `setSelected`
/// animates only on changes and always returns to the same resting scale.
private struct SelectionPopComponent: Component {
    var selected: Bool
    var baseScale: SIMD3<Float>
}
