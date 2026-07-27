# State — the single source of truth for right now

> Rewritten every session. If this file and any other file disagree about a fact, **this file
> wins** and the other file gets fixed. That includes `state.md` and `README.md` at the repo root,
> which are the project's human-facing history, not the agent's source of truth.

- **Last written by:** session 002 (2026-07-27) — AUDIT-001, The Completeness Auditor
- **Program phase:** Phase B (adversarial audits), **1 of 7 done**. Sessions 003–008 remain.
- **Next session:** 003 — AUDIT-002, The Game Designer
- **Code changed by the program so far:** none. Sessions 001–009 are read-only by design.

---

## Where the project actually is

Prism Rush is a **v1.6, feature-complete, technically strong iPhone game that has never been
submitted to the App Store.** 95 Swift files, ~22,300 lines, zero third-party dependencies, zero
binary assets except the generated app icon.

What is genuinely solid, and session 002 did not dent it:
- The deterministic core is real. Fixed 1/120 s timestep, seeded SplitMix64, a 200-seed solvability
  bot plus a 12,000 m soak, golden-pinned daily-challenge seeds. `RendererPort` is clean.
- **178 SPM tests pass in 8.85 s, re-measured this session at `dc2be8d`, zero failures.**
- Zero `TODO` / `FIXME` / `HACK` / `XXX` / `fatalError` in 95 files. Re-verified, still true.
- All 12 world families render distinctly, verified on device. Character previews are internally
  truthful (hero and swatch move in exact lockstep).

**Session 002's one-sentence verdict: the app is built but not finished — 50 of 59 user-facing
features are fully implemented and exactly one is outright absent, yet only 13 of 59 clear the
owner's own six decrees, and every failure state in the app is unfinished in the same way.**

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
3. **The docs are confidently wrong in the files agents read first.** `CLAUDE.md` is wrong on four
   load-bearing facts. `Store/metadata.md` sells a three-world game and the ship docs say to paste it
   verbatim into App Store Connect (PR-0010). The README claims 12 bespoke skies (9 exist) and
   per-world music that an owner decree deliberately disabled. A chain of sessions inheriting wrong
   memory compounds it.

## Backlog summary

| Severity | Session 001 | + Session 002 | Total |
|---|---:|---:|---:|
| SEV0 (conditional, unproven) | 1 | 0 | 1 |
| SEV1 | 14 | 2 | 16 |
| SEV2 | 40 | 17 | 57 |
| SEV3 | 123 | 5 | 128 |
| SEV4 | 3 | 0 | 3 |
| **Total** | **181 (+5 addendum = 186)** | **24** | **210** |

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
| 53 | How to Play / first-run gate | ✅ | ✅ | ⚠️ | ⚠️ | teaches 3 of ~8 mechanics |
| 54 | Power-Ups reference catalog | ✅ | ✅ | ❌ | ⚠️ | PR-0317 — different icons than the hub |
| 55 | Splash | ✅ | ✅ | ❌ | ✅ | does not auto-dismiss, by design |
| 56 | Music | ✅ | ✅ | ✅ | ⚠️ | **pinned to world 0 by explicit owner decree — the other 11 beds are intentionally unreachable. The defect is that the README still sells them** |
| 57 | SFX | ✅ | ✅ | ⚠️ | ⚠️ | PR-0320 — 4 "rising whoosh" SFX decay instead of swelling |
| 58 | Haptics | ✅ | ✅ | ❌ | — | needs a device |
| 59 | Pause | ✅ | ✅ | ⚠️ | ⚠️ | PR-0130 — session-summary block is dead code (HUD still visible behind the veil) |

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

- PR-0296 — **is the attract-track bleed-through through the hub cards intended?** Session 002
  quantified it (a full-width magenta band sweeps y = 0.667 → 0.799 over 10 s, repeatedly crossing
  the nav labels). It is a judgment call, not a provable defect. **Do not "fix" it without an
  answer.**
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
   both answers.
3. **PR-0040 — the music is a 1.82 s loop for the whole session.** Design change, needs sign-off.
4. **PR-0052 — is the Daily Challenge a *layout* guarantee or an *identical-experience* guarantee?**
5. ~~Mystery Box real money?~~ **Resolved (S-001): 300 coins, not real money.** Session 002 further
   confirms the odds are disclosed and sum to 100%, so 3.1.1's requirement is met today.
6. **NEW — PR-0296: is the attract track showing through the hub cards the intended neon look?**
   One yes/no unblocks it permanently, in either direction.

## Program hygiene

- `docs/agent/scratch/` and `docs/agent/audits/scratch/` are **gitignored**. They now hold session
  001's 537 KB survey plus session 002's ~600 KB of finder + verifier output and
  `runtime-auditor.md`. They will not survive a fresh clone. The committed audit file summarises them
  but does not contain them.
- Recovery tags: `pre-s001`, `pre-s002` exist locally.
- This worktree is `.claude/worktrees/prism-rush-audit-91c7ba` on branch
  `claude/prism-rush-audit-91c7ba`, based on session 001's `dc2be8d`. Session 001's own worktree
  (`beautiful-davinci-797e3b`) still exists; **session 003 should branch from session 002's tip, not
  from `main`** — `main` does not contain `docs/agent/` at all.
