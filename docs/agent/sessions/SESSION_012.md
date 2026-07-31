# Session 012 — the blast, the Warden rebuilt, and the economy finished

**Date:** 2026-07-31 · **Recovery tag:** `pre-s012` · **Base:** `e010b69`

Three commits, each built and run on the simulator before it was claimed:

| commit | what |
|---|---|
| `3b1cb21` | **THE BLAST** — a double tap spends charge to destroy obstacles ahead (PR-0458, D-028) |
| `ae68fc7` | **THE WARDEN, rebuilt** — it can never kill you, and it throws real hazards (PR-0459, D-029/D-030) |
| `7871dd5` | **The economy finished** — E6 and E7 of `AUDIT_011_ECONOMY` §3 (PR-0460, D-031) |

**254 SPM tests green** (was 231). Xcode build OK throughout. `DailyChallenge.layoutVersion` is
**still 11** — the v12 pin remains pre-armed and unspent.

---

## What the session was asked for, and what it delivered

The handoff named four priorities. Three are done. **The fourth (obstacle variety) is NOT, and the
honest reason is that it is the only one that spends the `layoutVersion` bump** — see "What was left"
below, which is deliberately specific so S-013 can start on it cold.

---

## 1. THE BLAST (PR-0458)

The owner's own idea, and the answer to "what does CHARGED mean". Gems fill the bank, a double tap
spends it, and a shockwave destroys every destructible obstacle within 46 m ahead.

**The design work that mattered was proving it costs nothing.** Three claims, all measured:

- **The input window was already dead.** A buffered jump only survives to touchdown if tapped within
  `jumpBuffer` (0.25 s) of landing, i.e. later than 0.565 s into an 0.815 s arc. `blastTapWindow`
  (0.30 s) lies entirely inside the span the engine already discards. Tap 1 still fires `jump()` on
  the frame it arrives, so the game's most-used input gains no latency at all.
- **It does not change the track.** With the player's route frozen, 8 seeds place byte-identical
  obstacles with and without blasting. Under a driven bot, kind and lane never differ on any seed and
  positional drift maxes at **0.0027 m — less than half the 0.0063 m the shipped slow-mo deploy
  already causes** through the same D-021 mechanism. No `layoutVersion` bump owed.
- **The pool caps never bind** (peak live 12/18 low, 10/14 tall, 5/6 bar, 2/6 split, 2/3 chasm over
  12 seeds × 12,000 m), which is *why* freeing a slot cannot change spawning.

The HUD chip stopped saying `CHARGE · 37%` and started saying `⚡ BLAST ×2`. A percentage is not a
decision; rounds are what the player spends.

### Two defects only the simulator could find

1. The shockwave ring shipped at 2.6 → 7.0 world units and painted a fat cyan hoop across the exact
   rows the player has to read. Retuned to 1.6 → 4.6 — perspective already makes a ring near the
   camera enormous, so a scale curve that *also* starts wide is wrong twice.
2. A `BLAST · 2 LEFT` popup fired on every shot, duplicating the HUD chip in the same colour as the
   wave crossing the same rows. Deleted; only running dry gets a word now.

### And one the integration read found

`blast()` had no guard for having nothing to hit, and `Warden.suppresses` deliberately sweeps an
arena clear — so a reflexive double tap during a fight destroyed nothing and spent a third of the
bank, silently. A blast with no target is now refused, and the tap falls through to the jump it would
otherwise have been.

---

## 2. THE WARDEN, rebuilt (PR-0459)

The owner's verdict was that the fight is "a red thing that covers the screen". The S-011 render
audit had already put numbers on it: a full-width opaque red band on screen for **92–95% of the
exposed phase**, a 100 ms dark gap between shapes, a curtain erasing **100% of the track beyond
5.3 m**, and a floor delivering **379 of its final 440 px in a single frame**.

**The Warden now has no attack of its own. It has no collision rule at all.** It throws real
obstacles onto the real deck, and the S-009 verb trichotomy survives one-for-one:

| was | is | answer |
|---|---|---|
| lance (per-lane red columns) | two `tall` walls, one lane open | change lane |
| floor (red slab on the deck) | a `chasm` blown in the deck | jump |
| curtain (red wall from the sky) | a `hangingBar` | slide, and **only** slide |

Travel time is the telegraph. Nothing new moves: a thrown hazard is static in world space and the
world scrolls it in, so `z = distance − d` still describes it.

### It can never kill you (D-029)

Not "forgives once" — never. v2.1's forgiveness was skippable anyway: the lethal branch required
`stumbleT <= 0` while `stumbleT` runs 0.90 s against a 0.15 s grace, so **any wall clip in the 60 m
before the arena mouth made the FIRST Warden hit lethal.** A landed hazard now costs the multiplier,
the tempo, one blast round, and the answer it would have been worth.

### The number that was wrong, and how the tests said so

The first build used a 46 m throw lead, reasoning that more reading time must be better.
`LaggedAutopilotTests` went red immediately in the direction that matters: **a bot reacting a full
0.75 s late took ZERO hits and killed 48 of 48 Wardens.** The S-011 verifier had already refuted "the
telegraph is too short" (measured usable windows 583–742 ms, and a 0.40 s bot survived them) — length
was never the problem, and buying more of it costs the fight its teeth.

At 34 m the two-sided gate reads:

```
[lagged] human floor (0.40 s): 0 hazards landed, every Warden killed
[lagged] sluggish   (0.75 s): 68 hazards landed, 31/48 Wardens killed
```

### The Autopilot lost code and gained nothing

Both Warden-specific override blocks are gone. The bot did not have to be taught the boss; the boss
was taught to speak the track. Its lane scan sees the walls, its chasm logic sees the holes, its
bar-slide commit sees the hanging bars — because they are the same entities the spawner places.

### Two more defects only running it could find

1. **The craft hovered at 4.2, inside the vertical span of its own hanging bar** (0.95 → 5.2), so the
   boss spent every curtain throw hidden behind its own attack — the exact opposite of the rebuild's
   purpose. Now 7.4, above the bar and above the camera's eye line.
2. **Thrown walls rendered in the world accent**, so the boss's wall was indistinguishable from the
   track's — and they follow a *different rule* (they stagger, they can never kill). Now always
   hazard red, everywhere, in every world.

The craft also moved out from 19 m to the throw lead (34 m), because a hazard appearing further away
than the craft supposedly throwing it is a lie the player can see (decree 2). `craftScale` went
1.70 → 2.55 to hold ~85% of its old apparent size at full health — and **more** than it as the craft
closes in, so the fight now ends with the boss at its largest instead of starting there.

---

## 3. The economy, finished (PR-0460)

**E6 — the IAP packs did not need re-pricing.** Measured against the new faucet: $0.99 buys 15–20
minutes, $19.99 buys 8.5–11 hours. "IAP should genuinely matter" is already satisfied by cutting the
faucet 6–7×; re-pricing on top would have overshot. Recorded as a deliberate no-change.

**E6 — the Mystery Box was wrong in both directions at once.** The −19% EV claim reproduces to the
digit (242.7 against 300), and is −23% re-derived after S-011 deleted the pack its 8% Coin Surge band
was valued at. But that same band made it too *generous* at the other end: a surge doubles a whole
run and charges bank with no cap, so a deep runner values it at their best run — the box turns
net-positive past a surged run of ~15,000 m. **It was the last surviving violation of D-026.** Band
deleted, rest re-weighted so EV is the price (300.5). The new test integrates the *shipped* function
and fails outright if any band ever returns a coin multiplier again.

**E7 — the level ladder was out-earning the game.** L1→L30 paid 10,300 direct coins over ~73–81
minutes; running for the same minutes pays 4,630–6,265. **Levelling was worth 1.6–2.2× the entire run
faucet.** With charges (13,050) plus an unbounded coin-surge stack it was 23,350 coins of priceable
value against an 83,500 catalogue — 28% of the game. Cut to 2,400 direct + 6,584 in charges, and the
charge grant moved off a flat multiply onto per-LEVEL rules (which also fixed a latent bug: the old
form multiplied by the level *delta* and was correct only by accident of the bands being flat).

---

## What was left, and why

**Obstacle variety (handoff priority 4) is NOT done.** The single biggest piece of it *is* built —
`hangingBar` exists, is collision-complete, is drawn, and makes slide mandatory wherever it appears —
but **no pattern places one**, because putting it in the catalogue is a spawn change and costs
`layoutVersion` 12 plus a golden rederivation plus a fresh 200-seed proof. That is a session's work
on its own and iron rule "don't start a determinism-affecting change on fumes" applies. The rest of
the finding (3 of 15 patterns consume zero randomness; 10 of the remaining 12 vary only by which of
three lanes) is untouched.

**Per-world Warden species** remain specified and unbuilt (`s009c_SPEC.md` §3) — carried since S-009.

**The blast has no bespoke sound.** It reuses `.boostStart` (a rising whoosh) and `.shieldBreak`. The
program's standing rule is that nothing here can hear a sound, so inventing one unheard is guesswork
shipped — same call S-010 made for the stumble. Queued behind PR-0456.

---

## Method note

The session opened with a six-agent scouting fan-out plus one hostile integration reader, all writing
to `docs/agent/audits/scratch/s012_*.md`. **The integration reader found three real defects in code
that had been written thirty minutes earlier** (the missing `mode` gate on `stepBlast`, the
uncleaned wave in `debugClearTrack`, and the arena/blast interaction above), and resolved two
questions the scouts had marked AMBIGUOUS by running headless probes rather than reasoning. That
pattern — build, then have a reader whose only job is to attack it — is worth repeating.

Two of the session's own leading assumptions were killed by measurement: that a longer telegraph must
be better (it made the fight unloseable), and that a bigger shockwave ring must read better (it
covered the read).
