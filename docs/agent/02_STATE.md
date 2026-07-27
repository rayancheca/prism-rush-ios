# State — the single source of truth for right now

> Rewritten every session. If this file and any other file disagree about a fact, **this file
> wins** and the other file gets fixed. That includes `state.md` and `README.md` at the repo root,
> which are the project's human-facing history, not the agent's source of truth.

- **Last written by:** session 001 (2026-07-27)
- **Program phase:** Phase A complete → **Phase B (adversarial audits), sessions 002–008**
- **Next session:** 002 — AUDIT-001, The Completeness Auditor
- **Code changed by the program so far:** none. Sessions 001–009 are read-only by design.

---

## Where the project actually is

Prism Rush is a **v1.6, feature-complete, technically strong iPhone game that has never been
submitted to the App Store.** It is not a prototype and it is not half-built. 95 Swift files,
~22,300 lines, zero third-party dependencies, zero binary assets except the generated app icon.

What is genuinely solid:
- The deterministic core is real. Fixed 1/120 s timestep, seeded SplitMix64, a 200-seed
  solvability bot plus a 12,000 m soak, golden-pinned daily-challenge seeds with a pre-armed
  next-version hash. The `RendererPort` seam is clean and the core imports Foundation only.
- **178 SPM tests pass in 7.28 s, measured this session, zero failures.** Real output is in
  `08_TESTING.md`.
- Zero `TODO`, `FIXME`, `HACK`, `XXX`, or `fatalError` in the entire source tree. Verified by grep.
- `Profile` has 44 stored properties, 44 `CodingKeys`, and 44 `decodeIfPresent ?? default` lines —
  iron rule 7 is actually held.
- The meta layer is broad: 24 characters, 12 world families, missions, achievements, daily
  challenge with its own leaderboard, StoreKit 2, Game Center, iCloud KVS, Sign in with Apple.

What is actually wrong, in one sentence: **the economy's iCloud merge is unsound, the store
listing describes a different game, and several submission-blocking compliance rows are open.**

## The three things that should worry you most

1. **The save-merge layer leaks money in four independent ways** (PR-0002, PR-0003, PR-0252,
   PR-0253). Two of them need nothing but a second device and airplane mode. One of them
   (PR-0005) can silently destroy a player's progress at launch. This is the single largest
   cluster in the backlog and it is all one subsystem: `Meta/ProfileStore.swift`.
2. **`Store/metadata.md` would be submitted as-is and it describes a three-world game.** The
   shipped build has twelve world families and most of v1.3–v1.6 is absent from the copy
   (PR-0010). The ship docs instruct the owner to paste it verbatim into App Store Connect.
3. **Three compliance rows are hard blockers and none of them is expensive** — an undeclared
   required-reason API (PR-0007), no account-deletion affordance despite Sign in with Apple
   (PR-0008), and a privacy manifest that contradicts every ship doc (PR-0009). These are hours
   of work standing between the project and a first submission.

## Backlog summary

| Severity | Count |
|---|---|
| SEV0 (conditional, unproven) | 1 |
| SEV1 | 14 |
| SEV2 | 40 |
| SEV3 | 123 |
| SEV4 | 3 |
| **Total** | **181** |

All filed by session 001 from a full ten-agent read of the source. **None has been adversarially
verified** — that is what sessions 002–008 are for. Expect promotions, demotions, merges, and
some outright wrong findings. See the provenance note at the top of `03_BACKLOG.md`.

## Completeness Ledger

**Owned by AUDIT-001 (session 002).** It does not exist yet. When it does it lives here, as a
permanent section, with one row per user-facing feature and columns for `implemented`,
`reachable`, `tested`, `polished`.

Raw material already gathered: `docs/agent/scratch/docs-claims.md` contains a **108-row claims
ledger** built by grepping every claim in `README.md`, `state.md`, `Store/metadata.md`, and
`reports/` against the shipped tree. AUDIT-001 should start from that file rather than rebuilding
it. It is gitignored, so **AUDIT-001 must read it in session 002 before the scratch directory is
ever cleaned.**

## Phased roadmap

Provisional. **Session 009 rewrites this** with all seven audits visible; do not treat it as
settled.

| Phase | Content | Rough size |
|---|---|---|
| Phase A | Scaffold + map (session 001) | ✅ done |
| Phase B | Seven adversarial audits (sessions 002–008) | 7 sessions |
| Phase C0 | Triage (session 009) | 1 session |
| Phase 1 | The `ProfileStore` merge rework — PR-0002, PR-0003, PR-0005, PR-0250, PR-0252, PR-0253, PR-0282, PR-0283. One subsystem, one coherent redesign, everything else depends on it | 2–4 sessions |
| Phase 2 | Ship blockers — PR-0007, PR-0008, PR-0009, PR-0010, PR-0004, PR-0034, plus whatever AUDIT-003 adds | 3–5 sessions |
| Phase 3 | Completeness — dead affordances, unreachable states, honest empty states (decrees 3 and 4) | 4–6 sessions |
| Phase 4 | Fun and retention — input latency, death legibility, the 1.8 s music loop, whatever AUDIT-002's economy math demands | 5–8 sessions |
| Phase 5 | Polish, Dynamic Type, accessibility, perf, docs | 5–8 sessions |

## Needs Rayan on a device

Nothing can move past `VERIFY-PENDING` without him. Carried forward every session until done.

- PR-0024 — do the camera and pose lerps land at the same speed on 60 Hz and 120 Hz hardware?
- PR-0025, PR-0260 — Instruments allocation and idle-battery traces.
- PR-0026, PR-0047 — input feel: tap-to-jump latency and the bottom-corner swipe dead zones.
- PR-0037, PR-0038, PR-0039, PR-0256 — audio: background-audio survival, interruption recovery,
  launch-mute honouring.
- PR-0043 — VoiceOver slider persistence in Settings.
- Every HUMAN GATE in `docs/SHIP_CHECKLIST.md`: App Store Connect record, the IAP products, both
  Game Center leaderboards, the App Privacy questionnaire, the signed upload.

Note the device gotcha recorded in memory: this repo lives under iCloud-synced `~/Desktop`, so
codesigned builds must use a `-derivedDataPath` **outside** the synced tree. Sim builds are fine.

## Session 001 addendum — the build was actually run

Rayan asked why no agent had launched the app. Correct catch: the 181 items above were pure static
reading. The build was then run for real — `./Tools/build.sh` → BUILD OK, installed and launched on
iPhone 17 Pro / iOS 26.5 (`10C15FE0-3D9A-40D5-9E45-C0702E906DF3`), driven with `PR_AUTOPLAY` and
`PR_SCREEN`.

Fifteen minutes produced four findings, one of them a money bug:

- **PR-0290 (SEV1)** — the shop renders hardcoded USD prices on live, tappable buy buttons whenever
  StoreKit has not loaded. A non-US player sees a price they will not be charged. Ten agents read
  `IAPCatalog.swift` and did not flag it.
- **PR-0291 (SEV2)** — score popups stack into an unreadable smear (seen at 189 m and again at
  660 m, so systematic).
- **PR-0292 (SEV2)** — a near-field tall obstacle washes out the SHIELD deploy button.
- **PR-0293 (SEV2)** — the Mystery Box discloses no odds.
- **PR-0294 (SEV3)** — `state.md`'s "Store unavailable fallback verified" note is no longer true.

**This is now mandatory** for every behavioural session: `01_RULES.md` §4, decisions D-003 and
D-004. Backlog total is **186**.

**Resolved by running it:** open question 5 and charter assumption A4 — the Mystery Box costs
**300 coins**, not real money, so Guideline 3.1.1's odds requirement does not bite. The charter's
own stricter non-negotiable still does (PR-0293).

**Blocked on Rayan:** the native simulator integration will not attach, reporting "Xcode is
installed but not selected" even though `xcode-select -p` already returns the right path and
`xcodebuild` works. Needs `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Until
then sessions drive the simulator through `xcrun simctl`, which cannot synthesise taps or swipes —
so interaction has to go through launch hooks or XCUITests.

## Open questions for Rayan

Carried in `HANDOFF.md` until answered. Ranked. **Question 5 is resolved — see the addendum above.**

1. **Is App Store submission still the goal, and on what timescale?** Everything in Phase 2 is
   priced against "yes, soon". (Charter assumption A1.)
2. **PR-0254 — should a run that used a paid revive be leaderboard-eligible?** Iron rule 10
   currently says yes by omission. This is a product call, not a bug.
3. **PR-0040 — the music is a 1.82 s loop for the whole session.** The single-bed decision was
   yours; adding long-form structure inside that constraint is a design change that needs your
   sign-off.
4. **PR-0052 — is the Daily Challenge a *layout* guarantee or an *identical-experience*
   guarantee?** The answer decides how much of PR-0020 has to be fixed.
5. **Is the Mystery Box ever purchasable with real money, or coins only?** If real money can buy a
   randomized outcome, odds disclosure becomes a hard 3.1.1 blocker. (Charter assumption A4.)

## Program hygiene

- `docs/agent/scratch/` and `docs/agent/audits/scratch/` are **gitignored**. They hold ~537 KB of
  session-001 survey output that the committed docs summarise but do not fully contain. They will
  not survive a fresh clone. AUDIT-001 and AUDIT-002 in particular should mine them first.
- Recovery tags: `pre-s001` exists locally. Tag `pre-sNNN` before every session.
- This worktree is `.claude/worktrees/beautiful-davinci-797e3b` on branch
  `claude/beautiful-davinci-797e3b`, not a clone of `main`.
