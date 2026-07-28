# Prism Rush → App Store: the extremely detailed, zero-assumed-knowledge guide

This is the complete human-gate walkthrough. Follow it top to bottom. Every value you must
type is in `code font` and is copy-paste exact — App Store Connect (ASC) and StoreKit match
strings **character-for-character**, so do not retype from memory.

**Legend:** ⚡ = takes effect immediately · 🍎 = waits on Apple (hours–days) · 💵 = needed only
because the app has in-app purchases.

**The numbers you'll reuse everywhere:**
| Thing | Value |
|---|---|
| App name | `Prism Rush` |
| Bundle ID | `com.rayancheca.prismrush` |
| Apple Team ID | `8M64JJQQAU` (already in `project.yml`) |
| Ships as version | `1.0` (`MARKETING_VERSION`), build `1` |
| Min iOS | 18.0 |
| ASC website | https://appstoreconnect.apple.com |
| Developer website | https://developer.apple.com/account |

---

## PART 0 — Accounts & money (one-time) 💵

You can't ship without these. Do them first; some have a wait.

### 0.1 Apple Developer Program — ⚡ to start, 🍎 ~24–48 h to approve
1. Go to https://developer.apple.com/programs/enroll/
2. Sign in with your Apple ID (the one you'll use forever for this).
3. Enroll as an **Individual** (simplest; your legal name becomes the seller name) or
   **Organization** (needs a D-U-N-S number — only if you have a registered company).
4. Pay the **$99/year** fee. Apple emails you when membership is active (usually a day or two).

> Until this is active you cannot create the app record or upload a build. Everything below
> assumes membership is **active**.

### 0.2 Agreements, Tax, and Banking — ⚡ to fill, 🍎 to verify 💵
Because Prism Rush has paid in-app purchases, Apple will not let IAPs go live until your
**Paid Apps Agreement** is active and tax/bank forms are complete.

1. ASC → **Business** (or **Agreements, Tax, and Banking**).
2. Accept the **Paid Applications** agreement (the free agreement is auto-accepted).
3. **Tax forms:** fill the U.S. tax form (W-9 if U.S.) and any others ASC prompts for.
4. **Bank account:** add the account Apple will pay royalties into.
5. Wait until the Paid Apps agreement status shows **Active** (can take a day).

> If you skip this, the app can still ship **Free**, but every IAP will be stuck in
> "Developer Action Needed / Missing Metadata" and players can't buy anything.

### 0.3 Xcode + tools on your Mac — ⚡
1. Install **Xcode 16 or newer** (the repo targets iOS 18 / Swift 6) from the Mac App Store.
2. Open Xcode → **Settings → Accounts → +** → sign in with the **same** Apple ID. This is what
   lets Xcode auto-create signing certificates.
3. Install xcodegen (the project file is generated, not committed):
   ```bash
   brew install xcodegen
   ```

---

## PART 1 — Register the App ID + capabilities — ⚡ (mostly automatic)

The app uses four capabilities: **In-App Purchase, Sign in with Apple, Game Center, iCloud
Key-Value storage**. `CODE_SIGN_STYLE: Automatic` means Xcode will register the App ID and
enable these on your first signed build — so you can often **skip this part** and let Xcode do
it. Do it manually only if a later step complains.

Manual path:
1. https://developer.apple.com/account → **Identifiers** → **+** → **App IDs** → **App**.
2. Description: `Prism Rush`. Bundle ID: **Explicit** → `com.rayancheca.prismrush`.
3. Under **Capabilities**, tick:
   - **In-App Purchase**
   - **Sign in with Apple**
   - **Game Center**
   - **iCloud** → enable **Key-value storage** only (do NOT create a CloudKit container — the
     app uses KVS, matching `PrismRush/Support/PrismRush.entitlements`).
4. **Register**.

---

## PART 2 — Create the app record in ASC — ⚡

1. ASC → **My Apps** → **+** (top-left) → **New App**.
2. Fill:
   | Field | Value |
   |---|---|
   | Platforms | **iOS** |
   | Name | `Prism Rush` |
   | Primary language | **English (U.S.)** |
   | Bundle ID | pick `com.rayancheca.prismrush` from the dropdown (it appears after Part 1, or after your first Xcode upload) |
   | SKU | `prismrush` (internal only, never shown to users) |
   | User Access | **Full Access** |
3. **Create**.

> **If the name is rejected** ("Prism Rush" is taken): the bundle ID does **not** have to
> change. Use an alternate from `Store/metadata.md §8` (e.g. keep trying, or append a word).
> The in-app wordmark stays "Prism Rush" regardless of the store listing name.

---

## PART 3 — Create the 7 in-app purchases — ⚡ to create, 🍎 to approve 💵

ASC → your app → left sidebar **Monetization → In-App Purchases → +**. Create **exactly**
these seven. The **Product ID must match `Products.storekit` character-for-character** or the
in-app shop silently shows fallback prices forever.

| Product ID (paste exactly) | Type | Reference Name | Price (tier) |
|---|---|---|---|
| `com.rayancheca.prismrush.coins.small` | **Consumable** | `Pouch of Coins` | $0.99 |
| `com.rayancheca.prismrush.starter` | **Consumable** | `Starter Bundle` | $1.99 |
| `com.rayancheca.prismrush.coins.medium` | **Consumable** | `Bag of Coins` | $4.99 |
| `com.rayancheca.prismrush.coins.large` | **Consumable** | `Vault of Coins` | $9.99 |
| `com.rayancheca.prismrush.coins.mega` | **Consumable** | `Crate of Coins` | $19.99 |
| `com.rayancheca.prismrush.doublecoins` | **Non-Consumable** | `Double Coins` | $2.99 |
| `com.rayancheca.prismrush.skin.aurora` | **Non-Consumable** | `Aurora Skin` | $1.99 |

For **each** IAP, ASC requires:
1. **Reference Name** (table above — internal only).
2. **Price** → choose the matching price point.
3. **Localization (English U.S.)** → a **Display Name** and **Description** players see:
   | Product | Display Name | Description |
   |---|---|---|
   | small | `Pouch of Coins` | `1,200 coins` |
   | starter | `Starter Bundle` | `3,000 coins to kickstart the roster` |
   | medium | `Bag of Coins` | `7,000 coins` |
   | large | `Vault of Coins` | `16,000 coins` |
   | mega | `Crate of Coins` | `40,000 coins` |
   | doublecoins | `Double Coins` | `Every run pays 2× coins. Forever.` |
   | aurora | `Aurora Skin` | `Exclusive Aurora character` |
4. **Review screenshot** (required): one screenshot of the in-app Shop screen. You'll generate
   these in Part 7.5; come back and attach one to each IAP. (Any clear Shop shot is fine.)
5. **Review notes** (optional): e.g. `Coin pack consumed in-game to unlock characters/worlds.`

> Starter Bundle + Crate are plain consumables to Apple — all the "first-purchase offer" and
> "BEST VALUE" logic lives in the app, not in ASC.
>
> The IAPs will sit in **"Ready to Submit"** and go live **attached to your first app version**
> (Part 8). Until they exist + are approved, the in-app shop honestly shows fallback prices with
> a quiet "APP STORE SETUP PENDING" footnote — that is expected, not a bug.

---

## PART 4 — Game Center leaderboards — ⚡

ASC → your app → **Services → Game Center**. Add **two** leaderboards. (If Game Center isn't
visible yet, it appears after the first build with the entitlement is uploaded — you can do this
after Part 7.)

### 4.1 Classic leaderboard
- Click **+** next to Leaderboards → **Classic Leaderboard**.
- **Leaderboard Reference Name:** `All-Time Best`
- **Leaderboard ID:** `prismrush.best`  ← must match exactly
- **Score Format Type:** Integer
- **Sort Order:** High to Low
- **Score Range (optional):** `0` to `10000000`
- Add an English localization: Display name `All-Time Best`.

### 4.2 Recurring leaderboard (the one people forget)
- Click **+** → **Recurring Leaderboard**.
- **Reference Name:** `Daily Rush`
- **Leaderboard ID:** `prismrush.daily`  ← must match exactly
- **Score Format / Sort:** Integer, High to Low
- **Recurrence:** Start date today at **00:00 UTC**, **Duration 24 hours**, **repeats every
  24 hours** (so it resets daily, worldwide, together).
- English localization: Display name `Daily Rush`.

> Without `prismrush.daily` the daily-challenge submissions silently no-op (no crash, scores
> just never appear on the daily board).

---

## PART 5 — App Privacy questionnaire — ⚡ (required before you can submit)

ASC → your app → **App Privacy** → **Get Started / Edit**. The build **does** collect data
(IAP, Game Center, Sign in with Apple, iCloud), so it is **NOT** "Data Not Collected".

Answer:
- **Do you collect data?** → **Yes**.
- **Data used to track you:** **None** (no ads, no analytics, no third-party SDKs).
- **Data linked to the user's identity:**
  - **Purchases → Purchase History** — purpose: **App Functionality**. Linked: Yes. Tracking: No.
  - **Identifiers → User ID** (Game Center identity + Sign in with Apple identifier) — purpose:
    **App Functionality**. Linked: Yes. Tracking: No.
- **Data not linked to you:** None.

Save/Publish the privacy responses.

---

## PART 6 — Listing metadata — ⚡ (all copy is pre-written in `Store/metadata.md`)

ASC → your app → the **1.0 version** page (left sidebar, under iOS App). Paste:

| Field | Value (from `Store/metadata.md`) |
|---|---|
| **Name** | `Prism Rush` |
| **Subtitle** | `Neon 3-world hyperspeed run` |
| **Promotional Text** | `Dash through three neon worlds at hyperspeed. Swap lanes, jump, slide, chain gem streaks, beat your best. Pure reflex arcade—no ads, no tracking.` |
| **Keywords** | `endless runner,arcade,gem dash,lane swap,jump slide,reflex,dodge,one tap,glow,synthwave,high score` |
| **Description** | the full text in `Store/metadata.md §4` |
| **What's New** | the text in `Store/metadata.md §5` |
| **Support URL** | a page you control (a GitHub repo README URL works for launch) |
| **Marketing URL** | optional |
| **Primary Category** | **Games**, Subcategory **Arcade** |
| **Age Rating** | answer the questionnaire honestly → it lands at **4+** |
| **Price** | **Free** (Pricing and Availability → Price Schedule → Free) |
| **Availability** | All countries/regions (or your choice) |

You also need (Part 7.5 generates these):
- **App icon** — the 1024×1024 marketing icon is at `Store/icon_1024.png`. Upload it under the
  version (App Store icon) if prompted; the in-build icon is already in the binary.
- **Screenshots** — required for at least the **6.9" iPhone** size. See Part 7.5.

---

## PART 7 — On your Mac: build, test, archive, upload — ⚡ (your time)

### 7.1 Get the code & generate the project
```bash
cd ~/Desktop/ClaudeProjects/projects/prism-rush-ios
git checkout main && git pull
./Tools/build.sh        # runs xcodegen + a simulator build; proves it compiles
```

### 7.2 Run the test suite (sanity — all green)
```bash
xcodebuild test -project PrismRush.xcodeproj -scheme PrismRush \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO
# expect 196 green (185 unit + 11 UI)
```

### 7.3 Play it for 10 minutes (the human pass)
Install on the simulator (or your phone) and spot-check: fresh-install tutorial, a normal run
(jump/slide/lane, gem streaks, CLOSE/SLICK), a Daily Rush (same track twice = identical; no
CONTINUE on death), the Shop (fallback prices + "SETUP PENDING" footnote is fine pre-launch),
Characters (carousel + buy/equip), Settings (volume sticks across relaunch), and Reduce Motion
(Settings → Accessibility) calming the animations. Full checklist: `reports/AGENT_wiring.md`.

### 7.4 First signed build sanity (registers the App ID + capabilities automatically)
1. `open PrismRush.xcodeproj`
2. Select the **PrismRush** scheme, destination **Any iOS Device (arm64)**.
3. Xcode top bar → it should show your team `8M64JJQQAU` and "Automatically manage signing".
   If it complains, Xcode → target **Signing & Capabilities** → tick **Automatically manage
   signing**, choose your team. This is when Xcode registers the App ID + the four capabilities
   on developer.apple.com for you.

### 7.5 Generate App Store screenshots — ⚡
```bash
./Tools/screenshots.sh          # captures the 6.9" set into Store/screenshots/
```
- This boots the iPhone 17 Pro Max sim, drives the app, and writes PNGs.
- The **6.9" set is required**. For the **6.5"** set, first install an iPhone 11 Pro Max sim
  (Xcode → Settings → Components), then re-run — the script auto-detects it.
- Captions per shot are in `Store/metadata.md §9`.
- Upload these under the version's **App Previews and Screenshots**.
- Re-use any Shop screenshot for the **IAP review screenshots** from Part 3.4.

### 7.6 Archive & upload — ⚡ to upload, then 🍎
1. Xcode → **Product → Archive** (destination must be **Any iOS Device**, not a simulator).
   Signing is automatic. Wait for the **Organizer** window.
2. In Organizer: select the archive → **Distribute App → App Store Connect → Upload** →
   accept the defaults (automatic signing, symbols on) → **Upload**.
3. The build processes in ASC for ~5–15 min. It appears under **TestFlight** first, then becomes
   selectable on the version page.

---

## PART 8 — Attach everything & submit — ⚡ to submit, then 🍎 review

On the **1.0 version** page in ASC:
1. **Build:** click **+** / **Add Build** → select the build you uploaded.
2. **In-App Purchases:** scroll to the IAP section on the version page → **add all 7** so they
   review *with* the app (first submission only — otherwise they stay "Ready to Submit" forever).
3. **Export Compliance:** Prism Rush uses only standard/exempt encryption (HTTPS via Apple
   frameworks). Answer the encryption question → **uses standard encryption / exempt** → you do
   not need an ERN. (In Info there is no custom crypto.)
4. **Age rating, Privacy, Pricing** — confirm all green (Parts 5–6).
5. **App Review Information:** add a contact email + phone. Sign in with Apple + Game Center work
   without a demo account, so a demo login is not required; add a note:
   `No login required. IAPs unlock cosmetic characters / coin packs. Game Center + Sign in with
   Apple are optional.`
6. Click **Add for Review** → **Submit for Review**. 🍎

---

## PART 9 — After you submit

- **Review time:** typically 24–48 h for a first arcade game (can be longer).
- **TestFlight first (smart):** before/after submitting, install the build on your real iPhone
  via TestFlight and replay the Part 7.3 checklist on hardware — **haptics especially** (the sim
  can't show them).
- **If rejected:** read the message in **Resolution Center**, fix, re-archive with the **same**
  `MARKETING_VERSION 1.0` but bump `CURRENT_PROJECT_VERSION` (build number) in `project.yml`
  (`1` → `2`), re-upload, resubmit. Common first-time causes:
  - IAP not attached to the version, or Paid Apps agreement not Active (Part 0.2).
  - Privacy answers inconsistent with what the binary does (Part 5).
  - Screenshots missing for a required device size (Part 7.5).
- **Release:** choose **manual** release (you press the button) or **automatic** (goes live on
  approval). Manual is safer for a first launch.

---

## One-page quick reference (already in `docs/SHIP_CHECKLIST.md`)
Account → App ID → app record → 7 IAPs → 2 leaderboards → privacy → metadata → build/test →
screenshots → archive/upload → attach build + IAPs → submit. That's the whole gate.
