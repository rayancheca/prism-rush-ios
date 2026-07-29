import SwiftUI

/// The two shapes every non-happy state in the app should wear (S-007, the failure-state sweep).
///
/// Before this file the repo had five mutually incompatible dialects for "you can't do this yet",
/// ranging from the excellent (`UnlockPanel`'s NEED n MORE + GET COINS) to the dead-end (a dimmed,
/// disabled button that says nothing at all). The good ones all fill the same four-slot sentence:
///
///   1. NAME       — what is blocked, as a noun.          ("Leaderboards", "App Store")
///   2. QUANTIFY   — the gap, as a number, monospaced.    ("NEED 200 MORE")
///   3. ROUTE      — one tap that closes the gap.         ("GET COINS ›", "RETRY")
///   4. ALTERNATIVE— the other path, quieter.             ("coin items still work")
///
/// Colour law, inherited from `UnlockPanel` and enforced structurally here: **`Role.danger` marks
/// only the shortfall NUMBER — never the container, never the route.** A state that is merely
/// *normal* (offline, pre-launch, empty, signed out) uses zero danger. That is decree 3 — "no
/// broken-looking states for expected situations" — expressed as colour rather than as a comment.

// MARK: - shortfall

/// "NEED n MORE" + one route out. Extracted from `LevelSelectView.UnlockPanel` (the app's best
/// shortfall state) so the rest of the app can stop reinventing a worse version of it.
///
/// Deliberately has **no self-clearing timer**: `UnlockPanel` leaves the row up because the player
/// should read the shortfall, not chase a flash. `CharacterSelectView.deny()` clears after 450 ms
/// and is the weaker of the two. New adopters follow `UnlockPanel`.
///
/// `shortfall` is an `Int` the CALLER computes inside its own `body`, so the live store read stays
/// at the point of use and observation is never broken (iron rule G3).
struct ShortfallRow: View {
    /// How many more of `unit` the player needs. Computed live by the caller — never cached.
    let shortfall: Int
    /// The thing being counted, plural, uppercase-ready. "MORE" reads as coins by convention.
    var unit: String = "MORE"
    let routeTitle: String
    let route: () -> Void
    /// Gold when the route leads to money, cyan when it leads to a screen.
    var routeTint: Color = Theme.Role.reward
    var identifier: String?
    /// Spoken destination, e.g. "Opens the shop".
    var routeHint: String = "Opens the shop"

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text("NEED \(shortfall.formatted()) \(unit)")
                .typeScale(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Role.danger)

            Button(action: route) {
                Text(routeTitle)
                    .typeScale(.caption)
                    .foregroundStyle(routeTint)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(routeTint.opacity(0.6)))
            }
            .buttonStyle(.neon)
            .accessibilityIdentifier(identifier ?? "")
            .accessibilityLabel("\(routeTitle). \(routeHint)")
        }
    }
}

// MARK: - state notice

/// A card for states that are *normal but not the happy path*: pre-launch store, no connection,
/// signed out, nothing to restore, an empty board.
///
/// `tone` is the whole point. `.calm` is the default because almost nothing in this list is the
/// player's fault or an error — the offline card's own comment says it best: "no danger red,
/// nothing is the player's fault". `.problem` exists for a genuine failure the player can act on
/// and should stay rare.
///
/// When `actionTitle` is nil the notice renders as plain content rather than a `Button`, so a
/// state with nowhere to go never looks tappable (decree 4 in reverse: nothing that leads nowhere
/// should *pretend* to lead somewhere).
struct StateNotice: View {
    enum Tone {
        case calm, celebratory, problem

        var tint: Color {
            switch self {
            case .calm:        Theme.Role.textSecondary
            case .celebratory: Theme.Role.reward
            case .problem:     Theme.Role.danger
            }
        }
    }

    /// SF Symbol. Outline reads as absence, `.fill` as presence — pick to match the state.
    let symbol: String
    let title: String
    var detail: String?
    var tone: Tone = .calm
    /// nil ⇒ nothing to tap ⇒ the notice is not a button.
    var actionTitle: String?
    var action: (() -> Void)?
    /// Swaps the action label for a spinner (a retry already in flight).
    var isBusy = false
    var identifier: String?
    /// Overrides the composed VoiceOver label when the visible copy reads badly aloud.
    var spokenLabel: String?

    private var routeTint: Color { tone == .problem ? Theme.Role.interactive : tone.tint }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tone.tint)
                Text(title)
                    .typeScale(.heading)
                    .foregroundStyle(Theme.Role.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }

            if let detail {
                Text(detail)
                    .typeScale(.body)
                    .foregroundStyle(Theme.Role.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Group {
                        if isBusy {
                            ProgressView().tint(routeTint)
                        } else {
                            Text(actionTitle)
                                .typeScale(.caption)
                                .foregroundStyle(routeTint)
                        }
                    }
                    .frame(minWidth: 84)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, 9)
                    .overlay(Capsule().strokeBorder(routeTint.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.neon)
                .disabled(isBusy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .neonCard(radius: Theme.Radius.l)
        // Order matters: `.accessibilityElement` must precede `.accessibilityIdentifier`, or
        // VoiceOver and XCUITest read the derived label instead of the crafted one
        // (LevelSelectView.swift:161 documents the same trap).
        .accessibilityElement(children: actionTitle == nil ? .ignore : .contain)
        .accessibilityIdentifier(identifier ?? "")
        .accessibilityLabel(actionTitle == nil ? (spokenLabel ?? composedLabel) : "")
    }

    private var composedLabel: String {
        detail.map { "\(title). \($0)" } ?? title
    }
}
