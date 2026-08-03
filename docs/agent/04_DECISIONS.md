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
