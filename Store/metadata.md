# Prism Rush — App Store Metadata

App Store Connect-ready metadata for **Prism Rush**. Every field with a platform
character limit is counted inline like `(27/30)`.

---

## 1. Name & Subtitle

**Name:** `Prism Rush` (10/30)

**Subtitle:** `Neon 3-world hyperspeed run` (27/30)

---

## 2. Promotional Text

> Editable any time without a new build. Limit 170 characters.

`Dash through three neon worlds at hyperspeed. Swap lanes, jump, slide, chain gem streaks, beat your best. Pure reflex arcade—no ads, no tracking.` (142/170)

---

## 3. Keywords

> One comma-separated string, no spaces after commas (to maximize the 100-char
> budget). High-intent arcade/runner terms only. No word reused from the name
> ("Prism", "Rush") or subtitle ("Neon", "3", "world", "hyperspeed", "run").

```
endless runner,arcade,gem dash,lane swap,jump slide,reflex,dodge,one tap,glow,synthwave,high score
```

**Length: 98/100**

---

## 4. Description

Three neon worlds. One reflex run. **Prism Rush** drops a tiny glowing slime onto
a three-lane hyperspeed track and dares you to survive. Swipe to switch lanes,
flick up or tap to jump, swipe down to slide — and air-slam straight back to the
ground when you're airborne. The longer you last, the faster it gets.

Snap up gems to build a streak multiplier from x1 all the way to x5 — it only
breaks when you take a hit, so every clean run compounds. Thread the needle past
a tall block for a **CLOSE** bonus, slide under a bar for a **SLICK** one, and
grab a Shield to soak one mistake or a Magnet to vacuum gems toward you. Push
deep enough and oscillating moving walls start hunting you down.

The world transforms around you every 800m — neon Metropolis skyline, bobbing
Crystal Caverns, blazing Solar Sands — then loops back harder. It all rides a
fully synthesized 132bpm synthwave soundtrack that layers up per world, with
punchy SFX, particles, screen shake, speed lines, and haptics. Climb the Game
Center leaderboard and chase a score worth bragging about.

**Features**
- Three crossfading neon worlds: Neon Metropolis, Crystal Caverns, Solar Sands
- Three-lane swipe controls: lane swap, jump (with landing buffer), slide & air-slam
- Gem streak multiplier x1 → x5 that only resets when you're hit
- CLOSE and SLICK near-miss bonuses for clutch play
- Shield and Magnet pickups for momentum and recovery
- Moving-wall obstacles that ramp up at high difficulty
- Looping difficulty curve that keeps every run faster than the last
- Original 132bpm synthwave score with per-world layers and full SFX
- Particles, screen shake, speed lines, and haptics for full-body feedback
- Game Center leaderboards: all-time best + a recurring daily-challenge board
- No ads, no analytics, no tracking — ever

---

## 5. What's New (v1.0)

Welcome to Prism Rush v1.0 — the launch run.

Three neon worlds, three-lane hyperspeed action, gem streak multipliers,
near-miss bonuses, Shield and Magnet pickups, moving-wall obstacles, an original
132bpm synthwave soundtrack, and a Game Center leaderboard. Swipe in and see how
far you can go. No ads, no tracking — just speed.

---

## 6. Category / Age / Price

| Field | Value |
|-------|-------|
| Primary Category | Games → Arcade |
| Age Rating | 4+ |
| Price | Free |
| In-App Purchases | 5 — Pouch of Coins $0.99 · Bag of Coins $4.99 · Vault of Coins $9.99 · Double Coins $2.99 · Aurora Skin $1.99 (see `Products.storekit`) |

---

## 7. App Privacy

**Declaration: data use must be declared — the shipped build is NOT "Data Not Collected".**

The v1.1+ build integrates StoreKit 2 in-app purchases, Game Center leaderboards
(`prismrush.best` + the recurring daily `prismrush.daily`), Sign in with Apple, and
iCloud key-value save sync (see README §Shipping). There is still no tracking, no
analytics, and no advertising SDK. Local UserDefaults stores settings/saves
(privacy manifest reason **CA92.1**).

- **Data used to track you:** None
- **Data linked to you:** Purchases (StoreKit); User ID (Game Center identity, Sign in with Apple identifier)
- **Data not linked to you:** None

*Rationale:* no first-party servers and no third-party SDKs beyond Apple's; the
declared data is what Apple's own services (IAP, Game Center, SiwA, iCloud) handle.
Confirm the exact ASC questionnaire answers at submission time.

---

## 8. Marketing One-Liner & Alternate Subtitles

**One-liner:** `Three neon worlds, one reflex run—how far can you go?` (55)

**Alternate subtitles (each ≤30 chars):**
1. `Neon endless runner rush` (24/30)
2. `3 worlds, one reflex dash` (25/30)
3. `Swipe, jump, slide, survive` (27/30)

---

## 9. Screenshot Caption Suggestions

> One caption per planned screenshot, in workflow order.

1. **Menu —** `Tap in. Three neon worlds are waiting.`
2. **World 1 (Neon Metropolis) —** `Hyperspeed through the neon skyline.`
3. **World 2 (Crystal Caverns) —** `Weave the floating crystals at full tilt.`
4. **World 3 (Solar Sands) —** `Blaze past pyramids in the Solar Sands.`
5. **Near-miss / streak —** `CLOSE calls and x5 streaks—stay clutch.`
6. **Game over —** `New best? Climb the Game Center board.`
