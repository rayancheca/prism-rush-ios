# HANDOFF → Session 008

## Paste this to start the next session

```
You are session 008 of a long-running program to finish and ship Prism Rush, a neon three-lane
endless runner for iPhone (Swift 6, SwiftUI, RealityKit, zero dependencies, zero binary assets).

Read docs/agent/01_RULES.md, then docs/agent/02_STATE.md, then this file.

You may and should change code. 01_RULES.md is split into judgment (advisory) and nine invariants
(damage prevention). Rayan's standing instruction is "never be limited by arbitrary rules, just
work however you think is best." Do not reinstate ceremony. Do not ask permission to fix something
you can verify.

Direction: App Store submission IS the goal, timing is open, and Rayan wants the app POLISHED
before publishing. Design and feel outrank compliance right now.

ASK RAYAN FIRST, in your opening message, because these two are genuinely different sessions:

  (a) PR-0456, the FULL AUDIO PASS — a standing owner request from S-006, still unstarted.
  (b) THE WARDENS — docs/agent/10_WARDENS.md, the per-world antagonist feature he designed WITH
      session 007. It is the designed fix for PR-0401 (the coin sink buys nothing that alters
      play), which is the largest structural gap left in the game.

(b) is the bigger prize and he was visibly energised by it; (a) is older and he asked for it first.
Do not guess — one question, then commit to one and go deep. Do not start both.

Build and RUN the app before you claim anything works. That rule is now seven for seven at catching
things static reading missed — session 007 REFUTED two filed defects by running the build (the
Mystery Box button was already disabled; tapping a pre-launch price already toasted). `swift test`
green is NOT the app working: it compiles Core/, seven Meta/ files and Audio/Synth.swift, and none
of UI/, Render/, IAP/, StoreKit or GameKit.

FIRST COMMAND, before anything else. docs/agent/scratch/ and docs/agent/audits/scratch/ are
gitignored and hold ~170 MB of working detail from seven sessions, including S-007's before/after
screenshots of every failure state and the nine scout reports the sweep was built from. Git does
NOT move them between worktrees. This copies them from wherever they still exist and is a no-op if
you already have them:

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

# What session 007 did

**Phase 3 is closed.** All eight failure-state items, plus two mid-session owner calls on the hub,
plus the Wardens design.

## 1. THE FAILURE-STATE SWEEP (PR-0302/0303/0304/0305/0306/0308/0311/0314/0315/0316)

Every one verified on the simulator. Before/after screenshots in `docs/agent/scratch/s007/`.

- **PR-0304, the emblem** — the Missions board said `ALL CLEAR` on an untouched 0/N board, so the
  first thing a new player read was that they had finished it. `ProfileStore.MissionBoardSummary`
  makes it a pure three-way (claimable / open / allClear) in the SPM-visible Meta layer. Now reads
  `18 OPEN · UP TO 4,130 COINS`. Four unit tests; the key one was impossible to write before.
- **PR-0306, the most important** — `.notConfigured` is the state a pre-approval build actually sits
  in. Six fabricated USD prices from `IAPCatalog.fallbackPrice` (which exists to size the layout),
  and the only disclosure was a footnote six screens down. Now: never renders a `$` StoreKit did not
  supply, and a calm first-viewport card. Header states are an **exhaustive switch** so the next
  state added gets a presentation by compile error.
- **PR-0302/0303** — the Mystery Box was the app's worst dead end. Now carries `UnlockPanel`'s
  shortfall grammar. The odds table (this app's honesty surface) is legible for the first time.
- **PR-0314** — one failed `AVAudioEngine.start()` silenced the app permanently, because the failure
  cleared the same flag every recovery path guarded on. Intent (`wantsAudio`) is now split from fact
  (`started`).
- Plus PR-0305 (mute undoable from Settings), PR-0308 (restore reports what it actually restored),
  PR-0311 (the Game Center dead card now has a SIGN IN route), PR-0315 (scores queued when signed
  out), PR-0316 (one first-purchase claim instead of five).

`PrismRush/UI/StateNotice.swift` — `ShortfallRow` + `StateNotice` — is the shared grammar, extracted
from `UnlockPanel`, which was already right. The sweep exists because there were **five
incompatible dialects** for "you can't do this yet".

## 2. Two owner calls on the hub (mid-session)

- **The glow behind the character.** *"I really dont like the background light behind the character
  … either take it off or change it for something cool and pretty."* It was two stacked diffuse
  glows smearing the 3D scene. Replaced with a **lit ring + light pool**, tinted per character.
  **He then corrected me:** I had briefly replaced the ring with a plain pool and he said the circle
  *"was so cool"* — the ring is back and is what ships. See D-013.
- **The launch deck.** The loadout chips were two wide pills pinned to the leading edge, reading as
  a bar that failed to fill. Now a compact centred cluster sitting on PLAY. **He may want more here
  — he asked for "much more intuitive" placement "taking inspiration from other similar games", and
  what shipped is the conservative version** (PLAY keeps full width, an S-005 owner call).

## 3. THE WARDENS (`docs/agent/10_WARDENS.md`) — designed, not built

He asked what would make the game stand out, and proposed per-world interactive enemies. The agreed
design, with his three decisions on record:

- **Combat is dodge-to-damage AND auto-fire, combined** (his call, not either/or). They interlock by
  attacking different things: **auto-fire breaks a SHIELD, at a rate driven by charge earned from
  gems collected during the run**; **dodging the exposed Warden's telegraphed attacks is the only
  kill path**. Zero new inputs, so decree 6 (one-frame readability) survives.
- The safety valve that keeps it fair: **being HIT abducts you; failing to DAMAGE does not.** An
  unbroken shield means the Warden breaks off — you lose the reward, not the run.
- Every 3rd world. Caught = struggle to escape, then death.
- Reward: world-exclusive character (headline), plus parts, a small coin bounty, and a plaque.

---

# Things you would otherwise rediscover the hard way

- **The iOS Simulator MCP tap tool cannot drive a SwiftUI `Toggle`.** Two toggles failed identically,
  including one I had never touched. Use XCUITest for switches. Also: **the coordinate space is
  402×874 points on the iPhone 17 Pro**, not 393×852 — `control{action:"launch"}` reports it.
- **A disabled SwiftUI button is dropped from the accessibility tree ENTIRELY** — not `isEnabled ==
  false`, but no match at all. A VoiceOver user cannot perceive a blocked CTA. Unfiled finding.
- **XCUITest coins are not deterministic** — the installed app persists across runs and mission
  claims bank coins, so any test needing "cannot afford" is unreachable without a coin-pinning hook.
  That is why PR-0302 has no XCUITest, and the file says so at the removal site.
- **An identifier on a row container is not queryable.** `ShortfallRow` takes a separate
  `shortfallIdentifier` for the text because of this.
- **`IAPManager.lastError` has TWO readers** — `ShopView` and `SettingsView`. A raw `Error`
  description written by one surfaces on the other's screen. That was half of PR-0308.
- **`MysteryBoxView`'s GET COINS must `dismiss()`, never `model.open(.shop)`** — ShopView is its only
  presenter, so opening the shop is a no-op that leaves the box on top of it.
- **SourceKit in this checkout resolves against macOS**, so `Theme`/`GameModel`/`UIKit` "errors" are
  noise. Believe `./Tools/build.sh`. It was wrong on every single file this session.
- **`cd` inside one Bash call persists into the next.** Use absolute paths.
- **Never drive the simulator while `xcodebuild test` runs** — concurrent installs crash the host.
- `state.md` (58 KB) and `README.md` (35 KB) at the repo root are history, not truth.

---

# Current state in one paragraph

Prism Rush is a v1.8, feature-complete iPhone game that has never been submitted: ~96 Swift files,
zero dependencies, zero binary assets but a generated icon, **215 Xcode tests and 196 SPM tests
green**, and a genuinely deterministic core behind a clean `RendererPort` seam. Session 002 found
that only ~13 of 59 features cleared the owner's six decrees and that every failure state was
unfinished in the same way. **Session 007 closed that entire class** — the app no longer has a state
that is raw, silent, or actively misleading. Sessions 004 and 006 closed the *structural* half of
session 003's verdict (act two out to 9,600 m; tier six and the chasm). **What remains of that
verdict is the economy half: the coin sink still buys nothing that alters play (PR-0401)** — and
`10_WARDENS.md` is now the designed fix for it, agreed with the owner but not built. Backlog is 262
items, 24 DONE. Five audits remain unrun.

# Rayan action items (surface them; do not try to do them)

1. **Does the new ring under the character look right?** He asked for the circle back and this is
   the version that ships — worth ten seconds of his eyes, including on a non-spectral skin (every
   other character gets a solid-hue ring; only Prism sweeps a spectrum).
2. **Is the launch deck fixed, or does he want more?** What shipped is conservative. He asked for
   "much more intuitive" placement and cited other games; PLAY keeping full width is an older owner
   call that constrained the answer. If he wants the chips off the hub entirely, the natural home is
   a pre-run confirm step (`PR_PLAYCONFIRM` already exists) — that is a real redesign.
3. **The slide SFX — does it actually sound better?** Carried from S-006, still unanswered. Nothing
   in this program can hear audio.
4. **Audio pass or Wardens next?** See the top of this file. Genuinely his call.
5. **Does the chasm feel right? Does act two? Does the hub?** All carried, all need his thumbs.
6. **The `Double Coins` IAP description in App Store Connect** — if already created with "Earn 2x
   coins, forever", correct it to `Every run pays 2× coins. Forever.` before submission.

# Open questions for Rayan (carried until answered)

- **PR-0040** — the music is a 1.82 s loop for the whole session, pinned to world 0 by his own
  decree. Long-form structure inside that constraint needs sign-off. **In scope for the audio pass.**
- **PR-0052** — is the Daily Challenge a layout guarantee or an identical-experience guarantee?
- **PR-0010** — `Store/metadata.md` sells a three-world game; the binary ships twelve families.
- **PR-0254** — should a run that used a paid revive be leaderboard-eligible? S-003 recommends
  counting it for missions/XP but not the leaderboard. Needs a yes/no.

# Resolved in session 007

PR-0302 · PR-0303 · PR-0304 · PR-0305 · PR-0306 · PR-0308 · PR-0311 · PR-0314 · PR-0315 · PR-0316.
New decisions: **D-012** (audio recovery is silent — a transient, self-healing condition gives the
player nothing to act on, so a warning would be noise), **D-013** (the character stands on a lit
ring, not in a diffuse glow; owner-corrected, and the glow was also the wrong COLOUR for spectral
skins since D-011), **D-014** (the Wardens design and its three owner decisions).
