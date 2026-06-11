import XCTest
@testable import PrismRush

/// The 24-character roster (v1.3's 16 + the v1.4 eight): catalog integrity + frozen legacy pins,
/// unlock-requirement evaluation (SkinUnlocks), the grant-once auto-unlock path, and the pinned
/// requirement copy.
@MainActor
final class SkinCatalogTests: XCTestCase {

    func testCatalogIntegrityAndLegacyPins() async {
        let all = SkinCatalog.all
        XCTAssertEqual(all.count, 24)
        XCTAssertEqual(Set(all.map(\.id)).count, 24, "unique ids")
        XCTAssertEqual(Set(all.map(\.name)).count, 24, "unique names")

        // The legacy 16 keep exact ids/hexes/costs — owners must notice nothing but upgrades.
        let pins: [(id: String, cost: Int, body: UInt32, antenna: UInt32, premium: Bool)] = [
            ("default", 0, 0, 0, false),
            ("ember", 200, 0xFF5E3A, 0xFFD23D, false),
            ("bolt", 300, 0x00B3FF, 0xFFFFFF, false),
            ("pebble", 0, 0x8E9BAE, 0xFFB13D, false),
            ("void", 350, 0xB26BFF, 0x00FFC8, false),
            ("toxic", 500, 0x39FF14, 0xFF2BD6, false),
            ("mono", 750, 0xF4F8FF, 0x0A0A14, false),
            ("blossom", 0, 0xFF8AD4, 0xB4FF5C, false),
            ("fang", 2_500, 0xFF3B30, 0x14141E, false),
            ("drift", 0, 0xE08A3C, 0x00FFC8, false),
            ("midas", 1_500, 0xFFD23D, 0xFFFFFF, false),
            ("shard", 0, 0x7DF9FF, 0xFFFFFF, false),
            ("wisp", 0, 0xDFF6FF, 0x9BF0FF, false),
            ("tempo", 0, 0xC6FF4D, 0xFF2BD6, false),
            ("aurora", 0, 0x00FFC8, 0xFF2BD6, true),
            ("eclipse", 0, 0x1A1A2E, 0xFF2BD6, false),
        ]
        for pin in pins {
            let s = SkinCatalog.skin(pin.id)
            XCTAssertEqual(s.id, pin.id)
            XCTAssertEqual(s.cost, pin.cost, pin.id)
            XCTAssertEqual(s.bodyHex, pin.body, pin.id)
            XCTAssertEqual(s.antennaHex, pin.antenna, pin.id)
            XCTAssertEqual(s.premium, pin.premium, pin.id)
        }
        XCTAssertEqual(SkinCatalog.skin("bolt").cost, 300, "Bolt = day-one first buy (R4)")
        XCTAssertEqual(SkinCatalog.skin("fang").cost, 2_500, "Fang = week-1 savings goal (R4)")

        // The v1.4 eight take the parking-lot coin rungs (2,000/3,500/5,000/7,500) plus the
        // level-8/18 beats, ach.gems tier 2, and the 14-day challenge pull.
        XCTAssertEqual(SkinCatalog.skin("tide").cost, 2_000)
        XCTAssertEqual(SkinCatalog.skin("thorn").cost, 3_500)
        XCTAssertEqual(SkinCatalog.skin("golem").cost, 5_000)
        XCTAssertEqual(SkinCatalog.skin("monarch").cost, 7_500)
        XCTAssertEqual(SkinCatalog.skin("circuit").unlock, .level(8))
        XCTAssertEqual(SkinCatalog.skin("nebula").unlock, .level(18))
        XCTAssertEqual(SkinCatalog.skin("facet").unlock, .achievement(id: "ach.gems", tier: 2))
        XCTAssertEqual(SkinCatalog.skin("vigil").unlock, .challengeDays(14))

        // Rig sanity + the two singletons.
        for s in all { XCTAssertTrue((0.85...1.12).contains(s.scale), "\(s.id) scale is visual-only") }
        XCTAssertEqual(all.filter(\.followsWorld).map(\.id), ["default"], "exactly one followsWorld")
        XCTAssertEqual(all.filter(\.premium).map(\.id), ["aurora"], "exactly one IAP skin")
        XCTAssertNil(SkinCatalog.skin("default").trailHex, "Prism's trail follows the world accent")

        // XP-locked roster matches the curve's unlock levels exactly (R1 single source of truth).
        let levelLocks = all.compactMap { if case .level(let n) = $0.unlock { n } else { nil } }
        XCTAssertEqual(levelLocks.sorted(), XPCurve.xpUnlockLevels)

        // Achievement unlocks must reference real MissionCatalog ladders at a reachable tier;
        // challenge-day unlocks must fit inside the 60-day challengeDaysPlayed window (≤ 50).
        for s in all {
            if case .achievement(let id, let tier) = s.unlock {
                guard let m = MissionCatalog.mission(id),
                      case .lifetimeTiered(let targets, _) = m.scope else {
                    XCTFail("\(s.id) references unknown achievement \(id)"); continue
                }
                XCTAssertTrue(tier >= 1 && tier <= targets.count, "\(s.id) tier in range")
            }
            if case .challengeDays(let n) = s.unlock {
                XCTAssertTrue(n >= 1 && n <= 50, "\(s.id) must stay inside the 60-day window")
            }
        }

        // Rarity ladder compares by rawValue; catalog order is rarity-major (the select grid
        // renders catalog order inside each rarity section).
        XCTAssertTrue(Skin.Rarity.common < Skin.Rarity.rare)
        XCTAssertTrue(Skin.Rarity.rare < Skin.Rarity.epic)
        XCTAssertTrue(Skin.Rarity.epic < Skin.Rarity.legendary)
        XCTAssertEqual(all.map(\.rarity), all.map(\.rarity).sorted())
        XCTAssertEqual(all.filter { $0.rarity == .common }.count, 4)
        XCTAssertEqual(all.filter { $0.rarity == .rare }.count, 9)
        XCTAssertEqual(all.filter { $0.rarity == .epic }.count, 7)
        XCTAssertEqual(all.filter { $0.rarity == .legendary }.count, 4)

        XCTAssertEqual(SkinCatalog.skin("nope").id, "default", "unknown id falls back to Prism")
    }

    func testSkinUnlocksEarnedBoundaries() async {
        let fresh = Profile()
        let shard = SkinCatalog.skin("shard")
        XCTAssertFalse(SkinUnlocks.earned(shard, profile: fresh, level: 11), "11 < 12")
        XCTAssertTrue(SkinUnlocks.earned(shard, profile: fresh, level: 12), "boundary inclusive")

        var ach = Profile()
        let wisp = SkinCatalog.skin("wisp")
        ach.achievementTier["ach.close"] = 0
        XCTAssertFalse(SkinUnlocks.earned(wisp, profile: ach, level: 30))
        ach.achievementTier["ach.close"] = 1
        XCTAssertTrue(SkinUnlocks.earned(wisp, profile: ach, level: 1), "achievement ignores level")

        // The v1.4 tier-2 achievement gate: tier 1 (100 gems claimed) is NOT enough for Facet.
        var hoard = Profile()
        let facet = SkinCatalog.skin("facet")
        hoard.achievementTier["ach.gems"] = 1
        XCTAssertFalse(SkinUnlocks.earned(facet, profile: hoard, level: 30), "tier 1 < 2")
        hoard.achievementTier["ach.gems"] = 2
        XCTAssertTrue(SkinUnlocks.earned(facet, profile: hoard, level: 1))

        var days = Profile()
        let tempo = SkinCatalog.skin("tempo")
        days.challengeDaysPlayed = Set((1...6).map { String(format: "2026-06-%02d", $0) })
        XCTAssertFalse(SkinUnlocks.earned(tempo, profile: days, level: 30), "6 days < 7")
        days.challengeDaysPlayed.insert("2026-06-07")
        XCTAssertTrue(SkinUnlocks.earned(tempo, profile: days, level: 1))

        // Vigil is the 14-day pull: 13 days short, 14 exact.
        let vigil = SkinCatalog.skin("vigil")
        days.challengeDaysPlayed = Set((1...13).map { String(format: "2026-06-%02d", $0) })
        XCTAssertFalse(SkinUnlocks.earned(vigil, profile: days, level: 30), "13 days < 14")
        days.challengeDaysPlayed.insert("2026-06-14")
        XCTAssertTrue(SkinUnlocks.earned(vigil, profile: days, level: 1))

        XCTAssertTrue(SkinUnlocks.earned(SkinCatalog.skin("default"), profile: fresh, level: 1))
        XCTAssertFalse(SkinUnlocks.earned(SkinCatalog.skin("ember"), profile: fresh, level: 30),
                       "coins go through the buy flow, never auto-grant")
        XCTAssertFalse(SkinUnlocks.earned(SkinCatalog.skin("aurora"), profile: fresh, level: 30),
                       "iap goes through the shop, never auto-grant")
    }

    func testRefreshSkinUnlocksGrantsOnceAndMarksSeen() async {
        let store = ProfileStore(testing: Profile())
        XCTAssertTrue(store.refreshSkinUnlocks(level: 1).isEmpty, "nothing newly earned at level 1")

        let granted = store.refreshSkinUnlocks(level: 6)
        XCTAssertEqual(granted.map(\.id), ["pebble", "blossom"], "L3 + L6 auto-grant, catalog order")
        XCTAssertTrue(store.profile.ownedSkins.isSuperset(of: ["pebble", "blossom"]))
        XCTAssertTrue(store.refreshSkinUnlocks(level: 6).isEmpty, "grant-once — second call is empty")

        store.mutate { $0.achievementTier["ach.dist"] = 1 }
        XCTAssertEqual(store.refreshSkinUnlocks(level: 6).map(\.id), ["drift"])

        store.mutate { $0.challengeDaysPlayed = Set((1...7).map { String(format: "2026-06-%02d", $0) }) }
        XCTAssertEqual(store.refreshSkinUnlocks(level: 6).map(\.id), ["tempo"])

        // Level-30 catch-up grants the remaining XP skins (catalog order) — never the coin/IAP
        // ones, and never the still-unmet achievement/challenge pulls (Facet t2, Vigil 14 days).
        XCTAssertEqual(store.refreshSkinUnlocks(level: 30).map(\.id),
                       ["circuit", "shard", "nebula", "eclipse"])
        for id in ["ember", "bolt", "tide", "fang", "midas", "thorn", "golem", "monarch", "aurora",
                   "facet", "vigil"] {
            XCTAssertFalse(store.profile.ownedSkins.contains(id), "\(id) must stay behind its gate")
        }

        // NEW badges: grants are unseen until CharacterSelect marks them.
        XCTAssertFalse(store.profile.seenSkins.contains("pebble"))
        store.markSkinsSeen()
        XCTAssertTrue(store.profile.seenSkins.isSuperset(of: store.profile.ownedSkins))
    }

    func testRequirementTextPinnedCopy() async {
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("default")), "")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("ember")), "200",
                       "coins render as the raw amount — the UI substitutes a CoinBadge")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("pebble")), "REACH LEVEL 3")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("circuit")), "REACH LEVEL 8")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("shard")), "REACH LEVEL 12")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("nebula")), "REACH LEVEL 18")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("eclipse")), "REACH LEVEL 25")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("drift")), "RUN 10,000 M LIFETIME")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("wisp")), "THREAD 100 CLOSE CALLS")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("facet")), "BANK 1,000 GEMS LIFETIME")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("tempo")), "PLAY 7 DAILY CHALLENGES")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("vigil")), "PLAY 14 DAILY CHALLENGES")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("monarch")), "7500",
                       "coins render as the raw amount — the UI substitutes a CoinBadge")
        XCTAssertEqual(SkinUnlocks.requirementText(SkinCatalog.skin("aurora")), "★ PREMIUM · SHOP")
        for s in SkinCatalog.all where s.unlock != .free {
            XCTAssertFalse(SkinUnlocks.requirementText(s).isEmpty, "\(s.id) locked cards need copy")
        }
    }
}
