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

## D-009 · A character's identity is fixed in TIME as well as in space

**Session 006. Owner decision, verbatim:** *"why does the character change colours as it runs.
that defeats the whole purpose of having different characters."*

Decree 1 has always said a character never changes identity with the world. Prism, the default
runner, cycled cyan → magenta → amber on an 8 s wall clock (`isPrismatic`, added in v1.4.2 as part
of the fix that stopped skins tracking the world palette). Because that cycle is world-*blind*,
S-005 recorded it in the handoff as compliant.

**That reading was too literal and is overturned here.** The purpose of decree 1 is that a roster
means something. A default runner that recolours as it runs defeats that exactly as thoroughly as
one that follows the world. Decree 1 now reads: **a character's identity is fixed in space AND in
time.**

Prism is its authored cyan `0x00F5FF` with the magenta antenna — which is what Reduce Motion users
already saw, so the still look was already designed. The shimmer machinery is deleted, not disabled:
inert machinery is how a future session reintroduces this by accident.

**Note for the record, since the owner's message said "reverted":** nothing was reverted. No
character code was touched in S-006 before this, and 23 of the 24 skins have always been fixed. The
shimmer was long-standing default-character behaviour, not a regression.

## D-010 · Tier six opens at 2,560 m, and the chasm is NOT up-weighted in act two's first wave

**Session 006, PR-0450.** Two placement decisions that look arbitrary and are not.

**Why 2,560 m (diff 0.8).** Two constraints pin it from both sides. Above: a good run is ~3,300 m
(§3 of the bible), so a tier that opens later is one most players never meet — and the whole point
of PR-0450 was that the last new thing arrived at 1,920 m. Below: act two draws from
`Spawner.pool`, a slot table that **bypasses `maxIndex` entirely**, so any gate later than
`actTwoAt` (3,200 m) would let the table spawn a pattern the ladder had not unlocked.
`DifficultyTests.testEveryWaveKeepsTheFullCatalogueReachable` probes d = 3,300 and pins exactly
this. 2,560 m is the one band that satisfies both.

**Why no wave-1 slot.** The chasm pattern is deliberately sparse — one obstacle across ~34 m
against a catalogue average near six per 100 m — so every slot it gains costs obstacle density.
Measured over 64 seeds: a wave-1 slot dropped act two's opening band to 5.95 obst/100 m, *below*
the act-one band before it, and pushed rest share 18.6% → 25.1%. Compensating with an extra
pattern 5 recovered the opening band (6.19) but dragged the deepest one down (7.36 → 6.87). Both
variants failed `testSecondActEscalatesPastTheSpeedCap`, PR-0400's regression guard.

**Density escalation wins.** It is load-bearing for the whole endgame; chasm-frequency smoothness
is not. The residual is accepted and documented on `Spawner.poolWave1`: the chasm runs 1.84/km when
tier six opens, dips to 1.06/km as act two's larger tables dilute it, then climbs to 2.20/km by
wave 3.

**What the instrument cannot see, recorded so nobody chases these numbers.** `DifficultyCurveTests`
counts input EDGES, not input precision. A chasm costs one jump, exactly like a low — but with a
±0.25 s window against the low's ±0.64 s. Every figure above therefore *undervalues* the chasm.

## D-011 · Prism wears a static rainbow, and "static" is the whole distinction

**Session 006, immediately after D-009. Owner:** *"keep prism as a static rainbow, not solid cyan."*

D-009 removed Prism's 8 s hue cycle and left it solid cyan — which fixed the objection but also
removed the reason the character is called Prism. The correction is narrow and worth stating
precisely, because the two states look similar in a still and are opposites in the invariant:

- **Forbidden (D-009):** an identity that CHANGES. A clock, a world palette, anything that makes
  the character look different at two moments.
- **Fine (D-011):** an identity that is COMPLEX. A fixed spectrum is one look, and it is the same
  look in frame 1, in frame 100,000, and in all twelve worlds.

The test pins the distinction rather than the pixels: there is no clock in the resolution path.

**Why the implementation looks the way it does.** The renderer is `UnlitMaterial` only — one flat
colour per entity, no textures, no shaders (zero binary assets). A gradient is simply not
available, so the rainbow is built from flat colour: `ProceduralMesh.bandedSphere` emits one mesh
with one PART per band and the caller supplies one material per part. The body stays a single
`ModelEntity` (squash, blink and the pose code all address `playerBody`), so the spectrum is just
its material array — no new entities, no new render path, no per-frame allocation.

**Bands are equal in HEIGHT, not equal in angle.** On a sphere those are equivalent for surface
area, so the bands read evenly wide rather than bunching at the poles — and it hands the 2-D swatch
a rule it can mirror exactly (clip to the silhouette, fill N equal-height strips). **Decree 2 holds
by construction:** both layers derive from ONE list and ONE rule, instead of two sets of numbers
that somebody has to keep in agreement. Any future body shape that wants a spectrum has to supply
both halves of that pairing; a test pins spectral skins to `.sphere` for exactly this reason.

`bodyHex` stays the authored cyan (it is the third band) because the glow, trail, wake and death
burst all read from it. The spectrum is the body's *surface*, not its identity colour.

---

## D-012 · Audio-engine recovery is SILENT (session 007, PR-0314)

**Decision.** When `AVAudioEngine` fails to start or dies, the app retries at four moments
(interruption end, route change, engine config change, app foreground) and tells the player nothing.

**Why.** Decree 3 says no broken-looking states for expected situations, and a silent game does read
as broken — which argues for a notice. But the condition is transient, now self-healing, and gives
the player **nothing to act on**. A warning about a problem that fixes itself is noise, and a
"sound failed" banner on a game whose sound is about to come back is a worse lie than saying
nothing. If a future session finds a failure mode that does NOT self-heal, revisit this.

**Mechanism.** `wantsAudio` (intent) is split from `started` (fact). They were one flag, which is
exactly why the bug existed: a failed start cleared `started`, and every recovery path guarded on
`started`, so the one failure that most needed a retry was the one that permanently disabled
retrying.

---

## D-013 · The character stands on a lit RING, not in a diffuse glow (session 007, owner-called)

**Decision.** The hero stage's pedestal is a crisp elliptical rim plus a tight light pool, tinted by
the skin — not a wide soft radial glow. The figure's own `3.2 × bodyR` halo is off on the hero.

**Origin.** The owner: *"i really dont like the backround light behind the character in the main
screen … either take it off or cange it for something cool and pretty."* Two stacked diffuse glows
were smearing the live 3D city and its perspective grid. Diffuse light has no edge; the visual
language of this game is edges.

**The owner corrected the first fix.** An intermediate version replaced the ring with a plain light
pool because a too-wide ellipse behind a sphere shows only its side tips and read as "whiskers". He
said the circle *"was so cool"* and asked for it back. **It was a sizing problem, not a reason to
drop the ring** — dropping it lower so the near arc clears the body fixes the read. Lesson: when the
owner names a specific element as good, fix its geometry rather than replacing the idea.

**It was also the wrong COLOUR.** The glow took its tint from `bodyHex`, so after D-011 gave Prism a
six-band rainbow surface the light under it stayed cyan — a glow that did not match the thing
casting it. Spectral skins now sweep their own bands. Fixed hues in an `AngularGradient`, no clock
in the path, so decree 1 and D-011 hold: this is surface, not a changing identity.

---

## D-014 · The Wardens — per-world antagonists, and the designed fix for PR-0401 (session 007)

**Decision.** Recorded in full in `docs/agent/10_WARDENS.md`. Agreed with the owner, not yet built.

Three owner decisions on record:
1. **Combat is dodge-to-damage AND auto-fire, combined** — he rejected the either/or framing.
2. **Wardens appear every 3rd world** (~2,400 m).
3. **Being caught is struggle-to-escape, then death.**

**The design problem and its solution.** A three-lane runner's inputs are fully booked (jump, slide,
two lane changes) and decree 6 requires one-frame readability, so a fourth input language would make
both the running and the fighting worse. The two combat modes coexist by attacking **different
things**: auto-fire breaks a SHIELD at a rate driven by charge earned from gems collected during the
run (so the gun is a timer the player earned, never a win button), and dodging the exposed Warden's
telegraphed attacks is the only path to the CORE. Skill at the existing verb set decides every fight.

**The fairness valve.** Being HIT abducts you; failing to DAMAGE does not. An unbroken shield means
the Warden breaks off and leaves — you lose the reward, not the run.

**Why it matters beyond being fun.** It is the designed fix for **PR-0401** — the coin sink buys
nothing that alters play — which is the surviving half of session 003's verdict and the largest
structural gap left in the design. Countermeasures bought with coins change how an encounter
resolves. It also gives the world ladder the real progression `05_GAME_DESIGN.md §6` says it
currently fakes.

---

## D-015 · A Warden is not an `EntityKind` (session 008)

**Decision.** The Warden is a first-class field of `GameSnapshot` (`warden: WardenState?`) with its
own state machine, lifetime and collision predicate — **not** a new case in `EntityKind`.

**Why.** `10_WARDENS.md §8` flagged that `Core/` has six switches over `EntityKind` carrying a
`default:` arm — `obstacleX`, the collision dispatch, the near-miss scorer, `freeLaneNear`,
`Autopilot.decide` and `Spawner.isObstacle`. A new case is silently *accepted* by all six and
becomes a decorative, non-lethal prop that the solvability bot cannot see. The doc treated that as a
cost to be paid carefully. It is avoidable instead: a Warden is a set piece, not an obstacle on the
deck, and modelling it as one was only ever a convenience. The renderer now gets a new field it is
*forced* to handle rather than an enum case it can ignore — the `fire(_:)` switch failed to compile
until every Warden event had a reaction, which is exactly the pressure we want.

**Consequence.** Zero of the six `default:` arms were touched, and `EntityKind` is unchanged.

---

## D-016 · Every beam closes the player's own lane (session 008)

**Decision.** A Warden's beam **always** closes the lane the player occupies when the telegraph
locks, and `wardenDoubleBeamChance` (0.4) of the time closes one other lane as well.

**Why — this was a defect, found by a test rather than by reading.** The first build had the beam
*usually* stalk (60%) and otherwise pick a lane at random, on the reasoning that a beam which always
followed you would be a rhythm rather than a read. It made the design's central invariant false: a
player who never moved at all won outright whenever three consecutive beams happened to pick empty
lanes, because "was not standing in the beam" was being scored as a clean dodge. It is not one, and
`testTheGunAloneCanNeverKill` caught it at 1 kill in 40 seeds.

Closing the player's lane every time makes standing still always fatal, so the gun can never win a
fight alone (`10_WARDENS.md §3`). The second lane is what preserves the *read*: answering every
telegraph with a blind sidestep is punished about half the time. At most two of three lanes ever
close, so a safe answer always exists, every attack resolves in exactly one cycle, and the fight
stays bounded at `wardenCoreHits` exchanges.

---

## D-017 · The arena is a pure function of distance, and it costs a layoutVersion bump (session 008)

**Decision.** Obstacles and boost pads are suppressed across a fixed 660 m stretch at the head of
every third world, filtered at `GameCore.apply` **after** `Spawner.fill` has already drawn. Gems,
rings and power-ups are deliberately kept.

**Why filter at apply rather than park the spawner.** Parking the cursor was the obvious
alternative and it is worse: it moves where every later draw lands, so the whole seeded stream past
the first arena shifts. Filtering downstream leaves `fill`'s cursor, distance and draw values
byte-identical to v1.8 — pattern *selection* never moves, and `PatternOrderTests` needed no edit.
Verified: with arenas on and off, the sequence of spawned obstacle kinds for a seed is identical.

**Why the arena is distance-derived and not fight-derived.** Tying suppression to how the fight is
going would make the realised track depend on player performance, and two players on the same daily
seed would run different layouts. That would void the daily challenge's only real promise.

**Why gems stay.** Gems are the ammunition. Leaving them turns the shield phase into something the
player *does* with verbs they already own, instead of a bar they watch empty.

**Cost.** The entity set on the deck changes, so the same seed no longer means the same track:
`layoutVersion` 9 → 10, goldens repinned in `DailyChallengeTests` **and**
`MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`. All eight pre-existing pins were
reproduced in Python from the SplitMix64 constants before the three new values were trusted, and a
v11 pin is pre-armed.

**Known cost, flagged for the owner.** 660 m every 2,400 m is ~27% of the track past the first
encounter running deliberately clear. The length is set by the crudest *provable* bound
(`wardenArmWindow` + `wardenMaxSeconds` × `boostSpeedMax`), against a measured worst case of 438 m,
so there is real slack to reclaim — but shrinking it means shortening `wardenShieldWindow`, which
moves the charge threshold. This is the feature's first tuning lever after playtesting.
