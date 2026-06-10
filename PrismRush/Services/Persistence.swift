import Foundation

/// The entire persistence surface for v1: best score and mute, in `UserDefaults`.
/// (Declared in the privacy manifest, reason CA92.1.)
enum Persistence {
    private enum Key { static let best = "pr.best"; static let muted = "pr.muted" }

    static var bestScore: Int {
        get { UserDefaults.standard.integer(forKey: Key.best) }
        set { UserDefaults.standard.set(newValue, forKey: Key.best) }
    }

    static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: Key.muted) }
        set { UserDefaults.standard.set(newValue, forKey: Key.muted) }
    }
}
