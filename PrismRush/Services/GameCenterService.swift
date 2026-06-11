import GameKit
import UIKit

/// Game Center: lazy authentication, best-score submission, and the friends leaderboard ("compete
/// with friends"). Fails silently offline / before the leaderboard exists in App Store Connect.
@MainActor
@Observable
final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterService()
    static let leaderboardID = "prismrush.best"

    private(set) var authenticated = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            MainActor.assumeIsolated {
                if let viewController {
                    GameCenterService.present(viewController)
                } else {
                    GameCenterService.shared.authenticated = GKLocalPlayer.local.isAuthenticated
                }
            }
        }
    }

    /// Submit a finished run's score. Checkpoint runs reach end-game speed (66 pts/s) from t = 0 —
    /// strictly better for best-score chasing — so they are never leaderboard-eligible
    /// (AGENT_core.md §Game Center). The local best still updates regardless; the leaderboard
    /// keeps each player's maximum, so submitting per-run scores converges on the true best.
    func submitRun(score: Int, usedCheckpoint: Bool) {
        guard !usedCheckpoint else { return }
        submit(score)
    }

    func submit(_ score: Int) {
        guard authenticated, score > 0 else { return }
        Task {
            try? await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [Self.leaderboardID])
        }
    }

    func showLeaderboard() {
        let vc = authenticated
            ? GKGameCenterViewController(leaderboardID: Self.leaderboardID, playerScope: .friendsOnly, timeScope: .allTime)
            : GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = self
        GameCenterService.present(vc)
    }

    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        MainActor.assumeIsolated {
            gameCenterViewController.dismiss(animated: true)
        }
    }

    private static func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
}
