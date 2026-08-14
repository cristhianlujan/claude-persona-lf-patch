# P0 Dual OCR Microbenchmark — 2026-08-14

## Status

**PROMISING_EXPERIMENTAL_CHALLENGER — NOT RUNTIME-PROMOTED**

This note records exact-head evidence for a second OCR family experiment. It does **not** grant P0-5 corpus credit, does **not** replace authentic human review, and does **not** authorize production.

## Governed source

- Source SHA-256: `e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7`
- Source evidence object: `be7fcf20-5f83-46d4-be0e-c80dc3ceed7c`
- Dimensions: `1536x1024`

## Canonical accepted evidence

Accuracy-only confirmation:

- exact HEAD: `7b07c6fb4a780a541aa55164f8c3def2f1636c93`
- workflow run: `31811172024`
- artifact id: `9223295221`
- artifact digest: `sha256:911bb78645c1e600d2feec5dfb0e1804d2e2477e5a4884acc5075a26e1142831`
- `lf-contract-check`: SUCCESS
- `Validate LF Packs`: SUCCESS

Extended accuracy + latency + model-hash confirmation:

- exact HEAD: `dd681d410726c5fec76e98aa93dbbbc6a45c8288`
- workflow run: `31811651869`
- artifact id: `9223477109`
- artifact digest: `sha256:1da229a11ed6a6033b9ebe88ba09e7ec8ff32f584faebec497211479705e7c2b`
- `lf-contract-check`: SUCCESS

## Engines

Baseline:

- family: `TESSERACT`
- language: `spa`
- PSM: `11`

Independent challenger:

- family: `PADDLEOCR`
- OCR version: `PP-OCRv5`
- language: `es`
- `paddlepaddle==3.2.0`
- `paddleocr==3.5.0`
- CPU execution

The experiment treats the engines as different families. Tesseract PSM variants are still a single family and are not counted as independent votes.

## Accuracy result

Eight curated technical target slices were evaluated on the same real screen. These slices are not human-adjudicated ground truth and grant zero real-corpus/P0-5 credit.

| Target | Tesseract | PaddleOCR | Reconciled |
|---|---|---|---|
| Name with accents | exact | exact | exact |
| Document number | exact | exact | exact |
| `+51` prefix | exact | exact | exact |
| Phone placeholder | exact | exact | exact |
| Email label | exact | exact | exact |
| Email placeholder | `Ej. miguelxcorreo.com` | `Ej. miguel@correo.com` | `Ej. miguel@correo.com` |
| Privacy sentence | exact | missing final period only | baseline preserved |
| Small footer | exact | exact | exact |

Summary at exact HEAD `dd681d...`:

- Tesseract exact-or-near: **7/8**
- PaddleOCR exact-or-near: **8/8**
- conservative reconciled: **8/8**
- unresolved review in these eight slices: **0**

The email correction is structural, not confidence-based: the Tesseract candidate violates an email invariant because it lacks `@`; PaddleOCR returns a structurally valid email and is therefore allowed to challenge the baseline for that slice.

## Reconciliation policy

Cross-engine confidence scores are **not calibrated against each other** and must not be compared to choose a winner.

Policy:

1. exact semantic agreement -> accept baseline;
2. challenger may auto-correct only when it repairs a machine-checkable structural violation in the baseline;
3. baseline valid + challenger invalid -> preserve baseline;
4. both structurally valid but different -> preserve baseline and record disagreement;
5. ambiguous/no baseline -> abstain / human review.

This is intentionally conservative. The second engine is a challenger, not an unrestricted majority voter.

## Latency result

At exact HEAD `dd681d...`, using one loaded PaddleOCR instance:

- initialization: `1.0613 s`
- full-screen predictions: `4.1000 s`, `3.5867 s`
- full-screen median: **3.8434 s**
- email crop predictions: `0.1405`, `0.0629`, `0.0604`, `0.0598`, `0.0600 s`
- warm email-crop median: **0.0604 s**
- crop/full-screen ratio: **0.0157**
- email recovered correctly in **5/5** crop runs

Therefore the evidence favors **Tesseract primary + selective PaddleOCR crop challenger**, not unconditional dual full-screen OCR.

## Model evidence captured

Observed model directories:

- `PP-OCRv5_server_det`
- `latin_PP-OCRv5_mobile_rec`

The extended run captured hashes for 42 files, 96,576,793 total bytes, with manifest SHA-256:

`f2a26088c196587ed32ed018f1f5b6e66226bd11c1fc615e8f7a98ad5478bf39`

Core weight hashes are recorded in `PADDLEOCR_EXPERIMENTAL_MODEL_MANIFEST_20260814.json`.

## Audit corrections made before accepting evidence

Earlier exploratory runs were not used as final evidence after audit found benchmark contamination:

- single-line Tesseract tokens were initially reconstructed using global `y` before `x`;
- the `+51` ROI included an adjacent dropdown caret;
- the privacy target did not initially cover the same semantic unit for word-level and line-level OCR;
- the first reconciler incorrectly allowed cross-engine confidence comparison.

The accepted runs listed above include all four corrections.

## Remaining gates before runtime promotion

The second family remains experimental until all of the following are satisfied:

- model source/revision is pinned end-to-end, not only file hashes after download;
- CI reproduces the exact model manifest from the pinned source;
- selective-challenger trigger policy is tested with positive and negative cases;
- broader real-screen benchmark meets the existing adoption corpus threshold;
- no regression in grouping, hierarchy, omission, atomicity, or human-review convergence;
- P0-4/P0-5 governance remains separate and no sealed holdout is used during tuning.

Current flags remain:

- `runtime_promoted=false`
- `production_authorized=false`
- `real_corpus_credit=0`
- `p0_5_credit=0`
- `holdout_accessed=false`
