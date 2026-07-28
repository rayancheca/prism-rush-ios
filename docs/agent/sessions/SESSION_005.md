# Session 005 — the hub redesign (PR-0452)

**Date:** 2026-07-28 · **Branch:** `main` (primary checkout) · **Recovery tag:** `pre-s005`
**Goal:** PR-0452 — redesign the hub. Rayan asked for it directly in S-004: *"i want a redesign of
the ui ux of the main screen. it just doesn't feel right."*

**Outcome: done and verified.** One goal, one coherent diff, three absorbed nits, one new defect
found and half-fixed. All suites green.

---

## 1. What I did before writing any code

**Recovered the scratch directories** (the handoff's `cp -Rn` loop) — 6.9 MB + 1.2 MB. The S-004
hub screenshot the critique is built on lives there and is gitignored.

**Captured three baselines at three profile states** — fresh, rewards-claimable (`PR_DEMOPROFILE`),
and late-game. There was no hook for the third, so I added `PR_HUBDEEP=1`: coins 24,500, best
128,400, 214 runs, level 23, world 15 (evolved palette live), every claimable already taken. It is
committed, so the third capture is repeatable by later sessions rather than a one-off.

**That capture changed the argument.** PR-0452 was filed with seven specific critiques from one
screenshot. The three-state set showed something worse and simpler:

> A player **214 runs in, 24,500 coins, world 15** got a **pixel-identical layout to first launch.**
> Only the numerals differed.

Six identical tiles is a symptom. The disease is that the hub had no sense of a journey — nothing
about it could change shape, so it could not respond to the player at all.

---

## 2. The direction, picked before touching code

The handoff was explicit that a redesign is design work and that I should pick a direction first.
**Editorial / arcade**, executed as one governing rule: *stop drawing three different kinds of thing
the same way.*

| Species | What it means | What it is |
|---|---|---|
| **Gradient** | the verb | PLAY, alone. 78 pt, ~65% width, 28 pt black type, 1 px top light edge |
| **Cards** | objects you act on | claim ribbon, Daily Rush launcher, loadout chips |
| **Bare rail** | exits | Characters / Shop / Worlds / Missions — no card chrome at all |

The third row is the one that does the real work. Removing the card chrome from navigation is what
stops "claim your coins" and "go to the shop" reading as the same class of object — the filed
critique's point 2, which no amount of respacing fixes.

**The structural insight the item did not have.** The old rail was three *different kinds of thing*
in three identical cells:

- **Daily Rush** is a way to *start a run* → it now stands beside PLAY, narrower and unfilled.
- **Rewards** is *coins waiting for you* → a full-width gold bar with a real CTA pill when
  claimable; a slim 40 pt tertiary strip when not. A different **height**, not a dimmed copy, so
  the hub visibly relaxes once you have taken everything.
- **Missions** is *a board you visit* → a nav exit with a gold count badge.

They shared a row because they were three leftover buttons, not because they are one class.

**Breaking the centre axis:** an editorial masthead — wordmark hard left, world dateline hard right
as two right-aligned micro lines, a rule under both. Tier one is two balanced clusters: identity
(level ring + BEST) left, resources (coins + gear) right, which fixes the lone-ring-versus-two-pills
imbalance. Only the hero and PLAY stay centred, which is exactly what makes them read as the two
focal objects rather than two more rows in a stack. The BEST/FIRST RUN chip moving up here also
dissolves the "two chips sandwich PLAY" problem — it was never a call to action, it is a fact about
the player.

---

## 3. Absorbed, as the item required

- **PR-0134** — the `rewards:` `AnyView` is **deleted**, not genericised. The hub renders its own
  ribbon and takes closures. That AnyView is the exact shape that severed observation and shipped
  the "Head Start does nothing" bug; deleting it is strictly better than making it generic.
- **PR-0149** — the hero stage takes its slot **exactly**: no floor (a floor is what could overflow
  a short screen) and no cap (a cap left a dead band between the name pill and the deck, which the
  first iteration actually showed). `CharacterHeroStage` derives everything from the height it is
  handed, so "whatever the slot offers" is the only correct argument.
- **PR-0150** — 44 pt target on the chip.
- **PR-0155 is NOT absorbed.** The item listed it, but it is a `ProfileView` defect: the hub and
  `LevelSelectView` already agree (both read `highestStartableWorld`). Left OPEN, said so.

---

## 4. PR-0453 — a defect found by looking, not by reading

Enlarging the stage made a faint box behind the character obvious. I did not guess at it:

1. **Is it even UI?** Two screenshots 5 s apart: the skyline scrolled, the band's edges held at
   **identical x**. UI overlay, not the 3D backdrop.
2. **Is it the mirrored reflection?** Disabled it, rebuilt, recaptured — band survived.
3. **Is it the `Canvas` colour mode?** `.extendedLinear` → `.nonLinear`, rebuilt, recaptured —
   band survived. Reverted both.
4. **Read the drawing code with the measurement in hand.** The body glow is filled as an ellipse
   `bodyR * 3.2` across — 1.6 × `size` at unit skin scale — inside a canvas frame `size` wide. The
   outer 30% of the glow is **hard-clipped by the canvas bounds**. Always has been; it is invisible
   on a small dark grid card and obvious once a big stage sits over a live 3D scene.

Fixed with `AnimatedCharacterSwatch.widthScale`, defaulting to **1.0 so every other call site is
byte-identical** — the same idiom `heightScale` already established in that file. The hub passes
1.6, kept just under the pedestal disc's 1.7 so the stage's clip width is unchanged.

**Deliberately not finished.** The 24-card grid, shop rows, NEXT UNLOCK strip and Mystery Box still
carry it — visibly, on the characters screen. Those slots are sized to the swatch, so widening the
canvas is a four-screen layout change. Filed as PARTIAL rather than smuggled into a redesign diff.

---

## 5. The trap, which cost two suite runs

`.accessibilityElement(children: .ignore)` placement is load-bearing and cuts **both ways**:

- On the **rail elements** (`railRewards`, `railDaily`) it must land **BEFORE** the identifier and
  label. Applied after, the label is silently dropped — but the element still **exists** and still
  **taps**, so only a label assertion catches it. `testDailyAndChestRewards` did.
- On the **nav exits** it must **not be applied at all**: it stops them surfacing as `.button`, and
  `InteractionUITests` looks up every one of them as `app.buttons[...]`. My first correction applied
  the rail rule uniformly and broke three navigation tests that had been passing.

`InteractionUITests.swift:21-23` documents the first half. Neither half is discoverable by reading
the code — the suite found both.

---

## 6. Verification

Every claim here has command output behind it.

```
./Tools/build.sh                                    → BUILD OK
xcodebuild test … -destination 'iPhone 17 Pro,OS=26.5'
    Executed 194 tests, with 0 failures (0 unexpected) in 183.101 seconds   ← unit
    Executed  11 tests, with 0 failures (0 unexpected) in 142.606 seconds   ← XCUITest
    ** TEST SUCCEEDED **
swift test -c release
    Executed 187 tests, with 0 failures (0 unexpected) in 25.028 seconds
```

Clean-launch screenshots — `uninstall` → `install` → `launch`, because `PR_FIRSTRUN` does not reset
the profile — at all three states, **opened and read**, in `docs/agent/scratch/s005/`:
`before_{fresh,mid,deep}.png`, `after_{fresh,mid,deep}.png`, plus the `crop_*` hero crops that
diagnosed PR-0453 and `v3_characters.png` showing the fix on the select stage and the artifact
still present on the grid cards below it.

The capture script deliberately has **no `|| true` and no stderr suppression** — S-004 lost a
screenshot loop to a silently-aborted `rm -f` and reported "0 files captured".

**One thing to know when comparing shots:** the default character, Prism, is `isPrismatic` — it
runs its own shared 8 s hue shimmer. It is yellow in one capture and pink in the next *from the same
build*. That is the character's fixed identity, not world-tracking, and not a decree-1 violation
(`CharacterSwatch.swift` annotates it explicitly). Do not read it as a change.

---

## 7. Decrees and invariants

- **Decree 2 (previews never lie)** — the hero still resolves through
  `SkinCatalog.skin(ProfileStore.shared.equippedSkinID)`, never raw `selectedSkin`.
- **Decree 3 (no broken-looking states)** — the idle ribbon is a deliberately different, calmer
  object, not a greyed-out button.
- **Decree 4 (everything leads somewhere)** — including the idle ribbon (opens the timers sheet).
  Nothing decorative was added.
- **Decree 6 (clarity)** — one gradient family, nothing pulses, and the PR-0445 lower-third scrim is
  preserved. A mirrored top band was added for the masthead; the first version left a visible seam
  across the skyline and was widened to four stops with a long tail.
- **G3 / invariant 6** — `ProfileStore.shared` read directly in `body`; `loadout` is still a
  concrete typed child (the left-align wrapper is an `HStack`, which preserves the concrete type —
  only `AnyView` severs observation).
- **Invariant 2 (spawn/determinism)** — untouched. No `Core/` file changed; `layoutVersion` stays 8.

---

## 8. What I did not do

- **PR-0450** (a genuinely new pattern/entity) — the handoff said not to start it in the same
  session as the redesign, and it is right.
- **PR-0254 + PR-0307** (revived runs count for missions/XP, not the leaderboard) — the named
  fallback. Not reached; the redesign plus the PR-0453 investigation used the session.
- **PR-0453 beyond the hub** — see §4.
- No audit ran. Five remain.
