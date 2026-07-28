# HANDOFF → Session 005

## Paste this to start the next session

```
You are session 005 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file. For your goal you will
also want docs/agent/03_BACKLOG.md PR-0452 (written as a brief, not a one-liner) and
docs/agent/05_GAME_DESIGN.md §1 — the hub is the meta loop's only surface.

You may and should change code. 01_RULES.md is split into judgment (advisory) and nine invariants
(damage prevention). Rayan's standing instruction is "never be limited by arbitrary rules, just
work however you think is best." Do not reinstate ceremony. Do not ask permission to fix something
you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED
before publishing. Design and feel outrank compliance right now.

Your goal is PR-0452: redesign the hub. Rayan asked for this directly in session 004 — "i want a
redesign of the ui ux of the main screen. it just doesn't feel right." Session 004 filed it with a
concrete critique and deliberately did not start it; a redesign is design work, not a patch.

Pick a visual direction BEFORE writing code. The current hub is six identical tiles in two rows of
three plus nine centre-aligned stacked rows — literally the "default card grid, no hierarchy"
pattern Rayan's own design rules ban. Do not ship another centred stack with nicer padding.

Verify with clean-launch screenshots at three profile states (fresh / rewards-claimable / world
12+) and OPEN them. A diff does not prove a redesign. PR_FIRSTRUN does not reset the profile —
only simctl uninstall does.

Build and RUN the app before you claim anything works. That rule is four for four at catching
things static reading missed, and your goal this session lives entirely in the half of the codebase
`swift test` does not compile.

Report back in three lines.
This file's absolute path: <repo>/HANDOFF.md
```

---

# Goal — PR-0452: redesign the hub

**Rayan asked for this directly, in session 004:** *"i want a redesign of the ui ux of the main
screen. it just doesn't feel right."* He added that if it was already in the notes it could wait,
and if not, to write it down. It was not, so S-004 wrote it down and did not start it — a redesign
is design work, not a patch, and S-004's remaining budget belonged to verifying a spawn-path change.
**It is now the top item.**

This is the first screen every player sees and the one they return to between every run.

## What is actually wrong

`docs/agent/03_BACKLOG.md` **PR-0452** carries the full critique and names the screenshot it came
from: `docs/agent/scratch/s004/hub_after.png` (gitignored — **look at it**). Short version, scored
against Rayan's own `~/.claude/rules/web/design-quality.md` banned-patterns list:

- **Six tiles, two rows of three, identical size / radius / spacing.** Literally the banned "default
  card grid with uniform spacing and no hierarchy".
- **Rewards and navigation read as the same class of object.** Nothing says the top row is *things
  that changed since you left* and the bottom row is *places to go*. The only hierarchy cue in the
  entire lower half is that REWARDS happens to be filled.
- **Nine centre-aligned stacked rows**, uniform rhythm, everything symmetric about one axis.
- **Two competing secondary chips sandwich PLAY** — "FURTHEST 01 · PULSE CITY ›" above and
  "FIRST RUN ›" below — so the primary action is framed by two equally-tappable-looking things.
- Dead second line: "MISSIONS / **BOARD**".
- Unbalanced top corners; the wordmark collides with the city backdrop.

**Pick a direction before writing code.** Rayan's rules list worthwhile ones; bento composition and
editorial/arcade both suit a neon runner.

## What binds you

- **Decree 2 — previews never lie.** The hero stage must show the skin the run actually plays. Use
  the resolver at `MenuView.swift:157` (`SkinCatalog.skin(ProfileStore.shared.equippedSkinID)`),
  never raw `selectedSkin`. This has been broken before.
- **Decree 4 — everything on screen leads somewhere.** No decorative tiles.
- **Decree 6 — clarity beats spectacle.** PR-0445 (S-004) just fixed the attract track cutting
  through the hub's glyphs, via a lower-third scrim in `GameView.swift`. Keep that true; if your
  layout moves content upward, move the scrim with it.
- **Invariant 6 (G3) — this one has shipped three bugs.** Never `@State` a shared `@Observable`;
  never snapshot `store.profile` into a `let` at the top of `body`. Reference `ProfileStore.shared`
  and `IAPManager.shared` directly in `body`. Keep `loadout` a **concrete typed child** — wrapping
  it in `AnyView` severed observation and shipped the "Head Start does nothing" bug.

## Absorb these rather than leaving them scattered

PR-0149 (hero stage forces a 140 pt floor inside a flexible slot — can overflow small screens) ·
PR-0150 (the BEST/FIRST RUN chip is ~25 pt with no 44 pt minimum, unlike every sibling) ·
PR-0134 (`rewards:` is still an `AnyView`, the exact shape that severed observation once) ·
PR-0155 (the WORLDS tile and the menu chip compute the world number differently).

## How to verify

```bash
./Tools/build.sh
xcrun simctl uninstall 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
SIMCTL_CHILD_PR_SKIP_SPLASH=1 xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 com.rayancheca.prismrush
sleep 10 && xcrun simctl io 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 screenshot after.png
```

Three profile states — fresh (coins 0, FIRST RUN), rewards-claimable, and deep (world 12+, evolved
palette live). The hub renders differently in each; a layout that only works at one is not done.

---

# If you finish, or if the redesign stalls waiting on taste

**PR-0254 + PR-0307 (decided in D-007, ~1 hour, fully specified).** A revived run counts fully for
missions and XP and is **not** leaderboard-eligible — the rule `usedCheckpoint` runs already follow.
Touches `recordRunResults` (`UI/GameView.swift:~680-792`). **Invariant 5 binds: keep the per-death
delta shape (`max(0, cumulative − awarded)`); do not reintroduce cumulative re-pays.** Clean,
self-contained, nothing blocks it.

**PR-0450 (big — the honest residual of S-004).** Act two changes how *often* you meet things; the
catalogue is still 14 patterns, so a player who has read all 14 has still read them all. One
genuinely new entity or verb in a sixth tier is the highest-value content work left, and the most
expensive: new mesh, new collision predicate, new bot policy, invariant 2 in full. Do not start it
in the same session as the redesign.

---

# What changed in session 004 — read before touching the spawner

**`DailyChallenge.layoutVersion` is now 8.** PR-0400 and PR-0414 landed together in one bump
because both touch the spawn path and two bumps would have bought nothing.

`Core/Spawner.swift` grew a second difficulty axis, `Spawner.intensity` (0 at 3,200 m → 1 at
9,600 m). Past 3,200 m: the pattern draw resolves through a **weighted table** in three front-loaded
waves, the gap continues 5 → 4, moving walls swing off phase 0, and a **greed line** of gems is hung
in a lane each pattern closes. All four are pure functions of distance consuming **zero RNG** —
`PatternOrderTests`' pinned per-pattern call counts are untouched and act one's selection is
byte-identical to v1.6.

Measured (`DifficultyCurveTests`, 64 seeds), act one's plateau → deepest wave: obstacles/100 m
6.02 → 7.63, Autopilot inputs/100 m 3.93 → 4.44, obstacle-free track 27.1% → 12.4%, gems priced in
risk 0.7% → 14.6%. v1.6 was flat in all four across 3,000–8,000 m.

**Things you would otherwise have to rediscover the hard way:**

- **Do not raise `speedCap`.** The readable lead is capped at ~65 m by the backdrop plane — 1.97 s
  at the cap — and pushing it back was tried and reverted in v1.6. Faster is unreactable, not
  harder. Receipt: `docs/agent/audits/scratch/verify-difficulty.md §12`.
- **`SolvabilityBotTests` cannot certify the greed line and does not claim to.** `Autopilot` reads
  only `activeObstacles` and has never collected a gem, so it walks the safe line every time and
  would stay green even if the greed line were lethal.
  `DifficultyCurveTests.testEveryGreedGemLeavesATakeableExit` is the separate proof. If you add
  gems anywhere, that is the test that must stay green.
- **Fixed-width measurement bands lie.** The mean pattern cycle is ~451 m; a 500 m band grid beats
  against it with a ~4.6 km period and manufactures a fake difficulty trend. Bands in
  `DifficultyCurveTests` are snapped to real pattern boundaries. Do not "simplify" that away.
- **Golden seeds are derived independently** (Python, from the SplitMix64 formula), never read off
  the code they pin. A **v9 pin is pre-armed** in `DailyChallengeTests`. Note that
  `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens` pins the *same* seeds from the meta layer
  and must be repinned in the same edit — easy to miss.
- `capGem` went 72 → 112. Measured peak demand is 94; v1.6 was silently dropping gems at
  `GameCore.apply`. `capGem` is **Core-only** — the renderer pools on demand and never reads it,
  despite what the old comment claimed (PR-0451).

---

# Traps (all still true, all have cost someone a session)

- **`swift test` green ≠ the app works.** It compiles `Core/`, seven `Meta/` files and
  `Audio/Synth.swift`. **Not** `UI/`, `Render/`, `IAP/`, `SynthEngine`, StoreKit or GameKit. Only
  `./Tools/build.sh` proves those. Your goal lives entirely in the half SPM does not compile.
- **Test counts elsewhere in this repo are stale.** `CLAUDE.md` says 95, `Tools/ci.sh` says 174.
  Measured truth at `9766e7d` is **187**. Trust `08_TESTING.md`.
- **`rm -f dir/*.png` aborts a zsh `&&` chain when nothing matches.** It silently killed S-004's
  first screenshot loop — the loop never ran and the failure looked like "0 files captured". Do not
  suppress stderr on capture commands.
- **`PR_FIRSTRUN` does not reset the profile.** Only `simctl uninstall` gives a true first launch.
- **The splash never auto-dismisses.** Tap it, or launch with `PR_SKIP_SPLASH=1`.
- **`Tools/qa.sh` and `Tools/screenshots.sh` hardcode this machine's UDIDs and fail silently via
  `|| true`** (PR-0050). A green run may mean nothing ran.
- **Never drive the simulator while `xcodebuild test` runs on it** — concurrent installs crash the
  test host and report a false TEST FAILED.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth. Where they
  disagree with `02_STATE.md`, `02_STATE.md` wins.
- `docs/agent/scratch/` and `docs/agent/audits/scratch/` are **gitignored** and hold ~2 MB from four
  sessions, including S-004's before/after hub screenshots. Git will not move them between
  worktrees — `cp -R` by hand if you make a new one.
- Don't put `./Tools/build.sh` (~2 min) inside a fan-out. Build once, up front, in the background.

---

# Current state in one paragraph

Prism Rush is a v1.7, feature-complete, technically strong iPhone game that has never been
submitted to the App Store: ~95 Swift files, ~22,600 lines, zero dependencies, zero binary assets
but a generated icon, **187 SPM tests green**, and a genuinely deterministic core behind a clean
`RendererPort` seam. Session 001 built the agent memory system and filed 186 items from static
reading. Session 002 produced the Completeness Ledger: 50 of 59 user-facing features are fully
implemented and exactly one — account deletion — is outright absent, but only 13 of 59 clear the
owner's six decrees. Session 003 wrote the design bible and found the structural problem — the game
ran out of design at 3,200 m, verified in source and measured on device — then fixed PR-0411 and
cut the program's process rules to nine real invariants. **Session 004 fixed the structural
problem**: there is now an act two out to 9,600 m, gems can cost something, and the hub no longer
has neon lines through its text. Backlog is 259 items, 6 DONE. Five audits remain unrun; the phase
gate is gone, so fixes and audits interleave, and polish outranks compliance until Rayan says
otherwise.

# Rayan action items (surface them; do not try to do them)

1. **App Store Connect still says "Earn 2x coins, forever."** Session 004 fixed the last two repo
   files that are the copy-paste source (`docs/APP_STORE_SETUP.md:128`,
   `docs/SHIP_CHECKLIST.md:43`), so what he pastes is now correct — but **the live product
   description in ASC is still false and only he can change it.** Residue of PR-0411; it blocks
   honest submission.
2. **Does act two feel right?** It is verified deterministic, fair and measurably escalating, but
   "measurably escalating" and "fun" are different claims and only a human makes the second. Ask
   specifically: is the 3,200 m step noticeable? Do the swung moving walls past ~6,800 m read, or
   feel cheap? Can you *see* the two coin lines diverge in time to choose, at speed? Is the safe
   line obviously correct, or is the choice real?
3. **Which visual direction for the hub?** PR-0452 lists candidates and deliberately does not pick.
4. Optional, still open from S-003: PR-0411 was fixed by making the *claim* true. The alternative —
   making the *product* true by multiplying the five un-multiplied faucets (daily reward, chest,
   level grant, mission claim, challenge tier) — is a better deal for buyers and a real economy
   rebalance. His call.

# Open questions for Rayan (carried until answered; none block session 005)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his own
  decree (`SynthEngine.swift:133`). Long-form structure inside that constraint needs sign-off. The
  other 11 beds exist and are intentionally unreachable.
- **PR-0052** — is the Daily Challenge a layout guarantee or an identical-experience guarantee?
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families plus
  an infinite evolved cycle. Needs a ledger-checked rewrite before submission (out of scope until
  the compliance pass).

# Resolved in session 004

PR-0400 (act two) · PR-0414 (risk-priced gems) · PR-0445 (attract-track scrim) · PR-0451 (stale
pool-cap comment + `capGem` 72→112) · PR-0411 repo-side residue. Filed: PR-0450, PR-0452.
No new decisions — D-005 … D-008 all held up in practice and none needed amending.
