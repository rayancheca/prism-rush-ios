import SwiftUI
import RealityKit

/// Owns the engine, the renderer, and the per-frame loop. The loop is driven by RealityKit's
/// `SceneEvents.Update` (per the directive): advance the fixed-timestep core by wall-clock dt,
/// then push the snapshot to the renderer. `PR_AUTOPLAY` / `PR_DEMO` reuse the proven Autopilot so
/// gameplay can be screenshotted deterministically on the simulator without manual gestures.
@MainActor
@Observable
final class GameModel {
    let core = GameCore()
    @ObservationIgnored let renderer = RealityRenderer()
    @ObservationIgnored private var sub: EventSubscription?
    @ObservationIgnored private var overTime: Double = 0
    @ObservationIgnored private var demoElapsed: Double = 0
    @ObservationIgnored private var demoDied = false

    @ObservationIgnored private let autoplay = ProcessInfo.processInfo.environment["PR_AUTOPLAY"] == "1"
    @ObservationIgnored private let demo = ProcessInfo.processInfo.environment["PR_DEMO"] == "1"

    /// Restart is allowed a short beat after death (avoids the death tap instantly restarting).
    var canRestart: Bool { overTime > 0.5 }

    func install(_ content: RealityViewCameraContent) {
        renderer.install(into: content)
        core.onFX = { [weak renderer] fx in renderer?.fire(fx) }
        if autoplay || demo { core.startRun(seed: 7) }

        sub = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dt = event.deltaTime

                if (self.autoplay || self.demo), self.core.mode == .play {
                    Autopilot.drive(self.core)
                }
                if self.demo, self.core.mode == .play {
                    self.demoElapsed += dt
                    if self.demoElapsed > 6, !self.demoDied { self.demoDied = true; self.core.debugForceDie() }
                }
                if self.autoplay, self.core.mode == .over {
                    self.core.startRun(seed: 7)
                    self.renderer.resetEntities()
                }

                self.core.advance(realDt: dt)
                self.renderer.sync(self.core.snapshot)
                self.overTime = self.core.mode == .over ? self.overTime + dt : 0
            }
        }
    }

    func startRun() {
        core.startRun()
        renderer.resetEntities()
        overTime = 0
    }

    /// Translate a finished drag/tap into game input. 22pt threshold separates tap from swipe.
    func handleGesture(_ t: CGSize) {
        let adx = abs(t.width), ady = abs(t.height)
        if max(adx, ady) < 22 {
            switch core.mode {
            case .menu: startRun()
            case .over: if canRestart { startRun() }
            case .play: core.jump()
            }
            return
        }
        guard core.mode == .play else { return }
        if adx > ady {
            core.changeLane(t.width > 0 ? 1 : -1)
        } else if t.height < 0 {
            core.jump()
        } else {
            core.slide()
        }
    }
}

struct GameView: View {
    @State private var model = GameModel()

    var body: some View {
        ZStack {
            Color(red: 7.0 / 255, green: 2.0 / 255, blue: 26.0 / 255).ignoresSafeArea()

            RealityView { content in
                model.install(content)
            }
            .ignoresSafeArea()

            // Full-surface gesture catcher (behind the overlays' own controls).
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { model.handleGesture($0.translation) })
                .ignoresSafeArea()

            HUDView(core: model.core)

            switch model.core.snapshot.mode {
            case .menu:
                MenuView(best: model.core.snapshot.best)
            case .over:
                GameOverView(snapshot: model.core.snapshot) { model.startRun() }
            case .play:
                EmptyView()
            }
        }
        .statusBarHidden(true)
    }
}
