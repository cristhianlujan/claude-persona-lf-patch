# OCR research report — UI screenshots

Status: applied research complete on 2026-08-12. Production adoption remains blocked. This report does not declare human acceptance, autonomous readiness, P0-5, or production authorization.

## Reconciliation note for PR #140

This file preserves the detailed research reasoning from the source artifact supplied to the continuation chat. The source artifact reports an implemented one-screen benchmark and names `ground_truth_real_screen_001.json` plus `ocr_benchmark_ui_v1.py`. Those producer artifacts are not present in PR #140 at reconciliation time, so their historical result is retained as research context but is **not** represented here as a fresh exact-HEAD rerun.

Verified independently in the current lot:

- persistence V2 contract executed 20/20 PASS with transaction rollback and zero committed test rows;
- real historical packet was reconstructed into the new persistence graph as `EXEC-P0-REAL-PERSIST-NORM-20260812-001` with 97 elements, 97 evidence units, 97 links and zero orphans;
- current acceptance remains `BLOCKED_REAL_EVIDENCE`.

This separation follows EKB `AUD-008`, `ARC-006`, `EKB-P0-011`, and `EKB-P0-017`.

## Executive conclusion

The safest architecture for this workload is a cascade, not a single OCR call:

1. decode and bind the immutable source;
2. detect text tokens and boxes;
3. detect controls/icons with an independent visual modality;
4. infer layout/reading order from geometry and control boundaries;
5. recognize text per bounded region;
6. assign every evidence unit exclusively;
7. run an independent omission sweep and a calibrated residual gate.

This directly addresses column mixing, shared evidence, missed compact controls, and tautological coverage. A document-layout engine can be a candidate detector, but document benchmarks do not establish accuracy on application screenshots. UI-specific parsers such as ScreenAI, OmniParser, UIED, and RICO-derived models are more transferable for controls and spatial semantics, while document OCR remains useful for text recognition.

The uploaded source report states that a one-screen layout-zone experiment did not beat the strict reader: reading-order accuracy improved while CER, WER, text F1, small-text recall, and bbox IoU worsened. Because the benchmark producer/truth files are absent from PR #140, this remains a historical experiment result rather than a reexecuted current-HEAD result. PaddleOCR, docTR, cloud OCR, ABBYY, and UI-specific learned parsers remain benchmark candidates only after governed weights/credentials, privacy review, and a sufficient real-screen corpus exist.

## 1. Architecture for columns and reading order

Use token-first detection plus a layout graph. Never accept a full-page OCR line as a semantic field merely because tokens share a Tesseract line id. Split on large geometric gaps, panel/field boundaries, and control containers; then order blocks by container and local reading direction.

The source research cites Tesseract page segmentation documentation and quality guidance as evidence that segmentation is configurable but is not a UI semantic layout contract. It also cites Ray Smith's layout work as precedent for treating layout analysis as a distinct problem.

PP-StructureV3 is identified as a relevant candidate because it separates layout detection, text recognition, and structure recovery. DBNet and CRAFT are relevant detector families because they produce text regions before recognition. They still require a UI-aware grouping layer.

Operational implication for LF:

- detect first, group second;
- never let Tesseract `line_num` become business/UI ownership by itself;
- evaluate cross-column merges and field-boundary merges explicitly;
- atomic coverage must remain injective (`EKB-P0-003`).

## 2. Separation of concerns

| Stage | Output | Must not decide |
|---|---|---|
| Text detection | token/line polygons | semantic field ownership |
| Recognition | string + confidence | reading order across panels |
| Layout | containers, adjacency, order | icon meaning without evidence |
| Semantic grouping | field/control relationships | new pixels or duplicated tokens |
| Icon/control detection | type-neutral geometry first | business intent from shape alone |
| Omission audit | independent denominator | reusing only reader candidates |

The architecture must expose producer→consumer provenance for each required field. This is not optional: EKB `AUD-008 / PRV-AUD-008` records a prior failure where a grader consumed a field no real producer emitted.

## 3. Truly independent omission modality

The minimum practical independent audit is geometry/edges/connected components that does not consume the primary OCR candidate list, combined with specialized control/icon detection. A stronger future audit uses a different learned family and weights, such as a UI parser or scene-text detector, while keeping its output out of the primary reader's denominator.

The source research identifies OmniParser, ScreenAI, and UIED as UI-oriented candidates for interactable-region and component understanding. These are better future omission-audit families than a second Tesseract PSM because PSM variants share an engine family and correlated errors.

EKB reinforcement:

- `EKB-P0-017 / PRV-P0-017`: Tesseract PSM variants do not count as a second OCR family.
- `ADR-P0-008`: do not declare OCR diversity until a second governed family exists.
- OpenCV/Canny remains a genuinely different visual modality for geometry/control evidence, but it is not a second OCR engine.

## 4. Residual calibration

Residuals should be computed after masking explained material regions, then classified by connected-component features rather than raw changed-pixel count. Calibrate separate distributions for text edges, control borders, antialiasing, shadows/gradients, and illustrations. Thresholds must be learned from versioned labeled screens and reported with false-positive/false-negative curves.

Until at least ten authorized real screens exist, residual output remains `BLOCKED_UNCALIBRATED`.

The policy is not “each pixel exactly once.” Background and rendering effects may be multiply covered or deliberately ignored; material controls and text must be explained or block with a traceable exception.

EKB `EKB-P0-018 / PRV-P0-018` adds a hard governance rule: any threshold that changes the material denominator must be versioned, justified, bound to config/receipt, and regression-tested below/at/above the cut.

## 5. Metrics

| Target | Primary metric | Required diagnostic |
|---|---|---|
| Text transcription | CER, WER | Spanish/diacritic and small-text slices |
| Text detection | precision/recall/F1 | mean IoU and center-distance failures |
| Controls/icons | precision/recall/F1 | recall by type and size |
| Cardinality | exact-match rate | under/over-count by repeated group |
| Grouping | field-group exact match | cross-column and cross-control merges |
| Reading order | pairwise order accuracy | container-level order |
| Evidence | duplicate-owner rate | orphan relevant-evidence rate |
| Atomicity | zero overmerge | `ATOMIC_ELEMENT_OVERMERGE` count |
| Coverage | unexplained-material rate | denominator producer family |
| Robustness | mutation escape rate | per-family rate, not aggregate only |
| Operation | p50/p95 latency, memory, cost | offline/egress/credential dependency |

Document/scene OCR benchmarks can inform metric design, but their data distribution is not a substitute for desktop financial onboarding screenshots.

## 6. Spanish, small text, truncation, and low contrast

Pin the Spanish traineddata hash and runtime version; slice CER for accents and punctuation; retain token boxes before grouping; upscale only within a declared preprocessing variant; test low-contrast and small-height bands separately. Truncation is a visual state, not permission to autocomplete hidden text. Recognition confidence cannot override source visibility.

The source report cites multilingual Tesseract work and PP-OCRv5 multilingual capability. Those are capability references, not proof on LF UI.

EKB `EKB-P0-020 / PRV-P0-020` adds:

- short/ambiguous OCR fragments need corroboration before entering the material denominator;
- real short labels must remain protected by positive regressions;
- when the primary pass misses a unit but two alternative passes agree spatially and textually, a corroborated fallback may be used under the governed policy.

## 7. Mutation and ablation evidence

Mutation campaigns must target omission, duplicate ownership, unjustified fragmentation, and compact-control deletion independently, with at least 100 deterministic mutations per family. Ablation should hold control detection constant while replacing only OCR/layout; otherwise a text experiment can appear to improve by silently changing the denominator.

Minimum campaign:

- 100 delete-material-element mutations;
- 100 delete-compact-non-text mutations;
- 100 merge-sibling-evidence mutations;
- 100 unjustified-text-split mutations;
- 400/400 detection required;
- zero escapes.

EKB `EKB-P0-011 / PRV-P0-011` strengthens this: fixtures alone are not sufficient for a critical gate. At least one representative mutation per critical invariant must be executed on a real source-bound candidate when available, and the unmodified positive must be rerun afterward.

Metamorphic relations are useful when labels are scarce — for example stable reading under lossless scaling or harmless padding — but do not replace real ground truth.

## 8. Operational viability

| Candidate | Offline/privacy | Cost/latency | Current disposition |
|---|---|---|---|
| Tesseract 5 | offline; open-source project | low dependency; CPU latency observed | retained baseline |
| PaddleOCR / PP-StructureV3 | can run offline after governed model acquisition | larger runtime/model footprint | deferred benchmark |
| docTR | can run locally with pinned detector/recognizer weights | deep-learning runtime and weights | deferred benchmark |
| Google Document AI / Cloud Vision | managed external processing | billed service; data egress/credentials | deferred pending privacy and credentials |
| Azure Document Intelligence | managed external processing | billed service; data egress/credentials | deferred pending privacy and credentials |
| AWS Textract | managed external processing | billed service; data egress/credentials | deferred pending privacy and credentials |
| ABBYY | proprietary/local or service depending product | license and deployment review required | deferred procurement benchmark |
| UI parsers | local possible depending model/license | model/GPU and domain validation | preferred future independent audit candidate |

No vendor capability page is treated as comparative accuracy evidence on the present LF screen.

## 9. Ensemble, cascade, detector, or replacement

Choose a cascade. Keep the source-bound CV detector and exclusive evidence model, use OCR as one recognition modality, and add a genuinely different audit family later. Do not ensemble two correlated Tesseract PSM outputs as if they were independent.

Replacement is justified only when the same versioned corpus shows better target metrics without HIGH/MEDIUM regression and with acceptable cost/privacy.

The evidence model must remain exclusive even if the OCR engine changes: one source evidence unit cannot justify two materially independent PASS elements.

## 10. Transferability

Transferable to UI screenshots:

- token boxes;
- explicit layout graphs;
- UI-specific component detection;
- exclusive evidence ownership;
- control cardinality;
- reading-order metrics;
- independent omission auditing.

Only partially transferable:

- document layout parsers, because invoices/pages have different containers, density, and reading conventions.

Weakly transferable without new evidence:

- scanned-document deskew/dewarp;
- table extraction;
- handwriting;
- natural-scene leaderboards.

The source report references RICO and RICO Semantics as useful UI datasets for pretraining/evaluation design, while noting that they do not match this desktop financial onboarding screen exactly.

## Applied finding on the authorized screen

Historical source statement: the current strict reader and one experimental same-screen layout-zone cascade were run against one curated technical ground truth. The candidate improved pairwise reading order but lost text quality and localization, so it failed the adoption gate; its zones were tuned on the evaluated screen.

Current reconciliation statement: the referenced benchmark runner and truth artifact are not present in PR #140, so that historical result has not been reexecuted in this lot. No external OCR engine is promoted. The valid current decision is:

- baseline architecture retained;
- `NO_SUPERIOR_CANDIDATE_PROVEN`;
- `BLOCKED_MISSING_BENCHMARK_PRODUCER_ARTIFACTS` for fresh B0/C1 reproduction;
- `BLOCKED_REAL_EVIDENCE` for autonomy/production.

## Source references preserved from the uploaded report

The source artifact cites these primary/official materials as research inputs:

- Tesseract command-line usage and ImproveQuality documentation;
- Ray Smith, “An Overview of the Tesseract OCR Engine” and layout-analysis research;
- PaddleOCR PP-StructureV3 and PP-OCRv5 documentation;
- DBNet and CRAFT papers;
- docTR official repository/model API;
- Microsoft OmniParser research/repository;
- ScreenAI paper;
- UIED paper/repository;
- OCR-D evaluation guidance;
- ICDAR robust-reading evaluation literature;
- multilingual Tesseract research;
- mutation-testing and metamorphic-testing literature;
- Google Document AI/Cloud Vision, Azure Document Intelligence, AWS Textract, and ABBYY capability documentation;
- RICO and RICO Semantics datasets.

These references describe methods/capabilities and support the architecture/research framing. They do not prove comparative accuracy on LF without the governed benchmark producer, frozen truth, source hashes and exact-HEAD result artifact.