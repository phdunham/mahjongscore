# Training data

Drop JPEG photos into the folder matching the tile's notation. One tile per
photo, centered, ~1/3 of the frame, plain background.

## Folder → tile

**Characters (萬)** — `1m` one · `2m` two · `3m` three · `4m` four · `5m` five · `6m` six · `7m` seven · `8m` eight · `9m` nine

**Dots / circles (筒)** — `1p` one · `2p` two · `3p` three · `4p` four · `5p` five · `6p` six · `7p` seven · `8p` eight · `9p` nine

**Bamboo (條)** — `1s` one · `2s` two · `3s` three · `4s` four · `5s` five · `6s` six · `7s` seven · `8s` eight · `9s` nine

**Winds** — `Ew` East (東) · `Sw` South (南) · `Ww` West (西) · `Nw` North (北)

**Dragons** — `Rd` Red / 中 · `Gd` Green / 發 · `Wd` White / 白

**Season flowers** — `1f` Spring 春 · `2f` Summer 夏 · `3f` Autumn 秋 · `4f` Winter 冬

**Plant flowers** — `5f` Plum 梅 · `6f` Orchid 蘭 · `7f` Chrysanthemum 菊 · `8f` Bamboo 竹

## Tips

- Fixed lighting + fixed background + varied tile rotation is ideal.
- ~30 photos per tile is a sane minimum. More for dot tiles (5p/6p/7p/8p/9p
  are the hardest for any model to distinguish).
- iPhone: Settings → Camera → Formats → **Most Compatible** (JPEG).
- When ready: open Xcode → Open Developer Tool → Create ML → Image Classifier,
  point it at this `training-data/` folder.

Run `scripts/check-training-data.sh` for a per-folder count.
