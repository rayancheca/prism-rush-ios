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

---

## D-020 · The stumble is one rescue from a near-miss, not a second life (S-010, 2026-07-30)

**Owner's words:** *"functionality like subway surfers where you basically have two lives. if you
half hit a wall you slow down for a sec… not two lives per say more like 1.5."*
Plus, on the Warden: *"stumble first then kill"*, and a stumble *resets the multiplier*.

**The rule, stated once.** A contact is a stumble when the smallest move that would have made it a
clean pass is shallow, measured on the axis whose VERB answers that obstacle, at the instant the
overlap begins. Deep on every applicable axis → death.

**Where the "0.5" actually lives.** Not in an accounting rule and not in a HUD pip. It is that the
rescue is *conditional* (only from a mistake that was nearly right) and *non-repeating*
(`stumbleRecover` 0.90 s of full vulnerability, in which any further contact — including one that
would otherwise stumble — is lethal). No counter, no resource, no hoarding.

**Why the kill line moved inward rather than the near-miss band being eaten.** The band that *looks*
like a half-hit (dx 1.25–1.57) is already the bottom third of CLOSE, the game's flagship reward.
Paying for the stumble out of that would have converted a bonus into a penalty. Instead the lethal
threshold moves 1.25 → 0.90 and CLOSE is untouched: nothing that used to pay now costs.

**`stumbleGrazeDX = 0.35`, and honestly what it buys.** Half the CLOSE band, so it derives from a
shipped constant. `px` eases at `laneLerpRate`, so crossing it takes ~21 ms against 30–80 ms of human
timing jitter: it converts roughly a quarter of "I swiped and it wasn't quite enough" deaths. **It
will be rarer than Subway Surfers.** Widening it is one edit and is a tuning decision, not an
architectural one — but at 0.90 the body is already 54% buried, and deeper stops reading as *half* a
hit at all.

**The split bar is why the measure is ESCAPE and not penetration.** A player dead between two covered
lanes is 0.15 into each — "shallow in both" — and 2.35 units from any safe position. Per-lane
penetration would hand a free rescue to the worst possible answer.

**Why the Warden's escalation is per-ENCOUNTER and not a timer.** Strikes are 1.05–1.20 s apart, so
any recovery window short enough to feel like a stagger expires before the next strike can arrive.
A timer-based "second hit kills" would leave a Warden mathematically incapable of killing anybody,
taking the fight's own hardness gate permanently red *because the fight got fairer*.

**The slowdown is not only flavour.** It costs ~13 points, which is nothing; the multiplier reset is
the punishment. But because `stumbleRecover` is a TIME window and the dip cuts speed, the stretch of
deck that must be survived while vulnerable falls from ~30 m to ~18 m. The stagger and the danger
window are coupled in the player's favour, which is the right shape.

**The one mandatory test change.** `SolvabilityBotTests` decided "unfair" only by asking whether the
bot DIED. A survivable contact would have turned an impossible pattern into a green stagger. It now
asserts **zero contacts** across all 200 seeds and the 12,000 m soak. It passes — the Autopilot never
enters a graze band, so its trajectories are unchanged.

**Determinism.** `layoutVersion` stays 10. Zero RNG, no `SpawnCmd`, no golden re-pin.

---

## D-021 · The spawner's inter-pattern GAP is player-distance-derived, not cursor-pure (S-010)

**This corrects the record**, and it bears directly on **PR-0052**.

`docs/agent/audits/scratch/s009b_probe_stumble.md` §6 recorded the spawner as fully cursor-driven,
concluding that a speed change "does not change *what* is placed or *where*". Half right.
`GameCore.spawn` calls `spawner.fill(to:dist:)` with the player's **live distance**, and
`Spawner.gapFor(dist)` derives the inter-pattern gap from it — so the gap is a function of where the
player was standing when a pattern was emitted, not of the cursor.

**Consequence:** any speed change nudges every later `d`. Measured: **0.0002 m at 184 m** — one part
in a million, three orders of magnitude below `obstacleZHalf`, and below the 0.14 m a single tick
covers. It cannot change an answer, a lane or a verb.

**This is not new and not the stumble's doing.** `StumbleTests.testStumblingPerturbsTheTrackNoMore
ThanAShippedPowerUpDoes` proves the identical drift from a chrono pickup and from the overdrive
boost, both shipped for versions. Pattern identity, order and lane are exactly equal in all cases.

**What it means for PR-0052.** The daily challenge has never been able to promise an *identical
experience* — only an identical *layout*. Three shipped power-ups already break the stronger reading.
The question is therefore answered by the code rather than open: `layoutVersion` guards which
patterns reach the deck, and that is the promise it can keep.

---

## D-022 · Warden presence: what the design spec got wrong, and how (S-010)

`s009c_SPEC.md` is a good document and most of it shipped as written. Three of its numbers did not
survive contact, and the pattern in how they failed is worth keeping.

1. **Halo clearance — an arithmetic slip.** It priced the rim's outer edge as `major × scale`
   (4.862) and omitted the torus **minor** radius. The true edge is 5.270, so its halo scale would
   have cleared the rim by 0.03 u ≈ **2 px** — the cyan ring welded to the hull for the whole
   7 s window, which is precisely the failure the section existed to prevent. Caught by redoing the
   sum, not by looking.
2. **The core's position — a projection failure.** It placed the core level with the hull's
   underside. The camera sits at y 5.1 looking **down** on a craft at 4.2, so an opaque 8.3-unit
   disc occluded it completely: the core was invisible for the entire exposed phase while the HUD
   read "CORE EXPOSED". Caught only by looking.
3. **Spar colour — a contrast failure.** Near-white spars on a pale hull, inboard of a dome taller
   than they are. Invisible. Caught only by looking.

**The lesson, which is the program's oldest one restated:** an arithmetic error in a spec is caught
by redoing the arithmetic, and both of the others were caught by nothing except running the app and
opening the screenshot. `swift test` compiles neither `UI/` nor `Render/`; 231 green tests said
nothing about any of the three.

---

## D-023
**The unlock ladder is pulled forward ~2.1×, and only the KINDS move.** (S-011, owner-directed.)

Gates: 260 / 576 / 1,440 / 1,920 / 2,560 m → **150 / 350 / 600 / 900 / 1,200 m**. The whole
15-pattern catalogue is now open by 60.5 s.

The measurement that forced it (`audits/scratch/s011_obstacles.md`, 600 seeds, integrating the real
speed ramp): a player dying at 1,500 m had met 10.9 of 15 patterns, and four of them were not
unlikely but **unreachable** — the tier gated at 1,440 m and the spawn horizon sits 115 m past it.
The five starter patterns were **49% of every encounter in a two-minute run**. The last new thing the
game ever introduced arrived at **111.6 s**, after speed (caps 3,077 m), gap and the ladder had all
stopped moving. That is the arithmetic behind the owner's *"the gameplay has been left stale."*

**The gap axis is deliberately NOT pulled forward with it.** New kinds arrive early; crowding still
arrives late, and every pattern is now met at a LOWER speed, which is strictly more reaction time.
The one exception is the chasm, whose window does not widen at lower speed (airborne distance minus a
fixed 8 m hole): 0.398 s of launch slop at the new gate versus 0.478 s at the old. Still wider than
the bar's 0.408 s jump window.

## D-024
**A moving wall closes a lane at every distance.** (S-011, owner: *"the moving walls are stupid as you
can always survive them by just sticking to one side."*)

`Patterns.wallPhase` returned `intensity(d)`-scaled swing, which is **zero below 3,200 m**. At phase 0
each wall parked dead centre and swept only x ∈ [−0.332, +0.332] across the 1.9 u lethal window, so an
outer lane cleared the 1.25 kill half-width by **0.618 u — 49% of margin, on both walls, every time**.
Parking in lane 0 and giving no input survived pattern 13 until the ramp closed an outer lane at
**6,841 m = 4 min 02 s**. Pattern 13 is the *exclusive* tier-five unlock, so the only new content in a
22-second stretch of ladder was the one pattern beatable by doing nothing.

Now ±`wallPhaseSwing` everywhere: wall 0 leaves lane 0, wall 1 leaves lane 2, a genuine 13 u weave.
The breadcrumbs the pattern already emitted were drawing exactly that route while the swing was off.
Act two loses this as an escalation axis and keeps its real one, the draw-table mix — a wall that
closes a lane is the correct BASELINE, not an endgame reward.

## D-025
**`Autopilot`'s chasm launch lead is derived from the physics, not clamped to constants.** (S-011.)

It was `clamp(0.28·v, 7, 11)`. Launching `L` before the leading rim clears the hole exactly when
`chasmAirborneEnter·v ≤ L ≤ chasmAirborneExit·v − 2·chasmHalfLength`; at v = 17.5 m/s that interval is
only **[0.51, 5.76]**, so the floor of 7 forced the launch *outside the window* and the bot landed
1.3 u short of the far rim, deterministically. It survived two versions because the chasm gated where
v ≥ 30.3, and 17.5 is reachable there only under a chrono (×0.65) — a coincidence no seed had hit.
D-023 made it common and seed 17604131991531453882 found it immediately.

The replacement is the apex rule — launch so the jump's apex lands on the hole's centre — which is the
exact rule `Patterns` case 14 uses to PLACE the hole. Prover and author now agree by construction
rather than by two sets of numbers that happened to match.

**Related, filed not fixed:** a chasm met while a chrono is active has its gem-arc telegraph point
~1.2 m early, because the hole is placed from the predicted RAMP speed while chrono moves the player
at 0.65×. It stays clearable (0.30 s of slop) but the cue misleads. Pre-existing; D-023 makes it more
reachable.

## D-026
**A gem is not a coin, and skill is the largest term in the faucet.** (S-011, owner-directed; full
audit in `audits/AUDIT_011_ECONOMY.md`.)

Gems were currency at 1:1 and 76–87% of every payout; `styleCoins` — the only term measuring whether
the player played WELL — was capped at 80 coins/run, about 6%. So the game paid for pickup, not for
play. Consequences: nothing cost more than 23 minutes, the 83,500-coin catalogue was 2 h 22 m, and
`$0.99 → 1,200 coins` was worth less than one good run.

Owner's four calls: a mid character should cost 30–45 min; **skill should pay much more**; Coin Surge
becomes **earned, never bought**; IAP should genuinely matter.

Implemented: `coinsPerGemDivisor` 20, distance 1/35 → 1/170, worlds 5 → 3, bounty 150 → 22, and
`styleCoins` uncapped at `(closes+slicks)·2 + surges·5`. Measured over two tuning passes: income cut
**6.3× / 7.4× / 7.2×** at 800 / 1,500 / 3,300 m, style share **3% → 47–59%**, a mid character
31–34 min, the catalogue ~21 h.

**Coin Surge was REMOVED from the coin shop, not re-priced.** 450 coins → +3,858 (+7,716 with Double
Coins) is 8.6–17× ROI, repeatable and uncapped: you could mint currency with currency, which is what
actually made buying a pack irrational. A re-price leaves a trap item whose safety depends on the
faucet never changing again, and the faucet changed twice in this one session. The invariant is now
structural: **no coin-spend path may grant a coin multiplier.**

**Not a spawn change.** Gem placement is untouched, so `layoutVersion` stays at 11 and the solvability
proof, the `PatternOrderTests` call counts and the daily goldens are all unaffected.

## D-027
**The `×N` multiplier belongs on the score, not on the gem chip.** (S-011, owner: *"what does x5 mean
in the [HUD]"*.)

`HUDView.gemMultPill` put `×N` in the chip's LABEL slot, where the word "GEMS" otherwise sat. The
reasoning ("it reads as *what this chip is*") failed on arithmetic, not typography: `mult` reaches its
×5 cap at **124 m / 7.16 s** and holds it for **90.3% of a clean run**, so the label was almost never
"GEMS" and the chip spent nearly every run showing a bare `×5` beside a five-digit number with nothing
naming either. And they were never related — `mult` multiplies SCORE; every currency line in
`GameCore` deliberately omits it. The multiplier now sits beside the score readout; the gem pill's
label is fixed text, so the no-reflow property that motivated the original design is preserved
without paying for it in meaning.

## D-028
**THE BLAST: a double tap is the game's first offensive verb, and CHARGE is its ammunition.**
(S-012, owner's own proposal: *"maybe double tap sends a blast originating from the player that
knocks things down and clears a path"*, and his answer *"CHARGE becomes its ammo"*.)

Every input in the game was evasion — three verbs, all of them "get out of the way". This is the
fourth and the only one that acts ON the world. It is also the answer to a second problem: the CHARGE
meter appears 1.5 s into the first run anybody plays and the thing it fed (a Warden's fire rate) did
not exist for another 104 seconds.

**Three things make the design work and each was verified rather than assumed.**

*The input costs nothing.* Tap 1 still fires `jump()` on the frame it arrives — a double-tap
recogniser would have to hold it for its window first, which is 0.30 s of added latency on the most
used input in the game (15% of the whole reaction budget at the speed cap). A second tap inside
`blastTapWindow` is the blast, and that window lies entirely inside the span where a buffered jump is
ALREADY discarded: a buffer only survives to touchdown if tapped within `jumpBuffer` (0.25 s) of
landing, i.e. later than 0.565 s into an 0.815 s arc. We are claiming dead input.

*It does not change the track, and therefore owes no `layoutVersion` bump.* Measured, not argued:
with the player's route frozen, 8 seeds place byte-identical obstacles with and without blasting;
under a driven bot, kind and lane never differ and positional drift maxes at 0.0027 m against the
0.0063 m the long-shipped slow-mo deploy already causes through the same D-021 mechanism. The pool
caps that could have made destruction change spawning never bind (peak 12/18, 10/14, 5/6, 2/6, 2/3
over 12,000 m).

*The Autopilot never learns it.* "Every pattern is survivable" must not quietly become "survivable or
destructible" — an unanswerable pattern would then pass the 200-seed proof by being deleted rather
than dodged. `PR_BLAST=1` drives it from the UI layer so autoplay stays capturable.

The chasm is immune by rule: you cannot knock down a hole, and it is the catalogue's only two-sided
timing window, so a second answer would undo the verb it was added to teach. And a blast with nothing
to hit is REFUSED rather than wasted — found by the integration read, because `Warden.suppresses`
sweeps an arena clear and a reflexive double tap there spent a third of the bank for no effect.

## D-029
**A WARDEN CAN NEVER KILL YOU. It has no attack of its own; it rebuilds the track.**
(S-012, owner verbatim: *"it can never kill you"*, *"throw real hazards"*, *"maybe it launches walls
down a lane, drops bars to slide under, blasts holes in the deck"*.)

Every shipped runner boss the S-011 research examined — Sonic Dash, Minion Rush, Crash On the Run —
models the boss as an OPPORTUNITY layer: no kill move, the lethal thing is the obstacle it places,
failure means the boss escapes with the reward. v1.9–v2.1 inverted this and ended the run on the
second landed beam. Worse, its "forgives once" was skippable: the lethal branch required
`stumbleT <= 0` while `stumbleT` runs 0.90 s against a 0.15 s grace, so any wall clip in the 60 m
before the arena mouth made the FIRST Warden hit lethal.

**The S-009 verb trichotomy survives one-for-one — it was never the problem.** What was wrong was
that all three shapes were abstract red bands painted on the player's own plane. The S-011 render
audit measured it: a full-width opaque red band on screen for 92–95% of the exposed phase, a 100 ms
dark gap between shapes, a curtain erasing 100% of the track beyond 5.3 m, a floor delivering 379 of
its final 440 px in one frame. So each shape became a real obstacle:

    lance   → two `tall` walls, one lane open  → change lane
    floor   → a `chasm` blown in the deck      → jump
    curtain → a `hangingBar`                   → slide, and only slide

Travel time IS the telegraph, and no new machinery was needed: a thrown hazard is static in world
space and the world scrolls it in, exactly like every other obstacle, so `z = distance − d` still
describes it. **The lead was measured, not guessed.** The first build used 46 m on the reasoning that
more reading time must be better; `LaggedAutopilotTests` immediately went red in the direction that
matters — a bot reacting a full 0.75 s late took ZERO hits and killed 48 of 48 Wardens. At 34 m
(1.15 s at the first encounter, closing to 22 m / 0.75 s at the brink) the same gate reads 68 hazards
landed and 31/48 killed, while a 0.40 s reaction is still never touched. The S-011 verifier had
already refuted "the telegraph is too short" — length was never the problem, and buying more of it
costs the fight its teeth.

A landed hazard costs the multiplier, the tempo, one blast round, and the answer it would have been
worth. Miss enough and the clock runs out and it leaves with your bounty. **The Autopilot lost both
its Warden-specific override blocks and needed nothing in return** — it did not have to be taught the
boss; the boss was taught to speak the track.

`layoutVersion` stays 11: no pattern places a hanging bar, and a throw goes in through `applyThrown`,
which draws nothing from the run's stream.

## D-030
**A hanging bar's ceiling is UNREACHABLE, not absent — and that distinction is decree 2.**
(S-012.)

Every bar in the game up to v2.1 could be jumped: `barHit` kills only between 0.95 and 1.65, and a
base jump puts the body's underside above the band for 0.434 s of its 0.815 s arc. **A player who
never once swiped down could complete the entire pattern catalogue.** Slide was the game's only
decorative verb.

The property that fixes it is "no jump clears it". `wardenCurtainKillBottom` got that by having no
top at all — and paid for it by forcing the MESH to be drawn taller than anything reachable, or else
promising a gap the collision does not honour. That was finding F5 of the S-011 render audit, where a
Super Sneakers jump put the body visibly clear of the drawn curtain and died anyway.

A ceiling above every attainable height gives the same guarantee honestly and 28% shorter. The
highest a body's underside ever gets is a Super Sneakers apex (3.748 m); `hangingBarKillTop` is 4.0,
the drawn mesh is exactly the kill band, and the margin is pinned — so raising the jump buff without
raising this turns the suite red instead of quietly opening a hole in the one obstacle whose entire
purpose is that there is no way over it.

## D-031
**The level ladder must not out-earn playing the game, and the Mystery Box must be neither a trap
nor a printer.** (S-012 — E6/E7 of `audits/AUDIT_011_ECONOMY.md` §3.)

*E7.* L1→L30 paid 10,300 direct coins and takes ~73–81 minutes; running for those same minutes pays
4,630–6,265 on the S-011 faucet. **Levelling was worth 1.6–2.2× the entire run faucet** — so the
session that made SKILL the largest term in the payout was immediately beaten by a counter that goes
up no matter how you play. With the power-up charges (13,050 at shop prices) plus an unbounded
coin-surge stack, the giveaway came to 23,350 coins of priceable value against an 83,500 catalogue:
28% of the whole game. Direct coins are cut 4.3× to 2,400; charges are halved and moved off a flat
multiply onto per-LEVEL grants so shields sit on even levels and Coin Surges on five-level milestones
(6 across the ladder, and now the only source of them in the game).

*E6, the Mystery Box.* Wrong in both directions at once. Its expected value was 242.7 against a 300
price — **−19%**, and −23% re-derived after S-011 deleted the pack its 8% Coin Surge band was valued
at. But the same band made it too GENEROUS at the other end: a surge doubles a whole run and charges
bank with no cap, so a deep runner values it at their best run, and the box turns net-positive past a
surged run of ~15,000 m. **That made it the last surviving violation of D-026** — a 300-coin spend
that returns a coin multiplier. The band is gone and the rest is weighted so EV is the price (300.5).
The coin bands alone stay at 240.5, so it is a lottery you break even on rather than a coin printer,
which with unlimited rolls and no cooldown is the only shape that is both fair and safe.

*E6, the IAP packs: NO CHANGE, deliberately.* Measured against the new faucet, $0.99 buys 15–20
minutes and $19.99 buys 8.5–11 hours. The owner's "IAP should genuinely matter" is already satisfied
by cutting the faucet 6–7×; re-pricing packs on top would have overshot.

## D-032
**A Warden throws things AT you.** (S-013 — owner feedback, verbatim: *"its not sending walls down
the lane like i asked … the walls he send come quicker like the trains from subway surfers"*.)

Until v2.3 every obstacle in the game — including a Warden's — was pinned to a fixed `d` and the
player ran into it. Nothing was ever launched at anybody, so the boss's "attack" was mechanically
indistinguishable from ordinary track that happened to be red. `CoreEntity.closeSpeed` (0 for
everything the spawner places, so ordinary track and every seeded proof are untouched) advances a
hazard toward the player on top of the scroll: **25 / 28 / 32 m/s by rank**, against a 29.5–33 m/s
run, so a hazard approaches at 1.85–1.97× the speed of the deck under it.

The leads moved OUT to 52/40 m to pay for it. That is not extra reading time — the window is
`lead / (run + close)`, so it is **0.95 s → 0.62 s** across the ranks against v2.2's flat 1.15 → 0.75.
The hazard is further away, arrives sooner, and visibly rushes.

**The first attempt used 9/16/24 and `LaggedAutopilotTests` refuted it in one run**: a bot reacting a
full 0.75 s late killed 48 of 48 Wardens, because 52 m against +9 m/s is a *more* generous window
than the thing it replaced. Moving leads out without moving closing speed up ships a boss that looks
faster and plays easier.

## D-033
**The rank ladder is real, and rank 3 shoots at you.** (S-013 — *"he should be easier at first and
tougher on harder levels. so when hes tougher he shoots you as well"*.)

v2.2's ladder was two numbers (throw interval, core hits) and a flat 14.5 s clock. v2.3 varies the
closing speed, the interval (1.55/1.30/1.10), the answers to kill (5/6/7) and the SCRIPT itself.

`WardenBand.shot` → `EntityKind.bolt`: a single-lane projectile aimed at the lane the player is
standing in at the moment of launch, closing `wardenShotCloseBonus` (6 m/s) faster than the wall
thrown beside it. **Rank 1 fires none** — the first Warden anybody meets is strictly the three shapes
the track already taught. A shot shares the lance's ANSWER, so no fourth input was added to the game
(decree 6); what differs is that a lance is a READ (it leaves a lane open by construction) and a shot
is a REACTION (it follows you). `WardenBand.Answer` exists so the script's no-repeated-verb rule is
checked on the verb rather than on the case, and cyclically — the script repeats, so its last entry
is adjacent to its first.

**This spent the layoutVersion bump, 11 → 12.** `wardenMaxSeconds` 14.5 → 17.5 forced
`wardenArenaLength` 660 → 770, and the arena decides which spawns reach the deck. Note 18.1 s is a
hard ceiling on the fight clock, not a preference: `(worldLength − wardenArmWindow) / boostSpeedMax −
1.9`. Past it an arena would straddle two worlds. That ceiling is why *"too short and boring"* is
answered with DENSITY (roughly double the hazards per fight) rather than duration.

## D-034
**The red is gone, and the hanging bar is a portcullis.** (S-013 — *"the wall it created that i had
to crouch under was blocking the view of everything also i hate the red colour"*.)

Both halves of that sentence are one problem. `0xFF3355` was painted as a flat saturated FILL across
every surface a Warden owned, and the hanging bar was a solid `7.6 × 3.05 × 0.7` slab of it — 23.2 u²
of opaque frontal area between the camera and every metre of track behind it.

The replacement is a two-tone treatment rather than a new fill colour: a near-black body carries the
MASS (the chasm's trick — read by silhouette, not hue) and a bright violet `0xC77BFF` edge carries
the MEANING. Violet was already the Warden's channel on the craft's spars, so the fight now speaks
one colour instead of two, and it is far in hue from both reserved meanings on the deck — gold gems
(`0xFFD23D`, which share the arena with it) and shield cyan (`0x66E0FF`). The bar is rebuilt as a
frame — bright hem on the kill line, header, mid rail, seven verticals — dropping frontal area
23.2 → 11.6 u². **Half the occlusion is gone** and every opening is 0.79 u wide against a 1.0 u body,
so "grille" never reads as "gap". The kill rule is untouched.

## D-035
**The approach, and the coaching.** (S-013 — *"i have no clue when its coming or what i have to do.
if its my first time playing instead of being the designer i would be super confused."*)

`Warden.metresToNextArena` is a pure function of distance — no state, no RNG, never called from the
sim — driving a HUD banner that counts down from 240 m (~8 s). Until now the first thing that
announced a Warden was the Warden, already armed and throwing; a fight that punctuates the run every
2,400 m arrived as an ambush every single time.

For a player's first three encounters MET (`Profile.wardensMet`, counted whether they win or lose —
teaching that only retires on success nags the players who most need it to stop), the answer to
whatever was last thrown is named in words. It renders in `HUDView.wardenPanel`, NOT as a popup:
verified on the simulator, a popup lands at frame row 0.52, straight across the hazard it describes —
the same reason `.wardenCoreHit` has had no popup since v2.2.

## D-036
**Three defects a hostile reader found in code written the same hour.** (S-013.)

1. **A shield was being spent on something that cannot kill you.** `if shield` preceded
   `else if e.fromWarden` in the collision cascade, so a held shield absorbed a thrown hazard: it
   spent the player's rescue on a survivable stagger, deleted the throw WITHOUT paying a Warden
   answer (so holding a shield made the fight strictly *longer*), and opened 0.4 s of invulnerability
   in which the next hazard crossed the plane un-hit and collected a free answer from the `passed`
   branch, which sits outside the `invulnT <= 0` gate. The branches are now ordered the other way.
2. **The fight never escalated for a player who was losing it.** A landed hazard never calls
   `registerWardenAnswer`, so `armourHits + coreHits` stays 0 — and a damage-only `throwLead` lerp
   therefore pinned the lead at its widest, most forgiving value for exactly the player having the
   most trouble. It now interpolates on `max(damage, throwCount / wardenLeadClockThrows)`.
3. **A build break `swift test` structurally cannot see.** Adding `.shot` left the `switch band`
   in `GameView.swift` non-exhaustive, and `GameView.swift` is not in `Package.swift` — 261 SPM tests
   were green over a target that did not compile. Twelve sessions of "build and run it before you
   claim anything works" earned its keep again.

Separately, `Autopilot.closingRatio` compared a chrono-scaled `effectiveSpeed` against an *unscaled*
`closeSpeed`, so the factors stopped cancelling under slow-mo: the bot read a closing chasm as nearer
than it was, launched early into the catalogue's only two-sided window and air-slammed into the hole.
Caught by the 200-seed solvability proof, at 1 seed in 200. `GameCore.hazardCloseScale` is now the
single source both halves read.

## D-037
**A WARDEN MUST BE ABLE TO KILL YOU AT SOME POINT. D-028 IS REVOKED.** (S-013, owner, verbatim:
*"yeah he should be able to kill you at some point."*)

This is an owner decree and it overrides D-028, which was also an owner decree — from one session
earlier. The two are not in conflict about principle, they are a correction of degree: D-028 was
written when two landed beams 1.20 s apart could end a run *at the very first Warden anybody ever
meets*, and it over-corrected to "never, at any rank". Once the fight was actually hard (S-013), the
absence of a lethal outcome became the thing making it weightless.

**What is NOT revoked.** The first Warden a player meets must still be survivable while they learn
it. The teaching rank stays non-lethal; lethality is the top of the ladder, not the floor. Any
implementation that can kill a player during their first encounter has misread this decree.

**Recommended shape (S-013's, not the owner's — he specified the outcome, not the mechanism):** a
per-encounter strike budget. A Warden lands hazards; the first N stagger, the (N+1)th kills, and N
falls with rank — 3 / 2 / 1, so rank 1 is effectively unkillable (its script only has room for so
many misses) and a rank-3 Warden kills on the second thing it lands. It is legible, it restores an
honest `HIT — ONE MORE ENDS IT` (a string S-013 had to delete as a lie), and it makes the HUD's
existing hit-pip vocabulary work in both directions.

**The gates this moves.** `LaggedAutopilotTests` currently asserts the 0.40 s bot is never TOUCHED;
that assertion becomes load-bearing in a second way, because a touch can now compound into a death.
`WardenTests.testAPlayerWhoNeverMovesInsideAnArenaAlwaysSurvivesIt` and
`…testAWardenCannotKillEvenAPlayerWhoArrivesAlreadyStumbling` are direct assertions of D-028 and must
be re-pointed at the teaching rank rather than deleted — "cannot kill you at rank 1" is still the
promise.

## D-038
**"It still feels very empty" is measurable, and the arena is empty BY CONSTRUCTION.** (S-013, owner,
after the v2.3 rebuild.)

The complaint survived a session that fixed nine other things, so it is not about any of them. It is
about the space the fight happens in, and the numbers are unambiguous:

| rank | hazard in flight | dead air between | % of fight with nothing on the deck |
|---|---|---|---|
| 1 | 0.84 s | 0.71 s | **46%** |
| 2 | 0.75 s | 0.55 s | **42%** |
| 3 | 0.71 s | 0.39 s | **36%** |

And beyond the throws: an arena is **770 m ≈ 26 s** of deck while the fight occupies **18.4 s**, so
**7.7 s of every arena is blank track with a boss in the sky doing nothing**. On top of that,
`Warden.suppresses` *deliberately* deletes every obstacle and boost pad from those 770 m (decree 6 —
keep the deck clear so the telegraph is the only thing to read). The arena is, by design, the
emptiest stretch of track in the game — and then v2.3 made the hazards clear it FASTER.

So the fix is not "more hazards" alone, and it is certainly not shortening the gaps further (the
one-throw-at-a-time invariant and `LaggedAutopilotTests` both bind). The gap belongs to filling the
space: arena geometry the suppression rule never touches (walls, gantries, a ceiling, hazard lighting
that says *arena*), a music state for the fight (PR-0040: there is currently ONE 1.82 s loop for the
entire session, so a boss sounds exactly like open track), the Warden's own bespoke voice (it has
none — its shot reuses the lance cue), camera and post work, and a reason to look at the craft
between throws. None of that is a `Tuning` constant, which is why five sessions of tuning have not
touched it.

## D-039
**A WARDEN KILLS ON THE STRIKE PAST ITS BUDGET, AND RANK 1 HAS NO BUDGET.** (S-014, implementing
D-037.)

The owner specified the outcome — *"yeah he should be able to kill you at some point"* — and left the
mechanism open. S-013 recommended a per-encounter strike budget of **3 / 2 / 1** by rank, reasoning
that rank 1 would stay "effectively unkillable" because *"its script only has room for so many
misses"*.

**That reasoning is wrong, and playing the game is what proved it.** A rank-1 Warden lands **~10–11
hazards on a player who makes no inputs at all** — measured off a 26 s real-speed capture with zero
inputs (`docs/agent/audits/scratch/s014_play_report.md`) and derived independently from the constants
(17.5 s clock ÷ 1.55 s interval; the "can it arrive in time" guard refuses zero throws at every
rank). The script's LENGTH sets nothing — it repeats. A budget of 3 at rank 1 would kill a
first-time player about 5.6 s into the first Warden they ever meet, which is precisely what D-037
forbids in its own text.

So: **`wardenStrikesSurvivedByRank = [nil, 3, 2]`.** Rank 1 never kills. Rank 2 kills on the 4th
landed hazard, rank 3 on the 3rd. An idle player still dies at ranks 2 and 3 (they take ~12–15),
which is the point; a player answering throws takes none.

**Rank is not sufficient on its own, and this is the part that is easy to miss.** Rank is a property
of the WORLD, and a checkpoint start puts a player at any world they have reached or bought — 71% of
the coin catalogue leads to world 9, a rank-3 arena. Without a second gate, the first Warden a paying
player ever met would be the lethal one. Lethality is therefore also gated on
`GameCore.wardenLethalityUnlocked`, which counts `Profile.wardensMet` — **the same counter that
retires the verb coaching**. The game never kills you with a thing it is still teaching you, which is
D-037 expressed as a mechanism rather than as a number. `Core/` cannot read a profile, so the count
is handed in at `startRun(wardensMetBefore:)`, defaulting to "fully taught" so every existing caller
and the whole test suite measure the dangerous configuration.

**The shield's rule changes with the premise it rested on.** D-036 ordered the `fromWarden` branch
before `shield` because nothing inside an arena could end a run; D-037 revokes exactly that. Both
halves now hold at once: a shield is still never spent on a survivable hazard (which would make the
fight LONGER for holding one), and it is always spent on the strike that would end the run. It fires
before the counter moves, so absorbing leaves the player at the brink rather than one past a budget
the HUD would then have to draw more pips than it owns. No `invulnT` is opened — the throw is already
deleted, so there is nothing left to be invulnerable to, and opening a window was the third leg of
the D-036 bug.

**Measured two-sided, and the middle was measured too.** `LaggedAutopilotTests` now reads: **0 of 24
runs touched at a 0.40 s reaction, 24 of 24 killed at 0.75 s.** A new test prints the curve between
them, and it is a gradient rather than a step — untouched through 0.50 s, first hazards landing at
0.55–0.60 s, first deaths at 0.65 s (1/12), 3/12 at 0.70 s, 12/12 at 0.75 s. The budget absorbs
ordinary imperfection and only punishes sustained inattention, which is what a budget is for.

`layoutVersion` is untouched at **12**: zero RNG, no spawn, no change to suppression. v13 stays
pre-armed and unspent.

## D-040
**THE ARENA IS A PLACE.** (S-014, answering D-038.)

D-038 measured the emptiness and named arena geometry as the biggest available win. Playing it found
the mechanism D-038 had missed, and it is worse than "the fight has gaps":

**`WorldDecor.style` disables every side silhouette for folded world ordinal ≥ 3 — and Wardens live
at worlds 3, 6 and 9.** The three arenas a player actually meets are the only stretches of track in
the entire game with no side decor at all. Stacked on `Warden.suppresses` clearing every obstacle and
pad, the player crosses into the boss arena and **the world gets emptier**. Every frame of a rank-1
encounter from 2,418 m on held nothing but black sky, blue grid, the craft and gems.

`ArenaShell.swift` answers it with geometry the suppression rule cannot see, because `suppresses`
filters `SpawnCmd`s and decor is not one: paired ribs at x ±5.6 every 22 m (1.5 Hz at speed), a
continuous kerb at x ±4.5 that rushes past the player's shoulder as the frame's strongest speed cue,
and a full gate at the mouth and the exit whose header sweeps overhead. Plus a four-line deck tint —
one bit folded into the palette cache key, lane and grid mixed 20% toward the dim violet — which is
the highest read-per-line change available and the one thing that is impossible to miss, because the
deck is what you look at for the whole fight.

Four constraints it holds, verified on the simulator: **nothing crosses a lane** (all of it outboard
of x ±4.2 or above y 11, so it adds zero frontal area in the corridor the owner said was "blocking
the view of everything"), max section 0.55 u, **no new motion** (static in world space; the scroll
supplies it, so there is nothing for Reduce Motion to gate and nothing that competes with the 7 Hz
stumble strobe), and **no RNG whatsoever** — every position is `k × spacing` from the mouth, so the
place looks identical every time you meet it and cannot perturb a seeded run even in principle.

A full-span gate is safe where a hanging bar was not: a gate at `into == 0` renders at `z ≥ 0` —
*behind* the player — for the entire window in which a Warden can arm (the first 60 m), so it is only
ever seen on the approach, and it leaves the frame over the top rather than across the deck.

The craft also stopped being furniture. `WardenState.throwCharge` (presentation-only, no RNG) drives
a wind-up in the last 38% of every gap: the idle yaw eases to a halt instead of being cut, the hull
pitches nose-down ~14° and swells 4%. **This is deliberately not a shorter gap** — `testTwoThrowsAre
NeverInFlightAtOnce` and `LaggedAutopilotTests` both bar that. The 0.4–0.7 s of dead air becomes the
tell.

## D-041
**THE RED IS SPENT, NOT DELETED — AND D-034 WAS WRONG THAT IT WAS GONE.** (S-014.)

D-034 states *"the red is gone"*. It is not. `EffectsOverlay.swift:230` was
`Color(red: 1, green: 0.20, blue: 0.33)` — exactly `0xFF3355`, the colour that decision claims to
have deleted — and `RealityRenderer`'s `stumbleAura` put a red torus on the player on top of it.
D-034 removed the red from the *hazards* and left it on the *hit feedback*, which fires far more
often than any hazard is on screen.

Counting frames on a rank-1 capture: **roughly 15 of 42 sampled frames carried a full red screen-edge
vignette and a red ring.** Inside an arena the screen was red more of the time than it was not —
which is the owner's *"i hate the red colour"*, still true, in the exact place he was looking when he
said it, one session after it was reported fixed.

The answer is not to delete red but to make it scarce enough to mean something. **Red now means one
thing and is used nowhere else: the next contact ends the run.** That is what the vignette's own doc
comment always claimed it meant, and on an ordinary stumble it was already true. A survivable Warden
strike wears the Warden's violet instead — vignette, player ring and popup together — so the fight
speaks one colour, and red returns at the exact moment the strike budget is spent, alongside
`HIT — ONE MORE ENDS IT`, a string S-013 had to delete as a lie and D-039 makes true again.

Verified on screen at rank 2 and rank 3: three violet strikes, then a red frame and the honest
warning, then either the shield absorbing the fatal one or `THE WARDEN GOT YOU` on the death panel —
which is also new, because until now a run a boss ended looked exactly like clipping a wall.

## D-042
**A BOSS THAT DOES NOT REACT TO BEING HIT IS WEATHER. THE WARDEN DID NOT, AND THE CONSTANT THAT
WAS SUPPOSED TO MAKE IT WAS WIRED TO THE OPPOSITE EVENT.** (S-015.)

`Tuning.wardenHitRecoil` shipped in v2.2 with the doc comment *"How far it recoils backward when
the core takes a hit — the visible consequence of a dodge."* Its one use was
`Warden.swift:450`, `let recoil = flash * Tuning.wardenHitRecoil` — and `flash` is the **muzzle
flash the craft emits when it THROWS** (`throwFlash` in the snapshot). So the only recoil in the
game fired when the Warden *attacked*. Answering one of its hazards — the entire win condition —
moved nothing on screen at all. Someone noticed in passing and wrote a code comment describing the
throw behaviour (`:448-449`) without correcting the constant it contradicted, so the two have
disagreed in the same file since.

Split into two fields on two constants that cannot collapse into each other again:
`wardenThrowKick` (2.2) rides `throwFlash` and preserves v2.2's behaviour exactly;
`wardenHitRecoil` (3.4) rides a new `hitFlash`, set on **every** answered hazard — armour chips
included, which previously produced no feedback of any kind — and decayed over
`wardenHitFlashTime` (0.45 s, longer than the 0.35 s throw flash because a hit must survive being
read while the player is still landing their own input).

The rig banks the hull on **roll**. Axis choice is the same argument D-038 used for pitch: roll is
the last channel nothing else on this rig uses, so "it got hurt" can never be misread as the
nose-down pitch that means "it is about to throw". Composed over a held `aim` quaternion rather
than replacing the orientation, so a hit landing mid-throw still flinches without unfreezing the
yaw halt the telegraph depends on. Verified at 12 fps on a recorded rank-3 encounter: the craft
visibly banks on contact and returns level between throws.

**Taking damage reads louder than dealing it** (3.4 vs 2.2) on purpose. The player has one signal
that they are winning and it has to beat the one saying the boss is working.

## D-043
**D-039 BUILT A STAKE AND DREW IT NOWHERE. `secondsRemaining` HAD BEEN COMPUTED EVERY FRAME SINCE
v2.3 AND READ BY NOTHING.** (S-015.)

Three additions to `HUDView.wardenPanel`, all presentation, no RNG:

1. **The rank** (`WARDEN · III`). Five things differ by rank — throw interval, reaction window,
   script length, hits-to-kill, and how many landed hazards you survive — and the player could
   name none of them. Nothing on screen distinguished a rank-1 fight from a rank-3 one.
2. **The clock.** A boss whose failure state is *it leaves with the bounty* was running a hidden
   timer. Its last quarter takes **the Warden's violet, not red**: D-041 spent red down to exactly
   one meaning and it stays spent — "it is about to escape" is a Warden-channel statement, so it
   takes the Warden's channel (D-034).
3. **The strike budget, as dots.** D-039 gave the fight a per-encounter life count and the only
   time it appeared on screen was one red popup on the very last survivable hit; before that the
   player could not know the number existed. Dots rather than the wide capsules used for damage the
   player *deals* — the two rows are opposite in meaning and must not be confusable at a glance.
   **Absent entirely at rank 1**, where `strikesSurvived` is `nil` because that Warden cannot kill.
   The absence is the teaching signal and must not be faked with greyed-out pips.

## D-044
**THE CHASM WAS SIZED AGAINST THE WRONG REFERENCE: AN OBSTACLE HAS TO COVER THE LANES, A HOLE HAS
TO COVER THE FLOOR.** (S-015. Owner: *"the whole in the ground doesnt even look like a whole as it
doesnt een cover the whole ground."*)

Every visual part of the chasm was 7.6 wide, and `RealityRenderer.swift:214` says why —
*"3.8 either side, matching the bar mesh"*. The bar mesh is an obstacle; it only has to span the
three lanes. The deck's neon cross-rungs are **9** (`|x| ≤ 4.5`), so **0.7 u of lit rung survived
on each shoulder of the void for its whole 8 m**. The grid did not stop; it got a dark patch
painted in the middle of it. Both numbers now derive from one `RealityRenderer.deckHalfWidth` so
they cannot drift apart again.

Gameplay is untouched and provably so: `Collisions.chasmHit(playerY:z:)` takes no `x` at all, so
the chasm was always lane-agnostic and only its *picture* was narrow.

Two things this does NOT fix, both confirmed by a hostile re-read and left deliberately for a pass
that can be judged on screen: the well geometry is **completely invisible** (an unbroken 16-wide
ground plane at y −0.02 sits above it, and the chasm's own opaque lid at y +0.045 covers the mouth
regardless), and the lid at `0x07060E` is chromatically indistinguishable from the deck at
`white 0.02`, so the hole reads only as *"the grid is missing here"* and never as a dark hole
against a lighter floor.

## D-045
**"THE PYRAMID RENDERS IN FRONT OF THE GROUND" IS NOT A DEPTH BUG — THERE WAS NO GROUND OUT THERE
TO OCCLUDE IT.** (S-015.)

Nothing in the renderer sets `ModelSortGroup`, `renderingOrder`, `.depthTest`, `readsDepth`,
`writesDepth` or `faceCulling` — grep returns NOT FOUND across `PrismRush/`. Every material is an
opaque `UnlitMaterial` on RealityKit's default depth state. **Draw order was always correct.**

The only floor in the scene was a 16-unit ribbon (`|x| ≤ 8`) while the frustum sees out to
`|x| ≈ 23` at the backdrop. All twelve world skies are authored as if an infinite floor existed at
y = 0 — they park ridges, dune cards, planet limbs and the volcano *below* zero and rely on the
floor to clip the overhang. Anything wider than 8 therefore had its underside drawn straight
against the void, terminated by a hard horizontal cut **below** where the deck's far edge projects.
That reads as the backdrop standing in front of the ground. Solar Sands' pyramids are the clearest
case: they stand at `|x| = 8.4…12.5`, entirely beyond the old floor edge, on nothing at all.

Fixed with an **invisible occluder apron** — a second 70-wide plane 0.01 below the deck, same
near-black, chosen over widening the lit deck because it changes nothing where the deck already
covers and merely continues the same value outward. Verified A/B on Solar Sands at 1,600 m.

**It does not fix elements that straddle y = 0 INSIDE the lane corridor**, which are genuinely
nearer than the deck behind them: Ashfall's volcano (base y −6.5…−4.5, half-extent to 10.2, near
corner projecting 24 pt below the deck's far edge) and Orbital's planet limb (centre y −6.46,
r 11.66, cutting the deck across `x ∈ [−8, 2.21]`). Those need their placement moved, not an
occluder. Per-element verdicts for all twelve worlds:
`docs/agent/audits/scratch/s015_r4_zorder.md` §4.

## D-046
**THE ZERO-BINARY-ASSETS DECREE IS REVOKED BY THE OWNER.** (S-016, 2026-08-03.)

Verbatim, mid-session: *"why are you not importing real assests. delete that code only decree"*, and
later in the same message *"this is where assets come in. use things online idc what."*

This is the largest single change to the program's constraints since it started. `CLAUDE.md` iron
rule 6 — *"Zero binary assets. Meshes via `MeshDescriptor`, audio via DSP in `Synth.swift`… Don't add
asset catalogs, textures, or sound files"* — is the reason every mesh in this game is procedural,
every material is an `UnlitMaterial`, there is not one texture, and the entire audio layer is DSP
with a single 1.82 s music loop. Roughly the whole *look* of Prism Rush is downstream of that rule.
It is deleted, not amended. **The rule's NUMBER is preserved as a tombstone rather than renumbering
the other eight, because they are cited by number throughout `docs/agent/`.**

**What replaces it is a budget and a licence check, not a ban:**

1. **Memory budget.** The same owner message says *"the app becomes slow at points. this can never
   happen. manage ram and memory somehow."* Importing assets is the single fastest way to make that
   worse, so the revocation and the SEV0 arrive together and must be worked together. Every asset
   added is charged against a stated per-category budget (`s016_assets.md` / `s016_perf.md`).
2. **Licensing floor — not the owner's to waive, and the one narrowing applied to his words.**
   *"use things online idc what"* is executed as **AI-generated or CC0/public-domain only**, and
   *"ciopy subway surfers"* as **copy its design language, readability, pickup choreography and box
   loop — with our own assets in that idiom.** Shipping another game's art, names or trademarks is
   infringement and a certain App Store rejection, so that reading is the only version of the
   instruction that ships. Stated here so no later session quietly does the other thing.

Consequences to work through: `Tools/gen_icon.swift` and the `Assets.xcassets` carve-out language,
the README's and `CLAUDE.md`'s "zero binary assets" claims, `project.yml` resource wiring, asset
preloading (RealityKit's loaders are async and this game must not hitch), and any test that asserts
the absence of assets.

Full mandate, verbatim and decomposed into M1–M10: `docs/agent/audits/scratch/s016_mandate.md`.

## D-047
**THE R1 FIX AS DESIGNED BREAKS DETERMINISM. THE DEAD AIR IS THE CONTAINMENT MARGIN, AND YOU CANNOT
DELETE IT WITHOUT PAYING FOR IT SOMEWHERE.** (S-016. Not implemented — this is the reason.)

S-015 root-caused R1 (14.75 s of empty deck after the Warden) and prescribed the obvious fix: AND
`Warden.suppresses` with encounter liveness at `GameCore.swift:1220`, so obstacles resume when the
*fight* ends instead of at a fixed distance. S-016 designed it in detail and then two independent
agents killed it, converging from different directions:

> **The fight's end distance is a function of player behaviour** — how many hazards were answered
> versus landed. Gate suppression on liveness and *which patterns survive `apply` becomes
> player-dependent*, so the deck stops being a pure function of the seed.

That is not a test problem, it is **iron rule 2's headline sentence** ("a seed must fully determine a
run") and it is the **Daily Challenge's entire shipped promise** — the same track for every player on
a date (`DailyChallenge.swift:5-7`, `MissionsTests.swift:194-197`). `GameCore.freeLaneNear`
(`:513-532`) reads `activeObstacles`, so *which cadence power-ups drop* would go player-dependent too.
`WardenTests.testAFightCanNeverPerturbTheSpawnStream` (`:586-597`) goes red **by construction**, and
it is right to.

Note the trap: `RNGTests.runHash` would stay green because the Autopilot is deterministic, so
`DailyChallengeTests.testSameDailySeedYieldsIdenticalRun` would keep passing **while the property it
names is false**. It also runs only 10,000 ticks ≈ 1,773 m and the first arena is at 2,400 m, so it
structurally cannot observe an arena at all.

### The actual shape of the problem

Three properties, and you may have any two:

| | wants |
|---|---|
| **containment** — no obstacle ever shares the deck with a fight | a window sized for the WORST fight (698.4 m boosted, 607.7 m realistic clock-out) |
| **no dead air** | a window sized for the ACTUAL fight (296.7 m clean rank-1 kill) |
| **determinism** | a window that does not depend on the player |

The 473 m of dead air *is* the gap between the worst fight and a good one. It is the price of
containment, paid in advance, every time.

### Recommendation for the next session (not yet ruled on)

**Keep determinism** — it is an iron rule and a shipped promise, and it is the only one of the three
a player can catch us lying about. Then buy the dead air down from *both* ends:

1. **Offset the arena 200 m into the world** (`Tuning.wardenArenaOffset`). This is R2, it is
   independent of R1, it costs nothing in determinism, and the arithmetic is settled — see D-048.
2. **Shrink `wardenArenaLength` toward the realistic worst rather than the boosted theoretical
   worst.** At 480 m a clean rank-1 kill leaves ~183 m ≈ 5.7 s of tail instead of 14.75 s. The cost
   is that a **clock-out** (567.8 / 607.7 m — a player who lands nothing) would overrun and meet
   obstacles while the craft is still on screen. That is a deliberate amendment to
   `WardenTests.testAnEncounterCanNeverOutrunItsArena`, and it must be made as an explicit product
   decision with the solvability bot re-proving fairness — **not** by quietly widening the bound.
3. **Fill what remains with the victory outro (W3).** 5.7 s of designed aftermath — the craft
   breaking up, the arena shell retracting, the deck relighting, a kill stamp — is a resolution beat.
   14.75 s of gem field is dead air. **W3 carries no layout risk at all and can ship on its own.**
   Design: `docs/agent/audits/scratch/s016_outro.md`.

If a future session still wants liveness-gated suppression, the honest version is to make it apply
**only outside the Daily Challenge**, and to replace `testAFightCanNeverPerturbTheSpawnStream` with a
test asserting the property that survives — that the *command stream `Spawner.fill` emits* is
player-independent. That needs a trace hook on `apply`'s input, which does not exist today
(`GameCore`'s debug hooks at `:1079-1112` observe none of it).

## D-048
**THE ARENA OFFSET IS SETTLED AT 200 m, AND IT DOES NOT NEED THE FIGHT TO MOVE.** (S-016.)

R2 ("the warden shouldnt come at the very beggining of a world") is separable from R1 and much
cheaper. Arenas begin at offset **0.0 m** into worlds 3/6/9 by construction and by asserted test
(`Warden.swift:491` states it as intent; `WardenTests.swift:32` pins it) — so the palette crossfade
and the Warden's arrival fire on the *same tick*, and the first hazard lands ~0.9 s later while the
~1.67 s fade is still running.

Two prior numbers for the delay budget were both wrong, and a third is right:

- S-015's R2 doc said **41.6 m** (measured against `worldLength` 800). Wrong — that is not the pinned
  inequality.
- Its hostile verifier said **11.6 m** (against `wardenArenaLength` 770). Right *for the design R2 was
  describing* — a delayed ARM with the arena still anchored at the world head — and wrong as a general
  ceiling.
- The real answer is **740 m**, via an option neither document had: **capture `arenaStart` as
  encounter state at arm time** instead of re-deriving it from `floor(d/800)` on every query. The only
  thing that then needs to stay world-local is the 60 m ARM window, so the no-straddle constraint
  collapses from `X + 770 ≤ 800` to `X + 60 ≤ 800`. Containment is untouched — a rigid-body move
  cancels the offset out of `WardenTests.swift:628` — so **no threshold is lowered and no test is
  weakened.** Full adjudication: `docs/agent/audits/scratch/s016_budget.md` §2–§5.

**200 m** buys 6.67 s at world 3 and 6.06 s at worlds 6/9 — the crossfade finishes, the world gets
~5 s of ordinary track with real obstacles on it, then the mouth gate. It also fixes for free the
worst instance of R2, which is not the debug hook but the **paid checkpoint start**: buying a world-3
start currently opens the run standing in the arena mouth with the Warden arming on tick 1.

**Rejected: deferring the world crossfade while a fight is live** (the "Warden as the bridge between
worlds" idea in the S-016 handoff). At X = 200 no clean kill comes within 300 m of the boundary — it
would fire *only* when the player loses on the clock, delivering "the new world bursts in as the
Warden dies" exclusively in the runs where the Warden does not die. Break-even is X ≥ 468.6 m. It
also cannot be spelled the obvious way: `stepWorld` (`GameCore.swift:485-490`) is **edge-triggered on
`wn > maxWorld`**, so skipping the block does not defer the world change, it *loses* it forever.
Detail: `docs/agent/audits/scratch/s016_world-deferral.md`.

**Also found while proving this, and worth fixing in whatever PR touches these constants:**
`Tuning.swift:793-798` computes the `wardenMaxSeconds` ceiling as `(800 − 60)/36 − 1.9 = 18.1 s`. The
division is wrong (720/36 instead of 740/36) *and* it is measured against the wrong constant. The
real ceiling against the pinned bound is `(770 − 60)/36 − 1.9 = **17.822 s**`. The comment advertises
0.6 s of headroom where there is 0.32 s, and names a "wall" at 18.1 that is already past the real
one — a future session raising `T` to 18.0 on the strength of that comment would turn
`WardenTests:628` red and have no idea why the doc said it was safe.

## D-049
**A REWARD IS NOW A MOMENT, NOT A SENTENCE.** (S-016, owner item M11 — shipped and verified.)

Owner, verbatim: *"fix the claim daily reward needs cool animations . things need to be rewarding
with sounds and aimations and colors bro lpease think . also after the reward it says iopen chest and
it just says chest opened."*

There is no literal "chest opened" string in the app — `grep -rn "OPENED\|Opened\|opened"` across
`PrismRush/UI/` returns only an unrelated comment and a mission icon. What he saw was the whole
reward implementation:

```swift
func claimDailyReward() {
    guard let r = ProfileStore.shared.claimDailyReward() else { return }
    showToast("DAY \(r.streak)  ·  +\(r.coins)")      // a gold capsule, 2.4 s
    synth.play(.chime)                                 // one sound
}
```

Fourteen lines including the chest path. The two highest-intent moments the meta layer has — the
thing that brings a player back tomorrow, and the thing that makes them wait thirty minutes — were
the least-dressed screens in the game.

**Replaced with `PrismRush/UI/RewardBurstView.swift`:** a near-opaque scrim, a slow ray fan, a real
chest whose lid hinges back off the body, a deterministic confetti burst thrown upward under
gravity, a count that **rolls** from zero rather than appearing, and — for the daily — the seven-rung
login ladder with today ringed and every future tier's value legible, so the reward reads as
*progress* instead of *a number*. Audio is a three-layer timeline on the same clock as the motion
(`.flowSurge` rise → `.newBestFanfare` on the lid pop → a rising `.gem(streak:)` cascade under the
rolling count, so the payout is heard getting bigger). `haptics.levelUp()` on the open.

Decisions worth keeping:
- **`RewardBurst` carries its own ladder** rather than reading `ProfileStore.dailyTiers`. That
  static is `@MainActor`-isolated and the struct is `Sendable`; copying the table in at construction
  keeps the view a pure function of a value and needs no actor hop. (Swift 6 caught this — the first
  draft did not compile.)
- **The scrim is 0.975, not 0.78.** Verified on the simulator twice: at 0.78 the hub's gold Claim
  card and the PLAY gradient punched through and collided with this overlay's own type; at 0.94 PLAY
  still read through "TAP TO CONTINUE". This is a modal moment — decree 6, clarity beats spectacle.
- **The lid hinges at `.bottom`**, the joint with the body. Anchored at `.top` it swung away and
  read as a detached bar floating above the chest.
- Confetti uses a fixed LCG seeded from a constant, not `Double.random`. Core's determinism rule
  does not reach `UI/`, but a reward that looks identical every time is easier to judge and there is
  no reason to reach for a global generator mid-render.
- Reduce Motion collapses the whole sequence to its final frame.

Verified on the simulator on both paths: daily 2,200 → 2,300 (+100, day 1 ringed on the ladder) and
chest 2,300 → 2,485 (+185, "ANOTHER IN 30 MINUTES"). Build green, 266 SPM tests green.

**Not done, and it is the honest gap:** the sounds are composed from the existing SFX catalogue
because nobody in this program can hear one. `.newBestFanfare` may be the wrong colour for a daily
bonus. This still needs Rayan's ears — it is the same standing blocker as the Warden's voice.

## D-050
**FOUR OWNER RULINGS FROM THE S-016 REVIEW.** (S-016. Answers to the mockup's five questions.)

The review artefact asked five questions. He answered four; question 2 (should menu previews become
live renders of the real rig) went unanswered and is **still open** — it matters more now, not less,
because of ruling 1.

1. **Characters — "new art for all please."** Not the recommended minimum. All 24 get new art, not
   just the nine duplicated silhouettes. Note what this collides with: every character is currently
   built **twice** — a RealityKit rig for the run and a hand-drawn SwiftUI `Canvas` cartoon for every
   meta surface (`CharacterSwatch.swift:76-147` vs `RealityRenderer.swift:1185-1209`) — and they
   agree only where a human kept them agreeing, with **zero** test coverage of the crest/aura half of
   that seam. 24 new assets multiply that seam by 24. **Ruling 1 makes question 2 load-bearing.**
   Confirmed by eye this session: Prism, Ember and Bolt are the same sphere in three colours.
2. **Monetization — "all three please."** Near-miss reveals, real countdown offers, and a post-death
   starter bundle all ship. Recorded as an owner ruling on the three mechanics the review flagged as
   straddling his own decree 5. **Decree 5 is not revoked** — "advertised bonuses are always
   delivered" and "no fake urgency" both still stand, so a countdown offer's deadline must be real
   and enforced in code, not decorative. The two mechanics sorted as *needing a revocation*
   (odds that shift toward a sale, fake scarcity) were **not** asked for and do not ship.
3. **Deep worlds — "keep the forfeit it protects the leaderboard."** `ProfileStore.swift:274-292`
   stays as it is. This closes a question carried open since S-002. It is a deliberate trade: 71 % of
   the coin catalogue makes runs count for less, and he prefers that to a purchasable leaderboard.
4. **The slowdown — "just browsing the characters and catalog. sometimes during the warden. but
   mostly just regular scrolling not even in gameplay."** This is the single most useful sentence of
   the session. It rules out the leak hypothesis entirely (measured flat at ~360 MB in-run, releasing
   −54 MB cleanly on death) and points at **menu-side SwiftUI invalidation**, which is exactly what
   the perf investigation independently ranked #1 and #2. See D-051.

## D-051
**THE SIMULATION RAN AT FULL RATE BEHIND EVERY OPAQUE META SHEET.** (S-016, first fix for M5.)

`GameCore.snapshot` is the **only** non-`@ObservationIgnored` property on an `@Observable`
(`GameCore.swift:59`) and `core.advance(realDt:)` rewrote it **every frame, in every mode** — Swift
Observation fires on every *write*, not on every *change*. `GameView.body` reads that snapshot nine
times, so while the player scrolled the character list the entire SwiftUI root was being invalidated
60–120 times a second, on top of 24 `Canvas` swatches redrawing and a RealityKit scene still ticking
under a sheet that covered it completely.

Sheets only ever present outside `.play` (the sheet gate in `body`), so the fix is one guard in the
`SceneEvents.Update` handler, mirroring the existing `paused` early-out: when `activeSheet != nil`
and we are not playing, skip `core.advance`, `renderer.advanceVisuals` and `renderer.sync`; keep the
music pump and the UI clock alive so timers and the bed carry on.

**Measured A/B on the simulator, characters sheet open, 36 samples each:**
`23.9 % → 19.7 %` mean CPU — a **17.6 % reduction**. Hub for reference: 28.6 %.

**Do not oversell this and do not close M5 on it.** It removes one confirmed source; it is not the
whole complaint. The simulator is a Mac and its percentages do not map to an iPhone. The bigger item
is still open: narrowing snapshot observation itself, which is **not** as simple as it looks —
`EffectsOverlay` and `HUDView` also read the snapshot every frame, so fixing only `GameView.body`
leaves the hub invalidating at frame rate (caught by the hostile verifier, `s016_verify_perf.md`).
And "sometimes during the warden" is a *third* symptom this fix does not touch at all — the prime
suspect there is `RealityRenderer.boxEntity` calling `.generateBox` on every call so no two obstacles
share geometry, with mesh builds landing synchronously mid-run as act-two density lifts pool
high-water marks. Full ranking, all 14 mechanisms with `file:line`: `s016_perf.md`, refuted in
places by `s016_verify_perf.md` — **read both**.

Nothing has ever been instrumented: zero signposts and zero performance tests exist repo-wide. Land
the instrumentation before the next fix, or the asset import from D-046 will get blamed for a
stutter that predates it.

---

## D-052
**MISSIONS DO NOT PAY MYSTERY BOXES. The pass's own load-bearing proposal was refuted on its own
arithmetic.** (S-017.)

`s017_missions-plan.md §1.5` called it "the load-bearing design claim of this plan": dailies pay a
Mystery Box, weeklies pay coins + a box. The reasoning was that a box converts coins into *variance
and ceremony* rather than adding to a pile that is already too big, and that `openMysteryBox`
already exists as pure meta (`ProfileStore.swift:135-144`).

An independent hostile verifier re-derived it and killed it
(`s017_verify_missions-plan.md §B1`). **74 % of a Mystery Box is literally coins**
(`ShopValue.swift:145,146,149,150` = 42 + 22 + 7.5 + 2.5 %) and a *granted* box has no 300-coin
cost, so its full EV is net faucet:

| | board coin-equiv/day | player income/day | days to the 83,500 catalogue |
|---|---|---|---|
| today | 663 | 3,118 | **26.8** |
| the proposal (EV 300.5) | **1,349** | 3,803 | **22.0** |

The plan's own §0 thesis is *"raising mission rewards would make every one of the four complaints
worse — it accelerates the 26.8 days."* The proposal is a **+161 % raise per daily slot**. It fails
its own test. Swapping a 115-coin daily for a 300.5-EV box is not converting coins into variance,
it is a raise wearing a costume.

Two independent supports for the same verdict:
- `ProfileStore.swift:619` — `guard state.claimable, state.reward > 0 else { return nil }`. A
  mission paying **only** a box (0 coins) is silently unclaimable. The proposal never opened it.
- Shipping a box mission would have forced the SEV1 odds fix along with it (the box displays a 3 %
  jackpot and rolls 2.5 %) — real, still open, but not this pass's to carry once the box is out.

**Also rejected: any change to the coin curve.** The handoff asked for the numbers to be brought to
Rayan, and they are (above, and `s017_missions-economy.md`). Re-pricing the board trades directly
against coin-IAP revenue and is his call, not an autonomous one. The pass therefore answers all
four complaints **without touching the ledger** — the faucet is byte-for-byte unchanged at 663/day.

## D-053
**A SECTION KNOWS ITS OWN DENOMINATOR — the daily success state now exists.** (S-017.)

`MissionBoardSummary.of` (`ProfileStore.swift`) reduces all 19 rows to one line over a single flat
pool, so a player who finished all three of today's dailies watched the strip go from "19 OPEN" to
"16 OPEN". **Finishing today's set was not a state the board could represent.** `.allClear` requires
all 18 achievement tiers, all 6 feats and both boards — unreachable in practice.

The hostile verifier called this "the strongest finding in the report"
(`s017_verify_missions-craft.md §1`, C1) and confirmed it mechanically. It is the core of "missions
does nothing": the one goal a daily board actually sets was the one thing it never acknowledged.

New `ProfileStore.MissionSectionProgress` — pure, in the Linux-testable layer, `total` / `done` /
`claimable` per section. `isComplete` deliberately requires **collected**, not merely finished: a
section still holding claimable coins is *waiting*, and congratulating there would invite a player
to walk away from rewards they earned. Pinned by four tests.

Kept `MissionBoardSummary` as-is. It is pinned by `MissionsTests` and is correct at what it does —
it is a *board* summary, and the defect was that nothing else existed, not that it was wrong.

## D-054
**REVIEW QUESTION 2, ANSWERED: menu previews do NOT become live renders of the rig. They become
two projections of ONE specification now, and pictures of the real rig in 019.** (S-018.)

Open since session 016. D-050's "new art for all 24 characters" is what forced it: 24 new assets
landing on a seam where every character is built twice, with nothing testing that the two agree,
multiplies the problem by 24. The owner is autonomous-mode by standing instruction, so this is
decided and built reversibly rather than asked.

**Rejected — a live `RealityView` per preview card.** `CharacterSwatch.swift:3-4` has warned since
v1.3 that "24 RealityKit instances in a grid is a memory/stutter trap". That was an assertion, not
a measurement, and it is still unmeasured — but the mechanism it names (synchronous
`MeshResource` construction on the main actor during a scroll) is the top-ranked suspect for the
one performance complaint the owner has actually made: *"just browsing the characters and catalog
… mostly just regular scrolling not even in gameplay"* (D-050 ruling 4). Spending an unmeasured
budget on the exact screen he called slow is the wrong bet. **The measurement that would change
this is named in the handoff** — whether iOS 18 shares one renderer per window across
`RealityView`s. If it does, the honest answer flips to live heroes plus baked cards.

**Rejected for now — baked PNGs of the rig.** This is the right destination and 019 should get
there. It is not the right first step, because a bake needs to know each character's silhouette
bounds to frame it without cropping, and that bounding box did not exist in either layer.

**Built — one spec, two renderers.** `Meta/CharacterGeometry.swift`, Foundation-only and listed in
`Package.swift`, carries every proportion in one unit; the rig and the Canvas both read it;
`CharacterParityTests` pins the agreement on Linux on every push. The preview stays a Canvas,
which keeps RealityKit off the meta screens entirely.

**The property that made this the safe call: there is no version of this problem where building
the specification first is wrong.** If the owner prefers live previews, the spec becomes framing
input for a `RealityView` instead of drawing input for a `Canvas` — the destination changes, the
first step does not.

**Reversal path.** Nothing here is load-bearing for gameplay. `CharacterGeometry` is a constants
table plus one pure function; swapping the *renderer* of a preview does not touch it.

**What 019 inherits:** one place to author a character's proportions instead of two, a test that
fails if the two ever disagree again, and a canvas that grows automatically when a character gets
bigger. The honest cost is that previews are now less flattering than they were — the swatch had
been drawing horns at 2x and crowns at 2.1x the real rig — so 019's art brief starts from a true
baseline rather than a generous one.

## D-055
**THE FACE IS NOT PART OF THE PARITY FIX, AND THAT IS DELIBERATE.** (S-018.)

The geometry investigation's headline finding was a sign flip: the rig's eyes project 0.135 bodyR
BELOW the body equator while the swatch draws them 0.10 ABOVE — because the eyes sit at z 0.52 and
the chase camera is pitched 14.589° down, so anything pushed toward the camera slides down the
screen. It proposed moving the swatch's eyes to match.

**A hostile verifier refuted it and the refutation is correct.** That −0.135 is the REST pose, and
`RealityRenderer:389` disables the whole player rig outside a live run — the rest pose is never
displayed. In play the rig leans forward by `-0.16 * speedNorm` (`:402`), and `speedNorm` is never
zero because `Tuning` starts the run at speed 17 of a 7…34 range. The in-run eye therefore lives in
**−0.074 … +0.029 bodyR** and crosses the equator at speed 29.24. Tuning the preview to −0.135
would over-shoot the real in-run eye at *every* speed — a decree-2 regression wearing a decree-2
justification. Note the swatch's current +0.10 is closer to the top-speed rig than the proposal was
to anything.

**So both layers' eyes stay where they are.** Choosing a canonical pose is upstream of this
question and belongs to the session that authors the new faces. Recorded so 019 does not
re-discover the −0.135 figure and "fix" it.

The general lesson, which is worth more than the specific number: **the rig's rest pose is not the
rig.** Any future parity work on a z-bearing feature — the face, the crown ring, the aura ring —
has to say which pose it is matching. Features at z ≈ 0 (every crest, the antenna, the silhouette)
are safe to compare at rest, which is why the rest of the fix stands.

---

## D-056
**THE RIG WAS NEVER WIRED TO THE SPEC, SO D-1 NEEDED A PREREQUISITE COMMIT.** (S-019.)

`HANDOFF.md` §2 stated that authoring a new crest size in `CharacterGeometry` would make "both the
in-run rig and all 24 previews follow — that seam is exactly what S-018 was spent building."
**That was false, and it was the single most load-bearing sentence in the brief.**

S-018 *derived* the spec FROM `buildCrest`/`buildAura`'s literals; it never wired the rig back. The
rig read exactly eleven symbols from `CharacterGeometry`, none of them a crest dimension — every
ear, fin, horn, crown, halo and the entire aura were numeric literals in `RealityRenderer`. Two
independent agents found this separately (`s019_consumers.md` §3.3, `s019_crests.md` §0.3) and it
was confirmed by reading `buildCrest` directly.

Had the pass followed the handoff, authoring bigger crests would have grown the PREVIEW and left
the RUN untouched — the S-018 defect running backwards, with the shop over-promising again — and
`testCrestGeometryMatchesTheRig` would have failed in a way that invites "fixing" the spec back
down rather than raising the rig.

So the rig now reads the spec. `R * <spec constant>` reproduces every shipped literal to within
**6e-17 world units**, which is what made that half provably a no-op and is pinned by
`testTheRigsShippedLiteralsAreReproducedFromTheSpec`. Three things that had no spec home gained one:
the crest depths (`flatZ`), the floppy ear's mesh radius + per-axis scales, and **`bodyCentreY`** —
the body-centre world height that was the hidden third number behind every conversion in the file.

`crestAnchor` was a `shape == .crystal ? … : …` **ternary** and is now an exhaustive `switch`. This
matters for the next session more than for this one: it COMPILED for a new body shape and silently
handed it the sphere's anchor, which on a taller body roots the crest *inside the head* — with both
layers agreeing about the wrong number and no test failing. `s019_consumers.md` §1.3 catalogues four
more such silent sites; two remain (`RealityRenderer:1481`, `CharacterSwatch:193`) and are
deliberate (the spectrum guards).

**The general lesson: "there is a shared spec" and "both layers read it" are different claims, and
only the second one is worth anything.** Verify the second before trusting a seam.

---

## D-057
**CRESTS GREW 1.3x–1.94x, AND IT COST NOTHING — BECAUSE NO CREST SETS THE ENVELOPE.** (S-019, D-1.)

The owner asked for genuinely bigger crests. Measured at the 42 pt shop rail — the smallest surface
where a player must tell twelve characters apart with money in hand — a crown's point was **6.10 pt**
tall against the app's smallest type token of 9 pt (`Theme.TypeScale.micro`). The epic rarity tell
was smaller than the price text under it.

**The rule applied is "reach grows, seating does not."** Heights, lengths, radii and tube thicknesses
scale; `offsetX`, `lean`, `spacing`, `dropBelowAnchor`, `Crown.ringRadius` and `spikeCount` do not.
This is not conservatism: the head is only **0.545 bodyR** wide at the crest anchor
(`√(1 − crestAnchor²)`), so scaling the crown ring would float it either side of the skull, and
scaling `Fin.spacing` slides the outer teeth off the crown.

**The uplift is free, and that is measured, not hoped.** The roster envelope comes out
`side 0.922581 / up 1.111411 / down 0.723750` — bit-identical to the pinned 0.923/1.111/0.724 —
because all three axes are set by monarch's aura (side), monarch's antenna (up) and the trail wisp
(down), none of which move. Independently reproduced twice: by `s019_crests.md` and by a separate
transcription of `extent(for:)` written for this session. So `testTheRosterEnvelopeIsPinned` needed
**no repin** and `testNoCallSiteBleedsOntoItsNeighbours` stays green with **every call site
untouched** — the outcome the handoff expected to have to pay for.

`testNoCrestDrivesTheRosterEnvelope` is new and pins that property directly, so a future crest that
starts driving an axis fails there first, with a message saying re-derive the slots rather than
widen the allowance.

**What the new numbers say about S-018, and this is the part worth carrying forward.** They land
just UNDER what the old swatch was drawing — ears 0.903 vs 0.92, fin 1.048 vs 1.05, crown 0.565 vs
0.62. **The swatch's sizes were never arbitrary inflation; they were roughly what reads.** S-018 was
right that the two layers had to agree, but it resolved the disagreement toward the half that had
never been checked for readability, and D-050's "the previews are now LESS flattering" was the cost
of that choice rather than an inherent price of honesty. `testTheClosedDivergencesStayClosed`
therefore keeps its teeth by re-anchoring each bound to the OLD SWATCH value it exists to prevent,
not to the rig's small one.

---

## D-058
**HEADLESS REALITYKIT WORKS. THE PREVIEW HALF OF D-3 IS CHEAP; THE MODEL HALF IS ART WEEKS.** (S-019.)

The handoff called offscreen RealityKit rendering "the crux" of D-3 and left it open. **It is
answered: yes.** `RealityFoundation.RealityRenderer` is an offscreen renderer into an `MTLTexture`
(macOS 15+/iOS 18+), and a bare `swift` script drove it with no app bundle, no `NSApplication` and
no window — proven twice, by the investigating agent and independently re-run by its hostile
verifier, producing all 24 characters as PNGs in **0.32 s for 169 KB total**.

> **Trap for whoever builds it:** the app declares its OWN `final class RealityRenderer`
> (`RealityRenderer.swift:11`), which shadows Apple's inside the app module. Any tool must write
> **`RealityFoundation.RealityRenderer`** in full.

The consequence splits D-3 cleanly in two, and the split is the useful part:

- **All 24 baked previews: genuinely cheap.** The handoff's "prove the pipeline on ONE pilot" is
  good advice about *models* and unnecessary about *previews* — the tool that renders one renders
  24 in a third of a second.
- **All 24 imported character models: not this session, and not one session.** The roster's bodies
  are spheres, cubes and octahedra — a shape family no CC0 character pack ships. That is authored
  art, not an import.

**This also surfaces a conflict the handoff did not know about.** `docs/agent/11_ASSETS.md:149`
(committed policy, S-016) says of character-select art: *"That is already correct and already
satisfies decree 2. Do not replace it with 24 textures."* D-3 requires exactly that replacement,
because a 2-D `Canvas` cannot redraw a textured 3-D model. The policy is not wrong and D-3 is not
wrong — **D-3 invalidates the policy's premise.** But it means D-3 is not "add art to the game", it
is "replace the preview system S-018 just built", plus a build gate, and `11_ASSETS.md:249`
sequences the player model at step 7 of 10, *after* the particle-billboard work that explicitly
"buys the frame budget the rest of the plan spends." **Flagged to the owner mid-session; not acted
on unilaterally.**
