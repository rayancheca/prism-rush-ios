# Prism Rush — Code Review

**Reviewer:** Claude (Opus 4.8, strict pass)
**Date:** 2026-06-12
**Scope:** Full read of every source, test, tool, config, and doc file in the repository. No files modified except this one.
**Commit reviewed:** `4b6d9ab` (main, v1.4.2)
**Verdict up front:** This is the most disciplined hobby-scale game codebase I have reviewed. The Core/Render seam is genuinely clean, the determinism story is real and well-tested, the economy is exploit-hardened with tests to prove it, and there is not a single `TODO`, `print`, `try!`, `as!`, `fatalError`, or `@unchecked Sendable` in shipping code. The serious issues are **product/design** (the "3 worlds on a loop" model the owner has flagged), a handful of **overstated claims** in the README/docs, and **moderate accessibility + test-coverage gaps** in the StoreKit/GameKit/SwiftUI surfaces. Nothing here is a crash or data-loss risk. Final score in §21.

---

## 1. Project Overview & Architecture Assessment

The architecture is the strongest thing about this project. It is a textbook ports-and-adapters design.

**Core/Render separation via `RendererPort` — the seam is clean (verified, not just claimed).**
- `Render/RendererPort.swift:8-15` defines a two-method protocol (`sync(GameSnapshot)`, `fire(FXEvent)`). The Core hands the renderer an immutable value (`GameSnapshot`, `Core/Models.swift:52`) plus one-shot value events (`FXEvent`, `Core/Models.swift:120`). The renderer never mutates game state and the Core never imports a renderer.
- This is *enforced mechanically*, not by convention: `Package.swift:14-23` compiles only `Core/`, four `Meta/` files, and `Audio/Synth.swift` on Linux — i.e. the deterministic layers literally cannot reference UIKit/RealityKit/SwiftUI or they would fail the Linux build. A `grep` for `Date()`/`.random`/renderer imports inside `Core/` comes back clean (the only `.random` in Core is the *seed default* in `GameCore.init`/`reset`, `Core/GameCore.swift:78,128`, which is correct — it seeds the deterministic stream when no seed is supplied).
- This seam is *why* the 200-seed solvability bot, run-hashing, and the whole economy test suite can run headless. The design pays for itself.

**Fixed timestep — correct.** `GameCore.advance(realDt:)` (`Core/GameCore.swift:147-157`) uses a standard accumulator: clamp `realDt` to `0.1` max, accumulate, drain in `Tuning.tickDt` (1/120 s) steps, then rebuild the snapshot once. The renderer interpolates separately via `advanceVisuals` driven by wall-clock dt. This is the canonical pattern and it is implemented correctly. The NaN guard (§3) is robust.

**Entity pooling.** `EntityPools` (`Render/Reality/EntityPools.swift`) reconciles the snapshot's stable ids against a live map, recycling vanished ids into per-kind free lists. `ParticleSystem` (`Render/Reality/ParticleSystem.swift`) is a bounded CPU pool of 560 pre-built spheres. Both are sound (caveats in §4/§13).

**Design philosophy vs execution.** The stated philosophy ("zero binary assets, one renderer behind one protocol, deterministic core") is executed faithfully. The gap between ambition and reality is small and lives almost entirely in the *marketing copy* (README claims, §16) and in *product scope* (the worlds, §1-product below), not in the engineering.

**The one architectural product limitation:** the game is sold as "three worlds… then loops back harder," and the world *identity* is keyed `world % 3` in every layer — `Theme.worlds[i % 3]` (`UI/Theme.swift`, `RealityRenderer.swift:471,871-872`), `WorldDecor` (`world % 3` at `:104,:276,:357,:362`), `WorldSky` family selection, `Synth.step` (`Audio/Synth.swift:263`), and the previews (`WorldPreviewCanvas.swift:70`). `WorldSky.restyle` adds per-*ordinal* placement variation seeded from the absolute index and ramps element counts with the cycle — but clamps it (`min(cycle, 2)`, `WorldDecor.swift:381,404,433,...`), so worlds 6, 9, 12… are the *same three families* with the same densities and only reshuffled placement. This is the owner's documented concern and it is real (see §19 / §20).

---

## 2. Swift 6 Strict Concurrency

The project builds under `SWIFT_STRICT_CONCURRENCY: complete` (`project.yml:11`) and the concurrency hygiene is genuinely good.

**`MainActor.assumeIsolated` — a justified workaround, not a hidden bug, but it is load-bearing and untestable.** There are **9 call sites across 6 files**: `GameView.swift` (the `SceneEvents.Update` handler, `:210`), `RealityRenderer.swift` (`reduceMotion` notification, `:168`), `SynthEngine.swift` (3× session/route/config notifications, `:141,:147,:150`), `ProfileStore.swift` (iCloud KVS change, `:42`), `IAPManager.swift` (foreground notification, `:64`), `GameCenterService.swift` (auth handler + delegate, `:18,:64`).

In every case the closure is a callback that Apple *does* deliver on the main thread/actor (NotificationCenter with `queue: .main`, RealityView `SceneEvents.Update`, `GKLocalPlayer.authenticateHandler`, the GC delegate), but whose closure type is not statically `@MainActor`-isolated, so the body needs `assumeIsolated` to touch main-actor state. **This is the Apple-documented pattern and it is correct here.** The honest caveat: `assumeIsolated` is a *runtime precondition* — it trades a compile-time guarantee for a crash-if-wrong assertion, and none of these paths are exercised by the test suite (they all live in the iOS-only layers). It is not masking an isolation problem; it is the idiomatic bridge for pre-async-await delegate/notification APIs. Verdict: acceptable, but it is the one place the type system is being told "trust me," and it should be on the manual-QA radar for OS behavior changes.

**Sendable conformances — correct and explicit, none suppressed.** `GameSnapshot`, `EntityState`, `SpawnCmd`, `FXEvent`, `GameMode`, `PickupKind`, `EntityKind`, `NearMissKind` (`Core/Models.swift`), `Profile`/`RunSummary`/`LevelUpResult`/`Mission`/`Skin`/`WorldPalette` are all `Sendable` value types. `SplitMix64` is `Sendable` (`Core/RNG.swift:5`). **There is not a single `@unchecked Sendable` or `nonisolated(unsafe)` in the codebase** (grep-verified). This is rare and commendable — most Swift 6 migrations leak at least a few escape hatches.

**Actor isolation across the boundary.** Everything stateful is `@MainActor`: `GameCore`, `RealityRenderer`, `EntityPools`, `ParticleSystem`, `WorldDecor`/`WorldSky`, `ProfileStore`, `IAPManager`, `SynthEngine`, `Music`, the services. The value types crossing the boundary are `Sendable`. This is a single-actor design (everything on main), which for a 120 Hz single-player game is the right call — there is no background work that needs an actor of its own, and the deterministic core is fast enough to run inline. `IAPManager.listenForTransactions` and `AccountService.refreshCredentialState` correctly hop back to `@MainActor` via `Task { @MainActor … }` / `MainActor.assumeIsolated`.

**`SceneEvents.Update` threading.** RealityKit delivers `SceneEvents.Update` on the main actor; the handler at `GameView.swift:209-245` wraps its body in `assumeIsolated` and does all per-frame work (sim advance, renderer sync, audio pump) there. Correct, and the per-frame ordering (`advance` → `advanceVisuals` → `sync` → `musicPump`) is sensible.

---

## 3. Game Core

**`advance()` accumulator — correct.** `Core/GameCore.swift:147-157`. The NaN/inf/negative guard (`guard realDt.isFinite, realDt > 0 else { return }`) is genuinely robust and the inline comment correctly explains *why* (`min(NaN, 0.1)` is NaN, which would poison the accumulator permanently). `GameplayTests.testAdvanceSurvivesNaNAndJunkDt` (`Tests/CoreTests/GameplayTests.swift:12-27`) pins exactly this: feeding `.nan`/`.infinity`/`-0.016`/`0` must not step the sim, and a valid frame afterward must still advance. The fix is real and tested.

**SplitMix64 — textbook-correct.** `Core/RNG.swift:10-16` is the canonical SplitMix64 (golden-ratio increment `0x9E3779B97F4A7C15`, the two MurmurHash3 finalizer multiplies, the `>>30/>>27/>>31` shifts). `unit()` uses the top 53 bits for a full-mantissa double in `[0,1)` (`:19-21`) — correct and matches the test (`RNGTests.testUnitInRange`, 100k samples). `int(_:_:)` and `pick` mirror the JS prototype's `ri`/`pick` semantics. `DailyChallengeTests.testGoldenSeeds` pins exact seed outputs forever (`Tests/CoreTests/DailyChallengeTests.swift:11-21`) — including a pre-armed `layoutVersion: 3` golden, which is unusually forward-thinking.

**Spawner + 14 patterns — sound, with a load-bearing invariant that is well-defended.** `Core/Spawner.swift` gates by a five-tier prefix ladder (`maxIndex(forDistance:)`, `:24-31`) and moving walls live *only* at the last index — `PatternOrderTests.testCatalogueOrderAndPatternIdentity` (`Tests/CoreTests/PatternOrderTests.swift:11-37`) asserts this, and `testTierLadderMonotoneAndRNGCountsPinned` (`:39-65`) pins **the exact per-pattern RNG-call count** `[1,1,0,1,1,3,1,2,0,1,1,1,2,0]` using a bijection probe against a stepped fresh stream (`:70-82`). This is exactly the right way to catch the "consumed one extra `rng.unit()` → silently reshuffled every seeded run" failure mode (iron rule 3). The anti-repeat reroll (`Spawner.swift:39-41`) is correctly accounted for in `layoutVersion 2`.
- *Edge cases handled well:* the overdrive runway (pattern 10) is proven obstacle-free and self-contained by a *geometric* invariant (`SolvabilityBotTests.testOverdriveRunwayContainmentInvariant`, `:31-55`): latest pad trigger + worst-case boost travel < pattern length. The ballistic gem arc (pattern 1/2/6/9/11) places gems on the predicted jump parabola using `crossingSpeed(at:)` — a *pure* function of distance, zero RNG (`Patterns.swift:32-57`), so speed-aware placement never perturbs the seeded stream.

**Autopilot bot — correct greedy policy, with the right conservative biases.** `Core/Autopilot.swift`. It scores lanes by distance-to-nearest-blocker, refuses to cross *through* a lane whose tall is in/near the kill band (`:80-85`), commits jumps/slides with leads that scale with `effectiveSpeed` (so chrono slow-mo is handled for free, `:89-92`), and air-slams to land early and re-arm. The greedy gaps are the *safe* direction: if the greedy bot survives, a perfect human can (greedy is generous, not clever). The honest limitation is in §10.

**Collision predicates — boundary-correct, no false positives/negatives found.** `Core/Collisions.swift` is pure and exhaustively boundary-tested (`CollisionTests`, `Tests/CoreTests/CollisionTests.swift`): low/tall/bar/splitBar/gem/magnet/ring/boostPad/near-miss bands all have ±-epsilon tests. The near-miss outer band (`1.95`) is *asserted* to stay below the lane pitch (`2.2`) so "standing one lane away" can never auto-award CLOSE (`CollisionTests.testCloseNearMissBand:154-155`, regression-pinned in `GameplayTests.testTallPassingOneLaneAwayAwardsNothing`). The shield-absorb grace window (`invulnDuration 0.4`) is tested against the twin-talls-at-same-`d` case (`GameplayTests.testShieldAbsorbSurvivesTwinTallsAtSameDepth`).

**Tuning constants — centralized, not magic.** `Core/Tuning.swift` is a single `enum` of named constants with comments. Collision code and patterns reference them by name. `GameplayTests.testRetunedFeelConstants` pins the feel constants so a regression is a deliberate act. This is exactly how it should be done.

**One genuine subtlety worth noting (LOW):** `revive()` (`GameCore.swift:496-513`) zeroes `boostT` and `flowStreak` ("a continue restarts clean") but does **not** clear `magnetT`/`doublerT`/`chronoT`. A revive can therefore carry over an active magnet/doubler/chrono. This is player-favoring and harmless, but it contradicts the "restarts clean" comment and is mildly inconsistent. Decide whether continues are clean or not, and make it uniform.

---

## 4. RealityKit Renderer

**`RendererPort` — clean seam, not leaky.** The renderer consumes `GameSnapshot.entities` (authoritative `x/y/z/kind/lane/spin/fading`) and never reaches back into the Core. `Core/Models.swift:31-33` documents that `y` is authoritative for every obstacle kind and the renderer obeys it (`RealityRenderer.swift:331-333`: "never hardcode heights here").

**`EntityPools` — lifecycle correct.** `sync` (`EntityPools.swift:22-46`) inserts/positions seen ids and recycles vanished ones into per-kind free lists; `prewarm` (`:58-66`) pre-builds rings/pads to the Core's caps so their first mid-run spawn doesn't allocate. `recycle` hides + reparents-out + returns to the free list. No churn, ids are stable. Correct.

**`ProceduralMesh` — correct `MeshDescriptor` usage, `UnlitMaterial` throughout.** `Render/Reality/ProceduralMesh.swift` builds positions + triangle indices with CCW-outward winding (back-face culled), no normals (correct for unlit). The `build` helper falls back to a sphere on generation failure (`:223-228`) — a safe degrade. Meshes are built once at init and reused. `CharacterProportions` (`:237-252`) is a shared source of truth for rig-vs-preview parity (pinned by `CharacterParityTests`).

**The "alloc-free steady state" claim — PARTIALLY OVERSTATED (MEDIUM, §13).** The *documented* fix is real: material **instances** are cached and only rebuilt on a palette-key change (`RealityRenderer.sync:183-199`), eliminating the ~44 `UnlitMaterial` constructions/frame the README cites. That specific claim holds. But "alloc-free in steady state" as a blanket statement is not literally true:
1. The place closure reassigns `model?.materials = [mA]` (and `[mA2]`/`[mGold]`/etc.) for **every visible entity, every frame** (`RealityRenderer.swift:336,338,349,358,361,369,374`). The *material* is cached, but `[mat]` is a fresh 1-element `Array` literal each time — N small heap allocations per frame, where N = visible entities. These could be skipped when the material is unchanged.
2. `GameCore.rebuildSnapshot` (`GameCore.swift:577-612`) copies `entityScratch` into the new `GameSnapshot` value each frame; because the previous snapshot still holds the buffer, the next-frame `entityScratch.removeAll(keepingCapacity:)` triggers one Copy-on-Write of the `[EntityState]` array per frame (bounded, ≤ ~110 elements).

Net: the renderer is *dramatically* leaner than before and the material-instance win is genuine, but there is still bounded per-frame allocation. The README should say "material-allocation-free" rather than "alloc-free."

**Material caching on palette-key change — correct.** The key `(worldFrom%3)*4096 + (worldTo%3)*256 + Int(blend*64)` (`:183`) quantizes the crossfade so the rebuild fires only on a real palette step; steady state (`blend == 1`, ~95% of frames) skips the whole block. Correct and the comment is honest about the quantization.

**Crossfade logic — visually correct.** `Palette` (`:868-884`) lerps bg/grid/accent/accent2 and pushes lane lines toward white by `(1-blend)` so they flare mid-transition and settle. The character is *deliberately excluded* from the crossfade (decree 1: identity never follows the world) — `sync:196-198` documents this. The sky identity swap lands on the same frame `worldTo` flips (`WorldSky.update:274-279`), synchronized with the horizon ring sweep and lane flare. No glitch path found.

**One concurrency-flavored note (LOW):** `advanceVisuals` reads wall-clock `Date().timeIntervalSinceReferenceDate` for the prismatic shimmer (`:523`) and `Double.random` for blink cadence (`:537`). This is in the **renderer**, not the Core, so it is allowed and intentional (decree 2: the menu hero and in-run body sample the *same* wall clock so they agree). Correct by design, but worth knowing it means the in-run Prism hue is not reproducible from a seed (it is cosmetic and never touches the sim, so this is fine).

---

## 5. Audio (AVAudioEngine + Pure DSP)

**Excellent split.** `Audio/Synth.swift` is pure Foundation DSP (oscillators with exp frequency ramps + amplitude decay, filtered noise, additive buffers) — Linux-testable and rendered offline by `Tools/render_sfx.swift`. `SynthEngine`/`Music` wrap it in AVAudioEngine. The boundary is clean.

**Session lifecycle — handled properly, including the failure modes most apps miss.** `SynthEngine` observes `interruptionNotification`, `routeChangeNotification`, and `AVAudioEngineConfigurationChange` (`SynthEngine.swift:137-152`) and self-heals via `recoverEngine` (`:159-174`). The comment at `:135-136` correctly identifies the real bug this prevents: without these, a phone call / Siri / headphone unplug stops the engine and `started` stays true, so *all later audio silently no-ops forever*. `musicStart` also self-heals if an interruption beat it (`:100-105`). This is more robust than most shipping games.
- Graceful degrade: if no `AVAudioFormat` can be made, the engine becomes "silent but alive" rather than crashing (`:36-43`), and every entry point guards on `started`.

**DSP correctness + caching.** Each `Synth.SFX` is rendered once and cached as an `AVAudioPCMBuffer` (`SynthEngine.play:85-98`); the gem pitch ladder collapses mod 26 so the cache stays bounded (`Synth.SFX.normalized`, `Synth.swift:299-302`). `SynthTests` verifies every SFX is finite, non-silent, correctly-sized, and not clipping (`Tests/CoreTests/SynthTests.swift`), and that pickup sounds are distinct and the death-sweep noise *swells* rather than decays. Good coverage of the pure layer.

**Threading.** Audio renders on AVAudioEngine's internal render thread; the app feeds it cached buffers from the main actor. `Music.pump` keeps ~4 steps queued ahead with sample-accurate contiguous buffers (no wall-clock drift) and a `safety < 8` bound on the refill loop (`Music.swift:65-84`). `reanchor` (`:58-63`) correctly handles the post-interruption case where the player's sample timeline is gone. SFX player selection picks an idle node or round-robins (`SynthEngine.schedule:125-133`).

**Memory.** Buffers are cached for app lifetime (bounded SFX catalog), particles/meshes are pooled, observers are stored and app-lifetime. No leak path found. The one thing to verify on-device: the SFX cache is unbounded in principle but the case set is finite (~26 cases × the 26-step gem ladder collapse), so it is effectively bounded.

---

## 6. SwiftUI Layer

**View decomposition — good.** Views are feature-scoped and mostly sized well. The two large files (`GameView.swift` 885 lines, `ShopView.swift` 733) carry a lot, but `GameView` is really `GameModel` (the app hub, ~700 lines) + a thin `GameView` body; the model is the heaviest single object and could be split (run-recording, milestone queue, and FX handling are separable concerns), but it is cohesive.

**`@Observable` usage — correct, and the project's own "G3" anti-pattern rule is followed rigorously.** No `@StateObject`/`ObservableObject` legacy anywhere. Singletons are referenced live in `body` (`ProfileStore.shared`, `IAPManager.shared`) rather than snapshotted into a top-of-body `let` — exactly what iron rule G3 demands. I and a second reviewer both searched specifically for the `let p = store.profile` capture-at-top-of-body bug and **found none**; the few `let p = ProfileStore.shared.profile` bindings live *inside* per-render computed sub-properties (e.g. `ShopView.swift:113,133,419`), which re-execute each pass so observation still registers. This discipline is consistently applied and frequently cited in comments.

**No `NavigationStack`/`NavigationPath`** — the app uses a hand-rolled sheet model (`GameModel.activeSheet`, `GameView.metaSheet`). For a full-screen game with custom transitions this is a reasonable choice; URL/route state isn't relevant here.

**Animation correctness.** Idle previews use `TimelineView(.animation(minimumInterval: 1/30))` (`WorldPreviewCanvas.swift:24`, `CharacterSwatch`, `RewardsBar`, `MissionsView`) — 30 Hz, Reduce-Motion-gated to a static `t=0` frame. `@ScaledMetric`/`typeScale` is used on most meta screens. Reduce Motion is honored thoroughly across the renderer and the SwiftUI previews.

**HUD performance — fine.** `HUDView` (`UI/HUDView.swift`) reads the observed `core.snapshot` and is `.allowsHitTesting(false)`; it redraws per frame but is cheap (a few text/shape nodes). The `.id(snap.mult)` on the multiplier pill (`:85`) intentionally re-triggers the scale transition. No unnecessary global invalidation found.

**Anti-patterns:** the only real one is **`AnyView` density in `ShopView.heroShell`** (~10 `AnyView` wraps per hero re-render, `ShopView.swift:146-197`) — `heroShell` should be made generic (`<P: View, Q: View>`) to drop them (MEDIUM, cleanliness/perf). Otherwise clean.

---

## 7. StoreKit 2 / IAP

This is handled with real care and is one of the better-tested areas.

**Transaction observation — correct.** `IAPManager.listenForTransactions` (`IAP/IAPManager.swift:204-215`) listens to `Transaction.updates`, grants verified transactions through `IAPCatalog.apply(_:transactionID:to:)`, and finishes them. The grant is **dedup'd by transaction id** inside `ProfileStore.applyOncePerTransaction` (`Meta/ProfileStore.swift:118-126`), so a redelivery of an unfinished transaction (app died before `finish()`) can never double-pay.

**Purchase-flow edge cases — all handled.** `purchase(_:)` (`:146-180`) distinguishes `.success`/`.verified`, `.userCancelled` (not surfaced as an error), `.pending` (tracked in `pendingProductIDs` so the Shop hides the offer until approval, preventing a second pending charge), unverified (`"not been charged twice — try Restore"`), and `@unknown default`. Errors are never swallowed: `lastError` carries a user-presentable message surfaced inline (ready) or as a toast (pre-launch). The four-state availability machine (`loading`/`ready`/`notConfigured`/`offline`, `:23-28`) with exponential backoff only on a *thrown* request (not on a pre-ASC empty catalog) is genuinely thoughtful and honest (decree 3 — no red errors for normal pre-launch states).

**Coin-grant replay idempotency — actually safe, and tested.** `grantCoinPack` (`ProfileStore.swift:135-144`) records the transaction id and the payout in the *same* `mutate` (atomic — a crash can't split marker from payout), and the +50% first-purchase bonus flag flips in the same mutate. `EconomyTests.testGrantCoinPackTransactionReplayIsIdempotent` and `testFirstPurchaseBonusPaysExactlyOnce` (`Tests/CoreTests/EconomyTests.swift:171-228`) prove a same-id replay is a no-op for base coins, bonus, and the purchase counter. The granted-id ledger is bounded to the newest 512 (`Profile.swift:72-83`, tested `:230-237`).

**iCloud merge for purchase credits — correct conflict resolution, and this was a real BLOCKER that is now fixed.** The naive `coins = max(local, remote)` would *destroy* a real-money purchase when the other device had more earned coins. `ProfileStore.merged` (`:601-631`) uses a per-device G-counter (`coinsPurchasedByDevice`, merged per-key-max so each install owns its slot) and credits the winning balance with every paid payout it hasn't seen. `EconomyTests.testCloudMergeNeverErasesPurchasedCoins` and `testCloudMergeConcurrentPurchasesOnTwoDevicesBothSurvive` (`:244-275`) prove both directions converge and no purchase is ever erased. This is the single most impressive piece of correctness work in the meta layer.

**Pre-launch shop state — honest.** Covered above; the Shop renders shimmer/footnote/retry per state, never a broken-looking error (decree 3).

**First-purchase bonus — cannot be exploited.** `coinPackPayout(base:bonusUsed:)` (`:109-111`) pays `base + base/2` once; the flag flips in the same grant mutate and cloud-merges as OR (`testFirstPurchaseFlagCloudMergeNeverRearms`, `:277-288`), so a fresh device can never re-arm it. Restores skip consumables entirely (`IAPCatalog.restore`, `IAP/IAPCatalog.swift:65-76`). Integer-half rounds down so it never overpays (`testCoinPackPayoutPureRule:167-168`).

**Gap:** there is **no unit test of `IAPManager` itself** — the availability state machine, `priceValue`/`coinsPerUnit` value-badge math (`ShopView.swift:311-338`), and `isPendingApproval` are exercised only by hand. The pure value-badge math in particular is trivially testable and should be (§10/§20).

---

## 8. Sign in with Apple + iCloud + Game Center

**AuthenticationServices — correct, including the revoke path most apps skip.** `AccountService.refreshCredentialState` (`Services/AccountService.swift:27-42`) checks the credential on launch and signs out on `.revoked`/`.notFound`/`.transferred` — Apple *requires* this, and it is implemented. Cancellation is not surfaced as an error (`:53`). The entitlement is wired (`project.yml:30-31`, `PrismRush.entitlements:5-8`).

**iCloud KV sync — conflict resolution is conservative and convergent.** `ProfileStore` mirrors the JSON profile to `NSUbiquitousKeyValueStore` (`:570-577`) and merges on external change (`mergeFromCloud:634-640`) using `merged` (max for progression/coins, union for monotonic sets, per-key-max for maps). `ProgressionTests.testCloudMergeKeepsMaxXPAndWatermark` pins the rules. **Storage-limit awareness is present:** `challengeDaysPlayed` is capped at 60 (`:551-555`), the granted-transaction ledger at 512, and the comment explains the device-local-board fields are deliberately *not* merged. KVS has a 1 MB / 1024-key limit; the single-key JSON profile with these bounds stays well under it. Good.

**Game Center — correct, with the right submission suppression.** `GameCenterService.submitRun` skips Game Center for `usedCheckpoint` runs (`:32-35`) — iron rule 10, because checkpoint runs reach end-game speed from t=0 and would be unfairly high. The daily challenge submits to a separate recurring board with the UTC day as context (`:47-53`). Errors are swallowed *intentionally* (offline / pre-ASC) with `try?` — acceptable for a non-essential leaderboard. The local best still updates regardless.

**Daily challenge seeding — UTC-correct and clock-exploit-proof.** `ProfileStore.todaysChallengeSeed` derives y/m/d in a UTC calendar (`:520-523`, `:303-307`) so the whole world rolls over together, and feeds `DailyChallenge.seed` (pure, no `Date`, `Core/DailyChallenge.swift`). `DailyChallengeTests.testSameDailySeedYieldsIdenticalRun` proves two cores from the same seed play byte-identical runs (the property the shared board stands on). Clock-rollback is hardened (§9).

**Gaps:** `GameCenterService`, `AccountService`, and the rule-10 submission suppression have **no unit tests** (the GameKit/AuthServices APIs are hard to fake, so this is understandable but still a coverage hole).

---

## 9. ProfileStore & Economy

**UserDefaults + iCloud split — correct and deliberate.** The whole `Profile` JSON goes to both UserDefaults (local) and KVS (sync). The one thing kept *out* of the synced profile is the per-install device id (`pr.device.id` in plain UserDefaults, `:52-58`) — correct, because two devices must never share the G-counter slot or the per-key-max merge would collapse concurrent purchases.

**Coin economy — cannot go negative, cannot be exploited.** `spendCoins` guards `coins >= n` (`:97-102`); `addCoins` guards non-zero. Every spend surface (revive, world unlock, skin buy) routes through it and uses the `Bool` return. The world ladder (`XPCurve.worldPrices`, 11 rungs summing to 59,400, `Meta/XPCurve.swift:83-92`) is gated by `unlockWorld` which range-checks, refuses already-startable worlds, and spends atomically (`ProfileStore.unlockWorld:223-230`). `EconomyTests.testUnlockWorldSpendsAndUnlocksIndividually` covers the full matrix.

**The revive economy fix — the delta-payout is correct, and tested.** This is subtle and done right. A revived run dies more than once, so every cumulative payout is awarded as `max(0, cumulative − alreadyAwarded)` (`GameView.swift:574-587`) and `totalRuns` counts exactly once (guarded by `statsRecorded`, `:602-643`). Score freezes at death (`die()` captures it, `GameCore.swift:470-477`) and the post-death decel distance is folded into `scoreOffset` on revive so no free points leak (`revive:502`). `GameplayTests.testScoreFreezesAtDeath` and `testReviveResumesAtFrozenScore` pin both halves. This is exactly the class of bug that ships broken in most runners, and here it is correct with regression tests.

**World-ladder purchase gate — correct and exploit-pinned.** The key invariant: a *purchased* deep-world start must never fold into `maxWorldReached` (or one bought-deep death would unlock every cheaper rung for free and pay reach achievements for never passing world 0). `ProfileStore.reachCredit` (`:240-242`) enforces it, and `EconomyTests.testPurchasedWorldStartNeverFoldsIntoReach` (`:123-158`) is an explicit BLOCKER pin walking the exploit chain. Achievements/XP/world-bonus all read reach, not purchase. Correct.

**XP/level system — pure, watermarked, boundary-tested.** `XPCurve` is entirely pure; `xp(for:)` reads only `RunSummary` so IAP `doubleCoins` can never inflate XP (`ProgressionTests.testXPFormulaFromSummary:120-127`). Level-up coin grants are watermarked by `xpLevelRewarded` so a cloud merge that raises the level without a run can't double-pay (`testLevelGrantWatermarkIdempotent`). Level boundaries are tested at ±1 for all 30 levels (`testXPCurvePinnedThresholds:60-66`).

**Mission/achievement claim engine — idempotent, clock-hardened.** `claimMission` refreshes daily/weekly boards first (so a stale claim can't pay), checks the live state, and writes the claim + reward in one mutate (`:477-505`). The CLAIM-ALL cascade resolves every claim against a single `now` so a UTC-midnight rollover mid-cascade can't underpay (per the UITest comment). `MissionsTests` covers claim-once, incomplete-pays-nothing, tiered order, and rollover wipes.

**Clock-manipulation hardening — present and tested.** `sanitized` clamps every future-dated timestamp to `now` on load (`:70-79`); read paths clamp too (`clamped`, `:83-86`). `EconomyTests.testDailyRewardClockRollbackExploitBlocked` / `testChestClockRollbackExploitBlocked` / `testSanitizedClampsFutureTimestampsOnLoad` prove set-clock-forward-then-back can't farm rewards. *Accepted residual* (documented in `state.md`): setting the clock *backward* re-rolls the daily mission board, allowing ~300–400 coins/day of farming — explicitly accepted as low-value and player-favoring.

**Profile decode resilience — iron rule 7, tested.** Every field is `decodeIfPresent(...) ?? default` (`Profile.swift:103-144`), so old saves never wipe or fail. `EconomyTests.testProfileDecodesLegacyJSONWithoutWiping` decodes a legacy blob with a removed field and missing new fields and proves nothing is lost. The equipped-skin self-heal (`equippedSkinID` resolver + `sanitized` + post-merge heal, AUDIT D3-1) is covered by four dedicated tests (`:357-399`).

---

## 10. Test Suite Quality

**Counts (verified by grep, not by README):** **147 unit-test methods** in `Tests/CoreTests/` + **11 XCUITest methods** in `UITests/` = **158 total**. (The README's "146 unit + 12 XCUITest" split is wrong; the *total* of 158 is right — see §16.) ~89 of the unit tests run on Linux via SPM.

**What's covered — extensively:**
- *Determinism:* `RNGTests.runHash` (`Tests/CoreTests/RNGTests.swift:47-64`) folds per-tick state into an FNV-1a hash under autopilot drive; reused by `DailyChallengeTests` and `FlowTests`. `FlowTests.testDeterminismAndPatternStreamIsolation` (`:106-126`) is the crown jewel: it proves that two *different input traces* on the same seed produce an **identical obstacle/pattern stream**, i.e. flow surges and gem fountains consume zero RNG (iron rule 3). This is the exact regression net the architecture needs.
- *Solvability:* `SolvabilityBotTests` — 200 seeds × 6,000 m + 10 seeds × 12,000 m deep soak + a forced-boost-into-next-pattern test + the geometric overdrive-containment invariant.
- *Mechanics-by-simulation:* `ArcCollectionTests` (7/7 gems on one jump across 4 speed tiers, with a length law), `RingTests` (boundary predicates + scripted thread paying exactly once), `BoostTests`/`PowerUpTests` (chrono/boost/doubler via the real core), `DifficultyTests` (gap monotonicity, tier gating, world-2-never-spawns-moving-walls).
- *Economy/meta:* `EconomyTests` (428 lines), `ProgressionTests` (392), `MissionsTests` (263) — clock hardening, cloud merge, watermarks, world ladder, decode resilience.
- *Catalog invariants:* `SkinCatalogTests` is the strongest single file — 24 unique ids *and* names, frozen legacy hex/cost pins, decree-1 (`bodyHex != 0` for all, exactly one prismatic, exactly one IAP), and crucially `levelLocks.sorted() == XPCurve.xpUnlockLevels` (level-unlock↔curve parity, single source of truth).

**The 200-seed bot — a great idea, but be precise about what it proves (the owner is right to question it).** It is a *deterministic greedy-policy regression tripwire*, not a proof of universal solvability. Specifically:
1. **200 seeds samples a 2⁶⁴ space.** Each *pattern* is independently solvable by construction (the patterns are hand-designed and gated), so the bot's real job is catching *accidental RNG-consumption drift* that desyncs placement — which it does well. But "every seed is solvable" is asserted on a sample, and the deep (12,000 m, full-density) soak is only **10 seeds**.
2. **A greedy bot surviving proves a *generous* lower bound** (if greedy clears it, a perfect player can). It does **not** prove the patterns are *fair or readable for a human at 33 m/s* — a pattern the bot threads with frame-perfect leads could still be unreadable to a person. That gap is structurally untestable headless and belongs to the on-device manual pass (which `state.md` still lists as outstanding).
3. **Recommendation:** bump the deep-soak seed count substantially (it is cheap — the bot runs ~9 s for the whole suite), and consider a randomized-seed CI nightly that widens coverage over time. And in the README, frame it as "no greedy-bot death across 200 seeds" rather than implying a universal-solvability proof.

**Coverage gaps (the honest holes):**
- **No `IAPManager` purchase-flow / availability-state test**, and the pure value-badge math (`coinsPerUnit`, `badge(for:)`) is untested despite being trivially testable.
- **No `GameCenterService` / `AccountService` test** (GameKit/AuthServices are hard to fake — understandable, but rule-10 suppression is asserted nowhere).
- **No renderer test** (acknowledged — not Linux-compilable; `CharacterParityTests` pins the *shared constants* but does not pixel-compare 2D preview vs 3D rig).
- **View logic is untested beyond 11 XCUITests** — pure, deterministic helpers like `ShopView.heroOffer`/`nextUnlockSkin`/`featuredID` and `RewardsBar`'s priority ladder could be unit-tested but aren't.

**Brittleness:** the tests are mostly behavioral, not markup-coupled; the XCUITests use label/state waits rather than timers (good). Golden seeds and exact-delta assertions are intentional pins, not brittleness. Quality is high.

---

## 11. CI / Tooling

**GitHub Actions — correct but narrow.** `.github/workflows/core-tests.yml` runs `swift test -c release` in a `swift:6.0-noble` container on every push/PR — i.e. the ~89 Linux-runnable deterministic tests. **It does not build or test the iOS app** (RealityKit/SwiftUI/StoreKit need an Xcode runner, which GitHub's Linux images can't provide). This is a reasonable free-tier choice, but it means **the 11 XCUITests, the renderer, the audio engine, and all SwiftUI never run in CI** — they are gated only by a local `./Tools/ci.sh` on a Mac. Worth stating plainly in the README and, ideally, adding a `macos-latest` job (even if it only builds + runs the unit bundle).

**`Tools/build.sh` / `ci.sh` / `qa.sh` — robust, with one stale comment.** `build.sh` xcodegen-generates and builds for the simulator with signing off (correct for a no-Team-ID-needed build). `ci.sh` chains generate→build→test behind banners. **`ci.sh:11-16` carries a stale comment block** claiming the test step "may report no tests until Phase 2 lands actual test files" — Phase 2 landed long ago (147 tests exist); this is doc-rot inside a script and should be deleted (LOW). `qa.sh` is a build→install→launch→screenshot loop. All three use `set -euo pipefail`. Default sim is `iPhone 17 Pro / 26.5` (overridable via env).

**`project.yml` — correct, complete.** Swift 6 / strict-concurrency complete, deployment target iOS 18, portrait-only, status bar hidden, entitlements wired (Game Center, Sign in with Apple, ubiquity KVS), StoreKit config attached to the run action, coverage gathering on. `MARKETING_VERSION 1.0` (the App Store version) vs the internal "v1.4.2" naming is a known intentional split. The app target globs `PrismRush/` (includes the single sanctioned `Assets.xcassets`); `Tools/` (standalone scripts with top-level code) is correctly outside the target.

**`gen_icon.swift` — genuinely generates the 1024² icon 100% in code** (CoreGraphics + ImageIO, no binary inputs, no text glyphs), writes an opaque PNG, and **auto-syncs it into `Assets.xcassets/AppIcon.appiconset`, `exit(1)`-ing on sync failure** — which mechanically enforces the CLAUDE.md "the catalog PNG is a byte-copy of the tool output" carve-out. Good. `render_sfx.swift` renders every SFX + 2 bars/world to WAV for human review (correct hand-rolled header, clamps before Int16). Both are fail-loud scripts, not shipped.

**CLAUDE.md — excellent, genuinely one of the best agent-facing project guides I've seen.** The "owner decrees" (verbatim product law) + "iron rules" (load-bearing invariants with the *why*) + the build/test seams are precisely what a coding agent needs, and the codebase visibly obeys them. The one risk: it is dense and a few of its cross-references point at the v1.2-era reports (§16).

---

## 12. Security & Privacy

**Team ID `8M64JJQQAU` hardcoded in `project.yml:12` (and the entitlements use `$(TeamIdentifierPrefix)`) — LOW risk, worth a note.** Apple Team IDs are *not secrets* (they appear in every shipped app's provisioning and receipts), so this is not a credential leak. But in a **public** repo it is identity metadata that, combined with `com.rayancheca.prismrush`, ties the repo to a developer account. There is no security consequence; flagging only for awareness. There is nothing to rotate.

**No secrets in source — verified.** Grep for API keys/tokens/passwords comes back empty; there are no first-party servers and no third-party SDKs. The only "identifiers" are the bundle id, Team ID, and Game Center leaderboard ids (`prismrush.best`, `prismrush.daily`) — all necessarily public.

**iCloud data — gameplay only, no PII beyond identity.** The synced `Profile` holds coins/stats/unlocks/purchase flags/transaction ids — no names, no contact info. Game Center provides a player identity and Sign in with Apple a stable opaque user id. `Store/metadata.md` correctly declares the data linkage (Purchases via StoreKit, User ID via Game Center / Sign in with Apple) rather than "Data Not Collected" — this was a previously-wrong claim that has been corrected (the stale `AGENT_docs.md` still shows the old wrong value, §16).

**One real (LOW) finding — Apple user id stored in `UserDefaults`, not Keychain.** `AccountService` writes `credential.user` and the given name to `UserDefaults` (`Services/AccountService.swift:62,65`). The swift-security guidance says sensitive identifiers belong in Keychain. The Apple user identifier is an opaque, app-scoped, non-credential string (not a token), and storing it in UserDefaults means it is wiped on uninstall (forcing a benign re-auth) rather than persisting — so the risk is minimal. Still, Keychain is the more correct home for it, and it would survive reinstall as Apple intends. Minor.

**No injection/XSS/SQL surface** — no web views, no database, no user-supplied strings rendered as markup. App Transport Security is default (no exceptions in the plist).

---

## 13. Performance

**Steady-state allocation — much improved, but "alloc-free" is an overstatement (MEDIUM, see §4).** The material-instance caching win is real (≈44 `UnlitMaterial` constructions/frame → 0). Remaining bounded per-frame allocations: the `model.materials = [mat]` array-literal per visible entity (`RealityRenderer.swift:336-374`), and one CoW copy of the `[EntityState]` snapshot array (`GameCore.swift:598-611`). Both are small and bounded (≤ ~110 entities) and won't cause hitches, but the literal claim should be softened to "material-allocation-free."

**Particle system — pooled correctly.** 560 pre-built spheres, manual physics, no per-frame allocation in `step` (`ParticleSystem.swift:80-96`); `burst`/`emit` advance a cursor over free slots and only reassign `model.materials` (cached via `matCache`, hard-capped at 64, `:122-128`). Time-based emission accumulators (`trailDebt`/`dustDebt`/`speedLineDebt`) keep density identical at 60/120 Hz — a nice touch. Minor: `matCache` keys on `UIColor`, whose equality can differ across color spaces, occasionally missing the cache; bounded by the 64-cap clear, so harmless.

**60 vs 120 Hz — handled correctly.** The fixed-timestep sim is rate-independent by construction; the renderer's per-second emission rates and the run-cycle gallop clock (`advanceVisuals`) are dt-scaled. ProMotion (120 Hz) just means more `SceneEvents.Update` ticks draining the same accumulator. There is no interpolation of the *render pose* between sim ticks (the renderer reads the latest snapshot directly), which at 120 Hz is fine and at 60 Hz is imperceptible for this camera; a true render-interpolation pass is the only thing missing if you ever wanted buttery 30 Hz, which you don't.

**Memory pressure / large objects.** Meshes built once, entities pooled, audio buffers cached, particles fixed. `WorldSky` pre-builds the entire 3-family set piece once (≤46 models visible) and recycles via `restyle`. No unbounded growth path. The granted-transaction ledger (512) and `challengeDaysPlayed` (60) are explicitly bounded for the KVS payload.

**Bundle:** zero assets means a tiny binary; no third-party code to bloat it.

---

## 14. Accessibility

**Reduce Motion — thorough and correct.** Honored in the renderer (shake/FOV/slide-roll/pose-extras/speed-lines all gated, with a subtle slide height-dip kept because slide is gameplay info — a smart exception, `RealityRenderer.swift:103-104,228-233`) and across every SwiftUI preview/animation. Observed live (not just sampled at launch) via the notification observer.

**Reduce Flashing — correctly implemented as a *scale*, not a binary.** The custom `reduceFlash` profile toggle scales every full-screen flash to 0.15× (`EffectsOverlay.FlashView:133`) and thins the HUD timer rings instead of blinking them (`HUDView:125-133`). Read live in `body` (G3) so it applies to the very next flash. This is a more humane implementation than most.

**VoiceOver — strong on meta screens.** Nearly every interactive element has `accessibilityIdentifier` + a crafted `accessibilityLabel` (+ frequent `accessibilityHint`); containers use `accessibilityElement(children:)` correctly; decorative glyphs are `accessibilityHidden`. Milestone popups post `.announcement` notifications (`EffectsOverlay:79-81`).

**Dynamic Type — INCONSISTENT, the main a11y gap (MEDIUM).** The `Theme.TypeScale` / `@ScaledMetric` system (`UI/Theme.swift:60-124`) is excellent and used broadly on Shop/Characters/Worlds/Missions/Rewards. But several surfaces **hardcode `.system(size:)`** and will not scale with the user's text size:
- **`ProfileView.swift`** — the worst offender among meta screens (account card, stats grid, leaderboard rows all hardcoded: `:118-122,:234-235,:260-280`).
- **`HowToPlayView.swift`** — the entire tutorial is hardcoded font sizes; a first-run tutorial that ignores large-text settings.
- **`PauseOverlay.swift`** — hardcoded (lower priority, game overlay).
- A few `size: 8` "REQUIREMENT" labels in `CharacterSelectView`/card badges are below the legibility floor *and* don't scale.
- The in-run **HUD** hardcodes sizes — defensible under decree 6 ("clarity in one frame"), but the *pause menu and tutorial* are not in-run and should respect Dynamic Type.

**Color contrast.** Eclipse's body was already lightened (`0x1A1A2E → 0x2A2A4A`, AUDIT D3-4) precisely for in-run contrast; the dark-on-dark risk is acknowledged and the on-device confirm is still listed as outstanding in `state.md`. Otherwise the neon-on-near-black palette is high-contrast.

---

## 15. Code Quality

**Naming — consistent across modules.** `camelCase`/`PascalCase`/`UPPER_SNAKE` per the conventions; descriptive intent names (`effectiveSpeed`, `reachCredit`, `equippedSkinID`, `flowStreak`). Boolean prefixes (`is`/`has`/`should`) are used.

**Dead code — essentially none.** No commented-out code blocks anywhere; comments are explanatory prose (often citing the decree/rule they enforce). A few defaulted-for-compat params (`PauseOverlay.snapshot`, `MetaScreenScaffold.onCoins`, `CoinBadge.action`) are legitimate optional config; `PauseOverlay.snapshot`'s nil path may now be vestigial — confirm or simplify (LOW).

**TODO/FIXME/HACK inventory — ZERO** in `PrismRush/`, `Tests/`, `UITests/`, `Tools/` (grep-verified). Remarkable for a project this size.

**Magic numbers — game-semantic values are centralized; some design-system values leak as literals.** Mechanic constants live in `Tuning`/`XPCurve`; spacing/radius/type live in `Theme`. The leaks (LOW/MEDIUM, maintainability): raw hex colors bypassing `Theme.Role` in `MissionsView` (section tints `:26-29`), `CharacterSelectView` (rarity colors `:387-391`), and `HowToPlayView`; and scattered timing literals (`ShopView.swift:704` uses a raw `2_600_000_000` ns where every other file uses `.seconds`/`.milliseconds` — inconsistent and easy to misread; cascade/toast beats as bare literals elsewhere). Naming these (`toastDuration`, `claimCascadeBeat`) would help.

**Force unwraps — listed, all low-risk.** In *shipping app code*, the only `!` are **implicitly-unwrapped optionals for two-phase entity init** (`RealityRenderer.swift:16-125` — `playerBody`, `antenna`, `backdrop`, `pools`, `decor`, `particles`, `ringPulse`; `WorldDecor.swift:221-253` — `farCard`, `ceiling`, `sunCore`, …) plus one `s!` iterating a fixed non-nil IUO array (`WorldDecor.swift:667`). These are the standard RealityKit scene-build pattern (assigned in `init`/`buildScene` before any use) and are low-risk. In **tests** and **tools**, force unwraps are deliberate fail-loud assertions (acceptable). There are **no `try!`, `as!`, `fatalError`, or `print`** in shipping code.

**Function/file size.** Functions are mostly < 50 lines. The outliers are `GameModel.install` (`GameView.swift:120-246`, dominated by debug/UITest env-var branches) and `recordRunResults` (`:558-660`); both are cohesive but `install` would benefit from extracting the `PR_DEMOPROFILE`/`PR_FIRSTRUN` test-fixture block. Files: `GameView.swift` (885) and `RealityRenderer.swift` (884) push the 800-line guideline; both are single cohesive responsibilities but are candidates for a split (the model vs the view; the renderer's character-rig vs the per-frame sync).

---

## 16. Documentation

**CLAUDE.md — complete and accurate** (see §11). The decrees and iron rules match the code.

**state.md — current and largely honest, with self-corrected doc-rot.** It reflects v1.4.2, lists blockers as "None," and is candid about accepted trade-offs (backward-clock daily farming, retroactive double-coins, post-revive mission tail not folded). It even carries an explicit *correction* of a previously-false record (`state.md:266,302-306`), which is good hygiene but also a signal the docs have needed repeated patching. The on-device "feel" QA pass (Bolt trail, Eclipse readability, 7/7 arc by feel, ring PERFECT timing) is correctly still listed as **outstanding**, not done.

**reports/ — trustworthy as historical artifacts, but stale and partly aspirational relative to shipped v1.4.2.** The `AGENT_*.md` reports describe the **v1.2 era**; several sections are wiring specs / handoff TODOs rather than as-built records. Two concrete contradictions to flag:
- **`AGENT_docs.md` is wrong now:** it claims "App Privacy: Data Not Collected" and "Free / no IAP" — directly contradicted by the corrected `Store/metadata.md` (which declares IAP + data linkage) and by QA.md flag 4. The stale report should be annotated or removed.
- **`AGENT_wiring.md` is stale:** it asserts "no `prismrush.daily` GC board, not specced anywhere," but the recurring daily board was later added and is now required by `SHIP_CHECKLIST.md`.
- The design docs (`DESIGN_characters.md`, `V13_SPEC.md`) carry inline "⚠️ SUPERSEDED BY DECREE 1" banners revoking the v1.3 "Prism the chameleon" idea — the override is handled honestly (the doc is amended, not shipped), exactly as CLAUDE.md demands.

**README — accurate in spirit, but with several concrete claims that don't survive verification (the owner asked me to check these):**
1. **Test split wrong:** README says "146 unit + 12 XCUITest"; the actual count is **147 unit + 11 XCUITest** (= 158, which is right). Cosmetic but it's a verifiable claim that's off.
2. **IAP count drift:** the README's shipping section says "5 IAP products"; the catalog (`IAP/IAPCatalog.swift`, `Products.storekit`) and `SHIP_CHECKLIST.md`/`Store/metadata.md` say **7** (5→7 in v1.4.1). The "5" references are stale.
3. **"Zero binary assets"** is contradicted by the sanctioned `Assets.xcassets/AppIcon.appiconset` carve-out (an app icon cannot ship without a catalog). The carve-out is owner-approved and the PNG is a generated byte-copy, but the headline claim should be qualified ("zero *hand-authored* binary assets; the lone icon PNG is generated by `gen_icon.swift`").
4. **"Alloc-free steady state"** — see §4/§13; true for *material instances*, overstated as a blanket claim.

**Screenshots — present and real.** 13 PNGs in `docs/screenshots/` (`00_icon` → `16_continue`), referenced by the README. Caveat: they're dated 2026-06-10/11 and may predate some v1.4.2 surfaces (24-character roster, 12-world ladder, Eclipse lighten); the v1.4.2 evidence lives in `reports/shots/v142/`. Worth re-capturing the README walkthrough against current `main`.

**Inline doc coverage — exceptional.** Nearly every non-trivial function has a doc comment explaining *why*, often citing the iron rule or decree it upholds. This is the best-documented code I've reviewed at this scale.

---

## 17. What's Genuinely Good (specific)

1. **The Core/Render seam is real and mechanically enforced** — `RendererPort.swift` + the Linux `Package.swift` make "the core can't import a renderer" a compile error, not a guideline.
2. **Determinism is proven, not asserted** — `RNGTests.runHash`, `PatternOrderTests`' bijection-probe RNG-call counting, and especially `FlowTests.testDeterminismAndPatternStreamIsolation` (different inputs → identical spawn stream) are the right tests and they exist.
3. **The iCloud purchase-merge G-counter** (`ProfileStore.merged:601-631` + `EconomyTests:244-275`) is genuinely sophisticated correctness work that most shipping games get wrong.
4. **The revive delta-payout + score freeze** (`GameCore.die/revive` + `GameView.recordRunResults`) is the textbook-hard runner economy bug, solved and regression-tested.
5. **AVAudioSession interruption/route recovery** (`SynthEngine:137-174`) prevents the silent-audio-forever failure that ships in countless apps.
6. **Clock-rollback hardening** (`ProfileStore.sanitized/clamped` + three tests) closes the classic timed-reward exploit.
7. **Zero `@unchecked Sendable`, zero `try!`/`as!`/`fatalError`/`print`/`TODO`** in shipping code — Swift 6 hygiene at a level most production codebases don't reach.
8. **`SkinCatalogTests`** enforcing `levelLocks == XPCurve.xpUnlockLevels` — the catalog and the curve can't silently diverge.
9. **Honest pre-launch store + leaderboard states** (decree 3) — `IAPManager.Availability` and the empty-leaderboard card never show a red error for a normal situation.
10. **Inline documentation quality** — the "why," tied to decrees/rules, throughout.

---

## 18. Critical Issues

### HIGH (bugs, crashes, exploits, data loss)
**None found in shipping code.** No crash path (the IUO entity fields are init-before-use; the NaN dt guard is robust), no economy exploit (every spend guards `coins >= n`, every grant is idempotent and tested), no data-loss path (decode is resilient, cloud merge is conservative-and-convergent). This is a genuinely sound build.

### MEDIUM (logic/UX/perf/maintainability)
- **M1 — "3 worlds on a loop" (product/architecture).** World identity is keyed `world % 3` in every layer; the 12-world ladder reuses 3 art families with clamped cycle-richening, so worlds 6/9/12 are visually the same three worlds reshuffled. This is the owner's flagged concern and is real. (`Theme.worlds[i%3]` everywhere; `WorldDecor.swift:104,357`; `WorldSky` cycle clamp `min(cycle,2)`.) → §20 for the fix.
- **M2 — "alloc-free steady state" overstated.** Per-frame `materials = [mat]` array literals per visible entity + one CoW `[EntityState]` copy/frame remain (`RealityRenderer.swift:336-374`, `GameCore.swift:598-611`). Bounded and harmless, but the claim should be "material-allocation-free." Optionally skip the per-frame material reassignment when unchanged.
- **M3 — Dynamic Type gaps** in `ProfileView`, `HowToPlayView`, `PauseOverlay` (hardcoded `.system(size:)` instead of `typeScale`). The tutorial and pause menu should scale.
- **M4 — Test coverage holes:** no unit tests for `IAPManager` (incl. the trivially-testable value-badge math), `GameCenterService` rule-10 suppression, `AccountService`, or pure view-logic helpers.
- **M5 — CI does not exercise the iOS app at all** (Linux-only). The XCUITests/renderer/audio/SwiftUI are gated only by a local Mac `ci.sh`. Add a `macos-latest` job.
- **M6 — `AnyView` density** in `ShopView.heroShell` (`:146-197`) — make `heroShell` generic.
- **M7 — README/doc claim drift:** test split (147+11 not 146+12), IAP count (7 not 5), "zero binary assets" vs the icon catalog, "alloc-free." Plus stale `AGENT_docs.md` (privacy) and `AGENT_wiring.md` (daily board).

### LOW (style / minor)
- **L1 — `revive()` clears boost/flow but not magnet/doubler/chrono** (`GameCore.swift:506`), contradicting its "restarts clean" comment. Pick one.
- **L2 — stale comment block in `ci.sh:11-16`** ("no tests until Phase 2").
- **L3 — Apple user id in `UserDefaults`, not Keychain** (`AccountService.swift:62`).
- **L4 — raw hex colors bypassing `Theme.Role`** in `MissionsView`/`CharacterSelectView`/`HowToPlayView`; raw nanosecond literal in `ShopView.swift:704`.
- **L5 — `PauseOverlay.snapshot` defaulted-nil path** possibly vestigial.
- **L6 — `matCache` keys on `UIColor`** (cross-color-space equality can miss; bounded, harmless).
- **L7 — `GameView.swift`/`RealityRenderer.swift` near the 800-line guideline**; the `install` test-fixture block and the model-vs-view split are extraction candidates.

---

## 19. Pre-Shipping Blockers

These are not code defects — the code is shippable. They are the *operational* gates (mostly from `docs/SHIP_CHECKLIST.md`, all currently outstanding) plus the doc-honesty fixes:

1. **App Store Connect setup (hard gates, human):** create the app record; create all **7** IAP products with IDs matching `IAPCatalog.allIDs` *character-for-character*; create **both** leaderboards (`prismrush.best` and the recurring `prismrush.daily` — without the latter, daily-challenge submissions silently no-op); complete the **App Privacy questionnaire** declaring the StoreKit + Game Center/Apple-ID data linkage (NOT "Data Not Collected").
2. **A real Mac build + the on-device manual pass** that `state.md` still lists as outstanding (Eclipse readability on Caverns, 7/7 arc by feel, ring PERFECT timing, Reduce-Motion statics). CI never runs the app, so this is the *only* gate covering the renderer/audio/UI.
3. **README/metadata honesty fixes** (the claim drift in §16/M7) before the repo is presented as a portfolio piece — the owner explicitly cares about this, and the wrong test/IAP counts and "zero binary assets" are exactly the kind of thing a senior reviewer checks.
4. **Decide on the worlds direction (M1)** — see §20. If the answer is "ship 3-on-a-loop for v1.0," then the marketing copy ("loops back harder") is at least honest; but it leaves the owner's stated dissatisfaction unaddressed.

---

## 20. Prioritized Improvement Recommendations

Ordered by impact.

1. **Address the worlds (M1) — the owner's top concern.** Two viable directions, both fitting the existing architecture:
   - **(Recommended) Distance-driven world *evolution* on top of the 3 families.** Keep the 3 palette archetypes but make each cycle visibly *transform* rather than repeat: drive palette, decor density, sky element counts, fog/tint, and music layering as continuous functions of the **absolute** `worldOrdinal` (which the snapshot already carries, `GameSnapshot.worldOrdinal`), not `ordinal % 3`. Remove the `min(cycle, 2)` clamps in `WorldSky` so cycle 3+ keeps differentiating (hue rotation per cycle, added set-piece layers, denser skylines). This is mostly *un-clamping and interpolating* code that already exists, and it directly answers "why do the worlds repeat?" with "they don't — they intensify."
   - **(Bigger) Procedurally-distinct worlds.** Generate per-ordinal palettes from a seeded hue/decor recipe (a `WorldRecipe(ordinal:)` pure function, mirroring `DailyChallenge.seed`) so world 7 looks like *world 7*, not Metropolis-again. This is the "infinite different worlds" option; it's more work but the seam (`worldOrdinal` already plumbed end-to-end, decor already seeds off the absolute index) is ready for it.
   Either way: bump `DailyChallenge.layoutVersion` only if spawn RNG changes (a pure-visual world overhaul does **not** touch the sim, so the bot stays green and seeds stay stable — a clean, low-risk change).
2. **Fix the README/doc claims (M7, L2).** Correct the test split (147+11), the IAP count (7), qualify "zero binary assets" and "alloc-free," delete the stale `ci.sh` comment, and annotate/remove the wrong `AGENT_docs.md` privacy claim. Cheap, high-credibility.
3. **Add a `macos-latest` CI job (M5)** that builds the app and runs the unit bundle (even without the UI tests). Today nothing in CI compiles the renderer/audio/SwiftUI.
4. **Close the cheap test gaps (M4):** unit-test `IAPManager`'s value-badge math and availability transitions, and the pure view-logic helpers (`heroOffer`/`nextUnlockSkin`/`RewardsBar` ladder) — they're pure and deterministic, so this is low effort, high value.
5. **Migrate `ProfileView`/`HowToPlayView`/`PauseOverlay` to `typeScale`/`@ScaledMetric` (M3).** Makes the tutorial and pause menu Dynamic-Type-ready.
6. **Strengthen the solvability soak (§10):** raise the 12,000 m deep-soak seed count and/or add a randomized nightly seed sweep; reframe the README claim as a regression tripwire, not a universal proof.
7. **Make `heroShell` generic (M6)**, resolve the `revive()` power-up-clear inconsistency (L1), and move the Apple user id to Keychain (L3).
8. **Refresh the README screenshots** against current `main` (v1.4.2 surfaces).

---

## 21. Overall Score & Verdict

### **8.7 / 10**

**Engineering: 9.5/10.** The architecture, determinism, concurrency hygiene, economy correctness, and test discipline are at or above professional production standard. I went looking hard for crashes, exploits, and data-loss and found none — every place I expected a runner to ship broken (revive economy, score freeze, cloud purchase merge, clock rollback, RNG-consumption drift) is correct *and* regression-pinned. The absence of any `@unchecked Sendable`/`try!`/`fatalError`/`TODO` in shipping code, under Swift 6 `complete` strict concurrency, is genuinely rare.

**Product/polish: 7/10.** Two things hold the score back. First, the **"3 worlds on a loop"** model — the owner's own flagged concern — is real and unaddressed: the 12-world ladder is a monetization/checkpoint surface over the same three `% 3` families, and the cycle-richening is clamped off after cycle 2. Second, a cluster of **overstated/stale claims** (test counts, IAP count, "zero binary assets," "alloc-free," stale reports) that, for a project the owner treats as a reputation piece, undercut otherwise-excellent work. The accessibility (Dynamic Type) and CI (no iOS job) gaps are real but secondary.

**Verdict:** *Ship-ready as code; not yet ship-complete as a product.* The build will pass review and run correctly. Before the App Store: complete the ASC operational gates (§19), run the outstanding on-device manual pass, and fix the doc-honesty claims. Before calling it *done* against the owner's intent: make a deliberate decision on the worlds (§20.1) — the recommended distance-driven evolution is a low-risk, sim-safe change that directly answers "why do the worlds repeat?" and would push the product score up to match the engineering.

This is a codebase a senior engineer would be glad to inherit. The gaps are honest, bounded, and mostly a sentence-edit or a config job away from closed — except the worlds, which deserve a real decision.
