# Session 014 — THE WARDEN: lethality, and the arena as a place

**Commit:** `f95363a` (`PR-0462`). Recovery tag `pre-s014`.
**Suite:** 266 SPM tests green (was 261). Simulator build green. Verified on device at all three ranks.
**`DailyChallenge.layoutVersion`: 12, untouched.** v13 stays pre-armed at `0x9E49_3424_C18A_59C5`.

The owner's instruction, closing S-013, was four things in one sentence:

> *"yeah he should be able to kill you at some point. i still need you to revise the warden so many
> times and test test test like a human because it still feels very empty."*

---

## 1. The thing that mattered most: I played it

Thirteen sessions verified this game with `Autopilot` — perfect information, zero latency — and with
autoplay captures in which the bot plays flawlessly. **Nobody had ever used real touch input.** That
is the mechanism behind "it still feels empty" surviving a session that fixed nine complaints: feel
is not in the test suite.

`mcp__Claude_Code_iOS_Simulator__control` drives real gestures. Full report and captures:
`docs/agent/audits/scratch/s014_play_report.md`, `docs/agent/scratch/s014/*.mp4`.

**Method note for the next session:** record with `simctl io recordVideo` and review contact sheets
built with `ffmpeg -ss <t> -i f.mp4 -vf "fps=2,scale=250:-1,tile=4x3" -frames:v 1 sheet.png`. That is
24 game states per image at real speed. Screenshots throttle the app into slow motion; video does
not. Use OUTPUT seeking (`-i file -ss t`).

### The three findings the suite structurally could not produce

1. **`HIT — IT SHRUGS IT OFF` fires ~10 times per rank-1 encounter.** The most repeated sentence in
   the fight told the player their mistake was free. That is the weightlessness D-037 revokes,
   rendered in words, once every 1.5 s.
2. **D-034's "the red is gone" is false.** `EffectsOverlay.swift:230` was `Color(red: 1, green: 0.20,
   blue: 0.33)` — exactly `0xFF3355` — and `stumbleAura` put a red torus on the player. D-034 took
   the red off the *hazards* and left it on the *hit feedback*, which fires far more often than any
   hazard is on screen. **~15 of 42 sampled frames were red-framed.** Inside an arena the screen was
   red more of the time than it was not.
3. **`WorldDecor.style` disables every side silhouette for folded ordinal ≥ 3 — and Wardens live at
   worlds 3, 6 and 9.** The three arenas a player meets are the *only* stretches in the game with no
   side decor at all. Stacked on `Warden.suppresses`, **the boss arena is emptier than open track.**
   D-038 measured the gaps between throws and missed this entirely.

Also found by playing: the death panel never mentioned the Warden, so a player could not tell whether
they had beaten it, lost to it, or whether it had been involved; and at rank 3 the hazards' violet
sits on world 9's violet grid — D-034 checked its hue against gems and shield cyan but never against
the world palettes.

---

## 2. D-039 — it can kill you

**`Tuning.wardenStrikesSurvivedByRank = [nil, 3, 2]`.** Rank 1 never kills; rank 2 kills on the 4th
landed hazard, rank 3 on the 3rd.

**S-013's recommended 3/2/1 is refuted, and playing it is what refuted it.** Its reasoning was that
rank 1 stays unkillable because "its script only has room for so many misses". The script *repeats* —
the 17.5 s clock and the 1.55 s interval set the throw count, and a rank-1 Warden lands **~10–11
hazards on a player who makes no inputs at all** (measured on device; derived independently by the
research pass). A budget of 3 there kills a first-timer 5.6 s into the first Warden they ever meet,
which D-037 forbids in its own text.

**Rank alone is not enough**, and this is the easy thing to miss: rank is a property of the WORLD, and
71% of the coin catalogue leads to world 9 — a rank-3 arena. So lethality is *also* gated on
`GameCore.wardenLethalityUnlocked`, counting `Profile.wardensMet`, **the same counter that retires
the verb coaching**. The game never kills you with a thing it is still teaching you. `Core/` cannot
read a profile, so the count is handed in at `startRun(wardensMetBefore:)`, defaulting to `Int.max`
("fully taught") so every existing caller and the whole suite measure the dangerous configuration.

**The shield.** D-036 put `fromWarden` before `shield` because nothing in an arena could kill — the
premise D-037 revokes. Both halves hold now: never spent on a survivable hazard, always spent on the
fatal one. It fires *before* the strike counter moves, so absorbing leaves the player at the brink
rather than one past a budget the HUD would have to draw more pips than it owns.

### The gate, measured on both sides and in the middle

```
[lagged] humanFloor (0.40 s):   0 hazards landed, 0/24 runs died
[lagged] sluggish  (0.75 s): 241 hazards landed, 16/64 Wardens killed, 24/24 runs ended by one

[lagged] reaction → deaths/12, hazards landed:
         0.400 s →  0/12     0        0.600 s →  0/12    14
         0.450 s →  0/12     0        0.650 s →  1/12    34
         0.500 s →  0/12     0        0.700 s →  3/12    45
         0.550 s →  0/12     1        0.750 s → 12/12   113
```

A **gradient, not a step**: the budget absorbs ordinary imperfection and only punishes sustained
inattention. `testTheDifficultyCurveBetweenTheTwoGatesIsMonotonic` pins that shape and would catch an
inverted window of the kind D-032 records.

---

## 3. D-040 — the arena is a place

`PrismRush/Render/Reality/ArenaShell.swift` (new, 280 lines). Ribs at x ±5.6 every 22 m, a continuous
kerb at x ±4.5, gates at the mouth and the exit, and a four-line deck tint (one bit folded into the
palette cache key; lane and grid mixed 20% toward the dim violet).

Constraints held and verified on screen: **nothing crosses a lane** (all outboard of x ±4.2 or above
y 11 — zero added frontal area in the corridor), max section 0.55 u, **no new motion** (static in
world space; nothing for Reduce Motion to gate, nothing competing with the 7 Hz stumble strobe),
**no RNG at all**. It touches no `SpawnCmd`, so the 200-seed proof, every daily golden and
`layoutVersion` are untouched by its existence.

The craft also stopped being furniture: `WardenState.throwCharge` (presentation-only) drives a
wind-up over the last 38% of every gap — yaw eases to a halt instead of being cut, hull pitches
nose-down ~14° and swells 4%. **Not a shorter gap**, which `testTwoThrowsAreNeverInFlightAtOnce` and
`LaggedAutopilotTests` both forbid. The dead air becomes the tell.

---

## 4. D-041 — the red is spent, not deleted

Red now means exactly one thing and appears nowhere else: **the next contact ends the run.** A
survivable Warden strike is violet in all three channels (vignette, player ring, popup), so the fight
speaks one colour. Red returns at the moment the budget is spent, alongside `HIT — ONE MORE ENDS IT`
— the string S-013 had to delete as a lie. And `THE WARDEN GOT YOU` replaces `SHATTERED` when a boss
ended the run.

Verified on device at rank 2 and rank 3: three violet strikes → red frame + honest warning → shield
absorbing the fatal one → `THE WARDEN GOT YOU`.

---

## 5. What I did NOT do, and why

- **Audio.** The research (`docs/agent/audits/scratch/s014_audio.md`) found something worse than
  D-038 recorded: a Warden hazard landing on you plays `.shieldBreak` with **no `fromWarden`
  branch** — the same buffer as a wall clip, your own shield breaking, the Warden's armour breaking,
  and a blast shattering walls. **One buffer, five meanings, three opposite in valence**, and under
  D-039 it is now the sound the whole fight turns on. There is also one 1.82 s music loop for the
  entire session, so a boss sounds exactly like open track. The file carries a costed design for
  both (a defaulted `fight: Float` on `Synth.step`, no new audio node). **I did not ship it**, for
  the same reason S-010/S-012/S-013 didn't: nothing in this program can hear a sound. This has now
  compounded four times and is a real part of "empty" — it needs Rayan's ears, and the design is
  ready for the moment it gets them.
- **The sky does not dim inside an arena.** At rank 3 world 9's pink halo fills two thirds of the
  frame and the craft is drawn on top of it — the boss has *less* visual authority at rank 3 than at
  rank 1, which is backwards. The arena shell improves it (the craft now sits inside a structure) but
  does not fix it. `docs/agent/audits/scratch/s014_camera_post.md` has the camera/post design.
- **Hazard violet vs. world violet.** Rank 3 lives in world 9, whose grid is violet. Filed, not
  fixed.
