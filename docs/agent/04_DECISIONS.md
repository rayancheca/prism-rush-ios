# Decision log (ADRs)

**Append-only.** Never edit or delete an entry. If a decision is reversed, append a new
entry that supersedes it and add `- Superseded by: D-NNN` to the old one (that one-line
addition is the only permitted edit to a past entry).

Every entry uses this format:

```
## D-NNN · <short imperative title>
- Date:        YYYY-MM-DD
- Session:     S-NNN
- Status:      ACCEPTED | SUPERSEDED(D-NNN) | REVERTED(D-NNN)
- Context:     What forced a choice. What was true at the time.
- Options:     The alternatives actually considered, one line each.
- Decision:    What we did, and why this one.
- Consequences: What this makes easy, what it makes hard, what it locks in.
- Revisit if:  The condition under which a future session should reopen this.
```

Write an ADR when a future session could reasonably reverse your call and would waste
time re-deriving why. Do not write one for routine implementation choices.

---

## D-001 · Adopt the multi-session agent program as the working method
- Date:        2026-07-27
- Session:     S-001
- Status:      ACCEPTED
- Context:     Prism Rush is feature-rich (v1.6, 95 Swift files, ~22.3k lines) and has been
               built across many ad-hoc sessions. `state.md` had grown to 58k and README to
               35k; both mix history, spec, and status, so no single file answers "what is
               true right now and what is next." The owner supplied a written program
               (Phase A scaffold → 7 adversarial audits → triage → execution) plus an
               operating-rules file.
- Options:     (a) Keep working ad hoc from `state.md`.
               (b) Adopt the program as written.
               (c) Adopt a lighter variant — skip the audits, go straight to a backlog.
- Decision:    (b), as written. The audit phase is the point: seven independent lenses in
               seven separate contexts produce genuinely different findings, where one
               context produces one finding restated seven times.
- Consequences: `docs/agent/` becomes the memory of record. `state.md` and `README.md`
               remain the project's human-facing history and are NOT the agent's source of
               truth — where they disagree with `02_STATE.md`, `02_STATE.md` wins and gets
               fixed. Eight sessions elapse before any code changes. In exchange, every
               later session starts from a map instead of a re-exploration.
- Revisit if:  Two consecutive audits produce fewer than five real findings each — at that
               point the remaining audit budget is better spent executing.

## D-002 · Write the charter from repo evidence rather than blocking on Rayan
- Date:        2026-07-27
- Session:     S-001
- Status:      ACCEPTED
- Context:     `PERSONAS.md` step 5 says to ask Rayan the charter questions first. The
               workspace `CLAUDE.md` states AUTONOMOUS MODE: never ask clarifying questions;
               make the best decision available and document it. These conflict directly,
               and this session runs non-interactively.
- Options:     (a) Block the session until answered.
               (b) Write the charter from the strongest available evidence — the six owner
                   decrees already recorded verbatim in the repo `CLAUDE.md`, plus
                   `README.md`, `state.md`, `Store/metadata.md`, `docs/SHIP_CHECKLIST.md` —
                   and mark every inference as an assumption.
               (c) Ship a stub charter.
- Decision:    (b). The owner decrees in `CLAUDE.md` are labelled "verbatim product law" and
               are a stronger source than answers reconstructed in a fresh conversation.
- Consequences: `00_CHARTER.md` carries an explicit **Assumptions** section. Every line in it
               is falsifiable by Rayan in one reading pass. The open questions are carried in
               `HANDOFF.md` until answered.
- Revisit if:  Rayan answers the charter questions — then rewrite `00_CHARTER.md` and mark
               the assumptions resolved.

## D-003 · Every behavioural audit must run the app, not just read it
- Date:        2026-07-27
- Session:     S-001 (addendum)
- Status:      ACCEPTED
- Context:     Session 001 produced 181 findings entirely from static reading. Rayan asked why no
               agent had spun up a simulator. Within fifteen minutes of actually building,
               launching and driving the app, four new findings appeared — including **PR-0290**,
               a money bug (hardcoded USD prices on live buy buttons when StoreKit has not
               loaded) that ten agents reading `IAPCatalog.swift` had not flagged, and two
               readability defects (PR-0291, PR-0292) that are invisible in source by
               construction. AUDIT-004 (Impatient Player) and AUDIT-005 (Device Matrix QA) are
               *entirely* about properties that do not exist in a source file.
- Options:     (a) Keep audits read-only and add a single play-test session at the end.
               (b) Require every behavioural audit to run the app as its first act.
               (c) Require it only for AUDIT-004 and AUDIT-005.
- Decision:    (b), on Rayan's explicit instruction ("it should def do that"). Running the app is
               now part of the Definition of Done for any audit or fix that concerns behaviour,
               and `01_RULES.md` §4 is amended to say so. This is the one authorised edit to the
               rules file.
- Consequences: Audit sessions get slower and better. A finding that could have been confirmed on
               a running build and was not is now an incomplete finding. Screenshots become the
               default evidence format, which also feeds the global README screenshot rule and
               PR-0051 (`Tools/screenshots.sh` cannot currently produce them).
               Note the sequencing constraint: **never drive the simulator while `xcodebuild
               test` is running on it** — concurrent installs crash the test host.
- Revisit if:  Simulator runs start costing more session time than the findings are worth, which
               would mean the app-driving harness needs fixing (PR-0051), not the rule.

## D-004 · Drive the simulator through `xcrun simctl` while the native integration is blocked
- Date:        2026-07-27
- Session:     S-001 (addendum)
- Status:      ACCEPTED
- Context:     The Claude Code iOS Simulator integration refuses to attach, reporting "Xcode is
               installed but not selected" and asking for
               `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. That path is
               *already* what `xcode-select -p` returns, and `xcodebuild -version` reports Xcode
               26.6 working normally, so the check appears to be misreporting. It needs Rayan's
               password either way, so no session can fix it.
- Options:     (a) Block on the integration.
               (b) Drive the simulator directly with `xcrun simctl` + `xcodebuild`.
               (c) Drive the Simulator app with generic screen-control tools.
- Decision:    (b). `simctl` gives install, launch, environment injection and screenshots — all
               that an audit needs. What it does *not* give is synthetic taps and swipes, so
               interaction must go through the repo's own launch hooks (`PR_AUTOPLAY`,
               `PR_SCREEN`, `PR_FIRSTRUN`, `PR_WORLD`, …) and the XCUITest target.
- Consequences: Audits can see the app but cannot freely poke at it. Anything needing arbitrary
               touch input has to be expressed as an XCUITest — which is a better outcome anyway,
               because it leaves a regression test behind. The live watch-along panel stays
               unavailable to Rayan until the `xcode-select` command is run.
- Revisit if:  Rayan runs the command and `attach` starts working, at which point prefer the
               native integration for interactive probing.

---

## D-005 · The program's process rules are advisory; a short invariant list is not
- Date:        2026-07-28 (session 003)
- Status:      ACCEPTED — **Rayan's explicit instruction**
- Context:     `01_RULES.md` had grown to ~290 lines of process ceremony written before anyone had
               run the program: read-only until session 010, seven audits before any code, rigid
               backlog block formats, session-log templates, context-budget percentages as hard
               gates. Rayan: *"stop focusing on hard set rules… most hard rules are stale from when
               claude had different ideas. please never be limited by arbitrary rules and just work
               however you think is best."*
- Decision:    Rewrote `01_RULES.md` (~290 → ~180 lines) split into **judgment** (advisory) and
               **invariants** (nine items). Cut: the read-only phase, the audit-before-code
               ordering, session-009-triage gating, format mandates, context-budget gates.
- Kept, and why — these are not process, they are damage prevention:
               determinism + seeded RNG · the solvability-bot + `layoutVersion` obligation on any
               spawn change (one extra `rng.unit()` silently rerolls every seeded run for every
               player) · `Core/` never imports a renderer · `Profile` decodes with defaults ·
               per-death delta payouts · G3 (`@Observable`) · Swift 6 strict concurrency ·
               no force-push · `project.yml` as the only build-config source.
- Also kept:   **run the app before claiming behaviour works** (D-003). Three for three: sessions
               001, 002 and 003 each had findings killed or discovered only by launching it.
- Consequences: Sessions may now fix code as they go. The audit sequence continues because it is
               producing real findings, not because a rule requires it. Expect faster, messier
               sessions; the invariant list is what stops "messier" from becoming "broken".
- Revisit if:  A session breaks one of the nine and ships damage — that means the list is missing
               something, not that it should be longer by default.

## D-006 · "Coins are the path" is revoked
- Date:        2026-07-28 (session 003)
- Status:      ACCEPTED — **Rayan's explicit revocation**
- Context:     `Spawner.swift:49-52` emits a gem breadcrumb into `safeEntryLane` before every
               pattern, and `Patterns.swift:128,:163` say "coins are the path". Session 003 verified
               across all 14 patterns that **no gem in the catalogue requires entering an unsafe
               lane**, so greed and survival are the same input and the game has no routing
               decision (PR-0414). It was filed as a reversal request because the behaviour was a
               deliberate v1.6 owner change.
- Rayan:       *"coins are not the path anymore — i just said that because coins were spread
               randomly before so i wanted them structured."*
- Decision:    The original intent was **structure, not safety**. Those are separable: gems should
               stay in deliberate, readable formations (structure) while some of them cost the
               player something to take (risk). PR-0414 is now a live design change, not a
               reversal request.
- Consequences: Any implementation is a spawn-path change and therefore carries invariant 2 —
               `SolvabilityBotTests` green (200×6,000 m + the 12,000 m soak) **and**
               `DailyChallenge.layoutVersion` bumped with `DailyChallengeTests` goldens repinned.
               Session 003 deliberately did **not** start it on low context; it is specced in
               `HANDOFF.md`.
- Revisit if:  Playtesting shows risk-priced gems make the early game feel punishing — the fix is
               to gate risk-priced gems behind a distance threshold, not to revert to all-safe.

## D-007 · A revived run counts for progression and is not leaderboard-eligible
- Date:        2026-07-28 (session 003)
- Status:      ACCEPTED — Rayan delegated the call ("you choose")
- Context:     PR-0254. Today a revived run is *partly* counted: the score reaches Game Center, but
               post-revive play earns no missions or XP (PR-0307). That is the worst of both
               answers — the player pays 150 coins, the number gets bigger, and progression stops.
- Decision:    Revived runs **count fully for missions and XP**, and are **not** submitted to the
               leaderboard — exactly the rule checkpoint runs already follow (`usedCheckpoint`).
- Why:         One coherent policy instead of two half-answers. A paid continue should buy *more
               game*, not just a bigger number; and a board where paying buys rank is not a board.
               The mechanism already exists and is tested, so this is a reuse rather than a new
               concept.
- Consequences: `recordRunResults` must fold post-revive progress (touches invariant 5 — keep the
               per-death delta shape, do not reintroduce cumulative re-pays), and revived runs join
               `usedCheckpoint` in skipping submission.
- Revisit if:  Rayan would rather sell the revive as leaderboard-legal — that is a monetization
               call, and it is his, not mine.

## D-008 · The attract track goes behind the hub cards
- Date:        2026-07-28 (session 003)
- Status:      ACCEPTED — Rayan delegated the call ("you choose")
- Context:     PR-0296 / PR-0445. Measured on a clean launch: the magenta attract grid crosses the
               "HEAD START ×1" glyphs and a solid band cuts horizontally across the
               CHARACTERS / SHOP / WORLDS row. Session 002 quantified it and left it unscored.
- Decision:    Push the attract track behind the card layer (or fade it under the lower third).
               It fails decree 6 — clarity beats spectacle — because the lines cross glyphs.
- Why:         The neon look survives fine behind the cards; what is lost is only the part that
               reduces legibility. This is the cheapest possible reading of "keep the vibe, drop
               the damage."
- Consequences: `UI/MenuView.swift` z-ordering only. Needs a clean-launch screenshot to verify —
               a diff alone does not prove it.
- Revisit if:  Rayan looks at it and prefers the bleed-through. He has seen this app far more than
               I have and it is a taste call; I am making it only because he asked me to.
