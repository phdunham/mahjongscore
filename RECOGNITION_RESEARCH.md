# Mahjong tile recognition — approach research

> Compiled 2026-04-19. Goal: balance accuracy vs human effort for Taiwan
> 16-tile winning-hand recognition on macOS / Apple Silicon.

## Executive summary

The realistic 95%+-accuracy offline path is a **YOLOv8/v11 detector trained
on a few hundred annotated tile photos, exported to CoreML, with an optional
42-class image classifier as a second-stage refiner**. Public 42-class
mahjong-detection models on Roboflow Universe report near-100% mAP, but **none
target Taiwan tile art** — the eight Taiwan flowers (春夏秋冬 + 梅蘭菊竹) differ
visually from Riichi flowers, so any pre-trained model needs flower-class
fine-tuning. The cheapest accuracy win available now is prompt engineering
plus a Claude-driven active-learning loop that bootstraps a local classifier;
the existing pipeline already has Claude as the labeling oracle. Apple's
`VNDetectRectanglesRequest` is a poor fit — community feedback consistently
reports it merges or misses adjacent rectangles, which is exactly the
geometry of a real winning hand. End-to-end CRNN "image → tile sequence"
is technically tractable but overkill since detection-then-classify already
ships in working Riichi projects. The single biggest specific risk —
pin/dot confusion — is best fixed with **crops**: a 42-class classifier on a
tightly-cropped tile face is a near-trivial closed-set problem (≤9 dots,
small ResNet/MobileNet >99%); the dot-counting failure only happens when the
model stares at a 22-tile composite.

## Comparison table

| Approach | Realistic accuracy | Setup effort (dev hours) | Apple-Silicon latency | Maintenance | Public assets | Top failure mode |
|---|---|---|---|---|---|---|
| 1. Vision rectangles + CoreML classifier | 70–85% (rectangle stage is the bottleneck) | 8–20h | <50ms total | Low | None tile-specific | Touching tiles merged into one rectangle |
| 2. YOLOv8/v11 detector (CreateML or Ultralytics) | 95–99% with ~500–2000 labeled images | 30–80h annotation + training | 15–40ms (yolov8n CoreML, ANE) | Medium | Roboflow Universe — 5+ mahjong datasets, several with 42 classes | Flower-art mismatch vs Taiwan set |
| 3. Two-stage row-detect → fixed slice | 85–92% (fragile to perspective) | 10–20h | <30ms | High (geometry tweaks) | None published | Half-raised winning tile breaks the slice |
| 4. End-to-end CRNN/transformer | 90–95% theoretical, no shipped baseline | 60–120h + ML expertise | 30–80ms | High | None for mahjong; LP/OCR analogs only | Hard to debug; needs sequence-ordered labels |
| 5. Claude API + prompt eng. + cache | 92–97% (pin tiles still the weak spot) | 2–6h | 1–3s network | Very low | N/A | Cost & offline goal unmet |
| 6. Claude-as-labeler active learning | 95–98% after ~500–1500 hands | 4–12h glue + ongoing review | Same as model trained into | Low (Claude carries new edge cases) | Existing pipeline is the labeler | Label noise on the very tiles we want to fix (pins) |
| 7. Fork an existing GitHub project | 90–99% on its native art | 10–40h | 15–40ms | Medium | lissa2077/Mahjong-Detection (YOLOv3/v4), saki-rinshan, hlin117/mahjongCV | Trained on Riichi tiles; won't transfer to Taiwan flowers |
| 8. Pure synthetic training | 60–80% on real photos w/o adaptation | 20–60h | Same as #2 | Medium | Camerash dataset has clean tile faces | Sim-to-real gap, especially gloss/lighting |

## Per-approach notes

### 1. `VNDetectRectanglesRequest` + CoreML classifier

Vision's rectangle detector finds quads via edge/contour analysis. Documented
strengths: isolated rectangles surrounded by background contrast (credit
cards, business cards, document scanning). For touching mahjong tiles, the
only visible edges are tops/bottoms of rows and short vertical seams between
adjacent tiles — Vision either returns one giant rectangle per row or fails
on the seam contrast. **No published mahjong benchmark exists**, but
developer-forum consensus is that adjacent-rectangle separation is what the
API does *not* do well. Useful only with a Sobel-based seam-detection
preprocessing pass; skip in favor of #2.

### 2. Trained YOLO detector

Dominant approach in the mahjong-recognition GitHub ecosystem. Modern
Roboflow Universe entries ship YOLOv8/v11 weights with **42 classes**
(matching our tile count exactly) — but classes use Riichi naming, not the
8 distinct Taiwan flowers. Need to relabel flowers and fine-tune.

**Annotation cost realism.** CreateML guidance is "30 images per class
minimum." For 42 classes that's 1,260 tile instances, but each photo has
16–22 tile boxes, so **80–150 photos is the floor**, 300–500 is comfortable.
At 30–90 sec/photo to draw boxes (touching-tile photos are fast — boxes snap
to row geometry), that's **~5–15 hours of pure annotation labor**. Roboflow,
CVML, or Vaida12345/Annotation help.

**Accuracy.** YOLOv9 hits "near 100%" mAP on closed-set tile detection.
YOLOv8s/m on public Roboflow datasets list mAP@0.5 in the 0.95–0.99 range.
Drops on real-photo lighting/gloss; expect **95–98% per-tile real-world**.

**Latency on Apple Silicon.** Ultralytics' CoreML export targets the ANE.
Published numbers are sparse but yolov8n on M1 ANE ~10–25ms at 640 input,
yolov8s ~20–40ms. Caveat: open Ultralytics issues #6788/#14668/#17889
about CoreML export discrepancies — validate post-export numerically.
CreateML's Object Detection template avoids the export pitfalls but offers
less architectural control.

**Failure modes.** Tightly touching tiles can produce IoU>0.6 between
adjacent boxes during NMS — set `iou_threshold` lower (0.3–0.4) for
inference. Half-raised winning tile is a different aspect ratio + lighting;
include several examples in training.

### 3. Row-detect → fixed slice

Find the long horizontal strip(s) via OpenCV/Vision edges or a tiny
segmentation model, divide each strip's width by 16 (or visible-tile count)
using known aspect ratio, run a 42-class classifier on each crop.

**Why appealing:** no object-detection annotation needed, just row masks.
And classification at 42 closed classes with clean crops is the easiest task
in this pipeline — MobileNetV2 transfer-learned on 30–80 images per class
hits 98–99%, dissolving the pin-tile problem.

**Why it breaks:** real photos rarely have axis-aligned rows; half-raised
winning tile shifts the slice grid; angled photos compress widths unevenly;
tile counts aren't always 16/16 (sometimes 17 with the winning tile aside).
No published mahjong project documents this as their primary pipeline.
`hlin117/mahjongCV` uses homographies for the rectification step (the
principled version) but is non-trivial to make robust.

### 4. End-to-end CRNN/transformer

Conceptually license-plate recognition: CNN backbone → BiLSTM/transformer →
CTC loss aligns emitted tile-class sequence to labels. Strengths: no bbox
annotation, output is naturally a sequence. Weaknesses: CTC is data-hungry
(5–10k labeled sequences typical for non-trivial alphabets); harder to debug
without per-tile localization; multi-row hands break left-to-right scan.
**Zero published work** applying CRNN to mahjong specifically. Overkill
since detection works.

### 5. Stay on Claude API

Two concrete wins available:

- **Crop-and-re-ask uncertain pins.** When Claude returns a 5p–9p, crop the
  bbox and send a focused single-tile prompt: *"How many red dots are
  visible? 1–9?"*. Claude's spatial reasoning on a single face is much
  better than on a 22-tile composite. Anthropic flags counting many small
  objects as a known weakness; cropping sidesteps the small-object regime.
- **Few-shot reference imagery.** Multimodal best-practices guidance shows
  reference images materially improve performance. Send 9 reference crops
  of 1p–9p once per session in a cache-able prefix.

Doesn't satisfy "fully offline" but at $0.01–0.03/photo plus ~$0.005 for
re-asks, **cheapest path to 97%+ accuracy today**.

### 6. Active-learning loop (Claude → local model)

Best long-run effort/accuracy ratio. We already have a working oracle
labeling photos. Save every photo + Claude's tile list (existing
`CorrectionsLog.swift` captures user corrections too — gold). After
~500–1500 labeled hands we have enough to train an offline detector or
detector+classifier stack.

**Minimum dataset for "good enough" offline:**
- 30–50 instances per class is the floor for transfer-learned models
- 100–200 instances per class for production
- That's 4,200–8,400 tile instances total at ~17 tiles/photo = **250–500
  hands for v1, 500–1,500 for production-grade**

**Risk:** Claude's pin-tile errors leak into training labels.
Mitigations:
1. Manually review pin-tile labels before training (~10 min/hand average for
   500 hands).
2. Claude self-consistency: ask twice with different temperatures, only
   auto-accept on agreement.
3. Pre-crop and ask Claude per-tile (#5) for clean per-tile pseudo-labels.

### 7. Existing GitHub mahjong projects — usability for Taiwan tiles

| Project | Architecture | Tiles | Useful? |
|---|---|---|---|
| Camerash/mahjong-dataset | Dataset only, scraped 240×320 tile faces, CSV labels | Chinese | Yes — source images for synthetic compositing or classifier seed |
| lissa2077/Mahjong-Detection | YOLOv3 + YOLO-tiny v4 (Darknet) | Riichi | Architecture dated; concept transfers; weights won't |
| hlin117/mahjongCV | OpenCV + homographies + classifier | Older | Reference for rectification |
| elise-ng/COMP4901J_Project | Denoising CAE + CNN classifier | Chinese | Academic, not production |
| saki-rinshan/RiichiMahjongCalculatorBackend | Backend for a recognizer app | Riichi | Full-stack reference |
| Roboflow jon-chan-gnsoa/mahjong-baq4s | YOLOv8/v11, **42 classes** | Riichi | Best off-the-shelf weights to fine-tune from |
| Roboflow riichimahjongdetection/chinese-mahjong-detection | YOLOv8, **42 classes**, 1.8k images | Chinese | Strong fine-tune starting point |
| Hirvola 2019 (Aalto MS thesis) | CV-based mahjong detection from video | Riichi | Useful methods chapter |

**Taiwan-specific:** zero hits. The 8 flower tiles with Chinese characters
are visually distinct from Riichi flowers (simpler kanji), so any Riichi-
trained model needs flower-class refinement.

### 8. Synthetic data

Composite tile-face images (Camerash) onto random backgrounds with random
lighting/perspective/blur/occlusion. Pure synthetic training lands 60–80%
real-photo accuracy without adaptation. Closing to >95% needs (a)
style-transfer/diffusion-based domain adaptation, or (b) fine-tuning with
~100–300 real photos. Best ROI: **synthetic pretraining + 100–300 real
photos** — halves real-annotation effort vs #2.

## Three concrete paths, ordered by effort

### Path A — Smallest effort (~6–10h), keep Claude

Stay on the API but eliminate the pin-tile failure mode and start
collecting training data:

1. Per-tile crop-and-re-ask for any tile Claude returns as 5p–9p. Use a
   tight prompt and reference images in a cached prefix.
2. Confidence-routed re-ask: ask Claude to output a confidence per tile;
   route low-confidence ones through the same per-tile re-ask.
3. Save photo + final label set + user corrections to a structured
   directory tree (already in place via `CorrectionsLog` /
   `TrainingDataSaver`). Silently builds the dataset for offline training.

Expected outcome: **96–98% per-tile**, $0.02–0.04/photo, no offline mode
but the dot-counting failure is gone.

### Path B — Medium effort (~30–60h), hybrid offline

Train a CoreML detector + classifier and ship offline-first with Claude
as fallback:

1. Take 200–400 photos of real winning hands across usual table/lighting.
   Annotate boxes+classes (or, faster: use Claude to pre-label, then
   human-correct only the boxes).
2. Fine-tune `yolov8s` from a Roboflow Riichi 42-class checkpoint, relabeling
   flower classes for Taiwan. ~30–60 min/epoch on M-series GPU; ~30 epochs
   typical.
3. Export to CoreML via Ultralytics' exporter; if hitting iOS/M1 issues
   (#6788/#14668), fall back to CreateML's Object Detection template
   trained on the same data.
4. Optional: per-crop 42-class MobileNetV2 classifier (CreateML Image
   Classification) as a confidence-boosting second stage.
5. Keep Claude as fallback for low-confidence whole-photo cases.

Expected outcome: **96–99% per-tile offline**, <50ms end-to-end on M1+.
Pin-tile problem dissolves because the classifier sees a single isolated face.

### Path C — Largest effort (~80–150h), fully offline production

Full active-learning loop + synthetic pretraining:

1. Build a synthetic compositor using Camerash tile faces + random table
   backgrounds (4–8h). Generate 20–50k synthetic photos with perfect labels.
2. Pretrain `yolov8s` on synthetic — gets ~70–80% real-photo accuracy
   with zero manual labels.
3. Run Claude pipeline as labeler on ~1,000 real photos; manually review
   pin-tile labels.
4. Fine-tune the synthetic-pretrained model on real labels.
5. Ship fully offline with on-device retraining loop: every user correction
   becomes a future fine-tune sample.

Expected outcome: **>99% per-tile, fully offline, robust to lighting and
new tile-set variants**. Real ML engineering effort and ongoing model
maintenance.

## Honest gaps in this research

- No published per-millisecond benchmark for yolov8n/s on the M1/M2/M3 ANE
  specifically — the 10–40ms range is interpolated from Photoroom's CoreML
  benchmark and Ultralytics general guidance.
- No paper or project measures Claude's mahjong-tile accuracy quantitatively;
  the ~90–95% / pin-tile-fail observation is novel data.
- Whether Roboflow's 42-class datasets cover Taiwan flower art wasn't
  directly verified — only that the class count matches. Download and
  inspect before fine-tuning.
- Minimum-dataset numbers come from CreateML guidance and general
  transfer-learning lore, not a mahjong-specific study.

## References

GitHub:
- https://github.com/Camerash/mahjong-dataset
- https://github.com/hlin117/mahjongCV
- https://github.com/elise-ng/COMP4901J_Project
- https://github.com/lissa2077/Mahjong-Detection
- https://github.com/sbaruzza/mahjong-opencv
- https://github.com/saki-rinshan/RiichiMahjongCalculatorBackend
- https://github.com/topics/mahjong-tiles
- https://github.com/bgshih/crnn
- https://github.com/Vaida12345/Annotation
- https://github.com/Doriandarko/Claude-Vision-Object-Detection
- https://github.com/hoangtheanhhp/CodeProject.AI-ObjectDetectionYOLOv8-coreml-apple-silicon-gpu

Roboflow datasets:
- https://universe.roboflow.com/test-upsgd/mahjong-tiles-oc9zz
- https://universe.roboflow.com/test-wmo8i/mahjong_yolo
- https://universe.roboflow.com/mahjong-i2y79/mahjong-image-detection
- https://universe.roboflow.com/jon-chan-gnsoa/mahjong-baq4s
- https://universe.roboflow.com/mahjong-jsgiv/mahjong-cv
- https://universe.roboflow.com/riichimahjongdetection/chinese-mahjong-detection
- https://universe.roboflow.com/riichimahjongdetection/riichi-mahjong-detection
- https://universe.roboflow.com/hust-xq5rx/riichi-mahjong/dataset/8

Other:
- https://medium.com/@jalee18/mahjong-tile-detection-with-deep-learning-using-u-net-cnn-with-tile-type-classification-750638862a46
- https://aaltodoc.aalto.fi/bitstream/handle/123456789/38947/master_Hirvola_Ossi_2019.pdf
- https://arxiv.org/pdf/1906.02146
- https://csci527-phoenix.github.io/documents/Paper.pdf
- https://www.kaggle.com/datasets/mexwell/mahjong
- https://courses.ece.cornell.edu/ece5990/ECE5725_Spring2024_Projects/01%20Friday%20May%2010/04%20Embedded%20Mahjong%20Player/Monday_group3_rz367_sy625/website/index.html

Apple / Vision / CoreML:
- https://developer.apple.com/documentation/vision/vndetectrectanglesrequest
- https://developer.apple.com/videos/play/wwdc2021/10041/
- https://developer.apple.com/videos/play/wwdc2019/424/
- https://developer.apple.com/documentation/createml/building-an-object-detector-data-source
- https://developer.apple.com/forums/thread/81659
- https://www.dabblingbadger.com/blog/2020/2/10/rectangle-detection
- https://medium.com/@s.deluca/swift-detecting-rectangles-5c15209f6601
- https://www.createwithswift.com/creating-an-object-detection-machine-learning-model-with-create-ml/
- https://hackernoon.com/how-to-label-data-create-ml-for-object-detection-82043957b5cb
- https://evilmartians.com/chronicles/object-detection-with-create-ml-images-and-dataset
- https://evilmartians.com/chronicles/object-detection-with-create-ml-training-and-demo-app
- https://apple.github.io/coremltools/docs-guides/source/opt-overview.html
- https://www.photoroom.com/inside-photoroom/core-ml-performance-benchmark-2023-edition

Ultralytics YOLO:
- https://docs.ultralytics.com/integrations/coreml/
- https://docs.ultralytics.com/modes/benchmark/
- https://github.com/ultralytics/ultralytics/issues/6788
- https://github.com/ultralytics/ultralytics/issues/14668
- https://github.com/ultralytics/ultralytics/issues/17889
- https://www.researchgate.net/publication/394305460_Benchmarking_YOLOv8-Tiny_for_Real-Time_Object_Detection_on_macOS

Anthropic Claude vision:
- https://platform.claude.com/docs/en/build-with-claude/vision
- https://platform.claude.com/cookbook/multimodal-best-practices-for-vision

Sim-to-real / domain adaptation:
- https://ai.bu.edu/syn2real/
- https://openaccess.thecvf.com/content_ECCVW_2018/papers/11129/Hinterstoisser_On_Pre-Trained_Image_Features_and_Synthetic_Images_for_Deep_Learning_ECCVW_2018_paper.pdf
- https://lilianweng.github.io/posts/2021-12-05-semi-supervised/
- https://www.nature.com/articles/s41598-023-50598-z

Mahjong rules:
- http://mahjong.wikidot.com/rules:taiwanese-overview
- https://en.wikipedia.org/wiki/Mahjong_tiles
- https://riichi.wiki/Mahjong_equipment
