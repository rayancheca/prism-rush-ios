# Session 008 — THE WARDENS, phase 1

**Goal (owner's call, asked at the top of the session):** build the Wardens, not the audio pass.
Session 007 left the two as genuinely different sessions and asked the next one not to guess.

**Result:** phase 1 of `docs/agent/10_WARDENS.md` is built, playable and verified on the simulator.
209 SPM tests green (was 196) and 228 Xcode tests green (was 215). Pushed to GitHub, along with
sessions 006 and 007, which had never been pushed.

---

## What shipped

A Warden guards **every third world** (2,400 m apart) inside a **660 m arena** swept clear of
obstacles and boost pads — but deliberately **not** of gems, because gems are the ammunition.

1. **Arrive.** The craft drops into view ahead.
2. **Shielded.** The player auto-fires; the rate is a **charge bank earned from gems and spent as it
   burns**. The arena being a gem field is what makes this phase something you *do* rather than a
   bar you watch. A player who banked nothing cannot break the shield — that is arithmetic, not
   balance (`wardenBaseDPS` alone never reaches `wardenShieldHP` inside the window).
3. **Exposed.** Telegraph → strike beams. Each beam **always** closes the player's lane, and 40% of
   the time a second one too. A clean dodge lands one core hit; three kill it.
4. **Caught** = death (respecting a held shield). **Failing to damage** = it breaks off and leaves.
   You lose the reward, not the run. That valve is the design's, and it is load-bearing.

Payout: a coin bounty, a score bonus, and `Profile.wardensDefeated`.

---

## The two defects the tests found, that reading would not have

**1. The gun could win on its own.** The first build had the beam *usually* stalk the player's lane
(60%) and otherwise pick at random — reasoning that a beam which always followed you is a rhythm,
not a read. That quietly falsified the design's central invariant. A player who never moved at all
won outright whenever three consecutive beams happened to pick empty lanes, because "was not
standing in the beam" was being scored as a clean dodge. It is not one.
`testTheGunAloneCanNeverKill` caught it at **1 kill in 40 seeds**.

Fixed by making every beam close the player's own lane, with a second lane closing 40% of the time.
Standing still is now always fatal; blind sidestepping is punished about half the time; at most two
of three lanes ever close, so a safe answer always exists and every attack resolves in one cycle.
(D-016.)

**2. A fight was unbounded.** An absorbed beam is spent *without* landing a core hit, and shields
stay collectable inside the arena — so a player trading shields could drag a fight past the end of
its own arena into resuming obstacles, which is exactly the beams-and-walls combination the arena
exists to prevent. Capped by `wardenMaxSeconds`, and the arena is now sized from the crudest
*provable* bound rather than from a measured typical case.

---

## The chasm guard, and why it was repaired rather than relaxed

The 200-seed bot stayed green immediately, but `testTheSoakActuallyDrivesTheBotAcrossChasms` went
red: 53 crossings against a floor of 72. That was correct behaviour — the first arena
(2,400–3,060 m) lands squarely on tier six's debut at 2,560 m and removes real chasm track.

Lowering the floor would have blunted the one guard standing between a green soak and a meaningless
one. Re-expressing it as chasms per *eligible* (non-arena) kilometre looked like the obvious repair
and is also wrong: an arena eats the **highest-frequency** band (1.84/km), so the eligible average
moves when `wardenArenaLength` moves — 0.92/km at 600 m, 0.84/km at 660 m. That would tie a chasm
assertion to an unrelated constant.

So the concerns were split. **Frequency** belongs to `DifficultyCurveTests`, which measures the
spawner and is provably unchanged by this work. **This** test now guards what only a driven run can
show — chasms reach the deck and get crossed, in every seed, repeatedly.

An A/B with suppression toggled off settled it: **0.92/km with arenas, 0.92/km without.** Identical.
The Wardens are rate-neutral on eligible track. (My first A/B *looked* like a 29% loss and was
simply a broken metric — the numerator counted chasms inside arenas that the denominator excluded.)

---

## Determinism

Arming a Warden costs **zero draws** from the spawn stream. The encounter derives its own
`SplitMix64` from `(runSeed, world)`, and the arena is a pure function of distance filtered at
`GameCore.apply` **after** `Spawner.fill` has already drawn. Parking the spawner cursor — the
obvious alternative — would have moved where every later draw lands.

Proved behaviourally: same seed, two runs, player behaviour diverged *only inside arenas* (safe,
they are swept clear); the sequence of spawned obstacle kinds is identical.

`layoutVersion` 9 → 10 all the same, because the entity set on the deck changes and a layout version
is a promise about the whole run. All eight pre-existing pins were reproduced in Python from the
SplitMix64 constants **before** the three new values were trusted; a v11 pin is pre-armed. The
integration-map agent independently derived the same values — and reported that its own first
attempt failed all eight from a transposed tag, which is precisely why the reproduce-first rule
exists.

---

## Verification — what running it actually caught

`swift test` compiles none of `UI/`, `Render/`, `IAP/` or the audio engine, so all of the below is
Mac-build and simulator work.

- The exhaustive `fire(_:)` switch **failed to compile** until every one of the seven new FX events
  had a reaction — in the renderer, in haptics, and in audio. That compile error is the whole reason
  D-015 models a Warden as a snapshot field instead of an `EntityKind`: a new enum case would have
  been silently swallowed by six `default:` arms.
- **The first beam render was wrong** and only screenshots showed it: a 34-unit deck plate that read
  as terrain rather than a lane, a column standing beside the player like a wall, and a dim maroon
  that read as mud against a bright world. Retuned (shorter plate, narrower column, brighter value,
  moved further up the track) and re-shot.
- Screenshotting throttles the simulator hard, which is useful — it lets you step through a fight
  almost frame by frame. Worth knowing: the run also advances *behind the splash screen*, so a
  naive launch-then-screenshot lands after the fight is over.

Evidence in `docs/agent/scratch/s008/`. The key frame is `warden_double_beam_dodged.png`: two lanes
closed, the player in the one safe lane, `HIT 1/3` landing, the pips agreeing.

---

## Numbers

| | Before | After |
|---|---:|---:|
| SPM tests | 196 | **209** |
| Xcode tests | 215 | **228** |
| Gems banked by the bot at 2,400 m (24 seeds) | — | 637 mean (586–686) |
| Encounters armed / killed in the 24-seed soak | — | 48 / 48, zero deaths |
| Worst-case encounter length measured | — | 438 m (arena 660 m) |
| Chasms per eligible km, arenas on vs off | 0.92 | **0.92** |

---

## What I did not do

- **No Countermeasures.** They are the part that actually closes PR-0401, and they are phase 3. The
  coin sink is still cosmetic-only today. Phase 1 exists to earn the owner's "the fight feels good"
  before more is built on it — that gate is his, and `10_WARDENS.md §9` sets it deliberately.
- **No abduction struggle.** A caught player just dies. Phase 2.
- **No bespoke Warden audio.** Every sound is a reuse chosen for what it already means. Inventing
  four DSP voices nobody in this program can hear would be guesswork shipped, and the full audio
  pass (PR-0456) is the right place for it.
- **Five audits still unrun.**
