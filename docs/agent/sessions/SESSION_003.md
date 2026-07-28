# Session 003 — Design bible and game-design audit

- Date:        2026-07-28
- Branch:      claude/prism-rush-design-audit-562d27 (reset onto session 002's tip `e7f7841`)
- Goal:        Write the design bible this project has never had, then find the design failures.
- Persona:     AUDIT-002, The Game Designer
- Items:       PR-0400 … PR-0445 filed (46 new)
- Outcome:     COMPLETE
- Code changed: **none** (read-only session by design)
- Context used at handoff: ~70%

## What I changed

- `docs/agent/05_GAME_DESIGN.md` — **rewritten from a 127-line skeleton into the design bible.**
  The session's primary deliverable. 12 sections: three loops, first 60 s, difficulty curve
  (computed + measured), mastery ceiling, economy with arithmetic, worlds, reward schedules,
  session shape, retention hooks, missing systems, what it does not cover, top three fixes.
- `docs/agent/audits/AUDIT_003_game_designer.md` — the audit report (new, write-once).
- `docs/agent/03_BACKLOG.md` — appended PR-0400 … PR-0445. Full blocks for the 12 likely to be
  picked up first; compact rows for the tail, per the PR-0001 precedent.
- `docs/agent/02_STATE.md` — header, verdict, worry #3, backlog table, Ledger row 53 correction,
  open questions 2/6/7, program hygiene.
- `HANDOFF.md` — rewritten for session 004 (AUDIT-003, The App Review Rejector).
- `docs/agent/audits/scratch/` — 20 new files (10 finder + 10 verifier), gitignored.

Session 001's and 002's scratch (~1.1 MB) was copied into this worktree by hand at session start.
Git will not carry gitignored files across worktrees.

## Evidence

```
./Tools/build.sh                  → BUILD OK
xcrun simctl install …            → INSTALL OK
Workflow: 20 agents · 3,893,589 subagent tokens · 740 tool calls · 0 errors · 1,699 s
  Find phase   10/10 done
  Verify phase 10/10 done
  124 findings raised → 92 survived → 32 killed → 34 severities downgraded
```

Measured difficulty curve (autoplay, 20 screenshots at 10 s intervals, HUD read per frame):

```
143→328   18.5 m/s     1,921→2,160  23.9      3,315→3,652  33.7  ← cap
328→523   19.5         2,160→2,455  29.5      3,652→3,989  33.7
523→730   20.7         2,455→2,767  31.2      3,989→4,324  33.5
730→947   21.7         2,767→3,038  27.1      4,324→4,660  33.6
947→1,177 23.0         3,038→3,315  27.7      4,660→4,995  33.5
1,177→1,389 21.2                              4,995→5,331  33.6
1,389→1,654 26.5
1,654→1,921 26.7
```

Five consecutive intervals at 33.5–33.7 m/s. Multiplier chip read **×5 in all 20 frames**.
Gem rate 1,948 / 5,331 = 0.365 gems/m. Clean-install first death: **72 m, score 132, +1 coin,
+16 XP**.

I did not run `swift test` — this session changed no code, and the suite's result at `e7f7841`
(178 tests, 8.85 s) is session 002's, already recorded. Claiming a fresh green would have been
noise, not evidence.

## What I learned about this codebase

- **`Spawner.fill` takes `dist` and nothing else; `Patterns.run` takes no world parameter.** This
  single fact settles the entire "are worlds progression?" question at the source level. Grep
  `world` in `Core/Spawner.swift` + `Core/Patterns.swift` → one hit, in a doc comment.
- **The difficulty seam already exists.** `Spawner.maxIndex` gates the catalogue by prefix index
  against distance. Adding a second act past 3,200 m is a change to that one function, not an
  architecture problem.
- **`nearMissInner` (1.25) is exactly `laneHitHalfWidth` (1.25).** The CLOSE band starts at the
  precise point you stop dying. That window is genuinely tuned; do not let a future audit "fix" it.
- **Launch hooks do not reset the profile.** `PR_FIRSTRUN` returned a hub reading `FURTHEST 15 ·
  11,200M`. For a real FTUE you must `simctl uninstall` then `install`. This is a stronger version
  of the stale-`activeSheet` trap already in the handoff.
- **`isPrismatic: true` on `Skin(id:"default")`** is why Prism is cyan on the splash and pink in
  the hub. Not a decree-1 violation — decree 1 forbids identity changing *with the world*, and
  Prism's identity *is* the prism. Now recorded in the bible §11 so it is not filed a third time.
- **The `00_CHARTER.md` "Explicitly out of scope" list is enforceable and I got caught by it.**
  It does not merely discourage analytics — it says *"Do not file backlog items proposing them."*
  Read `:94-98` before filing anything infrastructural.
- Coin income is `gems + dist/35 + 5·worlds + min(closes+slicks,40)·2`. At the measured gem rate,
  gems are 76–88% of it at every run length. Three of four components are rounding error.

## New backlog items filed

PR-0400 curve ends at 3,200 m (SEV1) · PR-0401 decoration meta loop (SEV1) · PR-0402 inverted
onboarding · PR-0403 world = reskin (SEV1) · PR-0404 price treadmill · PR-0405 multiplier loading
bar · PR-0406 first-death panel hierarchy (SEV1) · PR-0407 no notifications · PR-0409 execution-only
depth · PR-0411 2×-coins under-delivery (SEV1, money) · PR-0412 world purchase disclosure (SEV1) ·
PR-0413 tutorial banner wrong verb (SEV1) · PR-0414 safe-lane coin trail (reversal request) ·
PR-0415 economy pays 7% for distance · PR-0416…PR-0430 SEV2 tail · PR-0431…PR-0444 SEV3 tail ·
PR-0445 attract-track bleed (closes the PR-0296 question).

## Decisions made

None appended to `04_DECISIONS.md`. Every judgment I made is a *design recommendation* recorded in
`05_GAME_DESIGN.md` or an open question for Rayan, not a program decision a future session must
honour. Session 009 triages; it should not inherit my rulings as binding ADRs.

## Where I was wrong

1. **I nearly filed "zero analytics" as SEV2.** The charter bans it outright as a compliance
   commitment tied to the store listing, and explicitly forbids filing items proposing it. A
   verifier caught it. I withdrew it and recorded the real consequence (every retention claim here
   is permanently unfalsifiable) as an owner-made trade rather than a defect.
2. **My capture labels were sampling indices, not elapsed run time.** A verifier correctly attacked
   "523 m at t = 20 s" as unreproducible from the shipped tuning — it is. Everything the argument
   rests on is distance-anchored or delta-derived and survives, but the bad number is struck in the
   bible's provenance section rather than quietly repaired.
3. **I assumed the tutorial was opt-in and out-competed by the PLAY button**, and drafted a finding
   saying so. On a true first launch **PLAY routes straight into the gate**. Running the app killed
   my own finding before it reached the audit file.
4. **I inherited three false claims and would have propagated all three** had I not played the
   game first: "teaches 3 of ~8 mechanics" (it teaches ~17), and the handoff's "nothing teaches
   magnet, streaks, flow, or slide timing" (all four are taught). D-003 earned its keep again.
5. **My first economy model over-predicted early income by ~28×** (28 coins vs the measured +1 at
   72 m) because I applied the greedy-bot gem rate to a passive run. The 12× spread between hoover
   and non-hoover play is itself the finding, but I had to be corrected by the device to see it.
6. I let a `cd` into the scratch directory persist and briefly believed the directory had been
   deleted. Use absolute paths in this repo's tooling.

## Open questions for Rayan

1. **PR-0411 — "Earn 2× coins, forever" under-delivers on a paid product.** Decree 5, real money.
2. **PR-0254 — revive eligibility.** My ruling: count for missions and XP, leaderboard-ineligible.
3. **PR-0414 — "coins are the path" is your deliberate v1.6 change** and it is also why routing has
   no decision in it. Reversal request, not a bug.
4. **PR-0445 / PR-0296 — attract track through hub cards.** Ruled SEV2 (fails decree 6); one
   yes/no closes it.
5. Carried: App Store timescale · PR-0040 music loop · PR-0052 Daily Challenge guarantee.
