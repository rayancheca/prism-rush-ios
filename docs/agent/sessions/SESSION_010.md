# Session 010 — the stumble, and giving the Warden a body

**Date:** 2026-07-30 · **Branch:** `main` · **Recovery tag:** `pre-s010` (`e42ac8b`)
**Commits:** `bd8df3b`, `ac818a9`, `60a9985`
**Tests:** 218 → **231 SPM**, 0 failures. **238 Xcode unit tests**, 0 failures. 12 XCUITests green.
**`DailyChallenge.layoutVersion` is STILL 10.** The pre-armed v11 golden is still unspent.

Session 009 left three priorities, all with the owner's answers already on record. Two were built.
The third is his call and is surfaced, not spent.

---

## 1. THE STUMBLE (priority 1 — built)

> *"functionality like subway surfers where you basically have two lives. if you half hit a wall you
> slow down for a sec… not two lives per say more like 1.5."*
> Plus: a Warden beam **stumbles first then kills**, and a stumble **resets the multiplier**.

Until now the game had no vocabulary for *harm* — a contact either did nothing or ended the run.
That absence is also why S-008 reached for "the Warden leaves" as its only non-lethal lever and got
a polite antagonist.

**The rule, once:** a contact is a stumble when the smallest move that would have made it a clean
pass is shallow, measured on the axis whose VERB answers that obstacle, at the instant the overlap
begins.

| kind | axis | threshold |
|---|---|---|
| `tall` / `movingTall` | lateral | kill line 1.25 → 0.90 |
| `low` | lateral OR vertical | feet within 0.20 of clearing |
| `bar` | vertical, both edges | slid almost low enough / jumped almost high enough |
| `splitBar` | escape-to-gap OR vertical | — |
| `chasm` | **never** | no shallow overlap in an 8 m hole |

Design reasoning is in **D-020**. Three things worth carrying forward:

- **The kill line moved inward rather than the near-miss band being eaten.** CLOSE ([1.25, 1.95)) is
  untouched, so nothing that used to pay a bonus now costs a multiplier.
- **The split bar is why the measure is ESCAPE, not penetration.** A player dead between two covered
  lanes is 0.15 into each — "shallow in both" — and 2.35 units from any safe position.
- **Per-encounter, not a timer, for the Warden.** Strikes are 1.05–1.20 s apart; any window short
  enough to feel like a stagger expires before the next strike, so a timer rule would leave a Warden
  unable to kill anyone.

### The mandatory test change, and what it proved

`SolvabilityBotTests` decided "unfair" only by asking whether the bot **died**. Make contact
survivable and an unanswerable pattern becomes a green stagger. It now asserts **zero contacts**
across 200 seeds × 6,000 m and the 12,000 m soak — and it passes, because `Autopilot` plays
perfectly and never enters a graze band.

**The two-sided hardness gate got STRONGER:**

| reaction | before | after |
|---|---|---|
| 0.40 s (human floor) | 0 deaths | 0 deaths **and 0 beams land at all** (new assertion) |
| 0.75 s (sluggish) | some die | **24/24 die, 24 beams land** — exactly one rescue, then death |

That 24/24-with-24-beams figure is the mechanic working exactly as specified, measured.

### What it cost on the simulator — two rejections

Neither was visible from the code, and `swift test` compiles neither `UI/` nor `Render/`.

1. **The vulnerability shell read as a shadow.** A 30 %-opacity unlit red sphere over a bright
   character composites to a muddy dark disc. Replaced with an opaque ring — which then failed too,
   for a reason worth recording: **Prism wears a static rainbow (D-011), so a steady red ring reads
   as one more of its own bands** — and Prism is the default character. The fix is the **strobe**,
   not the hue: nothing else in this game blinks.
2. **A HUD chip was the wrong shape of thing.** It reflowed the whole top-right stack every 0.9 s,
   and the centred world banner drew straight through it. Replaced with a screen-edge vignette —
   whose first version was *also* wrong: fixed 260–620 pt radii on a 402 pt screen put the entire
   visible frame mid-ramp and rendered as a full-screen magenta wash. All radii are now derived from
   the live frame, and the centre third stays untinted at every urgency.

---

## 2. THE WARDEN PRESENCE PASS (priority 2 — steps 1–2 of `s009c_SPEC.md` §6 built)

> *"its just a basic triangle. no animations. nothing to tell you what it is or what it does.
> no screen shake. no effects. same every time. same functionality every time."*

Four of the six are answered. **Not built: "no screen shake / no effects" (spec step 3) and the
per-world species (step 6).**

- **Scale ×1.70** — 0.46 % of frame → ~2.2 %. Derived, not taste: an ordinary wall painted 4× the
  shipped craft, so the floor for a boss is "bigger than a wall" ≈ 1.84 %.
- **Form.** Under `UnlitMaterial` there are no normals, so a single-colour body *is* a silhouette —
  that is the literal content of "basic triangle". Now a banded disc with a one-value-darker keel, a
  three-slot dome, and a bright rim.
- **Circular in plan**, not the shipped octahedron: a rhombic plan swings its projected half-width
  43 % per half revolution, detaching the circular rim by up to 142 px and killing yaw-invariance.
- **The shed.** Six pooled spars, `coreHitsNeeded` shown, one detaching per hit, outermost-first
  alternating (n=5 → 4,0,3,1,2) so what reads is the **span narrowing**.
- **Deleted:** the shrinking core (a third redundant readout that made the boss *less* visible the
  closer it was to dying) and the 34° instantaneous yaw snap — a discontinuity, and the only
  "animation" the craft had. Replaced with constant idle yaw that stops dead on a telegraph, and a
  halo spinning 42 → 202 °/s as the shield fails.
- **The gun beam had never been seen working.** It reached the right *depth* and ran horizontally at
  y 1.05 while the craft hovers at 4.2 — it passed **3.1 units under the hull**. Now aimed with
  `look(at:)`, length = true 3-D distance, and always shield-cyan (red means "this can kill you"
  everywhere else in the rig, and the player's own gun is never lethal to the player).
- **BUG C finished.** `x` is zero for **all** of `.exposed`, not just during a wind-up.
- **`resetRig()`** — not tidying. The rig is built once and reused; a run reaching world 9 fights
  three Wardens with the same entities, and without it the second arrives dismembered.

**Three spec numbers did not survive contact** — see **D-022**. One was an arithmetic slip (the halo
clearance omitted the torus minor radius, leaving 2 px instead of the 26 px it required); two were
caught by nothing except running the app and looking (the core was invisible under an opaque hull
for the whole exposed phase while the HUD read "CORE EXPOSED"; near-white spars on a pale hull
vanished).

---

## 3. THE POST-KILL DEAD AIR (priority 3 — NOT spent, by design)

Measured in `s009b_probe_pacing.md`: **5.4–10.4 s** of visibly empty deck after the fight, against a
normal beat of 0.34 s, and the **longest hole belongs to the weakest player**. Structural — a
variable-length fight inside a fixed-length arena sized for the worst case.

This is the one item that costs a `layoutVersion` bump. **It needs Rayan's call and it did not get
one**, so the pre-armed v11 golden is deliberately still unspent.

---

## 4. A correction to the record (D-021)

The S-009b probe recorded the spawner as fully cursor-driven, so a speed change could not move a
spawn. **Half right.** Pattern content and order are cursor-pure, but `Spawner.gapFor(dist)` takes
the player's **live distance**, so any speed change nudges every later `d` by ~0.0002 m at 184 m.

Chrono and the overdrive boost have done exactly this for versions — proved in
`testStumblingPerturbsTheTrackNoMoreThanAShippedPowerUpDoes`, which pins all three against the same
baseline. **This answers PR-0052 from the code:** the daily challenge has never been able to promise
an identical *experience*, only an identical *layout*.

---

## Verification

- `swift test -c release` → **231 tests, 0 failures**.
- `xcodebuild test` → **238 unit tests, 0 failures**; 12 XCUITests green.
- One XCUITest (`testMuteIsReversibleFromSettings`) failed mid-session and was **not** a regression:
  repeated `simctl install` without `uninstall` had left `muted=1` in the profile. It passes on a
  clean profile — verified by uninstalling and re-running it alone.
- Six simulator captures across five rebuild-and-look cycles. Every visual claim above was checked
  by opening the PNG, and three of them were rejected and rebuilt on what the PNG showed.

## New debug hook

`PR_STUMBLE=1` holds the player permanently staggered (re-armed as the window expires) so the ring,
the vignette and the impact FX can be captured — `stumbleRecover` is 0.9 s, far shorter than a
launch-to-screenshot round trip, and the Autopilot never stumbles on its own.
