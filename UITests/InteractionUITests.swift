import XCTest

/// Real interaction tests — they drive the actual UI (tap buttons, assert state transitions). This
/// is the coverage gap that let the reported bugs ship: screenshots proved rendering, not behavior.
/// v1.3: updated for the Hero/Verb/Rail/Nav menu (settings gear lives in Profile, rewards live in
/// the 3-cell rail, characters are stage-and-shelf) + two new flows (locked requirement, XP bar).
final class InteractionUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        // Boot straight to the hub: the launch splash covers the menu until tapped, which would
        // hide every element these tests assert on.
        app.launchEnvironment["PR_SKIP_SPLASH"] = "1"
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    /// Element lookup by identifier across ALL element types: the rewards-rail cells wrap their
    /// Button in `.accessibilityElement(children: .ignore)` before the identifier lands, so they
    /// surface as plain elements, not `.button`s (the stage/nav buttons do surface as buttons).
    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Wait until an element's accessibility label contains `fragment` (rail cells re-label as
    /// their claim state advances — labels are the deterministic wait condition, not timers).
    private func waitForLabel(_ app: XCUIApplication, id: String, contains fragment: String,
                              timeout: TimeInterval = 6) -> Bool {
        let query = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", id, fragment))
        return query.firstMatch.waitForExistence(timeout: timeout)
    }

    /// A1 — dying must offer a way back to the menu, and it must actually return there.
    func testBackToMenuFromGameOver() {
        let app = launch(["PR_DEMO": "1"])   // autoplay, then force-die ~6s
        let back = app.buttons["backToMenuButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 25), "BACK TO MENU should appear on game over")
        back.tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 6),
                      "the menu PLAY button should appear after BACK TO MENU")
    }

    /// A3 — equipping a skin must reflect as equipped immediately (no close/reopen).
    /// v1.3 stage-and-shelf (R7): tapping a card focuses the stage; the stage button commits.
    func testEquipSkinUpdatesImmediately() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        app.buttons["charactersButton"].tap()
        let ember = app.buttons["skin_ember"]
        XCTAssertTrue(ember.waitForExistence(timeout: 6), "characters shelf should appear")
        XCTAssertEqual(app.buttons["skin_default"].value as? String, "equipped", "default starts equipped")

        ember.tap()   // focus Ember on the stage (preview before commit)
        let stage = app.buttons["skinStageButton"]
        XCTAssertTrue(stage.waitForExistence(timeout: 4), "stage button should exist")
        XCTAssertTrue(waitForLabel(app, id: "skinStageButton", contains: "Equip Ember"),
                      "focusing an owned skin should arm the EQUIP state button")
        stage.tap()   // commit

        var emberEquipped = false
        for _ in 0..<25 {
            if (app.buttons["skin_ember"].value as? String) == "equipped" { emberEquipped = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(emberEquipped, "ember should show as equipped immediately after committing")
        XCTAssertNotEqual(app.buttons["skin_default"].value as? String, "equipped",
                          "default should no longer be equipped after switching to ember")
    }

    /// B4 — pause must freeze the run, resume must dismiss the overlay, and quit must return home.
    func testPauseResumeAndQuit() {
        let app = launch(["PR_AUTOPLAY": "1"])   // bot-driven run, so we're in .play with a pause button
        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "pause button should show during play")
        pause.tap()
        XCTAssertTrue(app.staticTexts["PAUSED"].waitForExistence(timeout: 4), "PAUSED overlay should appear")
        app.buttons["resumeButton"].tap()
        XCTAssertTrue(app.staticTexts["PAUSED"].waitForNonExistence(timeout: 4), "PAUSED should dismiss on resume")

        app.buttons["pauseButton"].tap()
        app.buttons["quitButton"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5), "quit should return to the menu")
    }

    /// F3 — CONTINUE (revive for coins) must put the player back into the run.
    func testReviveContinuesRun() {
        let app = launch(["PR_DEMO": "1", "PR_DEMOPROFILE": "1"])   // dies ~6s, has coins to revive
        let cont = app.buttons["continueButton"]
        XCTAssertTrue(cont.waitForExistence(timeout: 25), "CONTINUE should appear on game over with coins")
        cont.tap()
        XCTAssertTrue(app.buttons["pauseButton"].waitForExistence(timeout: 6), "should be back in play after continue")
        XCTAssertFalse(app.buttons["continueButton"].exists, "game over should be dismissed")
    }

    /// F1/F2 — the REWARDS rail cell claims the daily login, then opens the chest, then (both
    /// consumed) opens the mini-sheet where the chest shows its cooldown and the daily is gone.
    func testDailyAndChestRewards() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        let rail = element(app, id: "railRewards")
        XCTAssertTrue(rail.waitForExistence(timeout: 6), "rewards rail cell should exist on the menu")
        XCTAssertTrue(waitForLabel(app, id: "railRewards", contains: "Daily bonus ready"),
                      "demo profile should start with the daily login claimable")
        rail.tap()   // lit cell → claims the daily login inline

        // S-016 (D-049) routed both of these rewards through `RewardBurstView` — a modal scrim —
        // and this test was never re-run against it. The burst lands between the two rail taps, so
        // the SECOND tap was hitting the scrim (dismissing it) instead of opening the chest, and
        // the cooldown assertion below failed. Verified pre-existing: it fails identically at
        // `pre-s017`. Dismissing it explicitly also makes this test prove both bursts fire.
        let burst = element(app, id: "rewardBurst")
        XCTAssertTrue(burst.waitForExistence(timeout: 8), "claiming the daily should raise a burst")
        burst.tap()
        XCTAssertTrue(burst.waitForNonExistence(timeout: 8), "the daily burst should dismiss")

        XCTAssertTrue(waitForLabel(app, id: "railRewards", contains: "chest ready"),
                      "after the daily claim the free chest should be next in the ladder")
        rail.tap()   // lit cell → opens the free chest inline

        XCTAssertTrue(burst.waitForExistence(timeout: 8), "opening the chest should raise a burst")
        burst.tap()
        XCTAssertTrue(burst.waitForNonExistence(timeout: 8), "the chest burst should dismiss")

        XCTAssertTrue(waitForLabel(app, id: "railRewards", contains: "Next free chest"),
                      "chest should go on cooldown after opening")
        rail.tap()   // nothing claimable → opens the rewards mini-sheet

        let chest = app.buttons["chestButton"]
        XCTAssertTrue(chest.waitForExistence(timeout: 6), "mini-sheet should show the chest row")
        XCTAssertFalse(chest.isEnabled, "chest should be on cooldown after opening")
        XCTAssertFalse(app.buttons["dailyRewardButton"].exists, "daily login should already be claimed")
    }

    /// Navigation — every hub entry opens its screen and back returns to the menu; the settings
    /// gear moved off the menu, so its route is Profile → gear (covers B8/Worlds + v1.3 reframe).
    func testHubNavigation() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        let routes: [(String, String)] = [
            ("worldsButton", "Worlds"),
            ("charactersButton", "Characters"),
            ("shopButton", "Shop"),
            ("profileButton", "Profile"),
        ]
        for (button, title) in routes {
            XCTAssertTrue(app.buttons[button].waitForExistence(timeout: 6), "\(button) should exist on the menu")
            app.buttons[button].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 6), "\(button) should open the \(title) screen")
            app.buttons["closeSheetButton"].tap()
            XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 6), "back should return to the menu from \(title)")
        }

        // Settings is reached through Profile now (uiux §1 — the gear left the menu).
        app.buttons["profileButton"].tap()
        let gear = app.buttons["settingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 6), "Profile should carry the settings gear")
        gear.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 6), "gear should open Settings")
        app.buttons["closeSheetButton"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 6), "back should return to the menu from Settings")
    }

    /// v1.3 — the hero stage routes to Characters, and focusing a locked skin pins its
    /// requirement copy on the stage button (R7 stage-and-shelf, DESIGN_characters §3.1 copy).
    func testHeroStageShowsLockedRequirement() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        let hero = app.buttons["heroStage"]
        XCTAssertTrue(hero.waitForExistence(timeout: 6), "hero stage should exist on the menu")
        hero.tap()

        let pebble = app.buttons["skin_pebble"]   // level-3 lock; demo profile is level 1
        XCTAssertTrue(pebble.waitForExistence(timeout: 6), "hero stage should open the characters shelf")
        pebble.tap()   // focus the locked skin on the stage
        XCTAssertTrue(waitForLabel(app, id: "skinStageButton", contains: "REACH LEVEL 3"),
                      "the stage button should pin the locked skin's requirement")
    }

    /// v1.3 — after a death the panel must surface the run's XP outcome (line + bar).
    func testGameOverShowsXPBar() {
        let app = launch(["PR_DEMO": "1"])   // autoplay, force-die ~6s — applyRunSummary has run
        XCTAssertTrue(app.buttons["backToMenuButton"].waitForExistence(timeout: 25),
                      "game over panel should appear")
        let xp = app.descendants(matching: .any).matching(identifier: "xpLine").firstMatch
        XCTAssertTrue(xp.waitForExistence(timeout: 6), "the XP line should render on game over")
    }

    /// v1.4 — the worlds ladder buy flow, the only coin-spend surface outside StoreKit (permanent
    /// coverage, replacing the temp XCUITest deleted after wave 3). The demo profile pins coins
    /// 8,000 / reach 6 / no purchases, so: the NEXT UNLOCK strip routes to rung 8's panel,
    /// 5,800 buys it (card flips OWNED, strip advances), rung 9 (7,400 > the 2,200 left) denies
    /// and arms GET COINS, which routes to the Shop.
    func testWorldsBuyFlowPurchaseDenyAndGetCoins() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        XCTAssertTrue(app.buttons["worldsButton"].waitForExistence(timeout: 6))
        app.buttons["worldsButton"].tap()

        let strip = element(app, id: "nextUnlockStrip")
        XCTAssertTrue(strip.waitForExistence(timeout: 6), "NEXT UNLOCK strip should sit above the fold")
        strip.tap()
        let buy8 = app.buttons["unlockButton_8"]
        XCTAssertTrue(buy8.waitForExistence(timeout: 4), "the strip should open the unlock panel")
        buy8.tap()   // 8,000 ≥ 5,800 → celebration, the panel dismisses itself ~1.1 s later

        // The strip re-derives from the SAME isWorldStartable flip that turns card 8 OWNED — and
        // unlike the card (below the LazyVGrid fold, so absent from the a11y tree) it's always
        // instantiated. The panel's `.isModal` hides it until the celebration auto-dismisses,
        // so this label wait doubles as the deterministic panel-dismissal wait (no timers).
        XCTAssertTrue(waitForLabel(app, id: "nextUnlockStrip", contains: "world 9"),
                      "a successful purchase should advance the strip to the next locked rung")

        // Re-tap until rung 9's panel opens: taps during the celebration beat land on the modal
        // scrim and are deliberately swallowed, so converge by retrying (not by a fixed timer).
        let buy9 = app.buttons["unlockButton_9"]
        var panelOpen = false
        for _ in 0..<15 {
            element(app, id: "nextUnlockStrip").tap()
            if buy9.waitForExistence(timeout: 1) { panelOpen = true; break }
        }
        XCTAssertTrue(panelOpen, "the strip should re-open the unlock panel for the next rung")

        buy9.tap()   // 7,400 > 2,200 → denial must arm NEED n MORE + GET COINS, never spend
        let getCoins = app.buttons["unlockGetCoins"]
        XCTAssertTrue(getCoins.waitForExistence(timeout: 4), "an unaffordable buy should arm GET COINS")
        getCoins.tap()
        XCTAssertTrue(app.staticTexts["Shop"].waitForExistence(timeout: 6),
                      "GET COINS should route to the Shop")
    }

    /// v1.4.2 — the first-run tutorial gate covers EVERY run entrance (AUDIT D6-1) and the ✕
    /// never force-starts a run (D6-2). PR_FIRSTRUN pins a zero-run profile regardless of what
    /// earlier CI cycles banked on this simulator. Three legs, in order:
    /// (1) FIRST RUN chip is informational — ✕ returns to the menu, no run;
    /// (2) the rail's DAILY RUSH cell interposes the tutorial — ✕ cancels, no run;
    /// (3) PLAY interposes the tutorial — LET'S GO (page 5) actually starts the chosen run.
    func testFirstRunGateCoversEntrancesAndCancelNeverStarts() {
        let app = launch(["PR_FIRSTRUN": "1"])
        let close = app.buttons["howToPlayClose"]
        let play = app.buttons["playButton"]

        // (1) info tap: FIRST RUN chip → tutorial → ✕ → menu, no run started. NOTE: the menu
        // stays in the hierarchy under the overlay, so "playButton exists" proves nothing —
        // dismissal is the ✕ disappearing, "no run" is the pause button never materializing.
        let chip = element(app, id: "bestChip")
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "zero-run menu should show the FIRST RUN chip")
        chip.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 6), "the chip should open the tutorial")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 6), "✕ should dismiss the tutorial")
        XCTAssertFalse(app.buttons["pauseButton"].exists, "the info ✕ must never start a run")
        XCTAssertTrue(play.isHittable, "the menu should be back in front")

        // (2) Daily Rush on a zero-run profile: tutored first, and ✕ still just cancels.
        element(app, id: "railDaily").tap()
        XCTAssertTrue(close.waitForExistence(timeout: 6),
                      "a zero-run Daily Rush tap should interpose the tutorial")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 6), "✕ should cancel the gated tutorial")
        XCTAssertFalse(app.buttons["pauseButton"].exists, "cancelling the gate must not start the challenge")
        XCTAssertTrue(play.isHittable, "the menu should be back in front")

        // (3) PLAY: tutorial, then LET'S GO commits to the run (4 × NEXT + the final button).
        play.tap()
        let next = app.buttons["howToPlayNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 6), "zero-run PLAY should interpose the tutorial")
        for _ in 0..<5 { next.tap() }
        XCTAssertTrue(app.buttons["pauseButton"].waitForExistence(timeout: 8),
                      "LET'S GO should start the chosen run")
    }

    /// v1.4 — the missions claim pipeline: CLAIM ALL cascade first (top of the board, sweeps the
    /// three seeded tier-1 achievements + any strays to zero), then the single-claim leg on
    /// ach.chests, which the demo profile pins past BOTH tier targets so exactly one claimable
    /// re-arms after the sweep (CLAIM ALL needs ≥ 2, so its pill must be gone by then).
    func testMissionsClaimAllCascadeAndSingleClaim() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        let rail = element(app, id: "railMissions")
        XCTAssertTrue(rail.waitForExistence(timeout: 6), "missions rail cell should exist on the menu")
        rail.tap()

        XCTAssertTrue(element(app, id: "missionsSummary").waitForExistence(timeout: 6),
                      "the summary strip should render on the board")
        let claimAll = app.buttons["claimAllButton"]
        XCTAssertTrue(claimAll.waitForExistence(timeout: 6), "≥2 seeded claimables should surface CLAIM ALL")

        claimAll.tap()   // cascade: one claim per 80 ms beat until the board is swept

        // S-017: the cascade now resolves into ONE `RewardBurstView` carrying the total, instead
        // of a 13 pt "+N" fading inside each card. It is a modal scrim, so it has to be dismissed
        // before the board is reachable again — and asserting on it first means this test now
        // proves the reward moment actually fires, which nothing did before.
        let burst = element(app, id: "rewardBurst")
        XCTAssertTrue(burst.waitForExistence(timeout: 8),
                      "CLAIM ALL should raise one reward burst for the whole set")
        burst.tap()
        XCTAssertTrue(burst.waitForNonExistence(timeout: 8), "tapping the burst should dismiss it")

        XCTAssertTrue(app.buttons["claim_ach.gems"].waitForNonExistence(timeout: 8),
                      "the cascade should retire Gem Hoarder's claim")
        XCTAssertTrue(app.buttons["claim_ach.slick"].waitForNonExistence(timeout: 8),
                      "the cascade should retire Limbo Legend's claim")
        XCTAssertTrue(claimAll.waitForNonExistence(timeout: 8),
                      "CLAIM ALL should disappear once fewer than 2 claims remain")

        // Single claim: ach.chests re-armed at tier 2 (progress 110 ≥ 100). It lives at the
        // bottom of the ACHIEVEMENTS ladder — scroll it into reach first.
        let single = app.buttons["claim_ach.chests"]
        XCTAssertTrue(single.waitForExistence(timeout: 6), "Chest Hunter tier 2 should re-arm after the sweep")
        for _ in 0..<10 where !single.isHittable { app.swipeUp() }
        XCTAssertTrue(single.isHittable, "the ladder should scroll the claim into reach")
        single.tap()

        // A single claim gets its own burst, naming that one mission.
        XCTAssertTrue(burst.waitForExistence(timeout: 8),
                      "a single claim should raise its own reward burst")
        burst.tap()
        XCTAssertTrue(burst.waitForNonExistence(timeout: 8), "tapping the burst should dismiss it")

        XCTAssertTrue(single.waitForNonExistence(timeout: 6),
                      "the final tier's claim should retire the button (receipt row)")
    }

    /// PR-0305 — mute persists across launches, and before the sweep the in-run corner speaker was
    /// the ONLY control that could clear it. A muted player had to guess that starting a run was
    /// the way back to sound. Settings must be able to undo it.
    func testMuteIsReversibleFromSettings() {
        let app = launch(["PR_SCREEN": "settings"])
        let mute = app.switches["muteToggle"]
        XCTAssertTrue(mute.waitForExistence(timeout: 6), "Settings must offer a mute control")
        XCTAssertEqual(mute.value as? String, "0", "a fresh profile starts unmuted")
        mute.tap()
        XCTAssertEqual(mute.value as? String, "1", "tapping must mute")
        mute.tap()
        XCTAssertEqual(mute.value as? String, "0", "and it must be reversible — the whole point")
    }

    // PR-0302's UI is NOT covered here, deliberately. The shortfall row only renders when the
    // profile cannot afford 300 coins, and XCUITest runs share an installed app whose coins
    // accumulate across runs (mission claims bank them), so the state is not reachable
    // deterministically. It needs a coin-pinning launch hook, which does not exist and which
    // PR-0313 (every PR_* hook ships un-gated in Release) argues against adding casually.
    // The affordability MATH is pinned by ShopValueTests.testMysteryBoxShortfallIsTheGapToTheCost
    // under `swift test`; the rendered state was verified on the simulator (S-007 screenshots).
}
