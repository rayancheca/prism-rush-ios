import Foundation

/// The single seam between `Core/` and any renderer.
///
/// The renderer never owns or mutates game state; the core never imports a renderer.
/// Concrete renderers (RealityKit today, SceneKit as Plan B) implement this protocol so the
/// game loop can drive either one identically.
@MainActor
protocol RendererPort: AnyObject {
    /// Push the latest immutable world snapshot. Called once per rendered frame.
    func sync(_ snapshot: GameSnapshot)

    /// React to a one-shot gameplay effect (burst, world banner, death shatter, …).
    func fire(_ event: FXEvent)
}
