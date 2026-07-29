# Wardens — per-world antagonists, and the fix for the coin sink

**Status:** **PHASE 1 BUILT (S-008)** — the encounter is live, playable and green. Phases 2–5
(abduction struggle, Countermeasures, the second Warden, the world-exclusive character) are not.
Design agreed with the owner in S-007.

> **Where this doc is now wrong, and why.** Three things changed under contact with the code. They
> are corrected in place below and recorded as D-015/D-016/D-017.
>
> 1. **§8's first bullet is obsolete.** It said the build would need new `EntityKind`s and would
>    have to thread six `default:` clauses. It does not: a Warden is a snapshot field with its own
>    collision rule, so `EntityKind` is untouched and all six arms were avoided rather than audited.
> 2. **§3's attack rule was underspecified and the gap was a real defect.** "Each attack read and
>    dodged cleanly lands one hit" left open what happens when the beam picks a lane the player
>    simply is not standing in. Scoring that as a dodge let a player who never moved win outright.
>    A beam now ALWAYS closes the player's lane; the variety comes from a second lane closing too.
> 3. **§8's last bullet cites the wrong lesson.** It warns that "the camera cannot see into a hole".
>    A Warden is the inverse problem — the camera looks 14.6° BELOW horizontal with a 31° half
>    angle, so a craft hovering at y 5.2 and z −26 sits comfortably in the upper third of frame.
>    Confirmed on the simulator, no camera change needed.
**Owner decisions on record:** combat = dodge-to-damage **and** auto-fire, combined (not either/or);
frequency = every 3rd world; catching the player = struggle-to-escape, then death.

> Origin: the owner asked, mid-S-007, "what other feature could I add to make this game stand out
> and different from every other runner game" — proposing per-world interactive characters: alien
> ships in the space world that shoot at you and try to take you away, a mummy in the pyramid world
> doing the same, with abilities earned from running or bought with coins.

---

## 1. Why this is the right feature, not just a fun one

It closes the single largest open structural gap in the design.

`02_STATE.md` worry #3 and `PR-0401`: **the coin sink buys nothing that alters play.** ~83,500 coins
of permanent sink buys cosmetics only. Session 003 named it; S-004 and S-006 closed the *catalogue*
half of the design problem (act two, tier six, the chasm) and left the *economy* half untouched. A
purchasable Countermeasure that changes how an encounter resolves is exactly the missing half.

It also fixes a second admitted weakness. `05_GAME_DESIGN.md §6` rules the world ladder past 12
"compliant but weak — it dresses repetition as progression". Twelve world families are currently a
reskin ladder. A world with a *named antagonist you can beat* is a place, not a palette.

And it gives an endless runner the thing it structurally lacks: **punctuation**. Run → escalate →
Warden → new world.

---

## 2. The hard constraint (read this before proposing any change)

Decree 6: *every input must be readable in a single frame.* The player's hands are already fully
booked — jump, slide, two lane changes. **Adding a fourth input language would make both the running
and the fighting worse.** Every mechanic below is built to add ZERO new inputs.

That is why auto-fire is automatic and why dodging is the kill.

---

## 3. The mechanic — two layers that need each other

A Warden is a **set piece**, not a constant presence: it arrives as the climax of a world segment.

### Layer 1 — SHIELD, broken by auto-fire

The Warden arrives shielded and untouchable. The character auto-fires forward — no aiming, no
button, no new input.

**Fire rate is driven by `charge`, and charge is earned from gems collected during the run.** The gun
is therefore not a win button; it is a *timer the player earned before the fight started*.

This is the load-bearing idea. It retroactively gives S-004's greed lines (PR-0414: a second gem line
hung in a lane the pattern closes) an in-fight consequence. Today taking that risk only buys
currency. With charge, greed during the run literally arms the player for the encounter — new depth
from a system that already exists and already has a fairness proof.

### Layer 2 — CORE, opened by dodging

Shield down → the Warden is exposed **and** begins attacking. Attacks are telegraph → window shapes,
the same grammar `THE CHASM` already uses (S-006): the beam locks a lane, the mummy's hands close
two. **Each attack read and dodged cleanly lands one hit on the exposed core.** Three core hits kills
it.

### Why they interlock

- Auto-fire alone can never kill it → the gun is never a win button.
- Dodging alone can never reach the core → running well before the fight matters.
- Skill at the EXISTING verb set decides every outcome.

---

## 4. Tuning — "not impossible, not too easy, actually rewarding"

The owner's three bars, and the mechanism that delivers each:

| Bar | Mechanism |
|---|---|
| Not too easy | The gun cannot kill. Three clean dodges under pressure is the only kill path. |
| **Not impossible** | **Being *hit* is what abducts you — failing to *damage* is not failing to survive.** If the shield never breaks inside the encounter window, the Warden breaks off and leaves. You lose the reward, not the run. This is the safety valve; keep it. |
| Actually rewarding | Gem greed during the run becomes fight power. Winning pays something running cannot. |

Bounded by construction:
- Fixed 3 core hits — never a war of attrition.
- Fixed encounter window (proposal: ~12 s) — the run always resumes.
- A player who dodges perfectly always survives, regardless of charge. Charge only decides whether
  they get to *win*.

### Reward — owner-decided (S-007), tiered

The owner picked the world-exclusive character as **the** reward and asked for the others layered
underneath, explicitly deferring the balance ("don't take my word as law, I'm not a game designer").
So: one headline goal, with texture under it.

| Tier | Reward | Why it earns its place |
|---|---|---|
| **Headline** | **A world-exclusive character**, unlocked by defeating that world's Warden N times | Ties bosses to the 24-character roster and gives the world ladder the real progression `05_GAME_DESIGN.md §6` says it currently fakes. This is the goal a player can NAME. |
| Every win | Countermeasure parts | Feeds the upgrade loop — fighting Wardens is how you get better at fighting Wardens. **Keep the headline character off this currency** so the loop can never gate the goal behind grinding. |
| Every win | A coin bounty | Immediate, legible payout. Deliberately the *smallest* tier: coins already have a sink problem and this feature exists to fix it, not feed it. |
| Permanent | A plaque per world on the Worlds screen | Free progression legibility — shows at a glance which Wardens you've beaten. Cheap, and it makes the Worlds screen a trophy case instead of a menu. |

Design note for whoever builds it: N should be small (3–5). This is a headline unlock, not a grind,
and the whole point of the feature is that the fight is the fun part.

---

## 5. Countermeasures — the coin sink that alters play

Bought with coins, permanent, per-family. These are the PR-0401 fix.

| Countermeasure | Effect |
|---|---|
| Charge Cell | Higher charge capacity → shield breaks sooner |
| Overclock | Higher fire rate per unit charge |
| Ion Shield | Survive one landed beam lock (one free escape) |
| Scarab Charm | The mummy closes ONE lane instead of two |

Each alters an encounter's resolution, is legible, and is honestly advertised (decree 5).

---

## 6. Abduction — the fail state

Owner call: **struggle to escape, then death.** A landed attack lifts the player; a brief window
allows a break-free (mash, or spend a Countermeasure). Fail and the run ends.

This is a genuinely new death with its own emotion, and it is the moment that makes a purchased
counter feel valuable.

---

## 7. Frequency

Owner call: **every 3rd world** (~2,400 m apart). Keeps it a special event, prevents a boss-rush
corridor, leaves the escalation between them room to breathe, and is the cheapest cadence to prove.

---

## 8. Build risk — what this actually costs

This is several sessions, not one. Honest list:

- **New `EntityKind`s in Core**, and Core has **six `default:` clauses that silently accept a new
  obstacle kind** and make it decorative, non-lethal and invisible to the bot: `obstacleX`, the
  collision dispatch, the near-miss switch, `freeLaneNear`, `Autopilot.decide`,
  `Spawner.isObstacle`. Map in `docs/agent/audits/scratch/s006_scout_*.md`. **Read it first.**
- **Iron rule 3**: the 200-seed × 6,000 m solvability bot must stay green *and must actually meet
  the Warden* — copy `SolvabilityBotTests.testTheSoakActuallyDrivesTheBotAcrossChasms`, which exists
  precisely because a green bot proves nothing if it never met the hazard.
- **`DailyChallenge.layoutVersion` bump** + goldens repinned in **two** places (`DailyChallengeTests`
  and `MissionsTests.testTodaysChallengeSeedMatchesUTCGoldens`). Derive in Python from the SplitMix64
  constants; reproduce the existing pins first.
- **Determinism**: the Warden, its attack order and its telegraphs must all come from the seeded RNG.
  No `Date()`, no `Double.random`.
- **`Profile` gains fields** (charge upgrades, Warden kill counts) → `decodeIfPresent ?? default`,
  iron rule 7.
- **Renderer**: new pooled entities, procedural meshes only, `UnlitMaterial` only, zero binary assets.
- **Readability**: the camera cannot see into a hole (S-006's lesson) — any Warden telegraph must
  read against the deck's neon grid, which is the canvas that made the chasm legible.

---

## 9. Phasing

1. **One Warden, one world — the alien tug** (abduction is the most distinctive). Dodge-to-damage +
   auto-fire, no Countermeasures yet. **Prove it reads at 33 m/s on the simulator**, not in a still.
2. Abduction fail state + struggle-to-escape.
3. First Countermeasures → closes PR-0401 for one world.
4. Second Warden (the mummy) to prove the template generalises across families.
5. Roll out the rest; wire the world-exclusive character reward.

Gate between 1 and 2: the owner plays it and says the fight feels good. Nothing in this program can
judge that, and a Warden that reads badly at speed is worse than no Warden.
