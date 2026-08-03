# S-014 — I played the Warden. Here is what it feels like.

**Instrument:** `mcp__Claude_Code_iOS_Simulator__control` driving real touch input on
`10C15FE0-3D9A-40D5-9E45-C0702E906DF3`, plus `simctl io recordVideo` at real speed (no screenshots
during capture, so no slow-motion distortion). Build: `.dd/Build/Products/Debug-iphonesimulator`,
verified to contain S-013's strings (`INCOMING`, `WARDEN AHEAD`, `SWIPE DOWN TO SLIDE`) before
anything below was written. Fresh profile (`simctl uninstall` first) so `wardensMet == 0` and the
coaching was live.

Captures kept in `docs/agent/scratch/s014/`:
`play_rank1.mp4`, `idle_rank1.mp4` (28 s, full rank-1 encounter, zero inputs),
`idle_rank3.mp4` (28 s, full rank-3 encounter, zero inputs), and the contact sheets
`sheet_idle_a.png`, `sheet_idle_b.png`, `sheet_r3_a.png` (2 fps, 24 frames each).

---

## The one-sentence verdict

**It is not a fight, it is weather.** Things fall on you at a steady rate, the game tells you ten
times that they did not matter, the boss never moves or reacts, the arena is the emptiest stretch of
deck in the game, and then a small grey line says `WARDEN WITHDREW` and the track resumes.

---

## What actually happened, run by run

### Run 1 — I played it, badly, and never learned I had

I launched at the first Warden with a full charge bank and made **exactly one input** (a lane change
left, answering a lance). Twenty-six seconds later I was dead at 3,247 m — killed not by the Warden
but by an ordinary obstacle 77 m *past* the arena, because I was still parked in lane 0 and had
stopped paying attention.

The death panel said `847m · World 5`. **It said nothing about the Warden at all.** I did not know
whether I had beaten it, lost to it, or whether it had even finished. A boss fight that leaves no
trace in the result screen is not an event.

### Run 2 — rank 1, zero inputs, full 26 s capture

The encounter ran 2,400 m → 2,858 m (≈ 15.5 s), landed **roughly 13 hazards on a completely
stationary player**, and ended `WARDEN WITHDREW`. Then the arena continued to 3,170 m —
**another ~312 m ≈ 10 s of totally empty deck with the boss already gone.**

### Run 3 — rank 3, zero inputs

Same shape, more hazards, `INCOMING — MOVE!` coaching appearing for the aimed shots. Also
unsurvivable-proof: it hit me a dozen times and could not kill me.

---

## The findings, in the order they hit me while playing

### 1. Every hit tells you it did not matter — ten times per fight

`HIT — IT SHRUGS IT OFF` (`GameView.swift:701`) fires on every landed hazard. In one rank-1
encounter I read that sentence about **ten times**. It is the single most repeated piece of text in
the fight, and its content is "your mistake was free". That is the whole of the weightlessness
D-037 revokes, rendered in words, once per second and a half.

### 2. THE SCREEN IS RED, AND D-034 IS WRONG ABOUT THIS

D-034 says *"the red is gone"*. **It is not.** `EffectsOverlay.swift:230` is
`Color(red: 1, green: 0.20, blue: 0.33)` — that is exactly `0xFF3355`, the colour the decision
claims was deleted. It is the hurt vignette, and `RealityRenderer.swift:1040` adds a red torus
(`stumbleAura`) around the player on top of it.

D-034 removed `0xFF3355` from the *hazards*. It left it on the *hit feedback* — which fires far more
often than any hazard is on screen. **Counting frames on the rank-1 contact sheets, roughly 15 of 42
sampled frames have a full red screen-edge vignette and a red ring on the player.** Inside a Warden
arena the screen is red more of the time than it is not, which is the exact thing the owner said he
hated, in the exact place he was looking when he said it.

*This is not an argument for deleting red.* It is an argument for **spending** it: see the
recommendation at the bottom.

### 3. The boss does nothing. Across 42 sampled frames the craft is pixel-identical

Same grey saucer, same pose, same constant cyan beam pointing straight down the middle. It does not
wind up, does not tell, does not aim, does not flinch when answered, does not react to being
damaged, does not lean into the throw in any way I could see at playing distance. D-038's *"a boss
in the sky doing nothing"* is literally accurate — I could not distinguish the frame before a throw
from the frame after one by looking at the craft.

### 4. At rank 3, the world's wallpaper upstages the boss

World 9's sky is a giant pink-and-gold concentric halo that fills the top two thirds of the frame.
The Warden — a small grey saucer — is drawn *on top of it* and nearly vanishes into it. **The boss
has less visual authority at rank 3 than at rank 1**, which is exactly backwards. Nothing dims the
sky, changes the lighting, or gives the set piece the frame.

### 5. At rank 3 the hazards are the same hue as the deck

World 9's track grid is violet. D-034 chose violet `0xC77BFF` for Warden hazards because it is far
in hue from gold gems and shield cyan — but it was never checked against the **world palettes**. At
7,325 m the two thrown walls are hard to separate from the grid lines behind them. That is a
legibility failure at the rank with the shortest reaction window (0.62 s).

### 6. The arena is furnished *less* than open track

The frame at 2,406 m (just before the mouth) has the world's dark-teal decor arc on the left. Every
frame from 2,418 m on has **black sky, blue grid, saucer, gems — and nothing else**. The player
crosses into the boss arena and the world gets *emptier*. `Warden.suppresses` is doing exactly what
it was written to do, and the result is that the most important 770 m in the game is the least
furnished.

### 7. There is no "you are out" beat, and no "you won/lost" beat

`WARDEN WITHDREW` is small, grey, and sits in the same popup slot as `+50`. Then ~10 s of empty
deck. Then ordinary track resumes with no transition — which is how I died in run 1.

### 8. What *does* work, and should not be broken

- The verb coaching is genuinely good. `SWIPE TO MOVE` → `SWIPE UP TO JUMP` → `SWIPE DOWN TO SLIDE`
  → `INCOMING — MOVE!` tracked the script correctly every time, and it reads.
- The lance is unambiguous: two walls, one lane open, and I could see which in a single frame.
- The portcullis (hanging bar) reads as a grille, not a gap — D-034's rebuild works.
- The arena-as-gem-field works. There is always something to pick up.

---

## What I would change, in priority order

1. **Spend the red instead of deleting it.** A Warden strike should flash the Warden's own violet,
   not `0xFF3355` — the fight then speaks one colour. Keep red for exactly one meaning: *the next
   one kills you*. That makes red rare, makes it mean something, answers the owner's complaint
   honestly, and gives D-037's strike budget a free readout that needs no new HUD element.
2. **`HIT — IT SHRUGS IT OFF` must become true.** With a strike budget it becomes
   `HIT — ONE MORE ENDS IT` on the last strike, which is the string S-013 had to delete as a lie.
3. **Furnish the arena.** It touches no gameplay rule — `Warden.suppresses` filters `SpawnCmd`s and
   cannot see decor.
4. **Give the craft a wind-up.** 0.4–0.7 s of dead air is not too short to fill; it is exactly long
   enough for a tell. And a tell converts dead air into tension without shortening a single gap,
   which is what `LaggedAutopilotTests` and the one-throw-at-a-time invariant both forbid.
5. **Let the boss own the frame.** Dim the world sky inside the arena. At rank 3 this is not polish,
   it is legibility.
6. **Say what happened.** A kill and a withdrawal must not look alike, and the run summary should
   record that a Warden was met.
