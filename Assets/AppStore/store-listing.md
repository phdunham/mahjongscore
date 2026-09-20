# App Store Connect listing — draft

Everything here is a suggestion to paste into App Store Connect. Nothing is
final until you save it there — edit freely. Character limits are Apple's.

## App Information

| Field | Value |
|---|---|
| **Name** (30 char max) | `Mahjong Score — Taiwan 16` (25 chars) |
| **Bundle ID** | `com.pdunham.mahjongscore` |
| **SKU** | `mahjongscore-ios` (anything unique to you; testers never see it) |
| **Primary language** | English (U.S.) |

"Mahjong Score" alone has no exact match on the App Store today, but close
names ("Score Mahjong", "Mahjong Scorer") already exist — adding "Taiwan 16"
makes it distinct and tells testers what it actually scores. Change it to
anything you like; it only affects what testers and TestFlight show.

## Version 1.0 information

| Field | Value |
|---|---|
| **Subtitle** (30 char max) | `Taiwan 16-tile hand scoring` (28 chars) |
| **Category** | Primary: Utilities · Secondary: none needed |
| **Copyright** | `2026 Paul Dunham` |

**Promotional text** (170 char max — the only field you can edit later
without a new review):
```
Tap in a Taiwan 16-tile winning hand and get the full tai breakdown —
round/seat wind, flowers, wait type, and every pattern explained in
plain English.
```

**Description** (4000 char max):
```
Score a Taiwan 16-tile mahjong winning hand in about 20 seconds.

Tap tiles into Concealed, Exposed, and Flowers — the app tracks how many
of each you've used and marks your winning tile automatically. Set round
wind, seat wind, and dealer, and Mahjong Score works out the wait type and
every scoring pattern for you, each one named in Chinese and explained in
plain English.

FEATURES
• Tap-to-enter grid with photos of real mahjong tiles
• Full tai breakdown, pattern by pattern
• Round/seat wind, dealer, self-drawn, and declared-ready handled for you
• "Special situations" for the rarer bonuses (won on the last tile, won
  after a kong, heavenly/earthly/human hand, and more) explained in plain
  language, not just Chinese terms
• A reference sheet for the payments that happen outside a winning hand —
  dice-roll penalties, flower-set payouts, and procedural penalties
• Works entirely offline. No account, no ads, no data collection.

This app targets one specific rule set: Taiwan 16-tile mahjong (台灣
十六張), the HK/Taiwan variant with flowers, tai scoring, and a fixed base.
It does not score Riichi/Japanese, American, or Chinese Official (MCR)
mahjong.
```

**Keywords** (100 char max, comma-separated, no spaces after commas — every
character counts):
```
mahjong,taiwan,16 tile,tai,score,scorer,scoring,flower,hand,calculator
```

**Support URL:** `https://github.com/phdunham/mahjongscore/issues`
**Marketing URL** (optional): `https://github.com/phdunham/mahjongscore`
**Privacy Policy URL:** `https://github.com/phdunham/mahjongscore/blob/main/PRIVACY.md`

## App Privacy questionnaire

The iPhone app makes no network requests and has no camera, photo, or
location access — the only stored data is your table settings, kept on
your device via `UserDefaults`. In App Store Connect → App Privacy, answer:

> **Do you or your third-party partners collect data from this app?**
> **No, we do not collect data from this app.**

That's the entire questionnaire — Apple skips the rest once you select
"No."

## Age rating questionnaire

Every question (violence, gambling, alcohol, mature content, etc.) should
be answered **None / No** — the result will be **4+**. The base-tai stakes
in the app are a scoring convention, not real-money gambling, so the
"Simulated Gambling" question is also **No**.

## Screenshots

`Assets/AppStore/Screenshots-6.9in/` — three screenshots at 1320×2868px
(Apple's required 6.9" iPhone size; App Store Connect scales them down for
smaller devices automatically):

1. `1-tile-entry.png` — the tile grid, photos of the real tile set
2. `2-score-breakdown.png` — a scored hand with the full tai breakdown
3. `3-table-payments.png` — the table-payments reference sheet

Apple requires at least one screenshot set; these three are enough. You can
add up to 10 per device size later without a new build.

## Build

| Field | Value |
|---|---|
| **Marketing version** | 1.0 |
| **Build number** | 1 |
| **Minimum iOS** | 17.0 |
| **Devices** | iPhone only |
| **Encryption** | None (already declared in Info.plist — no prompt at upload) |
