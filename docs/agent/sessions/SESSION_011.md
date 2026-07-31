# Session 011 — the gameplay session

**Trigger:** the owner's critique of the Warden and of the game generally, plus two mid-session
additions (the character-select background, and the coin economy).

**Method:** measure before changing. Two workflows (15 + 8 agents) and nine hostile verifiers; eight
structured questions to the owner; every change verified on the simulator, not from tests.

## Commits
- `7736058` character select: delete the faded colour box behind every character
- `934b211` the ladder, pulled forward — and the moving walls made real
- `0a5265d` the economy: a gem stops being a coin, and skill starts paying

## Decisions
D-023 (the ladder), D-024 (the moving-wall swing), D-025 (the Autopilot chasm lead),
D-026 (the coin faucet), D-027 (the `×N` on the score). Audit: `audits/AUDIT_011_ECONOMY.md`.

## Verified output (pasted, not summarised)

Solvability soak after the ladder + swing change:
```
Executed 5 tests, with 0 failures (0 unexpected) in 9.440 seconds     (SolvabilityBotTests)
```

Full SPM suite, after the economy rework:
```
Executed 231 tests, with 0 failures (0 unexpected) in 39.719 (39.735) seconds
```

Coin faucet, headless probe, 24 seeds, `mult = 1` (tuned over two passes):
```
  dist(m)   secs   gems  dist  worlds  style  bounty   TOTAL   coins/min
      800   42.1     10     4       3     24       0      41       58.4
     1500   73.8     21     8       3     47       0      79       64.2
     3300  137.2     42    19      12     84      22     179       78.3
    12000  411.1    148    70      45    339      88     691      100.9
   103000  3270.0   1218   605     384   2907     924    6038      110.8
```
Against the pre-change baseline (259 / 586 / 1,286) that is a **6.3× / 7.4× / 7.2×** cut, and the
style share moves from ~3% to 47–59%.

Golden derivation (Python reproduced all seven pre-existing pins BEFORE emitting a new one):
```
  OK  v10 2026-06-10 … OK v8 2026-06-10        MODEL REPRODUCES EXISTING PINS: True
  --- NEW layoutVersion 11 goldens ---
  2026-06-10  0xD6A1D1208B63B231     ← bit-identical to the pin S-010 pre-armed
  2026-06-11  0xF93767EADC39CCE6
  2025-12-31  0x507D973FD27E90AE
  --- v12 pre-arm ---  0x03B5B844D08B98AF
```

## What was refuted
Two of this session's own leading hypotheses died to its verifiers: the Warden telegraph is NOT too
short (583–742 ms of usable window at every rank), and the stumble is NOT too rare (25–45% of
lethal-band contacts). The stumble had simply shipped the previous day, and every capture the owner
reviews is autoplay — which structurally cannot stumble.

## Not built (approved, carried to S-012)
The blast (double tap, CHARGE as ammo); the Warden rebuild (no kill move, throws real hazards);
economy E6/E7 (sink re-pricing, Mystery Box EV, level-up giveaway); obstacle variety, including the
fact that SLIDE IS NEVER MANDATORY anywhere in the 15-pattern catalogue.
