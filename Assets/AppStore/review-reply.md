# Reply to App Review — guideline 2.1, new-account information request

Apple rejected 1.0 (2) on 2026-09-20 with the standard "limited App Review
history" questionnaire. It is **not** a bug report: they asked for a screen
recording and five pieces of written information. No code change is required.

## Upload build 1.0 (3) first

The reply below says the sample hand scores **21 tai**, which is true of the
current code. The already-submitted build 1.0 (2) scores it **22**, because
it predates defaulting "Self-drawn" to off. The screen recording Apple wants
has to match the build they review, so upload 1.0 (3) — already bumped and
verified — and record against that. Otherwise change every "21 tai" below to
"22 tai" and record with build 2 still installed.

Paste the text below into **both**:

1. App Store Connect → App Review → **Reply to App Review**
2. App Store Connect → the version page → **App Review Information → Notes**
   (they explicitly ask for it in the Notes field, for future submissions)

The screen recording (their item 1) has to be made on a physical iPhone —
see the checklist at the bottom.

---

## Reply text

```
Thank you for the review. Answers to each item are below, and I have also
added them to the App Review Information notes.

1. SCREEN RECORDING

A screen recording made on a physical iPhone running the latest iOS is
attached. It starts from launching the app and shows the typical flow:
entering a winning hand by tapping tiles, scoring it, reading the
breakdown, and opening the table-payments reference sheet.

The app has no account registration, no login, and no account deletion,
because it has no accounts at all. It has no user-generated content, no
sharing between users, and no paid content or features. Nothing in the app
is gated, so the recording shows every feature the app has.

2. PURPOSE AND TARGET AUDIENCE

Mahjong Score is a scoring calculator for Taiwan 16-tile mahjong (台灣十六張).

The problem it solves: in this variant, the score for a winning hand is the
sum of many separate patterns, each worth a number of "tai". Working the
total out by hand at the table is slow and error-prone, and the patterns are
traditionally named only in Chinese, so less experienced players cannot
check the result. Players commonly settle scores from memory or argument.

What the app does: the player taps the tiles of the winning hand into a
grid, sets the round wind, seat wind, and a few conditions, and the app
lists every scoring pattern the hand qualifies for, with the Chinese name,
a plain-English explanation, and the tai value of each, plus the total.

Target audience: people who play Taiwan 16-tile mahjong socially — in my
case my own family and regular playing group. It is a personal-scale
utility, not a game and not a gambling app.

3. SETTING UP AND ACCESSING THE MAIN FEATURES

No setup, login, credentials, configuration, or sample files are needed.
The app works fully offline from the moment it is installed. There is no
onboarding to complete and nothing to unlock.

To score a hand from a cold launch:

  a. The tile grid fills the top of the screen. Tap the row labelled
     "Exposed" to select it, then tap the 5-dots tile (in the "Dots 筒" row)
     three times.
  b. Tap the row labelled "Concealed" to select it, then tap, in order:
     1-character, 2-character, 3-character (the "Characters 萬" row);
     the 1-dot tile three times; 1-bamboo, 2-bamboo, 3-bamboo (the
     "Bamboo 條" row); the East wind tile three times; the North wind tile
     twice.
  c. Tap the first flower tile (the "Flowers" row).
  d. Tap "Score" at the bottom right.

Expected result: a total of 21 tai and a list of the scoring patterns that
make it up. The star marks the winning tile; tapping any entered tile
allows removing it or marking it as the winning tile instead.

Two things a reviewer may notice and wonder about, both intended:

  - Tapping "Score" before a complete hand is entered shows a red message
    explaining what is missing (for example, that a winning hand needs at
    least 17 tiles). This is validation, not an error state.
  - "Special situations" is a collapsed section holding rarer scoring
    bonuses. It is collapsed by default because those situations are
    uncommon.

The "Payments" button in the top right opens a read-only reference sheet
listing the traditional payments that happen outside a winning hand.

4. EXTERNAL SERVICES, TOOLS, OR PLATFORMS

None. The iPhone app uses no external services of any kind.

Specifically: no data providers, no authentication services, no payment
processors, no AI or machine-learning services, no analytics, no
advertising, no crash reporting, and no third-party SDKs or frameworks. The
app makes no network requests at all and contains no networking code. It is
built only against Apple's own SwiftUI and Foundation frameworks.

All scoring is computed on device by code included in the app. All content
(tile images, scoring rules) is bundled in the app at build time. This is
why the App Privacy section declares that no data is collected: there is no
mechanism in the app by which any data could leave the device.

5. REGIONAL DIFFERENCES

There are none. The app behaves identically in every region and on every
network. It has no region-gated features, no region-specific content, no
server, and no remote configuration, so there is nothing that could vary by
region. The interface is in English throughout, with the traditional
Chinese names of mahjong tiles and scoring patterns shown alongside the
English, as those names are part of the subject matter.

6. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL

The app does not operate in a regulated industry and contains no protected
third-party material.

On gambling specifically, since a scoring app for a tile game may raise the
question: the app does not support, simulate, or facilitate gambling. There
is no wagering, no betting, no real or virtual currency, no in-app
purchases, no prizes, and no mechanism to transfer anything of value. The
app does not connect to any gambling service. "Tai" is the traditional unit
of scoring in this variant of mahjong, in the same sense that points are
the unit of scoring in a card game; the app only counts them. It also does
not include a playable game of mahjong — it cannot be played, only used to
total a hand that was played with physical tiles away from the device.

On third-party material:

  - The tile images are my own photographs of the physical mahjong set my
    family plays with, taken by me and cropped by me for this app. They are
    not licensed, stock, or scraped images.
  - The scoring patterns are the traditional rules of Taiwan 16-tile
    mahjong, a centuries-old public-domain game. The Chinese pattern names
    are the traditional names of those patterns. The plain-English
    explanations were written by me.
  - All source code was written by me. The app includes no third-party
    code, libraries, or assets.

I have no licences or credentials to provide because the app requires none.

Thank you for your time.
```

---

## The screen recording (their item 1) — you have to make this

It must be made **on a physical iPhone**, not a simulator; Apple states
they review on real devices and asks for a recording from one. Your
iPhone 11 is fine.

**Record it:**

1. Add the screen-recording control if you have not already: Settings →
   Control Centre → add **Screen Recording**.
2. Make sure Mahjong Score is installed and has been opened at least once
   (so the developer-trust prompt is out of the way and does not appear in
   the recording).
3. Force-quit the app first, so the recording can begin with a cold launch —
   they ask for it to start with launching the app.
4. Open Control Centre, tap the record button, wait for the countdown, then
   go to the home screen.

**What to show, in this order (about 60–90 seconds is plenty):**

1. Tap the app icon on the home screen and let it launch.
2. Enter the sample hand from section 3 of the reply above, tapping at a
   normal, visible pace.
3. Tap **Score** and let the screen scroll to the result. Pause a moment so
   the total and the list of patterns are readable.
4. Scroll up to show the entered hand, then tap a tile to show the
   remove / mark-winning options, and dismiss.
5. Tap **Payments** to open the reference sheet, scroll it briefly, tap
   **Done**.
6. Tap **Clear** to show the hand resetting, ready for the next one.
7. Stop the recording from Control Centre.

**Then attach it** to your reply in the Resolution Center. If the file is
too large to attach, upload it somewhere with a public link (an unlisted
YouTube video or a Dropbox/iCloud share link both work) and put the link in
the reply text.

Do not re-record on a simulator, and do not submit a slideshow of
screenshots — both are common reasons this request gets sent a second time.
