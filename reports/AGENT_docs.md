# AGENT_docs — Prism Rush ASO / Store Metadata

## Scope
Produced App Store metadata only. Touched exactly two files:
- `Store/metadata.md` (all store copy)
- `reports/AGENT_docs.md` (this report)

No source under `PrismRush/` and no `README.md` were modified.

## What was produced
Full `Store/metadata.md` with nine sections: name + subtitle, promotional text,
keywords, description (hook + 3 paragraphs + feature list), What's New (v1.0),
category/age/price, App Privacy (Data Not Collected), marketing one-liner + 3
alternate subtitles, and 6 screenshot captions (menu → W1 → W2 → W3 →
near-miss/streak → game over).

All features in the copy map to the supplied ground truth: three crossfading
worlds (Neon Metropolis, Crystal Caverns, Solar Sands) every 800m with looping
difficulty, three-lane swipe controls (lane swap, jump + landing buffer, slide,
air-slam), gem streak x1→x5 (resets only on hit), CLOSE/SLICK near-miss bonuses,
Shield + Magnet pickups, moving-wall obstacles at high difficulty, 132bpm
synthwave with per-world layers + SFX, particles/screen shake/speed lines/haptics,
Game Center leaderboard, and zero data collection. No invented features.

## Character-limit checks (measured, not estimated)
| Field | Limit | Result |
|-------|-------|--------|
| Name `Prism Rush` | 30 | 10 — PASS |
| Subtitle `Neon 3-world hyperspeed run` | 30 | 27 — PASS |
| Promotional text | 170 | 142 — PASS |
| Keywords string | 100 | **98 — PASS (tight)** |
| One-liner | (soft) | 55 |
| Alt subtitle 1 `Neon endless runner rush` | 30 | 24 — PASS |
| Alt subtitle 2 `3 worlds, one reflex dash` | 30 | 25 — PASS |
| Alt subtitle 3 `Swipe, jump, slide, survive` | 30 | 27 — PASS |

Counts were measured with `printf '%s' "<string>" | wc -c` (byte count; all
strings are ASCII so byte count == character count). The em dash in the one-liner
is multi-byte in UTF-8, but the one-liner has no hard limit.

## Keyword field
Final string (98/100):
`endless runner,arcade,gem dash,lane swap,jump slide,reflex,dodge,one tap,glow,synthwave,high score`
- No spaces after commas (per instruction, to preserve budget).
- No word reused from name (Prism, Rush) or subtitle (Neon, 3, world, hyperspeed,
  run). "Runner" is intentionally used and is a distinct token from the
  subtitle's "run" — Apple tokenizes separately, and "endless runner" is the
  single highest-intent term for this genre, so the slight overlap is a
  deliberate ASO choice rather than wasted duplication.

## ASO assumptions
- Apple indexes keyword field + name + subtitle together, so genre anchors
  ("endless runner", "arcade") live in keywords while the subtitle carries the
  unique hook ("Neon 3-world hyperspeed run"). No keyword duplicates name/subtitle
  tokens, maximizing total indexed coverage.
- Mechanic terms ("lane swap", "jump slide", "dodge", "one tap") chosen as the
  search phrases a runner player actually types.
- Promotional text leads with the action hook and is safe to swap post-launch
  without a binary update.

## Open risks / unverified gates
- **App name availability is a human gate.** "Prism Rush" is not verified as
  available/unique on the App Store or as a trademark — App Store Connect may
  reject or require a variant. Needs a manual check before submission.
- **Subtitle uniqueness/competition** not assessed against live competitors.
- Keyword field is at **98/100** — almost no room to add terms; any future
  keyword swap must drop something first.
- Screenshot captions assume the planned 6-shot sequence (menu, 3 worlds,
  near-miss, game over) matches the actual captured screenshots; captions must be
  paired to the real images at upload.
- "4+" age rating and "Free / no IAP" are taken from fixed facts and must match
  the App Store Connect questionnaire answers and the actual build.
