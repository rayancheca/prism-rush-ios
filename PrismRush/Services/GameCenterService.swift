import GameKit
import UIKit

/// Game Center: lazy authentication, best-score submission, and the friends leaderboard ("compete
/// with friends"). Fails silently offline / before the leaderboard exists in App Store Connect.
@MainActor
@Observable
final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterService()
    static let leaderboardID = "prismrush.best"
    /// Recurring leaderboard (daily reset in App Store Connect) for the shared-seed daily challenge.
    static let dailyLeaderboardID = "prismrush.daily"

    private(set) var authenticated = false {
        didSet { if authenticated, !oldValue { flushPending() } }
    }

    /// Best score that arrived while signed out, this session.
    ///
    /// One value is a sufficient queue: the all-time board keeps each player's MAXIMUM, so
    /// submitting the best of the session converges on exactly the same result as replaying every
    /// run — without persisting anything. Before this, a player who launched without connectivity
    /// lost every score they set that session, silently (PR-0315).
    ///
    /// Deliberately NOT seeded from `profile.bestScore` on flush: the local best updates even for
    /// checkpoint runs, which are never leaderboard-eligible (iron rule 10). Only scores that
    /// already passed `submitRun`'s guard can land here.
    private var pendingBest = 0
    /// The daily board is per-day, so its queue carries the day it belongs to.
    private var pendingDaily: (score: Int, day: Int)?

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

    /// Submit whatever was banked while signed out. Fired by `authenticated` flipping true, so it
    /// covers a late sign-in from the Profile card as well as a delayed launch handshake.
    private func flushPending() {
        if pendingBest > 0 {
            let score = pendingBest
            pendingBest = 0
            submit(score)
        }
        if let queued = pendingDaily {
            pendingDaily = nil
            submitDailyChallenge(score: queued.score, day: queued.day)
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
        guard score > 0 else { return }
        guard authenticated else { pendingBest = max(pendingBest, score); return }
        Task {
            try? await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [Self.leaderboardID])
        }
    }

    /// Submit a daily-challenge run. `day` (UTC days since epoch) rides along as the context so a
    /// score's challenge date is recoverable; the recurring leaderboard handles the daily reset.
    func submitDailyChallenge(score: Int, day: Int) {
        guard score > 0 else { return }
        guard authenticated else {
            // Keep the best score for the CURRENT day only; a queued score from a previous day
            // would land on a board that has already reset.
            if pendingDaily?.day != day || score > (pendingDaily?.score ?? 0) {
                pendingDaily = (score, day)
            }
            return
        }
        Task {
            try? await GKLeaderboard.submitScore(score, context: day, player: GKLocalPlayer.local,
                                                 leaderboardIDs: [Self.dailyLeaderboardID])
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
