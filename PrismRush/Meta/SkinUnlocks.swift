import Foundation

/// The one place a skin's unlock requirement is evaluated — pure, Linux-testable, no UI imports.
/// `ProfileStore.refreshSkinUnlocks(level:)` uses `earned` to auto-grant; the locked cards in
/// CharacterSelect render `requirementText`.
enum SkinUnlocks {
    /// Non-purchase requirement met? (coins/iap return false — those go through buy flows.)
    static func earned(_ skin: Skin, profile: Profile, level: Int) -> Bool {
        switch skin.unlock {
        case .free:                          return true
        case .level(let n):                  return level >= n
        case .achievement(let id, let tier): return (profile.achievementTier[id] ?? 0) >= tier
        case .challengeDays(let n):          return profile.challengeDaysPlayed.count >= n
        case .coins, .iap:                   return false
        }
    }

    /// Requirement line for locked cards (UPPERCASE, the UI styles it).
    static func requirementText(_ skin: Skin) -> String {
        switch skin.unlock {
        case .free:                       return ""
        case .coins(let c):               return "\(c)"            // UI renders CoinBadge instead
        case .level(let n):               return "REACH LEVEL \(n)"
        case .achievement(let id, _):
            switch id {                   // copy pinned per id — never derive from Mission titles
            case "ach.dist":  return "RUN 10,000 M LIFETIME"
            case "ach.close": return "THREAD 100 CLOSE CALLS"
            case "ach.gems":  return "BANK 1,000 GEMS LIFETIME"
            default:          return "COMPLETE ACHIEVEMENT"
            }
        case .challengeDays(let n):       return "PLAY \(n) DAILY CHALLENGES"
        case .iap:                        return "★ PREMIUM · SHOP"
        }
    }
}
