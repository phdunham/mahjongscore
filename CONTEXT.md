# Mahjong Score — Project Context Summary

## Project
Taiwan 16-tile mahjong scorer. Mac SwiftUI app (`Sources/MahjongScoreApp/`) + `MahjongCore` Swift library. Runs as `swift run MahjongScoreApp` or as `build/MahjongScore.app` (built via `scripts/build-app.sh`). 116/116 tests passing.

## Architecture

**`MahjongCore` library** — pure Swift, no UI:
- `Tile.swift`: enum with cases for numeric/wind/dragon/flower; ASCII notation (`1m`–`9m`, `1p`–`9p`, `1s`–`9s`, `Ew/Sw/Ww/Nw`, `Rd/Gd/Wd`, `1f`–`8f`); Unicode glyph property; comparable+hashable
- `Meld`/`Hand`/`WinContext`: validated data model (5 melds + eye + flowers + winning tile)
- `Scorer`/`Decomposer`/`WaitInference`: scoring engine for ~56 of 88 patterns from twmahjong.com (Wave 1+2 done; Wave 3 deferred — `Rules.json` is the source of truth, see `RULES.md`)
- Recognition layer: `RecognizedTile` (tile + bbox + confidence), `ImageRecognizer` protocol, `ClaudeRecognizer` impl

**`MahjongScoreApp` target**:
- `ContentView.swift`: 3-section layout (top: photo + tile rows, middle: context form, bottom: score)
- `TileViews.swift`: `TileCard`, `TilePickerView` (modal flat 42-tile picker), `IdentifiedTile` (UUID-tracked, carries bbox + confidence)
- `APIKeyStore`: Keychain wrapper for Anthropic API key
- `CorrectionsLog` + `TrainingDataSaver`: save photo + cropped tile training samples to `~/Library/Application Support/MahjongScore/`
- `TrainingCoordinator` + `TileClassifier` + `LocalRecognizer`: CreateML training loop + offline recognizer (built but not yet useful — needs accumulated training data)

## Current state of recognition (Path A complete)
ClaudeRecognizer does two-pass: first-pass whole-image with structured tool_use → `RecognizedTiles` (rows + bboxes + per-tile confidence). Second pass re-verifies low-confidence tiles + ALL pin tiles below 0.95 + ALWAYS the winning tile, by cropping the bbox and sending a focused single-tile call. Prompt caching via system block + `cache_control: ephemeral` cuts repeat-call cost ~30–50%.

## Recent UI work
- Bigger tiles (64×88, 50pt glyphs)
- Click any tile → modal picker with all 42 tiles + Mark winning + Delete (2 clicks total per correction)
- Photo display 320×320 with click-to-enlarge modal
- Click empty photo placeholder → file picker
- Rotate buttons under photo, auto-re-runs recognition
- Low-confidence tiles get amber border + ⚠ badge
- Winning tile: half-raised + accent border + ★ badge
- HEIC support: `preparePhotoForAPI` decodes via CGImageSource → reads EXIF orientation → applies via Core Image `oriented(_:)` → fallback rotate 90° CW if still portrait (since winning hands are always landscape) → resize to ≤2048 long edge → JPEG q 0.85 (under Anthropic's 5 MB limit)

## Just shipped
Fixed the "iPhone photos load rotated 90°" bug by adding a portrait→landscape fallback in `preparePhotoForAPI` after the EXIF path, plus extracted `rotateCGImage` as a shared helper used by both the auto-orient and manual rotate buttons.

## Memory files (in `~/.claude/projects/-Users-pdunham-work-mahjongscore/memory/`)
- `project_overview.md` — Taiwan 16-tile, Mac-first → iPhone, Claude vision v1, twmahjong.com rules
- `how_to_run.md` — `swift run MahjongScoreApp` or `bash scripts/build-app.sh && open build/MahjongScore.app`
- `training_workflow.md` — Phase 7-B CoreML path
- `accuracy_backlog.md` — items 1+3 (winning-tile re-verify, prompt caching) and 2 (confidence indicator) shipped; remaining: **5** (few-shot reference imagery — biggest open easy win), 6 (smarter cropping for re-verify), 7 (hand history panel), Path B (train YOLOv8 detector when dataset is large enough), Path C (synthetic data + active learning)

## Reference docs in repo
- `RECOGNITION_RESEARCH.md` — full comparison of recognition approaches with effort/accuracy table
- `RULES.md` — Taiwan tai patterns reference

## Likely next tasks
- Item 5: few-shot reference imagery (5p–9p reference crops in cached system prefix) — biggest remaining easy accuracy win for pin tiles
- Item 7: hand history panel
- Path B kickoff: when training-data folder hits ~30+ samples per class, fine-tune YOLOv8 from Roboflow's 42-class chinese-mahjong-detection checkpoint

## App.swift note
`AppDelegate` forces `setActivationPolicy(.regular)` + `activate()` so the SwiftPM-launched executable surfaces a window (no real `.app` bundle Info.plist).
