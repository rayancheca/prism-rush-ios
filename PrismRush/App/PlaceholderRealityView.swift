import SwiftUI
import RealityKit
import simd
import UIKit

/// A single spinning neon prism on a void-purple backdrop, driven by `TimelineView(.animation)`.
///
/// Intentionally throwaway: this exists only to prove the RealityKit `RealityView` surface
/// (virtual camera, `ModelEntity` primitives, `UnlitMaterial`) compiles and renders on the
/// simulator. Phase 3 replaces it with the real `RealityRenderer` driven by `SceneEvents.Update`.
struct PlaceholderRealityView: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            RealityView { content in
                // Virtual (non-AR) camera looking at the origin.
                let cam = PerspectiveCamera()
                cam.camera.fieldOfViewInDegrees = 50
                cam.position = SIMD3<Float>(0, 0.25, 3.4)
                cam.look(at: .zero, from: cam.position, relativeTo: nil)
                content.add(cam)

                // Void-purple backdrop plane (previews the "fog fake" technique for Phase 4).
                let backdrop = ModelEntity(
                    mesh: .generatePlane(width: 60, height: 60),
                    materials: [UnlitMaterial(color: UIColor(red: 7 / 255.0, green: 2 / 255.0, blue: 26 / 255.0, alpha: 1))]
                )
                backdrop.position = SIMD3<Float>(0, 0, -10)
                content.add(backdrop)

                // Neon magenta prism (the hero primitive).
                let prism = ModelEntity(
                    mesh: .generateBox(size: 1.0, cornerRadius: 0.08),
                    materials: [UnlitMaterial(color: UIColor(red: 1, green: 43 / 255.0, blue: 214 / 255.0, alpha: 1))]
                )
                prism.name = "prism"

                // Cyan core for a little depth.
                let core = ModelEntity(
                    mesh: .generateSphere(radius: 0.32),
                    materials: [UnlitMaterial(color: UIColor(red: 0, green: 245 / 255.0, blue: 1, alpha: 1))]
                )
                core.position = SIMD3<Float>(0, 0, 0.55)
                prism.addChild(core)

                content.add(prism)
            } update: { content in
                if let prism = content.entities.first(where: { $0.name == "prism" }) {
                    prism.orientation = simd_quatf(
                        angle: Float(t) * 0.9,
                        axis: normalize(SIMD3<Float>(0.25, 1, 0.12))
                    )
                }
            }
        }
    }
}
