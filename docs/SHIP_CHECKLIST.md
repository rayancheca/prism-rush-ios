# Prism Rush — Ship Checklist

Your copy-paste path from this repo to the App Store, in order. Do the steps top to bottom.

Legend: ⚡ **instant** (takes effect immediately) · 🍎 **Apple review** (waits on Apple, hours–days).
Everything in App Store Connect (ASC) happens at <https://appstoreconnect.apple.com>.

> Note: the code calls this build the "v1.2 overhaul", but it ships to the App Store as **version
> 1.0** (`MARKETING_VERSION` in `project.yml`) — it's your first release.

---

## A. Create the app record — ⚡ instant

ASC → My Apps → **+** → New App:

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `Prism Rush` |
| Bundle ID | `com.rayancheca.prismrush` (pick it from the dropdown after step D, or register it first at developer.apple.com → Identifiers) |
| SKU | `prismrush` (anything unique; never shown to users) |
| Primary language | English (U.S.) |

**Backup name:** "Prism Rush" has never been verified as available. If ASC rejects the name, use one
of the pre-counted alternates in `Store/metadata.md` §8 (e.g. keep the name and change only if forced
— the bundle ID does NOT need to change with the name).

## B. Create the 7 in-app purchases — ⚡ to create, 🍎 to go live (submitted with your first build)

ASC → your app → Monetization → In-App Purchases → **+**. Create exactly these seven
(IDs must match `Products.storekit` character-for-character or purchases silently fail).
Until they exist here, the in-app Shop shows fallback prices with a quiet "APP STORE SETUP
PENDING" footnote — that's expected, not a bug.

| Product ID | Type | Price | Display name | Description (paste) |
|---|---|---|---|---|
| `com.rayancheca.prismrush.coins.small` | Consumable | $0.99 (Tier 1) | Pouch of Coins | 1,200 coins |
| `com.rayancheca.prismrush.starter` **NEW v1.4.1** | Consumable | $1.99 (Tier 2) | Starter Bundle | 3,000 coins |
| `com.rayancheca.prismrush.coins.medium` | Consumable | $4.99 (Tier 5) | Bag of Coins | 7,000 coins |
| `com.rayancheca.prismrush.coins.large` | Consumable | $9.99 (Tier 10) | Vault of Coins | 16,000 coins |
| `com.rayancheca.prismrush.coins.mega` **NEW v1.4.1** | Consumable | $19.99 (Tier 20) | Crate of Coins | 40,000 coins |
| `com.rayancheca.prismrush.doublecoins` | **Non-Consumable** | $2.99 (Tier 3) | Double Coins | Earn 2x coins, forever |
| `com.rayancheca.prismrush.skin.aurora` | **Non-Consumable** | $1.99 (Tier 2) | Aurora Skin | Exclusive Aurora character |

Notes on the two NEW ones: the Starter Bundle is the in-app first-purchase offer (the Shop only
shows it to players with zero purchases); the Crate is the whale-tier pack the BEST VALUE badge
points at. Both are plain consumables in ASC — all offer logic lives client-side.

Each IAP also needs a review screenshot (any in-app shot of the Shop screen works — step F.5
produces them) and must be **attached to the version** before you submit it.

## C. Game Center leaderboards — ⚡ instant to create

ASC → your app → Services → Game Center → add **two** leaderboards:

1. **Classic leaderboard**
   - ID: `prismrush.best`
   - Reference name / display name: `All-Time Best`
   - Score format: Integer · Sort: High to Low · Score range: 0 to 10,000,000
2. **RECURRING leaderboard** (not classic — this is the important one people miss)
   - ID: `prismrush.daily`
   - Reference name / display name: `Daily Rush`
   - Score format: Integer · Sort: High to Low
   - Recurrence: starts 00:00 **UTC**, duration 24 hours, restarts every 24 hours (daily reset)

Without `prismrush.daily` the daily-challenge submissions silently no-op — the game won't crash,
scores just never appear.

## D. Capabilities / App ID — ⚡ mostly automatic

The app uses: **In-App Purchase, Sign in with Apple, Game Center, iCloud Key-Value storage**.

You barely have to do anything: the Team ID (`8M64JJQQAU`) is already in `project.yml`, the
entitlements file is already in the repo, and `CODE_SIGN_STYLE: Automatic` means **Xcode registers
the App ID and enables the capabilities on your first signed build** (just be signed into your Apple
ID in Xcode → Settings → Accounts). If something complains, check developer.apple.com →
Identifiers → `com.rayancheca.prismrush` and tick the four capabilities manually
(iCloud: Key-Value storage only — no CloudKit container needed).

## E. App Privacy questionnaire — ⚡ instant (required before submission)

ASC → your app → App Privacy. The build is **NOT** "Data Not Collected" (it has IAP, Game Center,
Sign in with Apple, iCloud sync). Answers, matching `Store/metadata.md` §7:

- Data used to **track** you: **None** (no ads, no analytics, no third-party SDKs)
- Data **linked** to you:
  - **Purchases** → Purchase History (app functionality)
  - **Identifiers** → User ID (Game Center identity + Sign in with Apple identifier; app functionality)
- Data **not linked** to you: None

While you're in ASC, also paste in the listing copy from `Store/metadata.md`
(name, subtitle, promo text, keywords, description, What's New — all pre-counted against limits),
set category **Games → Arcade**, age **4+**, price **Free**.

## F. On your Mac — build, test, verify — ⚡ your time only

```bash
# 1. Get the code — everything ships from main
cd ~/Desktop/ClaudeProjects/projects/prism-rush-ios
git checkout main && git pull

# 2. Build (needs Xcode 26+, xcodegen: brew install xcodegen)
./Tools/build.sh

# 3. Full test suite — expect 196 green (185 unit + 11 UI)
xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
```

**4. Visual/audio pass** (10 minutes of actually playing; full list in
`reports/AGENT_wiring.md` §MAC VERIFICATION):

- [ ] Fresh install → PLAY shows the how-to-play tutorial once; "LET'S GO" starts the run
- [ ] Daily challenge card: play twice the same day → identical track; **no CONTINUE on death**;
      "today's best" + 7-day dots update; RUN AGAIN afterwards is a normal random run
- [ ] Game over: score counts up; TIME tile is frozen (pause 30 s mid-run, die → pause not counted);
      coin breakdown line sums to the "+N"; GET COINS opens the Shop over the death panel
- [ ] Revive: second death pays only the extra coins earned after the continue; best-score fanfare
      plays once per run
- [ ] Missions: a finished run moves the progress bars; CLAIM pays once and collapses the row
- [ ] Settings: volume sliders change audio live AND stick after relaunch; haptics toggle works;
      "Reduce flashing" makes the death flash barely visible
- [ ] Feel: split bar's gap reads clearly, chrono pickup visibly slows the world, HUD timer chips
      (MAG / ×2 / SLOW) don't overlap the mute/pause buttons
- [ ] Audio survives an interruption: trigger an alarm/timer mid-run → music returns after
- [ ] Quick VoiceOver + biggest-Dynamic-Type spot check on menu/shop/missions

**5. Screenshots:** `./Tools/screenshots.sh` (captures the 6.9" set into `Store/screenshots/`;
caption suggestions in `Store/metadata.md` §9). For the 6.5" size, download an iPhone 11 Pro Max
simulator via Xcode → Settings → Components first — the script auto-detects it.

## G. Archive & upload — ⚡ upload, then 🍎 review

Easiest path (GUI):

1. Xcode → open `PrismRush.xcodeproj` → select scheme **PrismRush**, destination
   **Any iOS Device (arm64)**.
2. Product → **Archive** (signing is automatic — Team ID is already configured).
3. In the Organizer window: **Distribute App** → **App Store Connect** → Upload → accept defaults.
4. In ASC: the build appears under TestFlight after ~15 min of processing. Select it on the
   version page, attach the 7 IAPs to the version, fill export compliance (uses only standard
   encryption → exempt), then **Submit for Review**. 🍎
5. Optional but smart: TestFlight it to your own phone first and replay the F.4 checklist on real
   hardware (haptics especially).

## H. After launch — ideas parking lot

- Rewarded continue via ads as an optional second revenue stream (deliberately skipped at launch — zero SDKs)
- More worlds + premium skin drops (everything is data-driven catalogs, cheap to extend)
- Weekend events / special challenge seeds on top of `DailyChallenge` (layoutVersion mechanism is ready)
- Achievements in Game Center mirroring the in-game achievement tiers
- Widget / Live Activity showing the daily challenge countdown
