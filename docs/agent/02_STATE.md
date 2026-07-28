# State — the single source of truth for right now

> Rewritten every session. If this file and any other file disagree about a fact, **this file
> wins** and the other file gets fixed. That includes `state.md` and `README.md` at the repo root,
> which are the project's human-facing history, not the agent's source of truth.

- **Last written by:** session 004 (2026-07-28) — the second act + risk-priced gems
- **Program phase:** audits 2 of 7 done, and the phase gate is gone (D-005) — audits and fixes now
  interleave. S-004 was a pure fix session; no audit ran.
- **Next session:** 005 — **PR-0452, the hub redesign. Rayan asked for it directly.** See `HANDOFF.md`.
- **Code changed by the program so far:** PR-0411 (S-003 + S-004 residue), **PR-0400, PR-0414,
  PR-0445, PR-0451 (S-004)**. The game's simulation has now been changed, not just its copy.
- **`DailyChallenge.layoutVersion` is 8** as of S-004. Every daily track changed; that is expected
  and is what a layout bump means.
- **The read-only phase is over (D-005).** Sessions may now fix code as they go. The audit sequence
  continues because it is producing real findings, not because a rule requires it.
- **Rayan's standing instruction (2026-07-28):** *"never be limited by arbitrary rules — just work
  however you think is best."* `01_RULES.md` was cut from ~290 lines of ceremony to ~180, split into
  judgment (advisory) and nine invariants (damage prevention). Read D-005 before reinstating any
  process.
- **Direction:** submission IS the goal, timing is open. **Polish first, publish at the end.** So
  design/feel work (`05_GAME_DESIGN.md`) outranks the compliance pass in priority; AUDIT-003 still
  runs, but its findings are a pre-submission checklist, not the next thing to fix.

---

## Where the project actually is

Prism Rush is a **v1.6, feature-complete, technically strong iPhone game that has never been
submitted to the App Store.** 95 Swift files, ~22,300 lines, zero third-party dependencies, zero
binary assets except the generated app icon.

What is genuinely solid, and session 002 did not dent it:
- The deterministic core is real. Fixed 1/120 s timestep, seeded SplitMix64, a 200-seed solvability
  bot plus a 12,000 m soak, golden-pinned daily-challenge seeds. `RendererPort` is clean.
- **187 SPM tests pass in ~24 s, re-measured by session 004 at `9766e7d`, zero failures.** The
  jump from 178 is S-004's `DifficultyCurveTests` (5) and four new gates in `DifficultyTests`. The
  runtime grew because the difficulty instrument plays 64 seeded Autopilot runs to 9,600 m.
- Zero `TODO` / `FIXME` / `HACK` / `XXX` / `fatalError` in 95 files. Re-verified, still true.
- All 12 world families render distinctly, verified on device. Character previews are internally
  truthful (hero and swatch move in exact lockstep).

**Session 002's one-sentence verdict: the app is built but not finished — 50 of 59 user-facing
features are fully implemented and exactly one is outright absent, yet only 13 of 59 clear the
owner's own six decrees, and every failure state in the app is unfinished in the same way.**

**Session 003's one-sentence verdict: the app is also not designed past two minutes — the
difficulty curve, the speed ramp and the pattern catalogue are all exhausted by 3,200 m, after
which nothing in the simulation ever changes again, and none of the 83,500 coins of permanent
sink buys anything that alters play.** Measured on device: five consecutive 10 s intervals at
33.5–33.7 m/s with a flat score rate. The design bible this project never had is now
`docs/agent/05_GAME_DESIGN.md`; read it before touching tuning, economy or progression.

**Session 004 fixed the first half of that.** There is now an *act two*: past 3,200 m the pattern
mix sheds its breather beats in three front-loaded waves, the gap keeps closing 5 → 4, the moving
walls swing off centre so the safe lane must be read rather than remembered, and a second gem line
is hung in a lane each pattern closes so greed and survival stop being the same input. Measured
(`DifficultyCurveTests`, 64 seeds): obstacles/100 m **6.02 → 7.63 (+27%)**, Autopilot inputs/100 m
**3.93 → 4.44 (+13%)**, obstacle-free track **27.1% → 12.4%**, gems priced in risk **0.7% → 14.6%**.
v1.6 was flat in every one of those columns across the whole 3,000–8,000 m range.

**What S-004 did NOT fix, and said so:** the catalogue is still 14 patterns (**PR-0450**) — act two
changes how often you meet things, not what things exist. And **the coin sink still buys nothing
that alters play** (PR-0401); that half of S-003's verdict stands untouched.

## The three things that should worry you most

1. **Every failure state fails identically.** Store not loaded, not enough coins, empty mission
   board, signed out of Game Center, audio failed to start, nothing to restore, a purchase awaiting
   parental approval — each is raw, silent, or actively misleading. The happy path is polished; the
   moment anything is not normal, the app stops being finished. **The good news: the correct pattern
   already exists in the codebase** (the Worlds `UnlockPanel` and the revive offer both show
   `NEED N MORE` + a route to coins). Most of Phase 3 is "use the pattern you already wrote."
2. **25 of 59 features have no automated test, and the green build conceals it.** `swift test`
   compiles none of `UI/`, `Render/`, `IAP/`, `SynthEngine`, StoreKit or GameKit;
   `CharacterParityTests.swift` is `#if canImport(UIKit)`-gated and silently compiles to nothing
   there. The whole interactive surface is 6 XCUITests in one file. Every session-002 finding lives
   in exactly the region the suite cannot see — that is the mechanism, not a coincidence.
3. **The game runs out of design at 3,200 m** (PR-0400, session 003). Last new pattern at 1,920 m,
   speed cap at 3,077 m, density cap at 3,200 m — verified in source and measured on device by four
   independent lenses. Every endgame structure (the infinite world ladder, 13,400-coin deep rungs,
   the leaderboard, the 12,000 m soak) rests on distance being an axis of challenge. Past 3,200 m it
   is an axis of patience. The fix seam already exists: `Spawner.maxIndex` gates by prefix index.
4. **The docs are confidently wrong in the files agents read first.** `CLAUDE.md` is wrong on four
   load-bearing facts. `Store/metadata.md` sells a three-world game and the ship docs say to paste it
   verbatim into App Store Connect (PR-0010). The README claims 12 bespoke skies (9 exist) and
   per-world music that an owner decree deliberately disabled. A chain of sessions inheriting wrong
   memory compounds it.

## Backlog summary

| Severity | Session 001 | + Session 002 | + Session 003 | Total |
|---|---:|---:|---:|---:|
| SEV0 (conditional, unproven) | 1 | 0 | 0 | 1 |
| SEV1 | 14 | 2 | 7 | 23 |
| SEV2 | 40 | 17 | 21 | 78 |
| SEV3 | 123 | 5 | 18 | 146 |
| SEV4 | 3 | 0 | 0 | 3 |
| **Total** | **181 (+5 addendum = 186)** | **24** | **46** | **256** |

Session 004 added three (`PR-0450` SEV2, `PR-0451` SEV3, `PR-0452` SEV2) and closed five
(`PR-0400`, `PR-0414`, `PR-0445`, `PR-0451`, and the `PR-0411` repo-side residue) → **259 items,
6 DONE.**

Session 003's 46 items are `PR-0400 … PR-0445`. **124 findings were raised, 92 survived an
independent hostile verifier, 32 were killed, and 34 severities were downgraded in review** — the
severities above are post-review. `PR-0416 … PR-0444` are filed compact (see the note beside them);
expand to the full block before working one.

Session 002's 24 items are `PR-0300 … PR-0323`. **Every one survived at least one adversarial
verifier whose explicit job was to refute it.** Session 002 also re-scored or refuted seven
session-001 items rather than re-filing them — see `audits/AUDIT_002_completeness.md` §5 and the
re-scores table at the end of `03_BACKLOG.md`. **Read those before working any session-001 item.**

Six audits remain unrun. Expect further promotions, demotions and merges. Session 009 triages.

---

## Completeness Ledger

**Owned by AUDIT-001 (session 002). Permanent. Update as work lands.**

Columns, defined so a future session scores identically:

- **Impl** — the code exists and does what the feature's name promises.
- **Reach** — a player can get to it in a shipped build, without a launch hook or a debugger.
- **Test** — a real automated test exercises it. `swift test` compiles **only** `Core/`, seven
  `Meta/` files and `Audio/Synth.swift`. `CharacterParityTests.swift` is `#if canImport(UIKit)`-gated
  and counts only inside the Xcode bundle. The entire UI surface has **6 XCUITests, in one file**.
- **Polish** — meets the six owner decrees. Strictest column; where the app is weakest.

`✅` holds · `⚠️` partial · `❌` fails · `—` n/a

| # | Feature | Impl | Reach | Test | Polish | Note |
|---|---|---|---|---|---|---|
| **CORE RUN** |
| 1 | Three-lane run: jump / slide / lane change | ✅ | ✅ | ✅ | ✅ | |
| 2 | Deterministic fixed-timestep sim | ✅ | ✅ | ✅ | ✅ | |
| 3 | Procedural track, 14-pattern catalogue | ✅ | ✅ | ✅ | ✅ | 200-seed bot + 12 km soak |
| 4 | Death + collision | ✅ | ✅ | ✅ | ⚠️ | legibility is AUDIT-004's |
| 5 | CLOSE / SLICK near-miss bonuses | ✅ | ✅ | ✅ | ❌ | PR-0291: `+50` popups stack 5 deep, illegible |
| 6 | Flow / multiplier | ✅ | ✅ | ✅ | ⚠️ | chip vanishes unexplained |
| 7 | Coins + gems | ✅ | ✅ | ✅ | ✅ | |
| 8 | Score + personal best | ✅ | ✅ | ✅ | ✅ | |
| 9 | Run duration (`timeSurvived`) | ✅ | ❌ | ❌ | ❌ | PR-0131 — accumulated every frame, plumbed to `GameOverView`, rendered nowhere |
| 10 | Checkpoint / play-from-world | ✅ | ✅ | ⚠️ | ⚠️ | works on device; PR-0319 latent `% 3` |
| 11 | Revive / CONTINUE | ✅ | ✅ | ⚠️ | ❌ | PR-0307 — post-revive play counts for stats, not progression |
| 12 | Daily Challenge / Daily Rush | ✅ | ✅ | ✅ | ⚠️ | voids armed loadout chips silently |
| 13 | Autopilot attract mode | ✅ | ✅ | ✅ | ✅ | |
| **POWER-UPS** |
| 14 | Slow-Mo | ✅ | ✅ | ✅ | ⚠️ | near-field art washes the button out |
| 15 | Speed Up | ✅ | ✅ | ✅ | ⚠️ | as above |
| 16 | Shield | ✅ | ✅ | ✅ | ⚠️ | PR-0292 |
| 17 | Head Start | ✅ | ✅ | ✅ | ❌ | reads ARMED in Daily Rush, is voided, nothing says so |
| 18 | Coin Surge | ✅ | ✅ | ✅ | ❌ | as above |
| 19 | Magnet | ✅ | ✅ | ✅ | ❌ | nothing in the app teaches it |
| 20 | Double Coins (IAP perk) | ✅ | ⚠️ | ✅ | ⚠️ | reachable only when StoreKit is `.ready` |
| **WORLDS** |
| 21 | 12 world families | ✅ | ✅ | ✅ | ✅ | all 12 verified distinct on device |
| 22 | Bespoke sky per world | ⚠️ | ✅ | ❌ | ⚠️ | 9 bespoke + 3 legacy inline; README claims 12 |
| 23 | Side-of-track decor per world | ⚠️ | ✅ | ❌ | ⚠️ | suppressed for folded index ≥ 3 → 9 of 12 have none |
| 24 | World unlock by distance | ✅ | ✅ | ✅ | ✅ | |
| 25 | World unlock by coins | ✅ | ✅ | ✅ | ✅ | **the app's best shortfall state — copy this one** |
| 26 | Ladder past 12 ("Pulse City II"…) | ✅ | ✅ | ⚠️ | ⚠️ | real art + evolved palette; whether to *label* a reskin as a new world is AUDIT-002's |
| **CHARACTERS** |
| 27 | 24 characters, distinct identities | ✅ | ✅ | ⚠️ | ⚠️ | `CharacterParityTests` does not run under `swift test` |
| 28 | Equip | ✅ | ✅ | ✅ | ✅ | |
| 29 | Buy with coins | ✅ | ✅ | ✅ | ❌ | zero-coin case is a silent shake (cf. row 25) |
| 30 | Buy with real money (Aurora) | ✅ | ⚠️ | ❌ | ❌ | PR-0160 — priced via a hardcoded `auroraID` |
| 31 | Achievement-gated characters | ✅ | ⚠️ | ⚠️ | ❌ | PR-0318 — bar reads 100%, skin stays locked |
| 32 | Previews match in-game (decree 2) | ⚠️ | ✅ | ❌ | ❌ | PR-0312 — swatches crop crests/antennae; aura ring clips everywhere |
| **PROGRESSION** |
| 33 | XP + levels | ✅ | ✅ | ✅ | ⚠️ | in-run bar previews 2 of 5 XP terms |
| 34 | Missions (daily/weekly/challenges) | ✅ | ✅ | ✅ | ❌ | PR-0304 — "ALL CLEAR" on a 0/N board at first launch |
| 35 | Achievements | ✅ | ✅ | ✅ | ⚠️ | |
| 36 | Mission claim / CLAIM ALL | ✅ | ✅ | ✅ | ⚠️ | mutates + persists the profile from inside `body` |
| 37 | Free chest / rewards rail | ✅ | ✅ | ⚠️ | ⚠️ | reward **is** delivered (0→100 verified); mini-sheet's CLAIM never renders |
| 38 | Stats / Profile screen | ✅ | ✅ | ❌ | ⚠️ | empty state is genuinely good; PR-0322 is not |
| 39 | Streaks | ✅ | ✅ | ✅ | ⚠️ | never explained in the app |
| **STORE** |
| 40 | 4 coin packs | ✅ | ⚠️ | ✅ | ❌ | PR-0306 — 7 USD prices at full opacity, all inert |
| 41 | Starter Bundle | ✅ | ⚠️ | ✅ | ❌ | PR-0316 — one of five products claiming one bonus |
| 42 | Mystery Box (gacha) | ✅ | ✅ | ⚠️ | ❌ | **odds ARE disclosed, sum to 100% — PR-0293 refuted.** PR-0302 + PR-0303 |
| 43 | Coin-spend power-up packs | ✅ | ✅ | ✅ | ⚠️ | "not enough coins" toast is an unreachable `else` |
| 44 | Restore Purchases | ✅ | ✅ | ❌ | ❌ | PR-0308 — reports success having restored nothing |
| 45 | Shop FEATURED rotation | ✅ | ✅ | ❌ | ⚠️ | hero priority 3 by documented design; content also reachable in the characters rail |
| **PLATFORM** |
| 46 | Game Center — `prismrush.best` | ✅ | ⚠️ | ❌ | ⚠️ | opens friends-first |
| 47 | Game Center — `prismrush.daily` | ✅ | ❌ | ❌ | ❌ | PR-0310 — advertised 4×, no in-app viewer |
| 48 | iCloud save sync | ⚠️ | ✅ | ⚠️ | ❌ | PR-0300 / PR-0005 — cold launch discards the local profile |
| 49 | Sign in with Apple | ✅ | ✅ | ❌ | ❌ | PR-0309 — completes, changes nothing |
| 50 | Account deletion | ❌ | ❌ | ❌ | ❌ | **the one outright-absent feature.** Required because row 49 exists. PR-0008 |
| 51 | Settings (volumes, haptics, reduce-flash) | ✅ | ✅ | ❌ | ⚠️ | |
| 52 | Mute / unmute | ✅ | ⚠️ | ❌ | ❌ | PR-0305 — only unmute is the in-run corner control; mute persists |
| 53 | How to Play / first-run gate | ✅ | ✅ | ⚠️ | ⚠️ | **corrected S-003:** teaches ~17 concepts over 5 pages, and PLAY routes into it on a true first launch. The defect is the shape, not the coverage — all text, pre-run, never in context (PR-0402) |
| 54 | Power-Ups reference catalog | ✅ | ✅ | ❌ | ⚠️ | PR-0317 — different icons than the hub |
| 55 | Splash | ✅ | ✅ | ❌ | ✅ | does not auto-dismiss, by design |
| 56 | Music | ✅ | ✅ | ✅ | ⚠️ | **pinned to world 0 by explicit owner decree — the other 11 beds are intentionally unreachable. The defect is that the README still sells them** |
| 57 | SFX | ✅ | ✅ | ⚠️ | ⚠️ | PR-0320 — 4 "rising whoosh" SFX decay instead of swelling |
| 58 | Haptics | ✅ | ✅ | ❌ | — | needs a device |
| 59 | Pause | ✅ | ✅ | ⚠️ | ⚠️ | PR-0130 — session-summary block is dead code (HUD still visible behind the veil) |

**Session 003 amendments to this Ledger** (the Ledger stays owned by AUDIT-001; these are
corrections of fact, not re-scores): row 53 above. Row 9 (`timeSurvived`) confirmed on device —
the death panel shows `72m · World 1` and `0 close calls` and no duration. Row 56 (music) confirmed
as an owner decree, not a defect. Row 26 (the ladder past 12) is now ruled on in
`05_GAME_DESIGN.md §6`: **compliant but weak** — "II" does real work so it does not lie, but it
dresses repetition as progression.

### Roll-up

| Column | ✅ | ⚠️ | ❌ |
|---|---:|---:|---:|
| Implemented | 50 | 8 | 1 |
| Reachable | 45 | 8 | 6 |
| Tested | 24 | 10 | 25 |
| **Polished** | **13** | **26** | **20** |

---

## Phased roadmap

Provisional. **Session 009 rewrites this** with all seven audits visible.

| Phase | Content | Rough size |
|---|---|---|
| Phase A | Scaffold + map (session 001) | ✅ done |
| Phase B | Seven adversarial audits (002–008) | **1 of 7 done** |
| Phase C0 | Triage (session 009) | 1 session |
| Phase 1 | `ProfileStore` merge rework — PR-0002/0003/0005/0250/0252/0253/0282/0283 **+ PR-0300** | 2–4 sessions |
| Phase 2 | Ship blockers — PR-0007/0008/0009/0010/0004/0034 **+ PR-0301**, plus AUDIT-003 | 3–5 sessions |
| Phase 3 | **Completeness — the failure-state sweep.** PR-0302/0304/0305/0306/0308/0311/0314/0315 are one coherent job: make every non-happy state use the pattern rows 25 and 11 already contain | 4–6 sessions |
| Phase 4 | Fun and retention — AUDIT-002's output | 5–8 sessions |
| Phase 5 | Polish, Dynamic Type, accessibility, perf, docs | 5–8 sessions |

## Needs Rayan on a device

Carried forward every session until done.

- **PR-0400 / PR-0414 — does act two FEEL right?** This is the one that most needs his thumbs.
  The change is verified deterministic, fair (bot green) and measurably escalating, but "measurably
  escalating" and "fun" are different claims and only a human can make the second. Specifically:
  is the 3,200 m step noticeable? Do the swung moving walls past ~6,800 m read, or do they feel
  cheap? Is the greed line legible at speed — can you *see* the two coin lines diverge in time to
  choose? Is the choice worth making, or is the safe line obviously correct?
- **PR-0452 — the hub redesign he asked for in S-004.** Direction is a taste call and his to make;
  the item lists candidate directions but does not pick one.
- ~~PR-0296 / PR-0445 — attract-track bleed-through~~ — **DONE (S-004).** Ruled on in D-008,
  implemented as a lower-third scrim, verified by clean-launch before/after screenshots kept in
  `docs/agent/scratch/s004/`. Worth 10 seconds of his eyes to confirm the taste call was right.
- PR-0024 — do camera/pose lerps land the same on 60 Hz and 120 Hz hardware?
- PR-0025, PR-0260 — Instruments allocation and idle-battery traces.
- PR-0026, PR-0047 — tap-to-jump latency, bottom-corner swipe dead zones.
- PR-0037, PR-0038, PR-0039, PR-0256 — background audio, interruption recovery, launch mute.
- PR-0043 — VoiceOver slider persistence.
- Every HUMAN GATE in `docs/SHIP_CHECKLIST.md`.

**Highest-value unblock:** a StoreKit configuration session. Six SEV2 findings sit behind it
(PR-0306 and the ask-to-buy / restore / unverified-transaction cluster) and none can be closed
without it.

Device gotcha, still true: this repo lives under iCloud-synced `~/Desktop`, so codesigned builds
need a `-derivedDataPath` **outside** the synced tree. Sim builds are fine.

## Open questions for Rayan

Carried in `HANDOFF.md` until answered. **Question 5 was resolved by session 001; question 6 is new.**

1. **Is App Store submission still the goal, and on what timescale?** Everything in Phase 2 is
   priced against "yes, soon."
2. **PR-0254 — should a run that used a paid revive be leaderboard-eligible?** Iron rule 10 says yes
   by omission. Product call. **Session 002 sharpens this:** PR-0307 shows post-revive play does not
   count for missions or XP — so a revived run is currently *partly* counted, which is the worst of
   both answers. **Session 003 rules:** revived runs should count for missions and XP and be
   **leaderboard-ineligible** — exactly the rule checkpoint runs already follow. One line of policy
   instead of two half-answers. Needs your yes/no.
3. **PR-0040 — the music is a 1.82 s loop for the whole session.** Design change, needs sign-off.
4. **PR-0052 — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?**
6. **PR-0411 — "Earn 2× coins, forever" under-delivers on a paid product.** Filed SEV1 by session
   003 after surviving verification (raised as SEV0, cut in review). This is decree 5 —
   "advertised bonuses are always delivered" — on real money. Worth your eyes before Phase 2.
7. **PR-0414 is a reversal request, not a bug.** "Coins are the path" (`Spawner.swift:49-52`) was a
   deliberate v1.6 change of yours; it is also the reason routing has no decision in it. You cannot
   have both a guaranteed-safe coin line and a greed-vs-survival tension. Pick one knowingly.
5. ~~Mystery Box real money?~~ **Resolved (S-001): 300 coins, not real money.** Session 002 further
   confirms the odds are disclosed and sum to 100%, so 3.1.1's requirement is met today.
6. **NEW — PR-0296: is the attract track showing through the hub cards the intended neon look?**
   One yes/no unblocks it permanently, in either direction.

## Program hygiene

- `docs/agent/scratch/` and `docs/agent/audits/scratch/` are **gitignored** and now hold ~1.5 MB:
  session 001's 537 KB survey, session 002's ~600 KB, and session 003's ~450 KB of 10 finder +
  10 verifier files. **They will not survive a fresh clone.** The committed audit files summarise
  them but do not contain them. Session 003 carried sessions 001–002's scratch across worktrees by
  hand (`cp -R`, since git will not move gitignored files) — **the next session must do the same or
  the whole chain's working detail is lost.**
- Recovery tags: `pre-s001`, `pre-s002`, `pre-s003` exist locally.
- This worktree is `.claude/worktrees/prism-rush-design-audit-562d27` on branch
  `claude/prism-rush-design-audit-562d27`. It was created from `main` and **reset onto session
  002's tip `e7f7841`** at session start. `main` still does not contain `docs/agent/` at all —
  **session 004 must branch from session 003's tip, never from `main`**, and must copy both scratch
  directories across if it works in a new worktree.
