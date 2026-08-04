# Session 019 — PASS 019: THE CHARACTER ART (part one)

**Date:** 2026-08-04 · **Recovery tag:** `pre-s019` = `12abbba` (already existed; not re-created)
**Decisions:** D-056, D-057, D-058 · **Backlog:** PR-0486, PR-0487 filed and closed

**Tests:** 286 SPM + 302 Xcode at start → **291 SPM + 307 Xcode** at end, all green.

---

## 0. What shipped

| # | commit | what |
|---|---|---|
| 1 | `af2d75f` | **PR-0486** — the Mystery Box rolled 2.5% while displaying 3%, and advertised a 1,200 jackpot against a real 1,400 (in two strings, one of them the VoiceOver label) |
| 2 | `f04be57` | **D-1** — the rig finally reads `CharacterGeometry`, then every crest grows 1.3x–1.94x |
| 3 | `40bffce` | **PR-0487** — the Mystery Box and the free chest now open the SAME chest, the same way (owner report, mid-session) |

---

## 1. The environment scare was real, and it is over

S-019's first attempt aborted because macOS revoked the host's access to `~/Desktop` mid-run. The
repo has since moved to `~/dev/personal/projects/`, and `python3 -c "import os; print(os.getcwd())"`
returns normally. **The abort condition is gone.**

One residue: `.build` still held a module cache pointing at the old `~/Desktop/ClaudeProjects/...`
path, and `swift test` failed with `missing required module 'SwiftShims'`. That reads like a broken
checkout and is not — `rm -rf .build` fixes it. Worth knowing because it is the *second* failure
mode in this program that impersonates a corrupt tree.

## 2. **A trap that cost an hour and will cost the next session an hour if it is not written down**

The first clean-baseline Xcode run reported:

```
Failing tests:
	WardenTests.testNoFixedStanceCanWinAFight()
** TEST FAILED **
```

**It was not a failing test.** `xcresulttool` gives the real reason:

```
{"children": [{"name": "Test crashed with signal term.", "nodeType": "Failure Message"}], ...}
```

SIGTERM — the test host was killed. I had run `swift test -c release` concurrently, and
`testNoFixedStanceCanWinAFight` is the slowest test in the repo (9 loops × up to 400,000 ticks;
`s014_lethality_seam.md` already flagged it as "passes but hangs"). CPU contention pushed it past
its timeout.

`CLAUDE.md` warns about `simctl` + `xcodebuild` concurrency. **It does not warn about `swift test` +
`xcodebuild`, and the symptom is indistinguishable from an inherited red test** until you open the
xcresult. Re-run alone: `** TEST SUCCEEDED **`, 292 + 12.

> **Rule: run `swift test` and `xcodebuild test` one at a time. If a single slow test "fails" with
> no assertion message, read the xcresult before believing it.**

## 3. PR-0486 — the Mystery Box odds

Two defects, both live, both favouring the house.

**Odds.** `mysteryOdds` disclosed 3% jackpot / 7% for 600; `mysteryReward` rolled 2.5% / 7.5%.
Fixed by raising the ROLL to the disclosure (`..<0.975` → `..<0.97`) — never the reverse, so nothing
a player has already seen becomes a lie. **The 600 band absorbs the 0.5%**, and it is the only bucket
that needed to move because the disclosed table already said 7% there: the two tables now agree
**row-for-row**, not merely in total. EV 300.5 → 304.5 against a 300 price; coin-only 240.5 → 245,
still under cost, so D-026's structural rule holds.

**Copy.** `ShopView` said "1,200-coin jackpot" twice against a real 1,400, one of them the
`accessibilityLabel`. Both now interpolate `ShopConsumables.mysteryJackpotCoins`, which
`mysteryReward` also returns.

**Two corrections to the handoff.** §4 said "The existing 'odds sum to 100 %' test stays green
without being edited." **There is no such test** — `grep -rn mysteryOdds Tests/` was empty, and the
displayed table had zero coverage. That absence *is* the reason a 3-vs-2.5 gap survived; PR-0293 even
quoted the wrong "1,200-coin jackpot" string verbatim in its own symptom line.
`testTheDisclosedOddsAreTheRolledOdds` is the missing gate: it **integrates the shipped function**
over [0,1) at 200k samples and compares each measured band to its disclosed row, so it cannot drift
out of step with the weights the way a hand-written sum would.

## 4. D-1 — and the sentence in the handoff that was wrong

Full reasoning in **D-056** and **D-057**. The short version:

- The handoff's premise — author in the spec and *"both the in-run rig and all 24 previews follow"* —
  **was false.** S-018 derived the spec from the rig's literals and never wired the rig back. Two
  agents found this independently; I confirmed it by reading `buildCrest`. Following the handoff
  would have grown the preview and left the run alone: the S-018 defect, backwards.
- So the rig now reads the spec. Provably a no-op: `R * <spec>` reproduces every shipped literal to
  **6e-17 world units**.
- Then the crests grew **1.3x–1.94x**, on the rule *reach grows, seating does not*.
- **It cost nothing.** The envelope is bit-identical, because monarch's aura/antenna and the trail
  wisp set all three axes and no crest reaches past them. No call site moved. No allowance widened.

## 5. PR-0487 — the owner's mid-session report

> *"the mystery box opening from the loaing screen and the one from the store have different
> animations please fix"*

They were **two different objects**. `RewardBurstView` (free chest / daily, from the hub) drew a real
chest with a hinged lid; `MysteryBoxView` (shop) showed `Image(systemName: "gift.fill")` that wobbled
and never opened. Extracted `TreasureChest`, used by both; the Mystery Box hinges on the same spring
and now ends on an **open** chest above the prize, as the reward overlay does.

**Two bugs found only by watching frame-by-frame video** — both made the hinge run invisibly:

1. `phase = .opening` was animated with a **1.0 s** `easeIn` shared with the grow/glow. Because
   `phase` selects the `Group`'s `switch` branch, that stretched the `idleContent → boxView`
   cross-fade across the whole sequence, so what was on screen when the lid moved was the *outgoing
   snapshot*, which does not re-render.
2. `lid` and `wobble` were set in one `withAnimation` while `wobble` still carried
   `.repeatCount(14)`. The repeating curve won the transaction.

The reveal beat is unchanged at 1050 ms (the lid moved earlier, not the prize later).

**Method note worth keeping:** three separate attempts to catch the hinge with stills failed, and I
twice concluded it worked when it did not. What settled it was `simctl io recordVideo` + `ffmpeg`
frame extraction + a pixel measurement of the chest's bounding box. **For an animation claim,
screenshots are not evidence.** Also: the displayed screenshot is downscaled non-uniformly from the
true 1206×2622 @3x buffer — reading tap coordinates off it is how I bought a Shield Pack by accident.
Use `xcrun simctl io … screenshot` and divide by 3.

## 6. Investigations on disk

Six investigations + six hostile verifications at `docs/agent/audits/scratch/s019_*.md`.
**Every verifier returned PARTIALLY REFUTED** — the S-018 pattern held exactly.

| file | headline |
|---|---|
| `s019_consumers.md` | widening `BodyShape` yields only **two** CI-visible compile errors; **five sites fail silently**; `Prop` has **no forcing function into `extent`** |
| `s019_crests.md` | the uplift is free; the rig does not read the spec (found independently) |
| `s019_bodyshapes.md` | extent arithmetic sound; **two geometry models wrong**, one producing a constant that would be typed straight in |
| `s019_props.md` | headline survives; **eleven other things wrong, five in geometry a builder would type verbatim** |
| `s019_motion.md` | `advanceVisuals` really has zero coverage; **four load-bearing numbers wrong**, one specified test does not compile |
| `s019_assets.md` | **headless RealityKit WORKS** (D-058); three of its 24 rendered previews are cropped and all 24 mis-sized |

> ⚠️ **A real hazard, recorded:** the assets agent's flagship visual evidence was invalidated
> mid-flight because I enlarged the crest constants while it was running. **Do not edit files an
> investigation is reading.** Either freeze the tree or finish the fan-out first.

## 7. What did NOT get done, and why

The handoff's D-2 (body shapes + prop slot), D-4 (run cycles) and the model half of D-3 are **not
started**. The designs exist and are adversarially reviewed, but every one of those reviews found
geometry errors that a builder would otherwise have typed in verbatim — so the designs need a
correction pass before they are safe to build from, which is exactly what §8 of `HANDOFF.md` says.

This is the handoff's own stated good outcome ("if the pass runs out of room after step 3, that is a
good outcome, not a failure") landing one step earlier than hoped, with the prerequisite nobody knew
about (D-056) discovered and paid for.
