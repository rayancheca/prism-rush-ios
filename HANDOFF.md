# HANDOFF → Session 009

## Paste this to start the next session

```
You are session 009 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. 01_RULES.md is split into judgment (advisory) and nine invariants
(damage prevention). Rayan's standing instruction is "never be limited by arbitrary rules, just
work however you think is best." Do not reinstate ceremony. Do not ask permission to fix something
you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED
before publishing. Design and feel outrank compliance right now.

ASK RAYAN FIRST, in your opening message — ONE question, because his answer splits the session:

  Has he PLAYED the Warden yet, and does the fight feel good?

  - If YES -> build phase 2 (abduction: caught = struggle-to-escape, then death) and then
    PHASE 3, THE COUNTERMEASURES. Phase 3 is the one that actually closes PR-0401 — the coin sink
    that buys nothing altering play — which is the largest structural gap left in the game. Phase 1
    shipped the FIGHT, not the ECONOMY, on purpose.
  - If NO / not yet -> do NOT build more on top of it. docs/agent/10_WARDENS.md section 9 gates
    phase 2 on him playing phase 1, deliberately, because a Warden that reads badly at speed is
    worse than no Warden. Offer PR-0456, the FULL AUDIO PASS, instead — a standing owner request
    from S-006, still unstarted, and independent of the Wardens.

To let him play it in ten seconds:
  ./Tools/build.sh
  xcrun simctl boot 10C15FE0-3D9A-40D5-9E45-C0702E906DF3
  xcrun simctl install 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 \
    .dd/Build/Products/Debug-iphonesimulator/PrismRush.app
  SIMCTL_CHILD_PR_WARDEN=1 xcrun simctl launch 10C15FE0-3D9A-40D5-9E45-C0702E906DF3 \
    com.rayancheca.prismrush
PR_WARDEN=1 starts the run at the mouth of the first arena with a full charge bank. Tap the splash
FAST — the run advances behind it.

Build and RUN the app before you claim anything works. That rule is now eight for eight. Session 008
shipped a beam render that looked right in code and read as terrain on screen; only a screenshot
caught it. `swift test` green is NOT the app working: it compiles Core/, seven Meta/ files and
Audio/Synth.swift, and none of UI/, Render/, IAP/, StoreKit or GameKit.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~200 MB of working detail from eight sessions, including S-008's Warden
screenshots and the seven scout reports + integration map the build was planned from. Git does NOT
move them between worktrees. This copies them from wherever they still exist and is a no-op if you
already have them:

  for w in "" .claude/worktrees/prism-rush-spawn-path-c7d88a \
           .claude/worktrees/prism-rush-design-audit-562d27 \
           .claude/worktrees/prism-rush-audit-91c7ba; do
    s="/Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/$w/docs/agent"
    [ -d "$s/scratch" ] && mkdir -p docs/agent/scratch && cp -Rn "$s/scratch/." docs/agent/scratch/ 2>/dev/null
    [ -d "$s/audits/scratch" ] && mkdir -p docs/agent/audits/scratch && cp -Rn "$s/audits/scratch/." docs/agent/audits/scratch/ 2>/dev/null
  done; du -sh docs/agent/scratch docs/agent/audits/scratch

If both are empty, say so in your report rather than working blind.

Report back in three lines.
This file's absolute path: /Users/rayankarimcheca/Desktop/ClaudeProjects/projects/prism-rush-ios/HANDOFF.md
```

---

# What session 008 did

**THE WARDENS, phase 1 — built, playable, verified on the simulator, pushed.**
209 SPM tests green (was 196), 228 Xcode tests green (was 215).

Rayan chose the Wardens over the audio pass when asked at the top of the session. He also asked
mid-session that everything be pushed to GitHub — it is, including sessions 006 and 007, which had
never been pushed (`origin/main` was 12 commits behind).

Full account: `docs/agent/sessions/SESSION_008.md`. Design, corrected against the build:
`docs/agent/10_WARDENS.md`. Decisions: **D-015** (a Warden is not an `EntityKind`), **D-016** (every
beam closes the player's own lane), **D-017** (the arena is a pure function of distance, and costs a
layoutVersion bump).

## The shape of it

Every third world (2,400 m), inside a **660 m arena swept clear of obstacles but NOT of gems** —
gems are the ammunition, so the shield phase is something you *do* with verbs you already own.
Auto-fire breaks the shield at a rate set by a **charge bank earned from gems and spent as it
burns**; a player who banked nothing mathematically cannot break it. Shield down → telegraph→strike
beams that **always** close the player's lane, and 40% of the time a second one. Three clean dodges
kill it. Caught = death; **failing to damage ≠ failing to survive** — it breaks off and you keep the
run. Zero new inputs, so decree 6 holds.

## Two defects the tests found that reading would not have

- **The gun could win on its own.** A beam that merely *usually* stalked let a player who never
  moved win outright whenever three beams happened to pick empty lanes — "wasn't in the beam" was
  being scored as a dodge. Caught at 1 kill in 40 seeds. Fixed by D-016.
- **A fight was unbounded.** An absorbed beam is spent without landing a core hit, and shields stay
  collectable in the arena, so shield-trading could drag a fight past its own arena into resuming
  obstacles. Capped by `wardenMaxSeconds`; the arena is sized from a provable bound.

## The chasm guard was repaired, not relaxed

It went red (53 crossings vs a floor of 72) because the first arena lands on tier six's debut at
2,560 m. Re-expressing it per eligible kilometre looked like the fix and is also wrong — an arena
eats the highest-frequency band, so that average moves with `wardenArenaLength`. Frequency now
belongs to `DifficultyCurveTests` (which measures the spawner and is unchanged); the bot test guards
presence. An A/B with suppression toggled off settled it: **0.92/km either way.**

---

# Things you would otherwise rediscover the hard way

- **The run advances BEHIND the splash screen.** Launch, then screenshot, and you land *after* the
  fight is over. Tap fast, or use `PR_AUTOPLAY` and let the bot survive so there is no game-over
  panel covering the evidence.
- **`xcrun simctl io screenshot` throttles the simulator hard** — a few metres of travel per shot.
  That is a feature: it lets you step through a 4-second fight almost frame by frame. It is far
  finer-grained than the MCP screenshot tool, which advances hundreds of metres per call.
- **iCloud created a `GameCore 2.swift` conflict copy mid-session and broke the build.** This repo
  lives under iCloud-synced `~/Desktop`. `.gitignore` already carries a `* [0-9].swift` rule from an
  earlier session, but gitignore does not stop SPM/xcodegen compiling it — `Package.swift` globs the
  whole `Core` directory. If you get `invalid redeclaration of GameCore`, look for `* 2.swift`.
- **SourceKit in this checkout resolves against macOS.** `Theme`/`GameCore`/`UIKit`/`Warden` "errors"
  are noise — it was wrong on every file this session too. Believe `./Tools/build.sh`.
- **Adding an FXEvent case is the good kind of breaking change.** Three exhaustive switches
  (renderer `fire`, `Haptics.handle`, `GameView.handleFX`) refuse to compile until each new event
  has a reaction. That is exactly why D-015 keeps the Warden out of `EntityKind`, where six
  `default:` arms would have swallowed it silently.
- **Derive layoutVersion goldens in Python and reproduce the existing pins FIRST.** The independent
  agent that cross-checked mine reported its own first attempt failed all eight pins from a
  transposed tag constant. A v11 pin is already armed.
- **Never drive the simulator while `xcodebuild test` runs** — concurrent installs crash the host.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v1.9, feature-complete iPhone game that has never been submitted: ~98 Swift files,
zero dependencies, zero binary assets but a generated icon, **228 Xcode and 209 SPM tests green**,
and a genuinely deterministic core behind a clean `RendererPort` seam. Session 002 found only ~13 of
59 features cleared the owner's six decrees and that every failure state was unfinished; **S-007
closed that entire class.** S-004 and S-006 closed the structural half of session 003's verdict
(act two to 9,600 m; tier six and the chasm). **S-008 built the fight that is designed to close the
economy half — but did not close it.** `PR-0401` (the coin sink buys nothing that alters play) is
**still open**, because Countermeasures are Warden phase 3 and phase 1 was gated on the owner
playing it first. Backlog is 263 items, 25 DONE. Five audits remain unrun.

# Rayan action items (surface them; do not try to do them)

1. **PLAY THE WARDEN.** This is the one that unblocks everything else — `10_WARDENS.md §9` gates
   phase 2 on it, and nothing in this program can judge whether a fight feels good. Specifically:
   does the telegraph read at speed? Is one safe lane out of three the right amount of pressure? Is
   the arena going quiet a welcome punctuation, or does it feel like the game stopped?
2. **Is 660 m of clear deck every 2,400 m too much?** That is ~27% of the track past the first
   encounter. It is sized from the crudest *provable* bound against a measured worst case of 438 m,
   so there is real slack — but shrinking it means shortening the shield window, which moves the
   charge threshold. His call after playing.
3. **Is the first Warden too easy?** The bot arrives at FULL charge every time and wins every fight.
   That is the safe direction for a first playtest, but it means charge is not yet a real choice.
   One constant (`wardenChargeFullGems`, currently 520 against ~637 banked) moves it.
4. **The slide SFX — does it actually sound better?** Carried from S-006, still unanswered.
5. **Audio pass or Warden phases 2–3 next?** See the top of this file.
6. **Does act two feel right? Does the chasm? Does the hub?** All carried, all need his thumbs.
7. **The `Double Coins` IAP description in App Store Connect** — if already created with "Earn 2x
   coins, forever", correct it to `Every run pays 2× coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his own
  decree. Long-form structure inside that constraint needs sign-off. **In scope for the audio pass.**
- **PR-0052** — is the Daily Challenge a layout guarantee or an identical-experience guarantee?
  **S-008 leaned on the layout reading** when it made the arena a pure function of distance rather
  than of how the fight goes. Worth confirming that was right.
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.

# Resolved in session 008

**PR-0457 phase 1** (the Wardens). New decisions **D-015**, **D-016**, **D-017**.
