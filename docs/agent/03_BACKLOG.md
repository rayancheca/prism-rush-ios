# Backlog

Every known defect, gap, and idea. IDs are never reused, even after `DONE`. Gaps in the number
sequence are intentional and fine.

**Status values:** `OPEN` · `IN-PROGRESS(S-NNN)` · `DONE(S-NNN)` · `VERIFY-PENDING(S-NNN)` ·
`WONTFIX(D-NNN)` · `DUPLICATE(PR-NNNN)`

**Severity:** SEV0 crash / data loss / money bug / guaranteed App Review rejection / determinism
break · SEV1 core function missing or broken, a player notices and quits · SEV2 feel, balance or
polish that measurably changes retention · SEV3 code health, tests, architecture, docs · SEV4
parking lot.

---

## Provenance and confidence — read before working any item

Every item below was filed by **session 001** from a full read of the source by ten survey agents
(`docs/agent/scratch/`, gitignored). Each cites `file:line`.

**These findings have NOT been adversarially verified.** One agent read the code and formed a
view; nobody tried to refute it. Sessions 002–008 (the seven audit personas) exist precisely to
re-derive these independently, and session 009 triages. Expect some of these to be wrong, some to
be understated, and some to merge.

Therefore:
- **Before fixing an item, re-read the cited code and confirm the finding yourself.** If it is
  wrong, mark it `WONTFIX` with a one-line reason — that is a useful outcome, not a failure.
- Severities here are first-pass. Session 009 re-scores everything with all seven audits visible.
- Items found by three personas independently are probably worse than their label here.

**Format note (a deviation, deliberate).** `01_RULES.md` §6 mandates the full ten-field block for
every item. Session 001 used the full block for SEV1 and SEV2 items, and a compact table row for
SEV3 items, because 120 full blocks written in one bootstrap session would be padding rather than
information. **Any SEV3 item promoted into a session's scope must be expanded into the full block
format before work starts.** Filed as `PR-0001`.

---

## PR-0001 · SEV3 · Backlog SEV3 items are in compact form, not the mandated block format
- Area:        docs/agent
- Found by:    S-001
- Status:      OPEN
- Symptom:     A session picking up a SEV3 item has no Repro, Fix sketch, Blast radius, or Verification field.
- Why:         Session 001 traded format fidelity for coverage while bootstrapping 120 items.
- Impact:      Only bites when a SEV3 item is actually scheduled.
- Fix sketch:  Expand the item into the full block at the moment it enters a session's scope. No bulk migration.
- Verification: The item you are working has all ten fields before you start editing code.

---

# SEV1 — core function missing or broken

## PR-0002 · SEV1 · iCloud merge can duplicate coins that were already spent
- Area:        Meta/ProfileStore
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     A player's coin balance silently inflates after a two-device sync, crediting purchased coins twice.
- Repro:       1. Device A buys a coin pack (balance and `totalPurchased` both rise). 2. Spend the coins on A. 3. Sync. 4. Device B merges: `merged.coins = max(local, remote) + max(0, mergedTotalPurchased − winnerPurchased)`.
- Why:         `totalPurchased` is a grow-only counter but `coins` shrinks on spend, so the top-up term re-credits already-spent purchases. `ProfileStore.swift:657-663`.
- Impact:      Real-money economy corruption in the player's favour; breaks every economy assumption AUDIT-002 will make. Also inflates the leaderboard-adjacent stats.
- Fix sketch:  Merge the balance as a proper CRDT: track `totalPurchased` and `totalSpent` as separate grow-only counters and derive `coins = totalEarned + totalPurchased − totalSpent`. Do not patch the max() expression in place.
- Blast radius: `Meta/ProfileStore.swift`, `Meta/Profile.swift` (new fields need `decodeIfPresent ?? default`), `Tests/CoreTests/EconomyTests.swift`.
- Verification: New test: simulate A-buys → A-spends → B-merges and assert the balance is unchanged. Plus the existing 30 EconomyTests stay green.

## PR-0003 · SEV1 · iCloud KVS is an unauthenticated entitlement source
- Area:        Meta/ProfileStore
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     Anything that can write the app's KVS blob grants itself every skin, every world, and Double Coins forever.
- Repro:       1. Write a crafted profile JSON into the app's `NSUbiquitousKeyValueStore`. 2. Relaunch on any signed-in device. 3. `mergeFromCloud` unions `ownedSkins` / `ownedProducts` / `purchasedWorlds` and ORs `doubleCoins`.
- Why:         `mergeFromCloud` validates only JSON well-formedness before unioning entitlements. `ProfileStore.swift:669-673, 692-698`.
- Impact:      Free unlock of every paid item, propagating to all the player's devices and surviving reinstall. Directly undercuts the IAP catalogue.
- Fix sketch:  Do not let the cloud grant entitlements. Derive `ownedProducts` and `doubleCoins` from verified StoreKit `Transaction.currentEntitlements` at launch; let KVS carry only non-entitlement progress. Coin-purchased skins are the harder case — decide whether they are cloud-trusted or re-derived.
- Blast radius: `Meta/ProfileStore.swift`, `IAP/IAPCatalog.swift`, `IAP/IAPManager.swift`.
- Verification: A test that feeds a hostile cloud blob and asserts no entitlement is granted.
- Blocked by:  PR-0004 (entitlement derivation has to be correct first)

## PR-0004 · SEV1 · An `.unverified` purchase is charged, never granted, never finished, and has no recovery path
- Area:        IAP/IAPManager
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     A player is charged, receives nothing, and every subsequent launch silently re-runs the same dead transaction.
- Repro:       Any purchase whose `VerificationResult` is `.unverified` (jailbreak, proxy, or a genuine StoreKit hiccup).
- Why:         The guard at `IAPManager.swift:154-157` correctly refuses to grant, but never calls `transaction.finish()`, so StoreKit redelivers it through `Transaction.updates` forever, and nothing surfaces the state to the player.
- Impact:      Money taken, nothing delivered, no path to resolution — the exact shape of an App Review rejection under 3.1 and of a refund complaint.
- Fix sketch:  On `.unverified`: surface an explicit, honest message ("we could not verify this purchase — contact support / try Restore"), and decide deliberately whether to `finish()` (stops the loop, loses the retry) or keep it pending with a bounded retry and a visible state. Do NOT silently finish it.
- Blast radius: `IAP/IAPManager.swift`, `UI/ShopView.swift`.
- Verification: StoreKit test configuration with verification failure injected; assert the UI shows the state and the loop terminates.

## PR-0005 · SEV1 · `load()` prefers the cloud blob outright and can discard a newer local save
- Area:        Meta/ProfileStore
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     A player loses progress on launch after a failed sync, a device restore, or KVS eviction.
- Repro:       1. Play offline, earning coins and unlocks (UserDefaults advances). 2. The KVS copy remains stale. 3. Relaunch — the stale cloud blob wins.
- Why:         `ProfileStore.swift:700-708` prefers the cloud copy at load with no merge against local.
- Impact:      Silent data loss. This is the worst possible failure for a game whose whole meta layer is a save file.
- Fix sketch:  Run the same merge at load that `mergeFromCloud` runs on the sync notification, rather than a preference. Merge must be monotone in every grow-only field.
- Blast radius: `Meta/ProfileStore.swift`.
- Verification: Test: stale cloud + newer local → merged result keeps the local progress.

## PR-0006 · SEV1 · Reading the rewards bar mutates and saves the profile from inside `body`
- Area:        Meta/ProfileStore, UI/RewardsBar
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     Potential "modifying state during view update" behaviour, and an unpredictable extra disk + iCloud write on a UTC rollover while the hub is on screen.
- Repro:       Be on the hub across a UTC midnight with the rewards bar visible.
- Why:         `RewardsBar.swift:23` calls `ProfileStore.unclaimedCount(now:)`; that path (`ProfileStore.swift:558`) can reach `refreshDailyMissions` → `mutate` → `save()` + `cloud.synchronize()`. A `body` evaluation writes an `@Observable`.
- Impact:      Classic SwiftUI reentrancy hazard; the repo has shipped three bugs from this family already (CLAUDE.md rule 5).
- Fix sketch:  Split the query into a pure read used by `body` and an explicit refresh driven by `.task`/`.onAppear`/a timer. Never let a `body`-reachable call mutate.
- Blast radius: `UI/RewardsBar.swift`, `Meta/ProfileStore.swift`.
- Verification: Grep every `body`-reachable `ProfileStore` call for a `mutate` path; add a comment marking the read-only entry points.

## PR-0007 · SEV1 · `ProcessInfo.systemUptime` is a required-reason API and is not declared in the privacy manifest
- Area:        Audio/SynthEngine, Support/PrivacyInfo.xcprivacy
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     App Store Connect rejects or warns on upload for an undeclared required-reason API.
- Why:         `SynthEngine.swift:150` calls `ProcessInfo.processInfo.systemUptime`, which Apple classifies under `NSPrivacyAccessedAPICategorySystemBootTime`. The manifest does not declare it.
- Impact:      Blocks submission. Cheap to fix, expensive to discover at upload time.
- Fix sketch:  Either declare the category with approved reason `35F9.1` in `PrivacyInfo.xcprivacy`, or replace the call with a non-required-reason clock if the use is only relative timing.
- Blast radius: `PrismRush/Support/PrivacyInfo.xcprivacy` or `PrismRush/Audio/SynthEngine.swift`.
- Verification: Archive and validate; the upload warning is gone.

## PR-0008 · SEV1 · No in-app account deletion path, but Sign in with Apple is wired
- Area:        Services/AccountService, UI/ProfileView
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     App Review rejects under the account-deletion requirement.
- Why:         `AccountService.signOut()` (`AccountService.swift:82-87`) clears both Keychain items — a complete local wipe, since there is no server — but `ProfileView.swift:122` labels it "Sign out".
- Impact:      A one-word problem that is a hard rejection. Note the *behaviour* may already satisfy the rule; the affordance and the labelling do not.
- Fix sketch:  Add an explicit "Delete account" affordance with a confirmation, stating plainly that no server data exists and what is removed. Keep "Sign out" separate.
- Blast radius: `UI/ProfileView.swift`, `Services/AccountService.swift`.
- Verification: The path exists, is reachable in two taps from Profile, and is described in `06_COMPLIANCE.md` row C3.

## PR-0009 · SEV1 · `PrivacyInfo.xcprivacy` declares no collected data while every ship doc says Purchases + User ID
- Area:        Support/PrivacyInfo.xcprivacy
- Found by:    S-001 (surveys: audio-services, docs-claims)
- Status:      OPEN
- Symptom:     The bundled manifest and the App Store Connect answers the owner is told to give will contradict each other.
- Why:         `PrivacyInfo.xcprivacy:6` has `<key>NSPrivacyCollectedDataTypes</key><array/>` (empty), while `Store/metadata.md` §7 declares Purchases and User ID as linked to the user.
- Impact:      5.1.x exposure. One of the two is wrong and it must be resolved before submission, not during review.
- Fix sketch:  Decide the truth: the app itself has no server, and Game Center / SiwA / StoreKit are Apple's own collection. Then make the manifest, `Store/metadata.md` §7, and the ASC questionnaire say the same thing. Write the reasoning into `06_COMPLIANCE.md`.
- Blast radius: `PrismRush/Support/PrivacyInfo.xcprivacy`, `Store/metadata.md`, `docs/agent/06_COMPLIANCE.md`.
- Verification: All three sources state the same declaration, with the reasoning recorded.

## PR-0010 · SEV1 · `Store/metadata.md` describes a different game, and the ship docs say to paste it verbatim
- Area:        Store/metadata.md
- Found by:    S-001 (survey: docs-claims)
- Status:      OPEN
- Symptom:     The App Store listing would claim three worlds ("Neon Metropolis, Crystal Caverns, Solar Sands") for a game that ships twelve world families, and omits most of what shipped in v1.3–v1.6.
- Why:         The metadata was written at v1.0 and never revised. Subtitle `Neon 3-world hyperspeed run` (`Store/metadata.md:12`); description and feature list at `:40-71`.
- Impact:      Guideline 2.3 metadata-accuracy exposure, and it undersells the actual product to buyers.
- Fix sketch:  Rewrite name/subtitle/keywords/description/what's-new/screenshot captions against the shipped v1.6 build. Do it after AUDIT-001's Completeness Ledger exists so every claim is checkable.
- Blast radius: `Store/metadata.md` only.
- Verification: Every line of the description maps to a `implemented AND reachable` row of the Completeness Ledger.
- Blocked by:  AUDIT-001 (the ledger)

## PR-0011 · SEV1 · RUN AGAIN after a Daily Rush silently starts a normal run and burns armed loadout charges
- Area:        UI/GameView
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     The player taps RUN AGAIN expecting another Daily Rush attempt, gets an ordinary run, and loses consumable charges they did not choose to spend.
- Repro:       1. Start a Daily Rush. 2. Die. 3. Tap RUN AGAIN.
- Why:         `GameView.swift:1116` wires `onRestart: { model.startRun() }` → `beginRun(fromWorld: 0, seed: nil, consumeLoadout: true)` (`GameView.swift:367-385`), dropping the challenge seed and consuming the loadout.
- Impact:      Violates owner decree 5 (advertised bonuses are always delivered) and decree 4. Loses the player real, earned consumables with no warning.
- Fix sketch:  Make `onRestart` re-enter the same run *kind*. For a challenge run either re-run the same seed (if a second attempt is allowed) or route back to the hub. Never consume loadout charges on a path the player did not opt into.
- Blast radius: `UI/GameView.swift`, `UI/GameOverView.swift`.
- Verification: XCUITest: daily run → die → RUN AGAIN → assert the run kind and that charge counts are unchanged.

## PR-0012 · SEV1 · Entity pools key on id but never validate `kind`, and `nextId` resets to 0
- Area:        Render/Reality/EntityPools
- Found by:    S-001 (survey: render)
- Status:      OPEN
- Symptom:     Latent. A reset that does not also reset the renderer would render the wrong mesh for an id permanently, and file it back into the wrong free list.
- Why:         `EntityPools.swift:27-34` writes `liveKind[s.id]` only on creation and the reuse branch trusts the existing entity; `GameCore.reset()` sets `nextId = 0` (`GameCore.swift:152`).
- Impact:      Not reachable today, but it is one missing `resetEntities()` call away and there is no assertion.
- Fix sketch:  Assert (or defensively recycle) when `liveKind[s.id] != s.kind` on the reuse path. Cheap and it converts a silent corruption into a loud failure.
- Blast radius: `Render/Reality/EntityPools.swift`.
- Verification: A unit or debug assertion that fires if the invariant is violated; confirm the normal path never trips it in a 12,000 m soak.

---

# SEV2 — feel, balance, and retention

## PR-0020 · SEV2 · The seeded spawn stream is not purely a function of the seed
- Area:        Core/GameCore, Core/Spawner
- Found by:    S-001 (survey: core)
- Status:      OPEN
- Symptom:     Two players on the same Daily Challenge seed can get different tracks if they use chrono or overdrive at different moments.
- Why:         `spawner.fill(to:dist:)` (`GameCore.swift:301`) samples `dist` at whichever tick the horizon crosses the cursor; per-tick distance depends on `effectiveSpeed`, which chrono/boost scale. Drift accumulates in `cursor` and eventually moves a pattern across a tier boundary (260 / 576 / 1440 / 1920 m), changing `maxIndex`, changing the draw, diverging the whole stream. `Spawner.swift:35-48`.
- Impact:      The Daily Challenge's core promise ("everyone plays the same track") is conditional. Every determinism test passes because the Autopilot never collects pickups, so the soak never exercises it.
- Fix sketch:  Drive spawn decisions from a quantised, player-independent distance (e.g. the cursor itself, or `floor(distance)`), so `gap` and `maxIndex` cannot drift with buff usage. This changes the spawn stream → **`DailyChallenge.layoutVersion` must bump** and the pre-armed v8 golden `0x2FC8A9EAC0B9E30F` applies.
- Blast radius: `Core/Spawner.swift`, `Core/GameCore.swift`, `Core/DailyChallenge.swift`, `Tests/CoreTests/DailyChallengeTests.swift`, `PatternOrderTests`.
- Verification: New test — same seed, two runs with different chrono/boost timing, identical obstacle `d` sequences (exact, not tolerance). Plus 200-seed bot + 12k soak green.
- Note:         The code comments assert the opposite (`RNG.swift:3-4`, `GameCore.swift:20-21`). Fix the comments either way.

## PR-0021 · SEV2 · `capGem = 72` is reachable and overflow is silent, truncating the coin path
- Area:        Core/GameCore
- Found by:    S-001 (survey: core)
- Status:      OPEN
- Symptom:     The coin trail that is supposed to show the safe route through a pattern just stops, exactly in the dense sections where the player needs it.
- Why:         `apply` returns without placing when the cap is hit (`GameCore.swift:667`, `Tuning.swift:84`). Pattern 10 alone emits 24 gems, pattern 11 emits 18, gap trails add 4–6 per pattern, and a flow surge injects 10 more — with gaps down to 5 m, three or four patterns coexist inside the 115 m horizon.
- Impact:      Directly undermines the v1.6 "coins mark a takeable route" principle and decree 6 (clarity). No counter, no FX, no test.
- Fix sketch:  Instrument first — add a debug counter and confirm reachability in a soak. Then either raise the cap or prioritise placement (route breadcrumbs before decorative fountain gems).
- Blast radius: `Core/GameCore.swift`, `Core/Tuning.swift`, renderer pool caps must stay in step.
- Verification: A soak that asserts zero dropped gem placements, or an explicit documented policy for which gems lose.

## PR-0022 · SEV2 · Gem arcs and rings are placed for the ramp speed, but a buffed player crosses at a different speed
- Area:        Core/Patterns
- Found by:    S-001 (survey: core)
- Status:      OPEN
- Symptom:     Under chrono the player falls short of the back half of a gem arc; under overdrive they overshoot it. The reward for a good jump silently disappears.
- Why:         `crossingSpeed` predicts `min(33, 17 + d·0.0052)` (`Patterns.swift:33-35, 46-58, 142-144`), but the player crosses at `effectiveSpeed` (chrono ×0.65, boost ×1.3). `gemPickup.dy` is only 1.15.
- Impact:      The two power-ups that are supposed to feel good actively remove rewards. `ArcCollectionTests` only exercises the un-buffed case.
- Fix sketch:  This is a design decision, not just a fix — either widen the collection window while buffed, or accept it and stop calling arcs a reward. Route through AUDIT-002 before coding.
- Blast radius: `Core/Patterns.swift` or `Core/GameCore.swift` (collection windows), `Core/Tuning.swift`.
- Verification: Test arc collection with chrono and with boost active, at several distances.

## PR-0023 · SEV2 · Super Sneakers makes prism rings uncollectable
- Area:        Core/Tuning
- Found by:    S-001 (survey: core)
- Status:      OPEN
- Symptom:     While the boots buff is active, jumping on the ring telegraph sails straight over the ring and scores nothing.
- Why:         Buffed apex is `(10.6·1.3)²/(2·26) = 3.649`; player centre at apex `3.649 + 0.66·1.12 = 4.389`. `ringY = 2.90` with `ringPassDY = 0.9` accepts centre ∈ (2.0, 3.8). `Tuning.swift:42, 96-98`.
- Impact:      A buff that removes a reward. The stated design contract ("only ever over-clears, never under-places", `Tuning.swift:38-41`) holds for obstacles and is violated for rings.
- Fix sketch:  Either scale `ringY` with the active jump multiplier, or widen `ringPassDY` while the buff is active, or suppress ring patterns during the buff. Collision-only change, so no `layoutVersion` bump — confirm that before committing.
- Blast radius: `Core/GameCore.swift` (ring pass test), `Core/Tuning.swift`.
- Verification: Test: activate Super Sneakers, jump on a pattern-9 telegraph, assert `ringPassed` fires.

## PR-0024 · SEV2 · Every camera and pose smoothing lerp is frame-rate dependent
- Area:        Render/Reality/RealityRenderer
- Found by:    S-001 (survey: render)
- Status:      OPEN
- Symptom:     The slide dip, boost FOV punch, chrono dip and camera lift all land about twice as slowly on a 60 Hz device as on a 120 Hz ProMotion device.
- Why:         Fixed per-frame alphas at `RealityRenderer.swift:234, 237, 243-244, 253, 259, 274, 282, 397`, while the comments quote absolute times. The lateral camera spring (`:262-264`) and antenna whip (`:623-625`) correctly scale by `sdt`, and the particle accumulators were explicitly fixed for this hazard (`:119-121`) — so this reads as an oversight.
- Impact:      The game feels materially different on non-ProMotion hardware, which is most of the installed base.
- Fix sketch:  Convert each fixed alpha to an `sdt`-scaled exponential (`1 - exp(-sdt/tau)`), using the time constants the comments already state.
- Blast radius: `Render/Reality/RealityRenderer.swift`.
- Verification: Device or simulator comparison at 60 and 120 Hz; the same visual settle time. VERIFY-PENDING on real hardware.

## PR-0025 · SEV2 · The pooled-entity place closure heap-allocates a materials array per visible entity per frame
- Area:        Render/Reality/RealityRenderer
- Found by:    S-001 (survey: render)
- Status:      OPEN
- Symptom:     ~1,800 small allocations per second at 120 Hz, contradicting the file's own "0 in steady state" claim (`:149`).
- Why:         `$0.model?.materials = [mA]` at `RealityRenderer.swift:376, 378, 389, 398, 401, 409, 414` builds a fresh `[any Material]` and writes a whole `ModelComponent` back into the ECS every frame. The materials are cached; the array wrapper is not.
- Impact:      Sustained allocation churn on the hot path — the thing that shows up as thermal throttling in a long session.
- Fix sketch:  Assign only when the material actually differs from the entity's current one.
- Blast radius: `Render/Reality/RealityRenderer.swift`.
- Verification: Instruments allocation trace over a 3-minute run. VERIFY-PENDING (needs a device).

## PR-0026 · SEV2 · Tap-to-jump only fires on touch-up
- Area:        UI/GameView
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     Jumps feel laggy. The delay is the player's own finger-contact duration, typically 60–120 ms, on top of everything else.
- Why:         `GameView.swift:1058` uses `DragGesture(minimumDistance: 0)` with only `.onEnded`; there is no `.onChanged` fast path for the tap case.
- Impact:      This is the single most-used input in the game. AUDIT-004 will find it in the first ten seconds.
- Fix sketch:  Fire the jump on first touch-down and mark the gesture consumed, so `.onEnded` does not double-fire; keep swipe detection on the drag path.
- Blast radius: `UI/GameView.swift` input layer.
- Verification: XCUITest asserting a jump within one frame of touch-down, plus on-device feel check (VERIFY-PENDING).

## PR-0027 · SEV2 · A swipe-out-and-back gesture is misread as a tap and jumps
- Area:        UI/GameView
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     A cancelled swipe, a circular thumb motion, or an over-corrected lane change makes the player jump when they did not ask to.
- Why:         `handleGesture` (`GameView.swift:893-911`) only sees the net translation at touch-up, so any path returning within 22 pt of its origin reads as a tap.
- Impact:      An unrequested jump at speed is usually a death, and it reads as the game's fault, not the player's — the exact failure mode that ends sessions.
- Fix sketch:  Track the maximum excursion during `.onChanged` and suppress the tap interpretation when it exceeded the threshold.
- Blast radius: `UI/GameView.swift`.
- Verification: Unit-testable if the gesture classifier is extracted; otherwise an XCUITest drag path.

## PR-0028 · SEV2 · The death panel's distance and world number keep climbing after death
- Area:        Core/GameCore, UI/GameOverView
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     The final distance shown on the game-over panel is larger than the distance the player actually reached, and keeps rising while the panel animates in.
- Why:         `stepSpeedAndDistance` integrates `distance` in `.over` mode (the post-death decel) with no mode guard, and the panel reads live values. `GameView.swift:1119`, `GameOverView.swift:66, 74-76, 381`.
- Impact:      The score freezes correctly but the headline distance does not — the panel lies about the run, which is a trust problem on the screen the player stares at most.
- Fix sketch:  Capture the run's final distance and world at `die()` and pass those immutable values to the panel.
- Blast radius: `Core/GameCore.swift`, `UI/GameView.swift`, `UI/GameOverView.swift`.
- Verification: Force a death at a known distance, assert the panel value equals it and does not change.

## PR-0029 · SEV2 · `reset(seed:)` never rebuilds the snapshot, so the menu can render a stale `.over` world
- Area:        Core/GameCore
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     After quitting to the menu, the renderer can briefly show the dead run's state.
- Why:         `init` (`:86`), `startRun` (`:113`) and `revive` (`:629`) all call `rebuildSnapshot()`; `reset(seed:)` (`GameCore.swift:138-154`) does not. `returnToMenu()` (`GameView.swift:494-504`) sets `mode = .menu` while `snapshot.mode` stays `.over`.
- Impact:      A visible inconsistency on a common path, and a trap for any future caller of `reset`.
- Fix sketch:  Call `rebuildSnapshot()` at the end of `reset`. Check no test depends on the current behaviour first.
- Blast radius: `Core/GameCore.swift`.
- Verification: Assert `core.snapshot.mode == .menu` immediately after `reset(seed:)`.

## PR-0030 · SEV2 · Profile persistence runs inside the fixed-timestep tick
- Area:        UI/GameView, Meta/ProfileStore
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     A disk write and an iCloud `synchronize()` happen inside `advance`'s tick loop at the moment of death — a frame spike exactly when the death animation should be smooth.
- Why:         `die()` is called from `stepObstacles`, inside `tick`, inside `advance`'s `while` loop; the FX sink (`GameCore.swift:559-564`) reaches the persistence path at `GameView.swift:680-792`.
- Impact:      Frame hitch on every death; also means simulation time and I/O are interleaved, which is a bad seam.
- Fix sketch:  Queue the run summary from the FX handler and apply it after `advance` returns.
- Blast radius: `UI/GameView.swift`.
- Verification: Confirm no `ProfileStore` write is reachable from inside `tick`; frame-time trace across a death (VERIFY-PENDING on device).

## PR-0031 · SEV2 · A StoreKit "pending" (ask-to-buy) is rendered as a red error
- Area:        IAP/IAPManager, UI/ShopView
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     A child whose purchase is awaiting a parent's approval sees a red error strip, which reads as failure.
- Why:         `IAPManager.purchase` sets `lastError` for the `.pending` case (`IAPManager.swift:166-167`) and `ShopView.swift:31` renders any non-nil `lastError` as an error.
- Impact:      Direct violation of owner decree 3 (no broken-looking states for expected situations). Ask-to-buy is a normal, common flow.
- Fix sketch:  Separate the state channel from the error channel: `lastError` for failures, a distinct `pendingNotice` rendered in a neutral/positive style.
- Blast radius: `IAP/IAPManager.swift`, `UI/ShopView.swift`.
- Verification: StoreKit test config with ask-to-buy enabled; the UI shows a calm, informative state.

## PR-0032 · SEV2 · A purchase can fail with zero feedback in the `.notConfigured` state
- Area:        UI/ShopView
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     The player taps buy and nothing at all happens.
- Why:         The toast fires only when `iap.availability != .ready && !iap.isPurchasable(id)`, and the red strip renders only when `availability == .ready`. A *partial* load (`.notConfigured`) falls between both. `ShopView.swift:770-775`.
- Impact:      Decree 3 and decree 4 violation, and a lost sale with no explanation.
- Fix sketch:  Make the feedback exhaustive over the availability enum — every state has exactly one presentation, chosen by a `switch` with no `default`.
- Blast radius: `UI/ShopView.swift`, `IAP/IAPManager.swift`.
- Verification: Exercise every `availability` case and assert a visible, non-error-styled response for each normal one.

## PR-0033 · SEV2 · The error strip in the shop is undismissible and goes stale
- Area:        UI/ShopView, IAP/IAPManager
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     A failed purchase leaves a red strip that stays until an unrelated success clears it.
- Why:         `lastError` is cleared only on a successful purchase (`IAPManager.swift:161`), a successful restore (`:185`), or a full load reaching `.ready` (`:83`). `ShopView.swift:31`.
- Impact:      A permanently angry-looking store. Decree 3.
- Fix sketch:  Give the strip a dismiss control and clear the error on view dismissal and on the next purchase attempt.
- Blast radius: `UI/ShopView.swift`, `IAP/IAPManager.swift`.
- Verification: Fail a purchase, dismiss, reopen — the strip is gone.

## PR-0034 · SEV2 · Refunded purchases are never revoked
- Area:        IAP/IAPManager, IAP/IAPCatalog
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     After a refund the player keeps Double Coins and the Aurora skin forever, on every device.
- Why:         `transaction.revocationDate` is never checked anywhere in `IAPManager.swift`, and `IAPCatalog.restore` (`:66`) only ever sets flags to true. The iCloud OR/union merge then makes it permanent.
- Impact:      Refund abuse is free and self-propagating.
- Fix sketch:  Check `revocationDate` in both `Transaction.updates` and `currentEntitlements`, and drive entitlements from the verified set rather than from sticky booleans.
- Blast radius: `IAP/IAPManager.swift`, `IAP/IAPCatalog.swift`, `Meta/ProfileStore.swift`.
- Verification: StoreKit test config revocation; the entitlement disappears.
- Blocked by:  PR-0003 (the cloud must stop re-granting it)

## PR-0035 · SEV2 · Setting the device clock forward farms both timed faucets
- Area:        Meta/ProfileStore
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     Advancing the clock immediately makes the daily reward and the chest ready again, repeatedly.
- Why:         Every clamp is `min(stored, now)` (`ProfileStore.swift:299-348`), which defends only against a backwards clock.
- Impact:      Unbounded free currency. Note `state.md` records backward-clock mission farming as an accepted trade-off — forward-clock was believed blocked, and per this reading it is not. Confirm before acting.
- Fix sketch:  Persist a monotonic reference (e.g. last-claim timestamps plus an accumulated-uptime cross-check) and require both to advance.
- Blast radius: `Meta/ProfileStore.swift`, `Tests/CoreTests/EconomyTests.swift`.
- Verification: Test that advances a synthetic clock by a week and asserts exactly one daily reward.

## PR-0036 · SEV2 · Five lifetime stats and the login streak are silently not merged across devices
- Area:        Meta/ProfileStore
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     Playing on a second device loses lifetime totals; the profile screen understates the player's history.
- Why:         `merged` starts from `local` and never touches `totalRuns`, `totalDistance`, `totalGems`, `totalCoinsEarned`, `bestStreak`, `loginStreak`, `dailyChallengeBest`. `ProfileStore.swift:657-689`; the docstring at `:641-648` implies otherwise.
- Impact:      Mission and achievement progress keyed off lifetime stats regresses. Feels like data loss even though entitlements survive.
- Fix sketch:  Merge each with the correct monotone operator (`max` for bests, `+` is wrong for counters that both devices increment — decide per field and document it).
- Blast radius: `Meta/ProfileStore.swift`.
- Verification: A merge test covering every profile field, asserting no field silently drops.

## PR-0037 · SEV2 · `.playback` with no `.mixWithOthers` kills the user's background audio at launch, even when muted
- Area:        Audio/SynthEngine
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     Opening the game stops whatever the player was listening to, and stops it even if the game itself is muted.
- Why:         `SynthEngine.swift:86-87` sets the category and activates the session inside `start()`, called unconditionally from `GameView.swift:142` at scene attach.
- Impact:      A well-known uninstall trigger. Note `.playback` was a deliberate v1.6 choice so music plays on silent — the fix is the missing option and the unconditional activation, not the category.
- Fix sketch:  Activate the session lazily (first actual sound), and honour mute by not activating at all. Evaluate `.mixWithOthers` against the "plays on silent" requirement — they interact.
- Blast radius: `Audio/SynthEngine.swift`, `UI/GameView.swift`.
- Verification: Start music in another app, launch the game muted, confirm the other audio survives. VERIFY-PENDING (device).

## PR-0038 · SEV2 · Nothing recovers audio when the app returns to the foreground
- Area:        UI/GameView, Audio/SynthEngine
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     After an interruption or a background trip, the game can come back silent for the rest of the session.
- Why:         `GameView.swift:1220-1222` only calls `model.pauseForBackground()` on `phase != .active`, and that only sets `paused = true` (`:447-449`). Nothing calls `recoverEngine()` on `.active`. Compounded by `play(_:)` being unable to self-heal a stopped engine (`SynthEngine.swift:101` is a bare `guard … else { return }`) while `musicStart` (`:119`) can.
- Impact:      Silent game after a phone call is a top-tier bug report.
- Fix sketch:  Handle the `.active` transition explicitly: verify `engine.isRunning`, recover if not. Also give `play(_:)` the same self-heal `musicStart` has.
- Blast radius: `UI/GameView.swift`, `Audio/SynthEngine.swift`.
- Verification: Backgrounding and interruption cycles on a device. VERIFY-PENDING.

## PR-0039 · SEV2 · The interruption handler ignores `shouldResume` and ignores `.began`
- Area:        Audio/SynthEngine
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     Audio resumes when it should not, or fails to when it should, after Siri or a call.
- Why:         `SynthEngine.swift:163-169` reads only `AVAudioSessionInterruptionTypeKey` and recovers on any `.ended`, ignoring `AVAudioSessionInterruptionOptionShouldResume` and doing nothing on `.began`.
- Impact:      Part of the same family as PR-0038; fixing them together is cheaper.
- Fix sketch:  Implement Apple's documented contract: pause and mark state on `.began`, resume only when `.shouldResume` is set on `.ended`.
- Blast radius: `Audio/SynthEngine.swift`.
- Verification: Siri and incoming-call cycles on a device. VERIFY-PENDING.

## PR-0040 · SEV2 · The music is a 1.8-second loop for the entire session
- Area:        Audio/Music, Audio/Synth
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     The soundtrack is audibly repetitive within the first minute and grating by minute three.
- Why:         `world` is pinned to 0 (`SynthEngine.swift:133`, the v1.6 owner decision to drop per-world beds), so `cycle = world / 12 = 0` and `layer` is always 0 (`Synth.swift:309`) — the whole bed is an 8-step, ~1.82 s loop, on the menu and in the run alike.
- Impact:      The README's headline claim that the bed "thickens" per world is false in the shipped build (see PR-0060). More importantly, a 1.8 s loop is a mute-button generator.
- Fix sketch:  Add long-form structure *within* the single bed the owner asked for — bar-level variation, a longer phrase, an intensity layer keyed to speed rather than to world. This needs an owner decision; it is a design change, not a bug fix.
- Blast radius: `Audio/Synth.swift`, `Audio/Music.swift`, `Audio/SynthEngine.swift`.
- Verification: Render the bed with `Tools/render_sfx.swift` and listen. Owner sign-off required.

## PR-0041 · SEV2 · No output limiter anywhere in the audio chain
- Area:        Audio/Synth, Audio/SynthEngine, Audio/Music
- Found by:    S-001 (survey: audio-services)
- Status:      OPEN
- Symptom:     Dense moments (several SFX plus the bed) can clip.
- Why:         Generators are purely additive (`Synth.swift:31, 50`) and nothing clamps to [-1, 1] before `makeBuffer` (`SynthEngine.swift:200-207`, `Music.swift:95-101`). The tests only assert peak ≤ 2.0.
- Impact:      Audible distortion at exactly the high-intensity moments the audio is meant to sell.
- Fix sketch:  Add a soft clip or a simple limiter at the buffer boundary. Tighten `SynthTests` to assert peak ≤ 1.0 afterwards.
- Blast radius: `Audio/Synth.swift`, `Audio/SynthEngine.swift`, `Audio/Music.swift`, `Tests/CoreTests/SynthTests.swift`.
- Verification: `SynthTests` peak assertion at 1.0; render and inspect the worst-case stack.

## PR-0042 · SEV2 · The OVERDRIVE HUD chip's depletion bar is mis-scaled for manual and pre-run boosts
- Area:        UI/HUDView
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     The overdrive timer bar empties instantly and then sits wrong for the rest of a manual or Head Start boost.
- Why:         The chip always passes `duration: Tuning.boostDuration` (1.0 s), but a manual deploy is 3.0 s (`speedUpDeployDuration`) and Head Start is 4.5 s (`headStartBoostDuration`). `HUDView.swift:179-181`.
- Impact:      The HUD lies about a consumable the player paid for. Decree 5 and decree 6.
- Fix sketch:  Carry the actual duration alongside `boostRemaining` (either in the snapshot or as a model-side value) and pass it through.
- Blast radius: `Core/Models.swift` (if the snapshot gains a field), `Core/GameCore.swift`, `UI/HUDView.swift`.
- Verification: Trigger all three boost sources and assert the bar's full-scale matches.

## PR-0043 · SEV2 · VoiceOver and keyboard slider changes in Settings are never persisted
- Area:        UI/SettingsView
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     A VoiceOver user changes a volume slider, leaves Settings, and the change is gone.
- Why:         The profile write happens only in `onEditingChanged` (`if !editing { commit(...) }`, `SettingsView.swift:104-107`). SwiftUI fires that for drag begin/end; an accessibility increment mutates the value without it.
- Impact:      Accessibility regression that silently discards user intent.
- Fix sketch:  Commit on value change (debounced), not on editing-ended.
- Blast radius: `UI/SettingsView.swift`.
- Verification: VoiceOver adjust, leave, return — the value persisted. VERIFY-PENDING (device or simulator VO).

## PR-0044 · SEV2 · No way to unmute from the hub
- Area:        UI/GameView, UI/SettingsView
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     A player who muted during a run cannot find how to unmute without starting another run.
- Why:         `GameView.swift:1068` hides the mute/pause cluster whenever `mode == .menu`, and `SettingsView` exposes three volume sliders but no master-mute toggle — even though `model.toggleMute()` / `profile.muted` exist and persist (`GameView.swift:603-607`).
- Impact:      Decree 4 (everything leads somewhere) and a real dead end for a common action.
- Fix sketch:  Add a master mute toggle to Settings, bound to the existing persisted flag.
- Blast radius: `UI/SettingsView.swift`.
- Verification: Mute in a run, quit to hub, unmute from Settings, confirm it persists.

## PR-0045 · SEV2 · Unaffordable Mystery Box "OPEN" gives no reason and no route to coins
- Area:        UI/MysteryBoxView
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     The button is dimmed and dead with no explanation and no way to get coins.
- Why:         `afford` only drives `.opacity(0.5)` and `.disabled(!afford)` (`MysteryBoxView.swift:58, 94-97`). Every comparable surface does better — `ShopView.packRow` appends a "not enough" line and routes to coins.
- Impact:      Decree 3 and decree 4.
- Fix sketch:  Mirror the `ShopView` pattern: shortfall text plus a GET COINS route.
- Blast radius: `UI/MysteryBoxView.swift`.
- Verification: Zero-coin state shows the shortfall and the route.

## PR-0046 · SEV2 · "Sign in to secure your account across devices" overpromises
- Area:        UI/ProfileView
- Found by:    S-001 (survey: ui-meta)
- Status:      OPEN
- Symptom:     The copy implies signing in protects the save. It does not — iCloud already syncs the save, and Sign in with Apple only stores a user id in the Keychain.
- Why:         `ProfileView.swift:130` vs `AccountService.swift:3-5` ("no server").
- Impact:      Decree 5 (honest monetization / honest promises) and a support burden when a player loses a save they believed was "secured".
- Fix sketch:  Rewrite the copy to say what sign-in actually does. If the answer is "very little", consider whether the affordance earns its place at all.
- Blast radius: `UI/ProfileView.swift`.
- Verification: The copy matches the behaviour, checked against `AccountService`.

## PR-0047 · SEV2 · Deploy buttons create swipe dead zones in both bottom thumb corners
- Area:        UI/GameView
- Found by:    S-001 (survey: ui-game)
- Status:      OPEN
- Symptom:     Lane swipes started low in the screen — where thumbs naturally rest — are swallowed by the deploy buttons.
- Why:         Three 64 pt circular buttons plus labels at `.padding(.bottom, 44)` / `.horizontal, 18` sit over the gesture surface. `GameView.swift:959-985, 1178-1186`.
- Impact:      Missed inputs at speed read as the game ignoring the player.
- Fix sketch:  Shrink the interactive area to the glyph, raise the cluster, or route unhandled touches through to the gesture layer.
- Blast radius: `UI/GameView.swift`.
- Verification: Swipe from the bottom corners and confirm the lane change registers. VERIFY-PENDING (device).

## PR-0048 · SEV2 · Buying a skin force-equips it, including on a redelivered transaction
- Area:        IAP/IAPCatalog
- Found by:    S-001 (survey: meta-iap)
- Status:      OPEN
- Symptom:     The player's chosen character is silently swapped out — potentially long after the purchase, on a `Transaction.updates` redelivery.
- Why:         `IAPCatalog.swift:58` sets `$0.selectedSkin = s` on grant; dedupe is per transaction id, so a family-shared or ask-to-buy-approved Aurora's first delivery swaps the selection.
- Impact:      Violates owner decree 1's spirit (the player's character is their pick) and is startling.
- Fix sketch:  Equip on an explicit purchase the player just made; never on a redelivery. Or never auto-equip and show a "wear it now?" affordance.
- Blast radius: `IAP/IAPCatalog.swift`.
- Verification: Redeliver a transaction and assert `selectedSkin` is unchanged.

## PR-0049 · SEV2 · CI never runs the XCUITests, and the "best-effort" unit-test step is not best-effort
- Area:        .github/workflows/ios-build.yml
- Found by:    S-001 (survey: tests-tools)
- Status:      OPEN
- Symptom:     A red CI run for a reason the comment says should not fail the build; and the 11 XCUITests only ever run when a human runs `ci.sh`.
- Why:         `ios-build.yml:64` passes `-only-testing:PrismRushTests`, excluding `PrismRushUITests` (they are compiled at `:51` but never executed). The step at `:58-65` is described as best-effort in the comment at `:56-57` but has no `continue-on-error`.
- Impact:      The interaction layer — the part Linux cannot type-check at all — has zero automated gate.
- Fix sketch:  Either make the step genuinely best-effort, or make it required and add the UI target. Pick one and make the comment match.
- Blast radius: `.github/workflows/ios-build.yml`.
- Verification: A CI run that executes the UI tests, or a comment that matches the behaviour.

## PR-0050 · SEV2 · Two `Tools/` scripts hardcode this machine's simulator UDIDs
- Area:        Tools/qa.sh, Tools/screenshots.sh
- Found by:    S-001 (survey: tests-tools)
- Status:      OPEN
- Symptom:     On any other machine, or after an Xcode reinstall, `simctl boot` fails silently (`|| true`) and the script proceeds against nothing.
- Why:         `Tools/qa.sh:7` and `Tools/screenshots.sh:22` embed `10C15FE0-…` and `52DF5467-…`.
- Impact:      A QA script that reports success while testing nothing is worse than no script.
- Fix sketch:  Resolve the simulator by name/OS with the existing `PR_SIM_NAME` / `PR_SIM_OS` override convention, and fail loudly when it cannot.
- Blast radius: `Tools/qa.sh`, `Tools/screenshots.sh`.
- Verification: Run with a bogus `PR_SIM_NAME` and confirm a loud failure.

## PR-0051 · SEV2 · `Tools/screenshots.sh` cannot produce the screenshots it claims to
- Area:        Tools/screenshots.sh
- Found by:    S-001 (survey: tests-tools)
- Status:      OPEN
- Symptom:     Six named states (`02_world1` … `06_gameover`) require gameplay; the script just sleeps and shoots (`:103-115`). Its own header (`:10-13`) still says "until the game is playable (Phase 8)".
- Impact:      Store screenshots are a submission requirement and this is the tool that is supposed to make them. Also breaks the global README rule requiring live workflow screenshots.
- Fix sketch:  Drive the app with the existing `PR_*` launch hooks and the autoplay mode to reach each state deterministically, then shoot.
- Blast radius: `Tools/screenshots.sh`.
- Verification: The six files are produced and each shows the named state.

## PR-0052 · SEV2 · The claimed daily-challenge fairness guarantee needs a decision, not just a fix
- Area:        Core, product
- Found by:    S-001 (S-001 synthesis of PR-0020 + PR-0021)
- Status:      OPEN
- Symptom:     "Everyone plays the same track each day" is advertised (`Store/metadata.md:64`) but is conditional on identical power-up usage (PR-0020) and on gem placement not being silently truncated (PR-0021).
- Impact:      Advertised-bonus honesty (decree 5) and leaderboard integrity.
- Fix sketch:  Decide the product answer first — is the daily a *layout* guarantee or an *identical-experience* guarantee? Then fix to match, and reword the listing.
- Verification: The listing text and the code agree, with the reasoning in `04_DECISIONS.md`.
- Blocked by:  PR-0020, PR-0021

---

# SEV3 — code health, tests, architecture, docs

Compact format (see the note at the top). Expand to the full block before working one.

## Documentation is stale in load-bearing places

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0060 | README's headline claim that the synthwave bed "thickens" per world is false in the shipped build | `README.md:26-28, 276` | Reword, or fix via PR-0040 |
| PR-0061 | `CLAUDE.md` says "12 spawn patterns"; `Patterns.count` is 14 | `CLAUDE.md`, `Core/Patterns.swift:27` | Correct the number |
| PR-0062 | `CLAUDE.md` test counts are wrong by ~101 (says 95 total / 89 SPM; real is 178 SPM, 196 total) | `CLAUDE.md` build block | Correct, and point at `08_TESTING.md` instead of duplicating |
| PR-0063 | `CLAUDE.md` says Linux compiles "4 Meta files"; `Package.swift` lists 7 | `CLAUDE.md`, `Package.swift:14-24` | Correct |
| PR-0064 | `Tools/ci.sh` banner claims 174 tests; real is 196 | `Tools/ci.sh:9-10` | Correct or delete the count |
| PR-0065 | `README.md:255` links to `CODE_REVIEW.md`, which has never existed in git history | `README.md:255` | Remove the link or restore the file |
| PR-0066 | `state.md` says "5 IAP products" in two places; `Store/metadata.md` says 7 | `state.md:468, 637` vs `Store/metadata.md:95` | Resolve against `Products.storekit` and fix all three |
| PR-0067 | Every `reports/shots/…` evidence link in README and state.md is dead for anyone who clones (`.gitignore:20` excludes the PNGs) | `README.md`, `state.md`, `.gitignore:20` | Either commit the evidence shots or stop citing them as proof |
| PR-0068 | `docs/SHIP_CHECKLIST.md:8-9` still describes the build as "the v1.2 overhaul" | `docs/SHIP_CHECKLIST.md:8-9` | Update to v1.6 |
| PR-0069 | `reports/design/V15_WORLDS_design.md:226-228` still specifies the rejected near-white World 12, with no supersession banner | that file | Add a supersession banner (do not delete history) |
| PR-0070 | `reports/design/V15_PLAN.md:12-15` locks in "honest passive perks" for higher-rarity characters, which the owner later rejected | that file | Add a supersession banner citing the decision |
| PR-0071 | `DESIGN_progression.md:133-139` lists unlock levels 3/6/10/15/22; shipped is `[3, 6, 8, 12, 18, 25]` (three conflicts total) | that file | Annotate like its sibling `DESIGN_characters.md` was |
| PR-0072 | `DESIGN_characters.md:161` prices Fang at 900; `V13_SPEC` R4 overrode it to 2,500 and the catalog ships 2,500 | that file | Annotate |
| PR-0073 | `DESIGN_uiux.md:142-143, 400-403` carry two decisions CUT by `V13_SPEC` R11, with no strike-through | that file | Annotate |
| PR-0074 | `Tuning.swift:38-42` comment says "×1.25 ≈ ×1.56 apex"; the constant is 1.3 (×1.69 apex) | `Core/Tuning.swift:38-42` | Correct the comment |
| PR-0075 | `state.md:189` repeats the same stale ×1.25 figure | `state.md:189` | Correct |
| PR-0076 | `ProfileStore.swift:384` comment states the opposite of what the code does (rollback "re-rolls the board"; code keeps it) | that line | Correct the comment; the code is the safer behaviour |
| PR-0077 | Two shipped launch hooks (`PR_DEEPWORLDS`, `PR_FIRSTRUN`) appear in no doc | `PrismRush/`, README, state.md | Document in `09_GLOSSARY.md` and README |
| PR-0078 | `RNG.swift:3-4` and `GameCore.swift:20-21` assert "a seed fully determines a run", which PR-0020 shows is conditional | those lines | Correct once PR-0020 is resolved |

## Core simulation

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0090 | The guaranteed power-up cadence is player-dependent: `freeLaneNear` reads `activeObstacles`, which shield absorbs mutate, shifting every later cadence pickup's kind | `GameCore.swift:320-334, 410-411` | Decide whether the cadence must be identical across players; if so, compute from the seeded set |
| PR-0091 | `activateHeadStart` has no "already boosting" guard, unlike its three siblings | `GameCore.swift:234-240` | Add the guard for symmetry |
| PR-0092 | `DailyChallenge.swift:24` — unguarded `UInt64(year*10000 + month*100 + day)` traps on negative input; `layoutVersion << 48` silently discards bits above 16 | that line | Guard the conversion; Core should never trap on external data |
| PR-0093 | Flow-fountain gems are placed with no obstacle awareness — they can sit inside a tall wall | `GameCore.swift:456-460` | Route through `freeLaneNear` like the cadence pickups do |
| PR-0094 | `.menu` mode integrates `distance` forever (7 m/s while idling); precision degrades in the cosmetic `sin` at large magnitudes | `GameCore.swift:273-284` | Clamp or wrap the menu distance |
| PR-0095 | `[weak self]` on a synchronous non-escaping closure adds retain/release per spawn command | `GameCore.swift:301-304` | Drop the weak capture |
| PR-0096 | `Spawner.maxIndex` and `gap` are recomputed inside the fill loop although `dist` cannot change within a call | `Spawner.swift:38, 48` | Hoist; also removes the misleading implication that the tier can change mid-fill |
| PR-0097 | `Patterns.run`'s `default:` arm returns 14 for an out-of-range index instead of trapping — a future off-by-one becomes silent empty track | `Patterns.swift:74-190` | `preconditionFailure` in debug |
| PR-0098 | `die()` neither breaks nor returns inside a manual index loop using `swapAt` removal — correct today, the most fragile construct in the file | `GameCore.swift:413-416` | Restructure for clarity, no behaviour change |
| PR-0099 | `jumpBuf` is left at a small negative residue rather than clamped to 0 (reads as a bug at a glance; is not one) | `GameCore.swift:352` | Clamp to 0 |

## Renderer

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0110 | The particle colour cache is defeated by the default prismatic skin, thrashing a 64-entry cache every ~2 s | `ParticleSystem.swift:122-128`, `RealityRenderer.swift:587-595` | Key the cache on a quantised hue, or exempt the shimmer |
| PR-0111 | `Date()` is read every frame although the result is floored to 30 Hz | `RealityRenderer.swift:587` | Use the existing `elapsed` accumulator |
| PR-0112 | `reduceMotionObserver` is stored but never removed; the class has no `deinit` | `RealityRenderer.swift:181-187, 114-115` | Add `deinit` removing the token |
| PR-0113 | `restyleMetropolis` indexes `eligible`/`eligibleFar` with no non-empty guard; safe only because of fixed build-time skyline geometry | `WorldDecor.swift:447-451, 479-480` | Guard; SEV0 if the geometry ever changes |
| PR-0114 | All 28 decor slot groups get a transform write every frame even when every child is disabled (9 of 12 worlds) | `WorldDecor.swift:93, 105-109` | Skip the write for fully-disabled slots |
| PR-0115 | The 36 grid rungs are individually repositioned every frame | `RealityRenderer.swift:363-364` | Parent to one scroll node |
| PR-0116 | The legendary aura ring's colour is frozen at rig-build time and never repainted, so a prismatic aura skin would break decree 2 | `RealityRenderer.swift:981, 731-741, 594` | Repaint the aura in `applyCharacterColors`; latent today |
| PR-0117 | `TempestSky.wrap(_:span:)` is dead code (private unused statics do not warn) | `TempestSky.swift:279-283` | Delete |
| PR-0118 | Every sky drives `sin` phases from `Float(elapsed)`, which never wraps — slow animations coarsen after hours | `RealityRenderer.swift:577` and each `*Sky.swift` | Wrap at 2π as `runPhase`/`auraSpin` already do |
| PR-0119 | `fire(.jumped)` arms a 0.12 s timer that immediately loses one frame, frame-rate dependently | `RealityRenderer.swift:320-323, 613` | Same family as PR-0024 |
| PR-0120 | `ParticleSystem.step` scans all 560 slots every frame even with zero live particles | `ParticleSystem.swift:81` | Track a live high-water mark |
| PR-0121 | The palette cache key packs three values into one `Int` with fixed decades and no bounds check | `RealityRenderer.swift:204` | Use a struct key; the first term is also redundant |

## UI

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0130 | `PauseOverlay`'s whole session-summary block is permanently dead — `snapshot` defaults to nil and `GameView` never passes it | `PauseOverlay.swift:10, 24-40`, `GameView.swift:1189` | Wire it or delete it (decree 4) |
| PR-0131 | `timeSurvived` is accumulated every frame, plumbed to `GameOverView`, and never displayed | `GameView.swift:267, 1120`, `GameOverView.swift:27` | Show it or remove the plumbing |
| PR-0132 | `@State private var model = GameModel()` allocates a throwaway `GameModel` on every `GameView` struct init | `GameView.swift:915` | Construct lazily or hoist ownership |
| PR-0133 | The autoplay bootstrap bypasses `beginRun`, skipping watermark and stats initialisation | `GameView.swift:212-217` | Route autoplay through `beginRun` |
| PR-0134 | `rewards:` is still an `AnyView`, the exact shape that severed `@Observable` tracking and shipped a "Head Start does nothing" bug | `GameView.swift:1105`, cf. `MenuView.swift:20-23` | Make it a concrete generic like `loadout` was |
| PR-0135 | `restartCountdown` can only ever be 1, so the panel reads "READY IN 1…" for the whole delay | `GameView.swift:286-289`, `GameOverView.swift:472-475` | Fix the arithmetic or drop the countdown |
| PR-0136 | `uiClock` advances during pause but `ageEffects` does not run, so effects jump on resume | `GameView.swift:259, 262-265, 802-816` | Freeze `uiClock` with the sim |
| PR-0137 | Declaration order and `zIndex` disagree across eight overlay layers | `GameView.swift:1146-1214` | Make `zIndex` explicit and consistent |
| PR-0138 | The `charges == 0` presentation in `deployButton` is unreachable — the caller only renders when `charges > 0` | `GameView.swift:989-1019, 967-979` | Delete the dead branch |
| PR-0139 | Root-level implicit `.animation(…)` modifiers on the outermost view | `GameView.swift:1218-1219` | Scope to the animating subview |
| PR-0140 | The tutorial-hint scan is O(entities) every frame while active (up to 72 gems plus obstacles, three predicates) | `GameView.swift:344-353` | Cache per-frame or drive from FX events |
| PR-0141 | Gem gold is a hardcoded `Color(red: 1, green: 0.82, blue: 0.24)` literal in two files instead of `Theme.Role.reward` | `HUDView.swift:129-132`, `PauseOverlay.swift:29` | Use the token |
| PR-0142 | `PauseOverlay` re-declares `Theme.actionGradient` inline and uses `.plain` instead of the project-wide `.neon` button style | `PauseOverlay.swift:47-49, 51, 62` | Use the shared style |
| PR-0143 | `GameOverView` (476 lines) and `HUDView` use zero Dynamic Type — every string is a fixed `.system(size:)` | both files | Adopt the existing `typeScale` system |
| PR-0144 | Three entire meta screens bypass Dynamic Type: Settings, MysteryBox, PowerUps | those files | Adopt `typeScale` |
| PR-0145 | Hardcoded 8–11 pt fonts in character/level select ignore Dynamic Type | `CharacterSelectView.swift:162, 428-434, 570-576, 529-534, 582`, `LevelSelectView.swift:223` | Adopt `typeScale` |
| PR-0146 | Rail-cell text can shrink to ~5 pt on a 320–375 pt screen | `RewardsBar.swift:111-114` | Raise the minimum scale factor or shorten the copy |
| PR-0147 | The meta-screen header has no overflow protection between a 40 pt back button and a variable coin badge | `MetaScreenScaffold.swift:29-38` | Add `lineLimit` + `minimumScaleFactor` |
| PR-0148 | How-to-Play cards can clip vertically — fixed `VStack`, 48 pt of padding, no `ScrollView` | `HowToPlayView.swift:233-248, 213` | Wrap in a `ScrollView` |
| PR-0149 | The hero stage forces a 140 pt floor inside a flexible slot, which can overflow small screens | `MenuView.swift:144-147` | Let it shrink |
| PR-0150 | The BEST/FIRST RUN chip is ~25 pt tall with no 44 pt minimum, unlike every sibling on the hub | `MenuView.swift:228-247` | Add `.frame(minHeight: 44)` |
| PR-0151 | The Mystery Box idle-phase escape is an unpadded `Button("CLOSE")` with a ~13×45 pt hit area, and the scrim tap is gated to `.revealed` | `MysteryBoxView.swift:99-101, 26` | Pad the button and ungate the scrim |
| PR-0152 | Several other tap targets across the meta layer fall below 44 pt | see `ui-meta.md` §Suspicious #25 for the measured list | Add minimum heights |
| PR-0153 | Meta sheets are not marked `.isModal` for VoiceOver, so `GameOverView` stays reachable behind them | `GameView.swift:1145-1147`, `MetaScreenScaffold.swift:16` | Add the trait |
| PR-0154 | Settings and PowerUps omit `onCoins` on the coin badge, unlike every other scaffolded screen | `SettingsView.swift:33`, `PowerUpsView.swift:70` | Pass `onCoins` |
| PR-0155 | The WORLDS profile tile shows `maxWorldReached + 1` while the menu chip and Worlds header use a different expression | `ProfileView.swift:223, 211`, `MenuView.swift:53`, `LevelSelectView.swift:23` | Pick one and share it |
| PR-0156 | `let p = ProfileStore.shared.profile` at the top of a computed property is the literal shape CLAUDE.md rule 5 forbids (works today by accident) | `ProfileView.swift:211` | Reference the store directly in `body` |
| PR-0157 | `ShimmerPulse` and the Mystery Box use `.repeatForever`, which the hub explicitly banned | `ShopView.swift:804-818`, `MysteryBoxView.swift:64` | Bound the animation; both already guard Reduce Motion |
| PR-0158 | "REACH IT · Nm" is styled as an actionable key but only dismisses the panel | `LevelSelectView.swift:528-541` | Restyle as informational (decree 4) |
| PR-0159 | The Settings restore Task is unstructured and uncancelled across a 2.4 s sleep | `SettingsView.swift:173-188` | Use `.task` so it cancels with the view |
| PR-0160 | `auroraID` is used to price every premium skin — correct only because Aurora is the sole `.iap` skin today | `ShopView.swift:597, 627, 682` | Look up the skin's own product id |
| PR-0161 | The rotation-hero `default` branch trusts `featuredPool` blindly; an unknown id silently renders free Prism as a premium hero | `ShopView.swift:206-220`, `SkinCatalog.swift:267` | Validate the pool against the catalog at startup |

## Meta, economy, and IAP

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0170 | The whole profile is written to iCloud KVS with an explicit `synchronize()` on *every* mutation — several per death | `ProfileStore.swift:620-627` | Coalesce and debounce |
| PR-0171 | `"pr.profile.v1"` is a literal in two places; changing one would silently wipe every save | `ProfileStore.swift:14, 36` | One constant |
| PR-0172 | `applyRunSummary`'s per-run mission loop has no `v > 0` guard, writing permanent zero entries on the first run | `ProfileStore.swift:455-459` cf. `:476-484` | Guard like `bump` does |
| PR-0173 | `challengeDaysPlayed` is trimmed to 60 on write but the merge unions without re-trimming (up to 120 entries) | `ProfileStore.swift:601-605, 677` | Re-trim after merge |
| PR-0174 | Daily *bonus* rolls over at local midnight while daily *missions* and the daily *challenge* roll over at UTC — 13 hours apart at UTC+13 | `ProfileStore.swift:302, 307-309` vs `:353` | Pick one calendar |
| PR-0175 | `grantedTransactionIDs` is trimmed to 512 *after* a union merge, dropping the other device's older markers | `Profile.swift:100-103`, `ProfileStore.swift:664-665` | Trim per-device before merging, or raise the bound |
| PR-0176 | `MissionCatalog.Metric.revives` is structurally unsatisfiable — `RunSummary.revives` is captured at the first death, where `revivesUsed` is 0 | `MissionCatalog.swift:51`, `GameView.swift:757` | Fix the capture point or remove the metric |
| PR-0177 | `unlockWorld` performs two separate saves; a crash between them debits coins without granting the world | `ProfileStore.swift:274-280` cf. `:122-129` | Single atomic mutate |
| PR-0178 | `pendingProductIDs.remove(id)` uses the requested id while the listener uses `transaction.productID` | `IAPManager.swift:158-160` vs `:209` | Use `transaction.productID` in both |
| PR-0179 | `save()` swallows an encode failure via `try?` | `ProfileStore.swift:621` | Log and surface |

## Audio and services

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0190 | `Synth.noise(swell:)` is a dead parameter — the render loop unconditionally applies decay, so four SFX get a decay where a swell was intended | `Synth.swift:37, 49-50` | Implement or remove the parameter |
| PR-0191 | The `layer >= 3` sub-octave swell is truncated to 57% of its length and cut mid-decay | `Synth.swift:339-341` | Fit the request to `stepFrames` |
| PR-0192 | `Music.pump` schedules into a dead player without checking `engine.isRunning` | `Music.swift:79-86, 90-92` | Guard and recover |
| PR-0193 | Three notification observer tokens are never removed; no `deinit` | `SynthEngine.swift:24` | Add `deinit` |
| PR-0194 | `GameCenterService.authenticated` never becomes true if the user signs in mid-session, although GameKit re-invokes the handler | `GameCenterService.swift:17-26`, `GameView.swift:145` | Update state on every handler invocation |
| PR-0195 | Keychain write failures are silently swallowed, leaving an in-memory sign-in with nothing persisted | `AccountService.swift:73-78` | Check the `Bool` and surface the failure |
| PR-0196 | Keychain queries omit `kSecAttrService`, so the service attribute defaults to empty | `Keychain.swift:14-17, 33-37, 49-51` | Set an explicit service |
| PR-0197 | `Haptics.tick` prepares six Taptic generators every 6 s during play even when haptics are disabled | `Haptics.swift:28-33` cf. `:36` | Check `enabled` in `tick` |
| PR-0198 | Every pickup kind gets the same `.success` haptic, while the audio branches across five kinds | `Haptics.swift:45-46` vs `GameView.swift:533-545` | Differentiate |

## Tests and tooling

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0210 | `Tools/gen_icon.swift` deletes the catalog entry before it copies — an interrupted run leaves no app icon | `Tools/gen_icon.swift:299-306` | Write to a temp path and move |
| PR-0211 | `testPlayerBoundsSlidingClearsLow` asserts the *opposite* of its name (the inline comment confirms the assertion is right) | `CollisionTests.swift:14-19` | Rename the test |
| PR-0212 | `GameplayTests.swift:216` guards and returns before its assertion, so the test can pass vacuously | that line | Fail instead of returning |
| PR-0213 | `testBotCollectsChronoDuringProceduralRuns` accumulates across ten seeds and asserts once outside the loop — nine seeds could spawn nothing | `PowerUpTests.swift:98-114` | Assert per seed |
| PR-0214 | `ArcCollectionTests.swift:27` indexes `cmds[0]` unchecked — traps instead of failing | that line | Guard with an explicit failure |
| PR-0215 | `RingTests.swift:63` has an unbounded `while` with no tick and no iteration cap | that line | Bound it; a hang burns a full CI runner slot |
| PR-0216 | `FlowTests.swift:123` compares a determinism field with `accuracy: 0.6` while the surrounding test proves exactness | that line | Compare exactly |
| PR-0217 | `CharacterParityTests` is wrapped in `#if canImport(UIKit)` and therefore silently compiles to nothing under `swift test` on every platform SPM runs on | `CharacterParityTests.swift:4` | Make the exclusion visible, or run it where it can run |
| PR-0218 | `Package.swift` names Meta/Audio files individually, so a new pure file is silently invisible to Linux CI | `Package.swift:14-24` | Use directory entries where possible, or add a check |
| PR-0219 | No CI job runs a linter, a formatter, or a coverage gate, despite `gatherCoverageData: true` and an 80% rule | both workflows | Add them |
| PR-0220 | Neither workflow sets `timeout-minutes`, so a hung test burns a full 6-hour runner slot | both workflows | Add timeouts |
| PR-0221 | `Tools/render_sfx.swift` renders 9 SFX and 3 music bars; `SynthTests` covers ~28 SFX cases and 24 music worlds | `Tools/render_sfx.swift:30-48` | Bring the audit tool up to date |
| PR-0222 | `ci.sh` and `build.sh` write `-derivedDataPath .dd` inside an iCloud-synced repo; device/archive builds must not | both scripts | Use a path outside the synced tree for signed builds |
| PR-0223 | The suite is 100% XCTest with zero `import Testing`, against the global rule preferring Swift Testing for new tests | `Tests/` | Decide and record in `04_DECISIONS.md`; do not migrate on a whim |

---

## Parking lot (SEV4)

| ID | Item |
|---|---|
| PR-0240 | Reconsider whether `state.md` (58k) and `README.md` (35k) should be split now that `docs/agent/` carries the operational memory |
| PR-0241 | Consider extracting `GameView.swift` (1,224 lines) — it exceeds the 800-line ceiling in the global coding rules and owns the model, input, lifecycle, and eight overlays |
| PR-0242 | Same for `RealityRenderer.swift` (1,106 lines) and `WorldDecor.swift` (848 lines) |

---

# Findings from the cross-cutting traces (PR-0250+)

Filed from `docs/agent/scratch/trace-findings.md`, which extracted defects the per-area surveys
did not see because they only appear when you follow the run lifecycle or the isolation topology
end to end. Same confidence caveat as everything above.

## PR-0250 · SEV1 · A decode failure silently wipes the entire profile
- Area:        Meta/ProfileStore
- Found by:    S-001 (trace: concurrency)
- Status:      OPEN
- Symptom:     Every existing player launches into a brand-new profile — no coins, no skins, no stats — with no error, no backup, and no diagnostic.
- Repro:       Any decode throw: a future release changing a field's type (`coins: Int` → `Double`), or a truncated KVS blob.
- Why:         `try? JSONDecoder().decode(Profile.self, from: data)` at `ProfileStore.swift:631, 701, 704`; both loaders fall through to `return Profile()` (`:634, :707`). Iron rule 7's `decodeIfPresent` armour covers *missing* keys, not *type-changed* keys or a truncated blob.
- Impact:      Not triggerable with today's schema. Catastrophic and undiagnosable if ever triggered — and the fix has to be in place *before* the release that would trigger it, not after.
- Fix sketch:  Catch the error rather than discarding it: keep the raw bytes in a quarantine key, log, and surface a recoverable state. Never silently substitute a fresh profile.
- Blast radius: `Meta/ProfileStore.swift`.
- Verification: Test feeding a truncated and a type-mismatched blob; assert the old bytes are preserved and the failure is observable.

## PR-0251 · SEV0 (conditional, UNPROVEN) · `MainActor.assumeIsolated` wraps GameKit's auth handler with no documented main-thread guarantee
- Area:        Services/GameCenterService
- Found by:    S-001 (trace: concurrency)
- Status:      OPEN
- Symptom:     If GameKit ever delivers `authenticateHandler` off the main thread, the app hard-traps at launch — unlaunchable, not merely racy.
- Why:         `GameCenterService.swift:17-25`. `authenticateHandler` is a plain non-isolated closure property; nothing in the API contract guarantees main-thread delivery. GameKit historically does, and the XCUITests never trip it. Contrast `AccountService.swift:41-43`, which correctly hops via `Task { @MainActor }`.
- Impact:      A launch-blocking trap gated on undocumented framework behaviour. The severity is conditional and the condition is unproven — this is exactly the kind of claim AUDIT-006 must resolve rather than accept.
- Fix sketch:  De-risk by switching to a `Task { @MainActor }` hop, matching the pattern `AccountService` already uses. This is not "silencing an isolation error" (which `01_RULES.md` §4 forbids) — it is replacing an assertion with an actual hop.
- Blast radius: `Services/GameCenterService.swift`.
- Verification: AUDIT-006 to establish whether the assumption holds. Either way the hop is safe.

## PR-0252 · SEV1 · Two devices plus airplane mode resurrect spent coins while keeping the purchase
- Area:        Meta/ProfileStore
- Found by:    S-001 (trace: concurrency)
- Status:      OPEN
- Symptom:     Free, repeatable acquisition of every coin-priced item. No hex editing, no jailbreak.
- Repro:       1. 8,000 coins on both devices. 2. On A, buy the 8,000-coin world (coins → 0, world owned, saved). 3. B, still holding 8,000 and unsynced, pushes its snapshot. 4. A merges: `coins = max(0, 8000) = 8000`, and `purchasedWorlds` is a union, so A keeps the world.
- Why:         `ProfileStore.swift:662-663` max-merges the balance while `:668-671` unions the entitlements. Spending is not represented anywhere the merge can see.
- Impact:      The entire coin ladder (up to 59,400 coins of worlds, plus every coin-priced skin) is free to anyone with two devices. Difficulty: trivial.
- Fix sketch:  Same root cause as PR-0002 — the balance must be derived from grow-only earned/purchased/spent counters, not merged as a max. Fix both together.
- Blast radius: `Meta/ProfileStore.swift`, `Meta/Profile.swift`.
- Verification: Two-profile merge test reproducing the exact sequence above; assert coins end at 0.
- Blocked by:  none — but land it together with PR-0002 and PR-0253.

## PR-0253 · SEV1 · Daily-login and free-chest rewards are farmable across two devices
- Area:        Meta/ProfileStore
- Found by:    S-001 (trace: concurrency)
- Status:      OPEN
- Symptom:     Unlimited re-claims of the daily bonus (up to 1,000 coins on day 7) and the 30-minute chest (60–220 coins), by alternating devices.
- Repro:       1. Claim the daily bonus on the iPhone. 2. Open the iPad, whose `lastDailyClaim` is older or nil. 3. Claim again. 4. Merge takes `max(coins)` — both land.
- Why:         `lastDailyClaim` and `lastChestOpen` are among the fields `merged()` silently keeps from `local` (`var merged = local`, `ProfileStore.swift:658`), while `claimDailyReward` (`:320-326`) and `openFreeChest` (`:339-348`) gate only on the local timestamp.
- Impact:      Directly undercuts the clock-rollback hardening the rest of the file is careful about (`:70-79`). Difficulty: trivial.
- Fix sketch:  Merge both timestamps with `max`, and merge the claim ledgers rather than dropping them.
- Blast radius: `Meta/ProfileStore.swift`.
- Verification: A merge test asserting both timestamps survive as the later of the two.

## PR-0254 · SEV2 · Revived runs are fully leaderboard-eligible, so continues are purchasable rank
- Area:        UI/GameView, Services/GameCenterService, product
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     A player buys two continues (150 + 300 = 450 coins) and submits the stitched score to `prismrush.best`.
- Why:         `submitRun` (`GameView.swift:791`) skips only on `usedCheckpoint`, and `core.revive()` (`GameCore.swift:607-630`) never sets it. Challenge runs are protected (`canRevive`, `GameView.swift:456`); the global board is not.
- Impact:      Pay-to-win on the one competitive surface. Note **iron rule 10 names only checkpoints**, so today's behaviour is what the rule specifies — this needs a product decision from Rayan, not a unilateral code fix.
- Fix sketch:  Decide: (a) leave as designed and say so publicly, (b) mark revived runs ineligible, or (c) submit the pre-first-death score. Whichever is chosen, amend iron rule 10 in `CLAUDE.md` to state it explicitly.
- Blast radius: `UI/GameView.swift`, `Core/GameCore.swift`, `CLAUDE.md`.
- Verification: Owner decision recorded in `04_DECISIONS.md`, then the code and the rule agree.

## PR-0255 · SEV2 · All post-revive progress is dropped from XP, missions, and per-world bests
- Area:        UI/GameView
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     A player spends coins on a continue, runs another 800 m, and receives zero XP, zero mission progress, and no per-world best credit for it.
- Why:         The `statsRecorded` branch (`GameView.swift:726-736`) pays coins and maxes lifetime stats but never calls `applyRunSummary` for the revived tail.
- Impact:      Owner decree 5 — an advertised bonus is not delivered. Also the root cause of PR-0176: `summary.revives` is structurally always 0 (`:757`), so the shipped `revives` mission metric can never progress.
- Fix sketch:  Apply the run summary once at the true end of the run rather than at the first death, or apply a delta for each revived segment.
- Blast radius: `UI/GameView.swift`, `Meta/ProfileStore.swift`.
- Verification: Revive once, run a known distance, assert XP and mission counters include the tail.

## PR-0256 · SEV2 · Audio starts at full volume before the saved mute setting is read
- Area:        UI/GameView, Audio/SynthEngine
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     A player who muted last session hears the hub bed fade in on every cold launch.
- Why:         `synth.start()` (`GameView.swift:142`) sets `outputVolume = masterTarget` while `muted` still defaults to `false` (`SynthEngine.swift:27, 88`), and `musicStart(calm:)` begins at `:143`. `synth.muted = saved.muted` only lands at `:200` and then ramps in over ~0.15 s/unit.
- Impact:      Ignores an explicit user setting, every single launch. Compounds PR-0037.
- Fix sketch:  Move the `let saved = ProfileStore.shared.profile` read above `synth.start()`.
- Blast radius: `UI/GameView.swift`.
- Verification: Mute, force-quit, relaunch — silence. VERIFY-PENDING (device).

## PR-0257 · SEV2 · Launch catch-up character unlocks celebrate underneath the splash and are lost forever
- Area:        UI/GameView, UI/EffectsOverlay
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     The chime and haptic fire, but the "NEW CHARACTER" headline never appears — and it never replays.
- Repro:       Take longer than ~1 s to tap past the splash on a launch where a catch-up unlock is granted.
- Why:         `install` calls `checkSkinUnlocks()` at `GameView.swift:210`; grants queue milestones (`:621-628`) released one per second by `ageEffects` into `EffectsOverlay`, which renders *below* `SplashView` at `.zIndex(10)` (`:1214`). `ownedSkins` insertion is the dedupe (`ProfileStore.swift:224-231`), so it cannot replay.
- Impact:      The reward moment for an unlock — the meta layer's main payoff — is silently destroyed on the most common path.
- Fix sketch:  Hold the milestone queue until the splash dismisses, or raise the overlay above it.
- Blast radius: `UI/GameView.swift`.
- Verification: Grant a catch-up unlock via a launch hook, wait out the splash, confirm the headline shows.

## PR-0258 · SEV2 · The death frame performs 4–7 synchronous profile encodes plus iCloud syncs
- Area:        UI/GameView, Meta/ProfileStore
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     A frame hitch at the exact moment the death animation should be at its most impactful.
- Why:         `GameView.swift:680-792` calls several `ProfileStore` mutators, and every `mutate` runs a full encode plus a `UserDefaults` write plus `cloud.synchronize()` (`ProfileStore.swift:620-627`).
- Impact:      Same moment as PR-0030 and the same root cause as PR-0170; fix all three together.
- Fix sketch:  Batch the whole run-summary write into one `mutate`, and debounce the iCloud sync.
- Blast radius: `UI/GameView.swift`, `Meta/ProfileStore.swift`.
- Verification: Count encodes across one death (a debug counter); assert exactly one.

## PR-0259 · SEV2 · RUN AGAIN after a checkpoint run always restarts at world 0
- Area:        UI/GameView
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     The player silently loses the world they reached — or paid up to 13,400 coins to unlock — with no "restart here" affordance.
- Why:         `GameView.swift:1116` — `onRestart: { model.startRun() }` uses the default `fromWorld: 0`.
- Impact:      Sibling of PR-0011. Probably intentional (checkpoint runs are not leaderboard-eligible), but it reads as a lost setting rather than a rule.
- Fix sketch:  Offer both, or restart where they were and label it. Fix alongside PR-0011 so restart semantics are decided once.
- Blast radius: `UI/GameView.swift`, `UI/GameOverView.swift`.
- Verification: Checkpoint run → die → RUN AGAIN → assert the starting world.
- Blocked by:  PR-0011 (same decision)

## PR-0260 · SEV2 · The whole SwiftUI tree re-evaluates at display refresh rate, including on the idle menu
- Area:        Core/GameCore, UI/GameView
- Found by:    S-001 (trace: run-lifecycle)
- Status:      OPEN
- Symptom:     Battery drain and heat while the app sits on the hub doing nothing.
- Why:         `advance` calls `rebuildSnapshot()` unconditionally (`GameCore.swift:168`), the snapshot is the one observed property, and `GameView.swift:280` drives `advance` every frame in every mode.
- Impact:      Up to 120 full view-tree evaluations per second for a static screen.
- Fix sketch:  Skip the rebuild when no tick ran and nothing changed, or drive the menu at a lower cadence.
- Blast radius: `Core/GameCore.swift`, `UI/GameView.swift`.
- Verification: Instruments on the idle hub. VERIFY-PENDING (device).

## Trace SEV3s

| ID | Item | Where | Fix |
|---|---|---|---|
| PR-0270 | Constructing a throwaway `GameModel` also builds a throwaway `RealityRenderer` and `SynthEngine`, each leaking an unremovable notification observer. SEV3 today; SEV1 the moment `RootView` gains any state | `GameView.swift:915` | Same fix as PR-0132; note the leak makes it worse than it looks |
| PR-0271 | Game Center scores finished before auth resolves are dropped, and every submission failure is invisible | `GameCenterService.swift:38, 40, 50` | Queue until authenticated; surface failures |
| PR-0272 | `core.best` is read from the profile once at launch and never re-synced after an iCloud merge | `GameView.swift:208` | Re-read on merge |
| PR-0273 | `returnToMenu()` does not clear `isChallengeRun` | `GameView.swift:495-504` | Clear it; feeds PR-0011 |
| PR-0274 | `resetEntities()` leaves `paletteKey`, `elapsed`, `blinkT`, `auraSpin`, `shimmerStep`, `skidCursor` untouched | `RealityRenderer.swift:669-694` | Reset all visual state together |
| PR-0275 | The revive rule is encoded as three unnamed magic numbers in three places | `GameView.swift:1114, 456, 1126` | One named constant |
| PR-0276 | The death frame's full `dt` is credited to `playTimeThisRun` before the tick that kills the player | `GameView.swift:267` vs `:280` | Credit only the elapsed portion |
| PR-0277 | `Core/` calls `.random(in: .min ... .max)` for the default seed — permissible (the seed is the boundary) but it is the only nondeterminism in the layer and deserves an explicit comment | `GameCore.swift:81, 139` | Document, or require an explicit seed and move the default to the caller |
| PR-0278 | Two notification observers discard their registration token, making removal impossible | `ProfileStore.swift:38`, `IAPManager.swift:57` | Retain the tokens |
| PR-0279 | The iCloud KVS payload has unbounded growth vectors and no size check against the 1 MB limit | `Profile.swift:37`, `ProfileStore.swift:249-251` | Bound the growable sets and check the encoded size before writing |
| PR-0280 | A `GameCenterService` instance method writes to the singleton instead of `self` | `GameCenterService.swift:22` | Write to `self` |
| PR-0281 | Settings slider `@State` is seeded from the profile in `init` and can commit stale values back over an iCloud merge | `SettingsView.swift:22-28` | Bind to the store rather than snapshotting |
| PR-0282 | A hand-set negative `coins` persists — `sanitized(_:now:)` has no range or negative clamp — and makes every price unaffordable | `ProfileStore.swift:70-79` | Clamp on load |
| PR-0283 | Fabricated `coinsPurchasedByDevice` slots make `merged()` *credit* the difference on every device, so a forged balance is re-granted on each sync | `ProfileStore.swift:659-663` | Falls out of the PR-0002 / PR-0252 rework; verify explicitly |
| PR-0284 | Clearing `grantedTransactionIDs` re-arms the IAP replay dedupe, so a StoreKit redelivery re-pays real grants; `firstPurchaseBonusUsed = false` re-arms the one-time +50% bonus | `ProfileStore.swift:161-168` | Derive replay protection from a source the save cannot forge |
| PR-0285 | Eight `PR_*` launch env hooks that mutate the real profile and grant power-ups ship in the release binary | `GameView.swift:146-253` | Gate behind `#if DEBUG` or a signed build check; difficulty to exploit is hard, but the cost of gating is near zero |

---

# Findings from actually running the build (PR-0290+)

Filed by **session 001 addendum**, after the owner pointed out that no agent had launched the app.
Everything above this line is static reading. Everything below was seen on a running build:
`./Tools/build.sh` → BUILD OK → installed and launched on iPhone 17 Pro / iOS 26.5
(`10C15FE0-3D9A-40D5-9E45-C0702E906DF3`), driven with the repo's own `PR_AUTOPLAY` and `PR_SCREEN`
launch hooks. Evidence screenshots were captured to the session scratchpad (transient — regenerate
with the commands in `08_TESTING.md`).

**These are the only findings in this file that are visually confirmed.** They took about fifteen
minutes and one of them is a money bug that ten agents reading `IAPCatalog.swift` did not flag.

## PR-0290 · SEV1 · The shop displays hardcoded US dollar prices when StoreKit has not loaded
- Area:        IAP/IAPCatalog, IAP/IAPManager, UI/ShopView
- Found by:    S-001 addendum (observed on a running build)
- Status:      OPEN
- Symptom:     A player outside the US sees `$0.99 / $1.99 / $2.99 / $4.99 / $9.99 / $19.99` on live, tappable buy buttons, and is then charged in their own currency at their own storefront price. The displayed price is not the price.
- Repro:       1. Launch the app without the StoreKit configuration attached (a bare `simctl launch`, or any real launch where the product load is slow, offline, or fails). 2. Open the Shop. 3. Observe fully-priced, fully-tappable cards. **Screenshot captured — this is what the shop renders today.**
- Why:         `IAPManager.displayPrice(_:)` is `storeProduct(id)?.displayPrice ?? (IAPCatalog.product(id)?.fallbackPrice ?? "")` (`IAPManager.swift:127-128`), and every `fallbackPrice` in `IAPCatalog.swift:28-35` is a hardcoded USD string. The comment says "shown if StoreKit hasn't loaded real pricing yet" — the problem is that the buy button is live at the same time.
- Impact:      Money. A non-US player is shown a price they will not be charged. This is Guideline 2.3.1 / 3.1 pricing-accuracy exposure, and it violates owner decree 5 (honest monetization) directly. It is also the exact case `state.md` believed was covered by a "Store unavailable" fallback — that fallback did not appear.
- Fix sketch:  Never render a price string that did not come from StoreKit. Show a skeleton or a neutral "…" while loading, and disable purchase until `availability == .ready`. Keep `fallbackValue` for internal value-badge math if it is genuinely needed, but never surface `fallbackPrice` to the player.
- Blast radius: `IAP/IAPManager.swift`, `IAP/IAPCatalog.swift`, `UI/ShopView.swift`.
- Verification: Launch with no StoreKit config; assert no `$` string appears and no buy button is enabled. Then launch with the config and assert real prices appear.
- Note:         Interacts with PR-0032 (a purchase can fail with no feedback in `.notConfigured`) and PR-0160 (`auroraID` prices every premium skin). Fix the three together — they are one "what does the shop show when the store is not ready" question.

## PR-0291 · SEV2 · Score popups stack into an illegible smear
- Area:        UI/EffectsOverlay, UI/GameView
- Found by:    S-001 addendum (observed on a running build, two independent frames)
- Status:      OPEN
- Symptom:     Four or more `+50` popups render on top of each other in the same place, producing an unreadable cyan blur instead of feedback.
- Repro:       Run with `SIMCTL_CHILD_PR_AUTOPLAY=1`; observed at 189 m and again at 660 m, so it is systematic rather than a one-off collision.
- Why:         Not yet diagnosed — popups appear to spawn at the collected gem's position with no stagger, jitter, or coalescing, and gems arrive in tight arcs and trails by design (a gem arc is 7 gems, a coin trail more).
- Impact:      The reward feedback for the single most frequent action in the game is unreadable exactly when the player is doing well. Decree 6 (clarity beats spectacle). This is a direct hit on the "one more run" feel loop that AUDIT-002 will care about.
- Fix sketch:  Coalesce simultaneous popups into one `+N` total, or stagger their spawn position and lifetime. Coalescing is probably better — it also reads as a bigger reward.
- Blast radius: `UI/EffectsOverlay.swift`, `UI/GameView.swift` (the FX sink).
- Verification: Autoplay through a gem arc and a coin trail; every popup legible.

## PR-0292 · SEV2 · A near-field tall obstacle swallows the SHIELD deploy button
- Area:        UI/GameView, Render/Reality/RealityRenderer
- Found by:    S-001 addendum (observed on a running build at 660 m)
- Status:      OPEN
- Symptom:     When a tall wall passes on the right at close range, its bright cyan face fills the bottom-right of the screen and the SHIELD button's glyph, label and charge badge wash out to near-invisible against it.
- Repro:       `SIMCTL_CHILD_PR_AUTOPLAY=1`, wait for a tall wall in the right lane at close range. **Screenshot captured.**
- Why:         The deploy buttons are flat translucent SwiftUI overlays with no scrim or contrast floor against whatever the renderer draws behind them.
- Impact:      A control the player paid for becomes unreadable at exactly the moment they most need it — a wall in their lane is when you reach for Shield. Decree 6.
- Fix sketch:  Give the deploy buttons an opaque or strongly-scrimmed backing, or a contrast-adaptive stroke. Cheap.
- Blast radius: `UI/GameView.swift` (`deployButton`).
- Verification: Same repro; the button stays legible against a full-brightness obstacle.
- Note:         Compounds PR-0047 (the same buttons create swipe dead zones in both bottom thumb corners). Same three controls, two independent problems — fix together.

## PR-0293 · SEV2 · The Mystery Box discloses no odds
- Area:        UI/MysteryBoxView, UI/ShopView
- Found by:    S-001 addendum (observed on a running build)
- Status:      OPEN
- Symptom:     The card reads "Coins, slow-mo, or a loadout boost — 1,200-coin jackpot!" for 300 coins, with no probability for any outcome.
- Why:         No odds are rendered anywhere on the card or in the reveal.
- Impact:      **Resolves charter assumption A4 and open question 5: the Mystery Box is a 300-coin purchase, not real money.** That means Guideline 3.1.1's loot-box odds requirement does not bite. But the charter's own non-negotiable says "**any** randomized purchase must disclose odds", which is deliberately stricter than Apple. By the project's own standard this is a gap.
- Fix sketch:  Print the outcome table on the card, or in a tappable "odds" affordance next to it. The distribution already exists in code; surface it.
- Blast radius: `UI/MysteryBoxView.swift`, `UI/ShopView.swift`.
- Verification: Odds visible before the player spends, matching the code's actual distribution.

## PR-0294 · SEV3 · The `.storekit` fallback path is not what `state.md` believes it is
- Area:        docs, IAP
- Found by:    S-001 addendum
- Status:      OPEN
- Symptom:     `state.md` records that under a bare `simctl` launch the shop shows a correct "Store unavailable" fallback, and cites it as verified v1.2 behaviour. On a running v1.6 build it shows fully-priced tappable cards instead.
- Impact:      A documented "verified" behaviour is no longer true, and the doc is what a future session would trust instead of re-checking. Either the behaviour regressed since v1.2 or the original observation was of a different state.
- Fix sketch:  Correct `state.md` once PR-0290 lands, and record the real fallback behaviour.
- Verification: Re-run the bare-launch shop capture and describe what is actually on screen.

## PR-0295 · SEV2 · A gesture in flight when you die carries through into the game-over panel
- Area:        UI/GameView, UI/GameOverView
- Found by:    S-001 addendum (reproduced with real touch input on a running build)
- Status:      OPEN
- Symptom:     You die mid-swipe and are instantly yanked onto the Profile screen without ever seeing the death panel. It reads as the game randomly navigating away from you.
- Repro:       1. Start a run. 2. Perform a swipe whose path ends near the vertical middle of the screen. 3. If the swipe kills you, `GameOverView` appears *under the still-moving finger* and the lift-off registers on whatever is beneath it. **Observed: a path ending at tap-space y=504 landed on "FULL STATS ›" at y≈493 and opened Profile.**
- Why:         `GameOverView` is inserted into the ZStack the moment `mode` becomes `.over`, while a `DragGesture` is still active. The `.onEnded` that fires afterwards is delivered to the newly-present panel.
- Impact:      The player never sees their score, their coins, or the CONTINUE offer — the entire monetised end-of-run moment is skipped by an input they did not make. Note the panel already gates **RUN AGAIN** behind a "READY IN 1…" countdown (`GameOverView.swift:472-475`) precisely to stop accidental restarts, so the hazard is already understood — **FULL STATS, CONTINUE and BACK TO MENU are simply not covered by it.**
- Fix sketch:  Extend the existing countdown gate to the whole panel, not just RUN AGAIN — ignore any touch whose gesture began before the panel appeared. Tracking the gesture's start timestamp against the panel's presentation time is enough.
- Blast radius: `UI/GameView.swift` (gesture layer), `UI/GameOverView.swift`.
- Verification: XCUITest: begin a drag, force a death mid-drag, release over each panel control, assert no navigation occurred.
- Note:         Strengthens PR-0135 (the countdown can only ever read "1") — the countdown is load-bearing for more than it currently covers.

## PR-0296 · SEV3 · The attract track scrolls visibly through the hub's translucent cards — owner call
- Area:        UI/MenuView, Render
- Found by:    S-001 addendum (observed on a running build, three launches)
- Status:      OPEN
- Symptom:     The menu-mode track's bright magenta grid lines read straight through the DAILY RUSH / REWARDS / MISSIONS and CHARACTERS / SHOP / WORLDS cards, and a horizontal line sweeps across the three nav labels as the track scrolls.
- Why:         The hub cards are translucent and sit over the live attract-mode RealityKit scene. The PLAY button is opaque and correctly occludes the track; the lower cards are not.
- Impact:      **This may be the intended neon aesthetic — it is a judgment call, not a provable defect, and it needs Rayan's eye rather than an agent's.** Recorded because a line sweeping across a nav label repeatedly does hurt legibility, which decree 6 cares about. Do not "fix" it without an answer.
- Fix sketch:  If unintended: raise the card fill opacity or add a scrim behind the bottom two rows. If intended: note it here as accepted so no future session re-files it.
- Verification: Owner decision recorded in `04_DECISIONS.md`.

---

# Findings from AUDIT-001, The Completeness Auditor (session 002)

Filed by session 002. Method: 10-agent hostile fan-out, **two independent adversarial verifiers per
dimension**, plus the auditor's own hands on a running build. Every item below survived at least one
verifier whose explicit job was to refute it. `[RUNTIME]` = observed on a running build.

**Read `docs/agent/audits/AUDIT_002_completeness.md` §5 before working any session-001 item** — that
section re-scores PR-0290, refutes PR-0293 and PR-0161, and demotes PR-0130 and PR-0176. Session 001
items were not renumbered, merged, or deleted.

## PR-0300 · SEV1 · Cold launch adopts the cloud profile wholesale and discards the local one
- Area:        Meta/ProfileStore
- Found by:    AUDIT-001 (session 002), finder `silent-failure`, both verifiers
- Status:      OPEN
- Symptom:     A player plays offline on device A, then launches on device B (or relaunches after a KVS push). The offline session's coins, XP and unlocks are gone.
- Repro:       Needs two devices or airplane mode — see AUDIT_002 §6. Static: find the cold-launch profile load and confirm it assigns the cloud value rather than calling `merged()`.
- Why:         `ProfileStore` has a `merged()` function that exists to prevent exactly this, and the cold-launch path does not call it. Verifier verdict: "SURVIVES (SEV1, borders SEV0)."
- Impact:      Silent, unrecoverable progress loss. Money-adjacent: purchased coins can be destroyed.
- Fix sketch:  Route the cold-launch path through the same `merged()` the sync path uses. Do not special-case first load.
- Blast radius: `Meta/ProfileStore.swift`.
- Verification: Two-device test, plus a unit test that asserts cold launch with both a local and a cloud profile keeps the union.
- Note:         **Overlaps session 001's PR-0005. Session 009 should merge these.** Filed separately because the mechanism — merge not called *on that specific path* — is more precise than PR-0005 records.

## PR-0301 · SEV1 · No Privacy Policy URL exists anywhere, and neither ship doc asks for one
- Area:        Store/, docs/, project.yml
- Found by:    AUDIT-001 (session 002), finder `docs-vs-code`, both verifiers
- Status:      OPEN
- Symptom:     The app ships Sign in with Apple, Game Center and iCloud KVS with no privacy policy to point App Store Connect at.
- Repro:       Static: grep the repo. Absent from `project.yml`, `Store/metadata.md`, `docs/SHIP_CHECKLIST.md`, `docs/APP_STORE_SETUP.md`.
- Why:         Never written. The ship docs do not list it as a gate, so the omission is invisible to the checklist.
- Impact:      A submission cannot be completed without it.
- Fix sketch:  Write the policy, host it, add the URL to `Store/metadata.md` and add a HUMAN GATE row to `SHIP_CHECKLIST.md`.
- Verification: AUDIT-003 (session 004) scores it against the live guidelines.
- Note:         Compliance is AUDIT-003's remit; filed here because a **missing artifact** is squarely the completeness mandate. Interacts with PR-0009.

## PR-0302 · SEV2 · [RUNTIME] The Mystery Box OPEN button is inert when unaffordable, and the app already has the right pattern
- Area:        UI/MysteryBoxView, UI/ShopView
- Found by:    AUDIT-001 (session 002), observed on a running build
- Status:      OPEN
- Symptom:     With 100 coins, `OPEN · 300` renders as a full-saturation cyan→magenta CTA. Tapping it does nothing at all — no shortfall copy, no route to coins, no shake, no toast, no disabled styling.
- Repro:       1. `SIMCTL_CHILD_PR_SCREEN=shop SIMCTL_CHILD_PR_SKIP_SPLASH=1 xcrun simctl launch <UDID> com.rayancheca.prismrush` with fewer than 300 coins. 2. Scroll to POWER-UP PACKS, tap Mystery Box. 3. Tap `OPEN · 300`. **Observed: no change whatsoever, balance unmoved.**
- Why:         The unaffordable branch has no handler at all, unlike its siblings.
- Impact:      A dead primary CTA on a monetised surface. Decrees 3 and 4.
- Fix sketch:  Reuse the existing pattern verbatim — `UnlockPanel` shows `NEED 400 MORE` + a `GET COINS` button; `GameOverView`'s revive shows `NEED 46 MORE  150` on a dimmed pill. Both are already written.
- Blast radius: `UI/MysteryBoxView.swift`.
- Verification: Launch with < 300 coins, tap OPEN, assert a shortfall message and a route to coins.
- Note:         One workflow finder described this button as "dimmed". It is not — at 100 coins it is at full saturation. The screenshot is authoritative.

## PR-0303 · SEV2 · [RUNTIME] The Mystery Box overlay has no backdrop scrim, making the odds table the least legible thing on screen
- Area:        UI/MysteryBoxView
- Found by:    AUDIT-001 (session 002), observed on a running build
- Status:      OPEN
- Symptom:     The odds panel and the OPEN/CLOSE controls are drawn directly over fully-legible Shop content. `BALANCED PICK`, `7,000`, `$4.99`, `FIRST PURCHASE +50%` (×2), `+32% BONUS`, `BEST VALUE`, `16,000` and `40,000` all read straight through the odds rows and buttons.
- Repro:       Shop → Mystery Box. **Verified settled, not mid-animation: two consecutive screenshots are identical.**
- Why:         No dimming layer behind the overlay.
- Impact:      The one surface that exists to satisfy the charter's "any randomized purchase must disclose odds" non-negotiable is the hardest thing on screen to read. Decree 6.
- Fix sketch:  Add the scrim the other modal overlays use. Separately, give `CLOSE` real button chrome — it is currently bare text, unlike every other control in the app.
- Blast radius: `UI/MysteryBoxView.swift`.
- Verification: Screenshot the overlay; no Shop text may be legible behind the odds panel.

## PR-0304 · SEV2 · [RUNTIME] The Missions board says "ALL CLEAR" on first launch, when every mission is 0/N
- Area:        UI/MissionsView
- Found by:    AUDIT-001 (session 002), observed on a running build
- Status:      OPEN
- Symptom:     `ALL CLEAR · NEW BOARD IN 3:32` sits above seven rows reading `0/150`, `0/15`, `0/10`, `0/1.0k`, `0/75`, `0/30`, `0/5`.
- Repro:       Fresh install → `SIMCTL_CHILD_PR_SCREEN=missions`. **Screenshot captured.**
- Why:         The summary strip's state is derived from "nothing claimable" rather than "nothing in progress", and those coincide on an empty board.
- Impact:      The first thing a new player reads on this screen tells them they have finished it. Decree 3 — first launch is the most important state this surface has.
- Fix sketch:  Distinguish the two states: `6 MISSIONS AVAILABLE` when nothing is complete, `ALL CLEAR` only when every mission is genuinely done.
- Blast radius: `UI/MissionsView.swift`.
- Verification: Fresh profile, open Missions, assert the strip does not read ALL CLEAR.
- Note:         Same screen shows `RESETS 3:32` (no unit) beside `RESETS 3D` — two formats, one screen. Fix together.

## PR-0305 · SEV2 · [RUNTIME] Mute cannot be undone from the hub or Settings, and it survives relaunch
- Area:        UI/GameView, UI/SettingsView
- Found by:    AUDIT-001 (session 002), finder `dead-affordances`, verifier SURVIVES (SEV2)
- Status:      OPEN
- Symptom:     A player who mutes mid-run, quits to the menu and relaunches has a permanently silent game with no visible way to fix it.
- Repro:       Start a run, tap the corner speaker, quit to menu, force-quit, relaunch. Audio stays off; Settings offers no mute control.
- Why:         `toggleMute()` (`GameView.swift:603`) has exactly one caller — `GameView.swift:1072`, the in-run/game-over corner control. It persists to the profile (`:606`) and is restored at launch (`:200-201`). `SettingsView` has three volume sliders and no mute.
- Impact:      The player must guess that starting a run reveals the only unmute. Decree 4.
- Fix sketch:  Add a mute row to Settings bound to the same profile field.
- Blast radius: `UI/SettingsView.swift`.
- Verification: Mute in-run, relaunch, unmute from Settings.

## PR-0306 · SEV2 · [RUNTIME] Pre-approval store: seven hardcoded USD prices at full opacity, every one inert
- Area:        IAP/IAPCatalog, IAP/IAPManager, UI/ShopView
- Found by:    AUDIT-001 (session 002), observed on a running build
- Status:      OPEN
- Symptom:     With `availability == .notConfigured` the Shop shows `$2.99`, `$1.99`, `$0.99`, `$4.99`, `$9.99`, `$19.99` and Aurora `$1.99` at full opacity. **Tapping `$0.99` produces nothing — no toast, no sheet, no error, no state change.** The only disclosure is a grey `PRICES SHOWN · APP STORE SETUP PENDING` footnote roughly six screens below the first price.
- Repro:       Bare `simctl launch` (no StoreKit config) → `PR_SCREEN=shop`. **Screenshots captured of both the prices and the no-op tap.**
- Why:         `.loading` shimmers the price pills (`ShopView.swift:705`, `:722`) and `.offline` renders a first-viewport RETRY card (`:72-99`). `.notConfigured` has neither mitigation, and its tap handler has no branch.
- Impact:      Decrees 3 and 4. Every price-shaped control on the app's monetised surface is dead, silently, in exactly the state a pre-approval build sits in.
- Fix sketch:  Give `.notConfigured` the same treatment as `.offline` — a first-viewport card — and never render a `$` string that did not come from StoreKit.
- Blast radius: `UI/ShopView.swift`, `IAP/IAPManager.swift`.
- Verification: Launch with no StoreKit config; assert no `$` string appears above the disclosure.
- Note:         **This RE-SCORES PR-0290 from SEV1 to SEV2 and refutes its "money bug" framing** — nothing is charged because nothing happens. See AUDIT_002 §5. Do not work PR-0290 and this item separately.

## PR-0307 · SEV2 · Post-revive play is invisible to missions, achievements and XP, but still moves the Profile stats
- Area:        UI/GameView (`recordRunResults`), Meta/MissionCatalog
- Found by:    AUDIT-001 (session 002), finder `catalog-missions`; **both verifiers independently PROMOTED it SEV3 → SEV2**
- Status:      OPEN
- Symptom:     A player pays 150 coins to CONTINUE. Everything after the revive counts toward their lifetime stats and toward no mission, no achievement and no XP.
- Why:         The run summary is captured at the first death; the post-revive continuation is not folded back in.
- Impact:      Decree 5 — the advertised benefit of a paid continue is not fully delivered. This is the most expensive single action in the game.
- Fix sketch:  Fold the post-revive segment into the same summary before `applyRunSummary`. Iron rule 9 applies: payouts stay per-death deltas, `applyRunSummary` once per run.
- Blast radius: `UI/GameView.swift:680-792`.
- Verification: Revive, collect gems, die; assert the daily gem mission advanced by the full run total.
- Note:         Related to PR-0176 — both are "the run summary is captured too early".

## PR-0308 · SEV2 · Restore Purchases reports success when nothing was restored
- Area:        IAP/IAPManager, UI/SettingsView
- Found by:    AUDIT-001 (session 002) — found independently by **three** of the ten finders
- Status:      OPEN
- Symptom:     A player who has never purchased anything taps Restore Purchases and is told "Purchases restored." The failure path separately leaks a raw error string into a different screen.
- Why:         The success message is unconditional on completion rather than conditional on a non-empty restore set.
- Impact:      Decree 3. A player debugging a missing purchase is actively misled.
- Fix sketch:  Report the count. "Nothing to restore" is an honest, intentional-looking outcome.
- Blast radius: `IAP/IAPManager.swift`, `UI/SettingsView.swift`.
- Verification: Restore with no purchases; assert the message says nothing was restored.

## PR-0309 · SEV2 · Sign in with Apple completes and changes nothing observable
- Area:        Services/AccountService, UI/ProfileView
- Found by:    AUDIT-001 (session 002), finders `dead-affordances` + `unreachable-code`, both verifiers SURVIVES
- Status:      OPEN
- Symptom:     The card promises to "secure your account across devices". The flow completes. No signed-in state differs from signed-out; nothing reads the resulting identity.
- Impact:      Decree 4, and the largest gap between what a feature claims and what it does. Also drags in PR-0301 and PR-0008 (an account that can be created must be deletable).
- Fix sketch:  Either wire the identity to the cloud save key, or remove the card until it does something. Removing is legitimate and cheaper.
- Blast radius: `Services/AccountService.swift`, `UI/ProfileView.swift`.
- Verification: Sign in; assert an observable state change.

## PR-0310 · SEV2 · The daily Game Center leaderboard is advertised in four documents and has no in-app viewer
- Area:        Services/GameCenterService, UI
- Found by:    AUDIT-001 (session 002), finder `docs-vs-code`
- Status:      OPEN
- Symptom:     `prismrush.daily` is submitted to and never displayed. The player has no way to see the board they are competing on.
- Fix sketch:  Add a daily board entry point on the Daily Rush surface, or stop advertising it.
- Blast radius: `Services/GameCenterService.swift`, `UI/RewardsBar.swift`.
- Verification: Open the daily board from inside the app.

## PR-0311 · SEV2 · [RUNTIME] The Game Center row on Profile is a dead card that tells the player to quit the app
- Area:        UI/ProfileView
- Found by:    AUDIT-001 (session 002), observed on a running build + finder `empty-error-states`
- Status:      OPEN
- Symptom:     `Leaderboards need Game Center` / `Sign in from the Settings app, then relaunch.` — no tap target, no in-app sign-in, and the copy asks the player to leave the app and come back.
- Repro:       Fresh install, `PR_SCREEN=stats`, not signed in to Game Center. **Screenshot captured.**
- Impact:      Decree 4. This is the signed-out state's only Game Center surface, and it leads nowhere.
- Fix sketch:  Present `GKLocalPlayer`'s own auth view controller from a tappable row.
- Blast radius: `UI/ProfileView.swift`, `Services/GameCenterService.swift`.
- Verification: Tap the row while signed out; assert the Game Center sign-in sheet appears.

## PR-0312 · SEV2 · Every character swatch crops the top off the character
- Area:        UI/CharacterSwatch, UI/CharacterSelectView, UI/ShopView
- Found by:    AUDIT-001 (session 002), finder `catalog-skins`
- Status:      OPEN
- Symptom:     18 of 20 crests and every antenna tip are cut off in the grid, shop and next-unlock swatches. The legendary aura ring is structurally wider than its own canvas and is clipped on **every** surface, including the menu hero and the splash.
- Why:         The preview canvas's drawing bounds do not account for the crest/antenna/aura extents above the body.
- Impact:      **Decree 2 — previews never lie.** The rarest visual tell in the game (the legendary aura) is the one the player never sees intact.
- Fix sketch:  Compute the silhouette's true bounding box in `CharacterProportions` and inset the canvas by it.
- Blast radius: `UI/CharacterSwatch.swift`, `Render/Reality/ProceduralMesh.swift`.
- Verification: Render all 24 at swatch size; assert no non-background pixel touches the top edge.
- Note:         `CharacterParityTests.swift` is `#if canImport(UIKit)`-gated and does **not** run under `swift test`, which is why this survived.

## PR-0313 · SEV2 · Fourteen `PR_*` launch hooks compile into the Release binary with zero `#if DEBUG` gating
- Area:        UI/GameView, App/
- Found by:    AUDIT-001 (session 002), finder `silent-failure`; **gating verified independently by the auditor**
- Status:      OPEN
- Symptom:     Every state/cheat hook (`PR_AUTOPLAY`, `PR_SCREEN`, `PR_DEMOPROFILE`, `PR_DEEPWORLDS`, `PR_SHIELD`, …) is live in a release build. One of them destructively rewrites the saved profile.
- Repro:       `grep -rn "#if DEBUG" PrismRush --include='*.swift'` → **0 results across 95 files**, against 17 `ProcessInfo` reads of `PR_*`.
- Impact:      Debug affordances shipping in the release path. Exploitability is AUDIT-007's to price — a player cannot easily set env vars on a shipped iOS app — but the destructive profile hook makes the downside asymmetric.
- Fix sketch:  Wrap every hook read in `#if DEBUG`. Keep them: they are how every future session reaches states. Just do not ship them.
- Blast radius: `UI/GameView.swift`, `App/RootView.swift`.
- Verification: Release build; assert every `PR_*` read is compiled out.

## PR-0314 · SEV2 · Audio-engine start failure is permanent — every recovery path is gated behind the flag the failure clears
- Area:        Audio/SynthEngine
- Found by:    AUDIT-001 (session 002), finder `silent-failure`, verifier SURVIVES (SEV2, down from SEV1)
- Status:      OPEN
- Symptom:     One failed `AVAudioEngine` start and the app is silent for the rest of its life. No retry fires, and the player is told nothing.
- Why:         The failure clears the same `running` flag that every recovery path checks before attempting a restart.
- Impact:      A silent game reads as broken. Decree 3.
- Fix sketch:  Track "failed" separately from "not running" so interruption recovery can still fire.
- Blast radius: `Audio/SynthEngine.swift`.
- Verification: Force a start failure, then trigger an interruption; assert audio recovers.

## PR-0315 · SEV2 · Game Center scores are silently discarded for the whole session when auth fails at launch
- Area:        Services/GameCenterService
- Found by:    AUDIT-001 (session 002), finder `silent-failure`
- Status:      OPEN
- Symptom:     A player who launches without connectivity loses every score that session. No retry, no queue, no message.
- Fix sketch:  Queue submissions and retry on auth success; persist the queue across launches.
- Blast radius: `Services/GameCenterService.swift`.
- Verification: Launch offline, set a best, reconnect; assert the score submits.

## PR-0316 · SEV2 · Five products simultaneously advertise the single first-purchase bonus
- Area:        UI/ShopView
- Found by:    AUDIT-001 (session 002), observed on a running build
- Status:      OPEN
- Symptom:     All four coin packs carry `FIRST PURCHASE +50%` and the Starter Bundle carries `FIRST PURCHASE OFFER`. Exactly one can ever be true; the badge reads as a per-pack property.
- Repro:       Open the Shop on a profile with no purchases. **Screenshot captured.**
- Impact:      Decree 5 — honest in mechanism, misleading as presented.
- Fix sketch:  State it once, as an account-level banner: "Your first purchase gets +50%."
- Blast radius: `UI/ShopView.swift`.
- Verification: Assert the bonus is asserted once per screen, not five times.

## PR-0317 · SEV2 · Two icon systems for the same five power-ups
- Area:        UI/ShopView, UI/PackRewardBurst, UI/LoadoutStrip vs UI/PowerUpGlyph
- Found by:    AUDIT-001 (session 002), finder `half-migrated`
- Status:      OPEN
- Symptom:     The shop, the reward burst and the hub draw SF Symbols; the in-run surfaces draw the procedural `PowerUpGlyph`. The same power-up is a different picture depending on where the player meets it.
- Impact:      Decree 2, and it defeats the purpose of having an identity glyph at all.
- Fix sketch:  Route the three stragglers through `PowerUpGlyph`. The component already exists.
- Blast radius: `UI/ShopView.swift`, `UI/PackRewardBurst.swift`, `UI/LoadoutStrip.swift`.
- Verification: Grep for SF Symbol names in those three files; expect none for power-ups.

## PR-0318 · SEV2 · Achievement-gated characters need a CLAIM tap the requirement copy never mentions
- Area:        UI/CharacterSelectView, Meta/SkinUnlocks
- Found by:    AUDIT-001 (session 002), finders `catalog-skins` + `catalog-missions`
- Status:      OPEN
- Symptom:     The progress bar reaches 100% and the character stays locked, with nothing on screen explaining that a mission tier must be claimed first.
- Impact:      A player who has genuinely earned the unlock believes the game is broken. Decree 3.
- Fix sketch:  Either auto-claim on completion, or say "Claim the mission to unlock" on the locked card.
- Blast radius: `UI/CharacterSelectView.swift`, `Meta/SkinUnlocks.swift`.
- Verification: Complete an achievement-gated requirement without claiming; assert the card explains what remains.

## SEV3 — compact rows (per this file's format note)

| ID | Sev | Finding | Cite |
|---|---|---|---|
| PR-0319 | SEV3 | `startRun` folds the checkpoint world by `% 3` (pre-v1.5 modulus) while `stepWorld` uses `Tuning.worldFamilyCount` = 12. **[RUNTIME] Latent, not player-visible** — picked world 4, correctly got Orbital Drift, because the renderer derives the world from distance and never reads the field `startRun` corrupts. Fires the day anyone re-wires `GameCore.world`. | `Core/GameCore.swift:110` vs `:290` |
| PR-0320 | SEV3 | `Synth.noise(swell:)` is never read — four "rising whoosh" SFX decay instead of swelling, and the test guarding it passes vacuously. | `Audio/Synth.swift` |
| PR-0321 | SEV3 | `Profile.ownedProducts` is written by all four IAP grant paths, persisted, decoded and cloud-merged — and read by nothing. | `Meta/Profile.swift:116` |
| PR-0322 | SEV3 | [RUNTIME] Profile stacks `LEVEL 1` and a `LVL 3 · PEBBLE` chip in one card with no "NEXT" label; the Characters screen labels the identical fact correctly as `NEXT UNLOCK`. | `UI/ProfileView.swift` |
| PR-0323 | SEV3 | The meta header's coin badge is a Shop link on four screens and inert on two — same pixels, different behaviour. | `UI/MetaScreenScaffold.swift` |

## Re-scores and refutations from session 002 (do not re-file these)

| Existing item | Session 002 verdict |
|---|---|
| PR-0290 | **RE-SCORED SEV1 → SEV2**; "money bug" framing refuted (tapping a buy button does nothing). Superseded in substance by PR-0306. |
| PR-0293 | **REFUTED — recommend `WONTFIX`.** Odds *are* disclosed before spending and sum to 100%. Only the legibility problem survives, as PR-0303. |
| PR-0130 | Dead code **CONFIRMED**; consequence **REFUTED** → SEV3. The HUD stays visible behind the pause veil, so the player can see their distance. |
| PR-0176 | **SURVIVES, demoted to SEV4.** Value is pinned to 0, but no mission uses the metric, so nothing is broken for a player. |
| PR-0161 | **Partially REFUTED.** `featuredPool` is a 4-element constant of known ids, so the `default:` branch cannot fire today. Latent only. |
| PR-0131, PR-0138, PR-0158, PR-0160 | **CONFIRMED.** PR-0158 confirmed at runtime and escalated — the panel has no labelled exit at all. |
| PR-0296 | **CONFIRMED and quantified** (band sweeps y = 0.667 → 0.799 over 10 s, full width). Still an owner call. Do not fix without Rayan. |
