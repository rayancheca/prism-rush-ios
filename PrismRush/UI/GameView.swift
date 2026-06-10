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
    @ObservationIgnored let haptics = Haptics()
    @ObservationIgnored private var sub: EventSubscription?
    @ObservationIgnored private var overTime: Double = 0
    @ObservationIgnored private var demoElapsed: Double = 0
    @ObservationIgnored private var demoDied = false
    @ObservationIgnored private var uiClock: Double = 0
    @ObservationIgnored private var popupCounter = 0

    @ObservationIgnored private let autoplay = ProcessInfo.processInfo.environment["PR_AUTOPLAY"] == "1"
    @ObservationIgnored private let demo = ProcessInfo.processInfo.environment["PR_DEMO"] == "1"

    // SwiftUI-facing effect state (observed).
    struct Popup: Identifiable {
        let id: Int
        let text: String
        let color: Color
        let worldX: Double
        let born: Double
    }
    private(set) var popups: [Popup] = []
    private(set) var flashID = 0
    private(set) var flashStrength: Double = 0
    private(set) var bannerID = 0
    private(set) var bannerName = ""
    private(set) var bannerOrdinal = 0

    /// Restart is allowed a short beat after death (avoids the death tap instantly restarting).
    var canRestart: Bool { overTime > 0.5 }

    func install(_ content: RealityViewCameraContent) {
        renderer.install(into: content)
        haptics.prepare()
        core.onFX = { [weak self] fx in self?.handleFX(fx) }
        if autoplay || demo { core.startRun(seed: 7) }

        sub = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dt = event.deltaTime
                self.uiClock += dt
                self.haptics.tick(dt)

                if (self.autoplay || self.demo), self.core.mode == .play {
                    Autopilot.drive(self.core)
                }
                if self.demo, self.core.mode == .play {
                    self.demoElapsed += dt
                    if self.demoElapsed > 6, !self.demoDied { self.demoDied = true; self.core.debugForceDie() }
                }
                if self.autoplay, self.core.mode == .over {
                    self.startRun()
                }

                self.core.advance(realDt: dt)
                self.renderer.advanceVisuals(dt)
                self.renderer.sync(self.core.snapshot)
                self.overTime = self.core.mode == .over ? self.overTime + dt : 0
                self.ageEffects()
            }
        }
    }

    func startRun() {
        core.startRun()
        renderer.resetEntities()
        overTime = 0
        popups.removeAll()
    }

    // MARK: effects

    private func handleFX(_ fx: FXEvent) {
        renderer.fire(fx)
        haptics.handle(fx)
        switch fx {
        case let .gemCollected(x, _, streak):
            let mult = min(5, 1 + streak / 8)
            addPopup("+\(10 * mult)", color: Theme.color(0xFFD23D), worldX: x)
        case let .nearMiss(kind, x):
            addPopup(kind, color: kind == "CLOSE" ? Theme.color(0x00F5FF) : Theme.color(0xFFD23D), worldX: x)
        case let .pickup(kind, x, _):
            addPopup(kind == .shield ? "SHIELD" : "MAGNET", color: .white, worldX: x)
            flash(kind == .shield ? 0.18 : 0.15)
        case let .shieldAbsorbed(x):
            addPopup("SHIELDED", color: .white, worldX: x)
            flash(0.25)
        case .died:
            flash(0.5)
        case let .worldChanged(index, ordinal):
            bannerName = Theme.worlds[index % 3].name
            bannerOrdinal = ordinal
            bannerID += 1
        case .jumped, .slid, .landed, .laneChanged:
            break
        }
    }

    private func addPopup(_ text: String, color: Color, worldX: Double) {
        popupCounter += 1
        popups.append(Popup(id: popupCounter, text: text, color: color, worldX: worldX, born: uiClock))
        if popups.count > 12 { popups.removeFirst(popups.count - 12) }
    }

    private func flash(_ strength: Double) { flashStrength = strength; flashID += 1 }

    private func ageEffects() {
        if !popups.isEmpty { popups.removeAll { uiClock - $0.born > 0.9 } }
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

            EffectsOverlay(model: model)
        }
        .statusBarHidden(true)
    }
}
