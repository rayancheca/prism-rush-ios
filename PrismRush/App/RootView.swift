import SwiftUI

/// App root. Hosts the full game (RealityKit scene + SwiftUI overlays).
///
/// When the app is launched as the unit-test host, the heavy RealityKit scene (decor + particle
/// pools + meshes) is skipped: the Core tests don't need it, and building it in the headless test
/// runner is unstable. The tests `@testable import` Core directly and never touch this view.
struct RootView: View {
    private static let isUnitTesting =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some View {
        if RootView.isUnitTesting {
            Color.black.ignoresSafeArea()
        } else {
            GameView()
        }
    }
}
