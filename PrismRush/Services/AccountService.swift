import AuthenticationServices

/// Sign in with Apple — gives the player a stable, private account identifier (no passwords, no
/// server). The credential's user id is stored locally; iCloud already syncs the save itself.
@MainActor
@Observable
final class AccountService {
    static let shared = AccountService()

    private(set) var userID: String?
    private(set) var displayName: String?
    private(set) var lastError: String?

    private enum Key { static let id = "pr.appleUserID"; static let name = "pr.appleName" }

    init() {
        userID = UserDefaults.standard.string(forKey: Key.id)
        displayName = UserDefaults.standard.string(forKey: Key.name)
    }

    var isSignedIn: Bool { userID != nil }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        lastError = nil
        switch result {
        case .failure(let error):
            // A user cancellation is not an error worth showing.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            lastError = error.localizedDescription
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  !credential.user.isEmpty else {
                lastError = "Sign in didn't return an account."
                return
            }
            userID = credential.user
            UserDefaults.standard.set(credential.user, forKey: Key.id)
            if let given = credential.fullName?.givenName {
                displayName = given
                UserDefaults.standard.set(given, forKey: Key.name)
            }
        }
    }

    func signOut() {
        userID = nil
        displayName = nil
        UserDefaults.standard.removeObject(forKey: Key.id)
        UserDefaults.standard.removeObject(forKey: Key.name)
    }
}
