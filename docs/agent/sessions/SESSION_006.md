# Session 006 — the chasm, and two things Rayan asked for mid-session

**Goal on entry:** PR-0450 — the pattern catalogue had been 14 since v1.3, fully unlocked at
1,920 m. S-004 built an act two that changes how *often* you meet those 14; nothing new to meet.

**Delivered:** tier six and a new verb (PR-0450), plus two owner requests that arrived mid-session
and outranked everything queued: the slide SFX (PR-0454) and Prism's colour shimmer (PR-0455).

Recovery tag `pre-s006`. Worked directly on `main`, as S-005 did.

---

## 1. THE CHASM — PR-0450

A full-width 8 u gap in the deck. `EntityKind.chasm`, `SpawnCmd.chasm`, `Collisions.chasmHit`,
pattern 14, tier six at 2,560 m, `layoutVersion` 8 → 9.

**What makes it a new KIND of moment rather than a recombination.** It is the catalogue's first
obstacle with an EXTENT rather than a plane, and its first **two-sided timing window**. Every other
jump in the game is one-sided — clear a plane, and jumping early is free — so nothing until now
punished going too *soon*. Go early at a chasm and you land in it.

The window is symmetric by construction: the gap is centred on the APEX of the jump its gem arc
cues, so launch slack is ~±0.25 s at every speed (±7.5 u at the tier's unlock speed, ±8.5 u at the
cap), the same order as `jumpBuffer`. Pinned by
`PatternOrderTests.testChasmSitsAtTheApexSoItsWindowIsSymmetric`, which derives the airborne window
from the ballistic constants rather than from `Patterns`.

**Taught with the device the catalogue already owns.** Pattern 1's contract is "the arc jump IS the
survival jump". So: a 3-gem run-up on the standard 1.7 spacing pulls the player into a lane, arc
gem 0 lands as the launch cue, and three of the seven arc gems hang over the void — the reward is
collected mid-flight. This pattern prices TIMING, not routing, and grows no greed line by
construction (it closes no lane, so `greedLane` returns nil).

### Why tier six sits at 2,560 m — pinned from both sides (D-010)

- **Above:** a good run is ~3,300 m, so a later gate is one most players never meet. The whole
  complaint was that the last new thing arrived at 1,920 m.
- **Below:** act two draws from `Spawner.pool`, a slot table that **bypasses `maxIndex` entirely**.
  Any gate later than `actTwoAt` (3,200 m) would let the table spawn a pattern the ladder had not
  unlocked. `DifficultyTests.testEveryWaveKeepsTheFullCatalogueReachable` probes d = 3,300.

2,560 m (diff 0.8) is the one band satisfying both. Below it `maxIndex` returns a **literal 14** —
what `Patterns.count` used to evaluate to — so every draw under the gate is byte-identical to v1.7.

### Iron rule 4, amended rather than routed around

The old shorthand was "moving walls stay LAST". Tier six puts the chasm behind them. Moving walls
are now the last entry of tier FIVE (index 13, still exclusive to it); the chasm is index 14. The
rule's actual content — every tier is a prefix, a pattern's index is its unlock rank — is unchanged.
`CLAUDE.md` and `PatternOrderTests` both updated to pin literal indices.

### Measured — the step (`DifficultyCurveTests`, 64 seeds)

```
  band(m)      obst/100m  inputs/100m  gems/100m  priced%  rest%  chasm/km  phase
      0- 1200       5.28         3.01       41.2     0.7%  35.9%      0.00  act 1
   1200- 2400       5.61         3.68       42.2    10.5%  28.4%      0.00  act 1
   2400- 2560       6.21         4.18       38.8    10.9%  17.5%      0.00  act 1 t5
   2560- 3200       6.06         3.54       41.3    14.2%  18.0%      1.84  act 1 t6
   3200- 4267       6.33         4.08       40.6    12.3%  18.6%      1.06  act 2 w1
   4267- 6400       6.96         4.22       37.3    12.1%  15.3%      1.41  act 2 w2
   6400- 9600       7.36         4.84       37.9    13.5%   9.0%      2.20  act 2 w3
```

Below the gate the chasm is not rare, it is **impossible** — the ladder cannot select index 14 and
the spawn cursor never runs behind the player. Act two's own escalation survives intact.

### Two variants measured and REJECTED (D-010)

The chasm pattern is deliberately sparse — one obstacle across ~34 m against a catalogue average
near six per 100 m — so every act-two slot it gains costs obstacle density.

| variant | act two opening band | deepest band | verdict |
|---|---|---|---|
| chasm in wave 1 | **5.95** (below the act-one band before it), rest 25.1% | 7.36 | FAILED PR-0400's gate |
| + an extra pattern 5 to compensate | 6.19 | **6.87** (dragged down) | FAILED |
| no wave-1 slot (shipped) | 6.33 | 7.36 | passes |

Density escalation is load-bearing for the endgame; chasm-frequency smoothness is not. The residual
dip (1.84 → 1.06 → 2.20/km) is accepted and written on `Spawner.poolWave1`.

**What the instrument cannot see:** it counts input EDGES, not input *precision*. A chasm costs one
jump, exactly like a low — but with a ±0.25 s window against the low's ±0.64 s. Every number above
therefore *undervalues* the chasm. Recorded so nobody tunes against them.

### Invariant 2, discharged in full

- 200-seed × 6,000 m bot **and** the 12,000 m soak: green, first run. The Autopilot needed one new
  rule (jump at `0.28·v` before the LEADING rim; never air-slam while over the void) and the lead
  sits mid-range at every speed the chasm can appear at, with > 7 u of margin either side.
- `layoutVersion` 8 → 9; goldens repinned in `DailyChallengeTests` **and**
  `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`. All derived in Python from the
  SplitMix64 constants — the script reproduced all seven pre-existing pins first, which is what
  makes the new three trustworthy. A v10 pin is pre-armed.
- **New guard: `testTheSoakActuallyDrivesTheBotAcrossChasms`.** A 200-seed proof that never meets
  the hazard is not a proof. This asserts every 6,000 m run encounters the tier-six pattern and the
  bot clears it, so a moved gate / edited pool / zeroed cap turns the soak red instead of leaving it
  green and meaningless.

### The visual took two rounds on the simulator, and neither failure was visible statically

1. **Near-black well → invisible.** The deck is already black with neon grid lines, so an 8 u gap
   rendered as two gold stripes lying on the track. A player would read that as a bar and SLIDE —
   the wrong verb, i.e. a decree-6 failure, not a polish nit.
2. **Visible walls were still not enough**, and the reason is geometry rather than colour: a chase
   camera this low **cannot see into a hole** until it is nearly on top of it, so depth cues arrive
   long after the jump had to be committed.

What carries the read is **interrupting the deck's grid**: an opaque lid at y 0.045 (above the rungs
and lane lines, below the 0.05 boost-pad decal) so the glowing track visibly STOPS for 8 m —
legible at the full 65 m of backdrop lead. The well underneath still does its job close-up and at
the apex. Before/after: `scratch/s006/chasm_11.png` → `v5_3_crop.png`.

Every face is double-wound: nothing sets `faceCulling`, and `ProceduralMesh.build` falls back to a
plain **sphere** on a bad descriptor with no log and no test failure — two silent ways this could
have shipped looking wrong with a green suite.

Added `PR_CHASM=1` (same shape as `PR_SHIELD`/`PR_SNEAKERS`) so the gap is inspectable head-on.

---

## 2. The slide sound — PR-0454 (Rayan, mid-session)

> *"i really dont like the sound the game makes whenever you slide. its so harsh and horrible."*

Two structural causes, not taste:

1. **No attack.** The burst hit full amplitude on sample 0. An instantaneous broadband onset is a
   click; the game's other percussive cues are tones and get away with it.
2. **6 dB/oct at 600 Hz** still passes plenty of 2–5 kHz — the band the ear is most sensitive to.

`Synth.noise` gained `attack` and `poles`, both defaulted so every existing caller is byte-identical.
Slide is now a 35% ramped, two-pole 320 Hz whoosh at vol 0.14 (was one-pole 600 Hz at 0.20) over a
softer low anchor, 0.20 s so the ramp has room — still far inside `slideDuration` 0.55.

**PR-0320 turned out to be live and worse than filed:** `swell:` was *declared and never applied* —
the body always used `(1 - frac)`, so all four callers asking for a whoosh that builds got one that
dies. It read correctly at every call site and did nothing, which is why it survived. Now
implemented.

**And `.slid` is now edge-triggered.** The Autopilot re-arms the slide every tick, and `.slid`
drives both the SFX and the `slidesThisRun` mission counter — so autoplay/demo runs played **120
overlapping slide sounds a second** and counted ticks rather than slides. Human play (one swipe =
one sound) is unaffected; the re-arm itself is unchanged.

**Unverifiable here.** No agent in this program can hear the output. This is DSP reasoning plus the
existing sanity tests. Needs Rayan's ears.

---

## 3. Prism's shimmer — PR-0455 / D-009 (Rayan, mid-session)

> *"idk if its just for the test or what but you reverted my choice back several months. why does
> the character change colours as it runs. that defeats the whole purpose of having different
> characters"*

**Nothing was reverted, and the record should say so plainly.** No character code was touched in
S-006 before this; 23 of the 24 skins have always carried fixed authored hexes. What he saw is
Prism — the *default* runner — cycling cyan → magenta → amber on an 8 s wall clock (`isPrismatic`),
which landed in **v1.4.2** as part of the fix that stopped skins following the world palette, and
has shipped ever since. S-005's handoff explicitly recorded it as decree-compliant *because it is
world-blind*.

**That reading was too literal and is overturned (D-009).** The point of decree 1 is that a roster
means something; a default runner that recolours as it runs defeats that as thoroughly as one that
tracks the world. Decree 1 now covers **space and time**.

Prism is its authored cyan `0x00F5FF` with the magenta antenna — exactly what Reduce Motion users
already saw, so the still look was already designed and shipping. `isPrismatic`, `prismaticColor`,
`prismaticPeriod`, `prismaticStops` and the renderer's ~30 Hz shimmer clock are **deleted, not
disabled**: inert machinery is how the next session brings this back by accident. Prism gained an
explicit `trailHex`, so `trailHex == nil` no longer means "ride the shimmer" — the test now pins
that *every* skin authors its own trail.

Decree 2 holds by construction: swatch and rig both resolved through the same function, so both move
to `bodyHex` in lockstep.

### 3b. …and then a static rainbow (D-011)

> *"keep prism as a static rainbow, not solid cyan."*

Solid cyan removed the objection but also removed the reason the character is called Prism. The
correction is narrow and the distinction is the whole point: **decree 1 forbids an identity that
CHANGES, not one that is COMPLEX.** A fixed spectrum is one look — identical in frame 1, frame
100,000, and all twelve worlds. The test pins that by asserting there is no clock in the resolution
path, not by asserting pixels.

**The renderer is `UnlitMaterial` only** — one flat colour per entity, no textures, no shaders — so
a gradient was never available and the rainbow had to be built out of flat colour.
`ProceduralMesh.bandedSphere` emits ONE mesh with one PART per band; the caller supplies one
material per part. The body stays a single `ModelEntity` (squash, blink and the pose code all
address `playerBody`), so the spectrum is nothing but its material array.

**Bands split by equal HEIGHT, not equal angle.** On a sphere those are the same for surface area,
so bands read evenly wide instead of bunching at the poles — and it gives the 2-D swatch a rule it
can mirror exactly (clip to the silhouette, fill N equal-height strips). That is what makes decree 2
hold *by construction*: both layers derive from one list and one rule, not from two sets of numbers
somebody keeps in sync. A test pins spectral skins to `.sphere`, since that pairing is what exists.

Six bands top to bottom: magenta, violet, cyan, green, gold, orange-red. The cyan band is the
authored `bodyHex`, left unchanged because the glow, trail, wake and death burst all read from it.

Verified on all three surfaces: `prism_run_2_crop.png` (in-run rig), `prism_hub_crop.png` (hub
hero), `prism_chars_crop.png` (detail card) — same six bands, same order.

---

## Verification

```
swift test -c release        →  191 tests, 0 failures (~29 s)
xcodebuild test              →  198 unit + 11 XCUITest = 209, 0 failures  ** TEST SUCCEEDED **
./Tools/build.sh             →  BUILD OK
```

Simulator, world 9 autoplay: `docs/agent/scratch/s006/` — `chasm_*.png` (v1: unreadable),
`v3_*.png` (v2: walls, still unreadable), `v5_*.png` (shipped: grid interrupted, solid-cyan Prism).

## Filed

`PR-0454` (slide SFX), `PR-0455` (Prism identity). Closed: `PR-0450`, `PR-0320`.
Decisions: `D-009`, `D-010`, `D-011`.
