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
        refreshCredentialState()
    }

    var isSignedIn: Bool { userID != nil }

    /// Apple requires checking the credential on launch: the user can revoke the app's Sign in
    /// with Apple grant from Settings at any time, and a revoked/transferred credential must drop
    /// us back to the signed-out state (stale IDs would silently break sync trust).
    func refreshCredentialState() {
        guard let id = userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { [weak self] state, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .revoked, .notFound, .transferred:
                    self.signOut()
                case .authorized:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

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
