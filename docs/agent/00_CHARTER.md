# Charter

> Write policy: only when Rayan changes direction. Everything here is meant to be stable
> across hundreds of sessions. If a session finds itself wanting to edit this file, that is a
> signal to stop and ask, not to edit.
>
> **Provenance:** session 001 wrote this from repo evidence, not from a conversation. See
> `D-002` in `04_DECISIONS.md`. The **Assumptions** section at the bottom lists every line
> Rayan has not personally confirmed. Sources used: the six owner decrees recorded verbatim in
> the repo `CLAUDE.md` (labelled there as "verbatim product law"), `README.md`, `state.md`,
> `Store/metadata.md`, `docs/SHIP_CHECKLIST.md`, `project.yml`.

---

## What Prism Rush is trying to be

A neon three-lane endless runner for iPhone that is good enough to sit next to commercial
arcade runners on the App Store without apologising, built entirely in Swift.

> **AMENDED BY THE OWNER, 2026-08-03 — D-046.** This section used to read "built entirely in
> Swift with **zero binary assets**", and the paragraph below used to say the constraint "is not
> a gimmick to be relaxed when it gets inconvenient". The owner deleted it in one line: *"why
> are you not importing real assests. delete that code only decree."* Real meshes, textures,
> models and sound files are now permitted and wanted.
>
> Everything still standing in the codebase — every procedural mesh, every `UnlitMaterial`, the
> whole DSP audio layer — exists because of the old rule, so the *style* it produced is the
> game's look and is not to be thrown away casually. But it is now a style, not a law.
>
> **What replaces it is a budget and a licensing floor, not a ban** — see
> `docs/agent/11_ASSETS.md`. Neither is the owner's to waive: we ship only what we have the
> right to ship, and every asset is charged against a stated memory budget, because the same
> instruction that revoked the rule also said *"the app becomes slow at points. this can never
> happen."*

Two things must both be true at ship:

1. **It is a real game.** A stranger picks it up, understands it in ten seconds, and wants a
   second run without being asked.
2. **It is a portfolio piece.** The repo is public. An engineer who opens it should find a
   deterministic simulation core with a clean renderer seam and a real test suite, not a
   tutorial project with good screenshots.

Neither one alone is success.

## Who it is for

- **Primary:** a phone-arcade player with 90 seconds and no patience for onboarding. They will
  not read anything. They judge the game on the first run and the first death.
- **Secondary:** an engineer reading the source. `README.md` and the architecture are part of
  the product for this audience.
- **Rayan:** the owner, solo developer, playing it himself and reacting. Owner play-feedback
  has repeatedly overruled written design docs in this project's history, and that ordering is
  correct — see "Decision authority" below.

## The quality bar for shipping

Shipping means: submitted to the App Store, approved, and something Rayan is willing to put his
name on publicly. Concretely:

- **Passes App Review on the first submission.** A rejection is a process failure, not bad
  luck. `06_COMPLIANCE.md` exists so no row is ever `UNKNOWN` at submission time.
- **No broken-looking state for any expected situation.** Offline, pre-launch store, empty
  leaderboard, first launch, zero coins, everything owned. Owner decree 3 sets this bar higher
  than Apple does.
- **Every claim in the store listing is true of the built binary.** The listing is checked
  against the Completeness Ledger, not against memory.
- **The deterministic core stays deterministic.** A seed fully determines a run; the
  200-seed solvability bot and the deep soak stay green; `DailyChallenge.layoutVersion` is
  bumped whenever the spawn stream moves.
- **The full suite is green on a Mac before any push**, not just the Linux SPM subset. Linux
  never type-checks the UI, render, StoreKit, audio-engine, or GameKit layers.
- **The UI looks designed.** If a screen looks like default SwiftUI, it is not done.

## Non-negotiables

1. **No dark-pattern monetization. No manipulative retention mechanics aimed at minors. Any
   randomized purchase must disclose odds. The game should be hard to put down because it is
   good, not because it is engineered to exploit.**
2. ~~**Zero binary assets.**~~ **REVOKED BY THE OWNER, 2026-08-03 (D-046).** Replaced by a
   **memory budget** and a **licensing floor**, both in `docs/agent/11_ASSETS.md`: ship only
   AI-generated or CC0/public-domain work ("copy subway surfers" is its design language, never
   its art, names or trademarks), and charge every asset against a stated budget.
   `PrismRush/Assets.xcassets` is no longer a carve-out, it is the catalogue — but
   `AppIcon.appiconset` stays a byte-copy of the `gen_icon.swift` output and is never
   hand-edited.
3. **Zero third-party dependencies.** Apple frameworks only.
4. **Zero ads, zero analytics, zero tracking.** This is advertised in the store listing and is
   therefore also a compliance commitment, not just a preference.
5. **`Core/` never imports a renderer or UIKit.** The `RendererPort` seam is what makes the
   simulation testable headless; it is load-bearing and not negotiable for convenience.
6. **The six owner decrees in the repo `CLAUDE.md` are product law** and outrank any design
   doc, spec, or prior decision. Reproduced here in short form so this file stands alone:
   1. A character never changes identity with the world — including the default.
   2. Previews never lie: menu hero, swatches, shop cards and teases match in-game exactly.
   3. No broken-looking states for expected situations.
   4. Everything on screen leads somewhere; no dead decorative elements.
   5. Zero ads, no dark patterns; advertised bonuses are always delivered.
   6. Clarity beats spectacle; every input readable in a single frame.
7. **Never mark work `DONE` on reasoning alone.** If it cannot be verified in the session's
   environment, it is `VERIFY-PENDING` and it goes on Rayan's device list.

## Explicitly out of scope

Do not build these. Do not file backlog items proposing them. If one becomes genuinely
necessary, it needs an ADR and Rayan's sign-off first.

- iPad, Mac Catalyst, visionOS, Android, or web. `TARGETED_DEVICE_FAMILY` is `1` (iPhone) and
  stays there.
- Landscape orientation.
- Any first-party server, account backend, or cloud save beyond iCloud KVS.
- Multiplayer, real-time or asynchronous, beyond the existing Game Center leaderboards.
- Any third-party SDK, including analytics, crash reporting, and ad networks.
- ~~Any binary asset — texture, audio file, model, font.~~ **Struck, D-046** — these are now
  wanted. See `docs/agent/11_ASSETS.md` for the budget and the licensing floor that replaced the
  ban. (Left visible rather than deleted: this line sat on a *forbidden* list for sixteen
  sessions, and a future agent who finds it half-remembered needs to see that it was revoked.)
- A second renderer. `RendererPort` exists so one is *possible*; building one is not the goal.
- Rewriting a working subsystem because a session finds it inelegant.

## Decision authority, when sources conflict

Highest to lowest. This ordering has already been exercised in this project's history — the
v1.3 "Prism the chameleon" design decision was revoked because it violated decree 1.

1. Rayan, in the current conversation.
2. The owner decrees in the repo `CLAUDE.md`.
3. This charter.
4. `docs/agent/02_STATE.md` and the rest of `docs/agent/`.
5. `state.md`, `README.md`, `reports/design/*.md` — history and rationale, not law. When one of
   these conflicts with a decree, **the doc is wrong**: amend the doc, never "ship the doc".

## What "finished" looks like

The backlog is empty of SEV0/SEV1/SEV2 items, `06_COMPLIANCE.md` has no `FAIL` and no
`UNKNOWN` that an agent could have resolved, every human gate in `docs/SHIP_CHECKLIST.md` is
checked, and the binary is in review. Polish items (SEV3/SEV4) may legitimately remain open at
ship.

---

## Assumptions — Rayan has not personally confirmed these

Each is falsifiable in one reading pass. Until confirmed, treat them as the working answer and
do not re-litigate them mid-session.

| # | Assumption | Basis | What changes if it's wrong |
|---|---|---|---|
| A1 | Shipping to the App Store is still the goal, and soon | `docs/SHIP_CHECKLIST.md`, `docs/APP_STORE_SETUP.md`, the open HUMAN GATES list in `state.md` | If it is now a portfolio piece only, the entire compliance phase drops and AUDIT-003 is wasted |
| A2 | iPhone-only, portrait-only, iOS 18+ is final | `project.yml` | An iPad claim reopens a large layout and review surface |
| A3 | Free-to-play with the existing 7 IAPs is the final monetization shape | `Store/metadata.md` §6, `Products.storekit` | Changing the model invalidates most of AUDIT-002's economy math |
| A4 | The Mystery Box is a **coin-spend** surface, not a real-money randomized purchase | `state.md` mentions "coin-spend pack purchase" | If real money can buy a randomized outcome, odds disclosure becomes a hard 3.1.1 blocker, not a courtesy |
| A5 | The target audience skews young enough that the "no mechanics aimed at minors" clause binds in practice | 4+ age rating in `Store/metadata.md` | Nothing loosens — the clause is a floor either way |
| A6 | The public GitHub repo staying public matters to Rayan | `README.md` is 35k and written for readers | If it goes private, README quality stops being a product requirement |
| A7 | "Three neon worlds" in the store listing is stale copy, and 12 world families is the truth | `Tuning.worldFamilyCount = 12`, v1.5 notes in `state.md` vs `Store/metadata.md` §4 | This is a 2.3 metadata-accuracy exposure either way and is already a backlog candidate |
