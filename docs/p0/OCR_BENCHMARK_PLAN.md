# OCR benchmark plan

Version: 1.1 — reconciled 2026-08-12

## Scope and dataset

- Real source: one authorized 1536×1024 PNG, SHA-256 `e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7`.
- Original ground-truth identifier: `ground_truth_real_screen_001.json`, classified by the source artifact as `CURATED_TECHNICAL_GROUND_TRUTH_NOT_HUMAN_ADJUDICATION`.
- Real corpus gate: 1/10, therefore `BLOCKED_REAL_EVIDENCE`.
- Synthetic fixtures are allowed only for regression, mutation, state variants, and metamorphic tests; they add zero real-corpus credit.
- Sources are read-only. Every benchmark run must verify source and ground-truth SHA-256 before OCR.

### Reconciliation status

The uploaded benchmark plan declares 47 text regions, 13 compact controls/icons, four field groups, and a frozen reading-order policy. However, at reconciliation time PR #140 does not contain `ground_truth_real_screen_001.json` or `ocr_benchmark_ui_v1.py`. Therefore:

- those denominators are preserved as **declared historical benchmark metadata**, not independently recomputed by this lot;
- B0/C1 historical results are not promoted to a fresh same-HEAD benchmark;
- current benchmark execution status is `BLOCKED_MISSING_BENCHMARK_PRODUCER_ARTIFACTS`;
- this does not block persistence V2 verification, which was executed independently and returned 20/20 PASS.

This distinction implements EKB `AUD-008` (every required field must have a producer/verifier) and `ARC-006` (historical success cannot certify a newer HEAD).

## Variants

| ID | Definition | Current status |
|---|---|---|
| B0 | current strict reader: Tesseract PSM3/11/12 consensus + current CV compact detector | historical baseline; not reexecuted in this reconciliation |
| C1 | same-screen proportional layout zones + crop PSM6 at 2×; current CV detector held constant | historical ablation; source artifact reports rejection; not reexecuted current HEAD |
| C2 | PaddleOCR PP-OCRv5 + PP-StructureV3 with pinned model hashes | deferred: runtime/weights not governed |
| C3 | docTR detector/recognizer with pinned weights | deferred: runtime/weights not governed |
| C4 | OmniParser or comparable UI parser as independent omission modality | deferred: model/runtime and corpus absent |
| C5 | Google Document AI/Cloud Vision | deferred: credentials, cost, privacy/data-egress review absent |
| C6 | Azure Document Intelligence v4 | deferred: credentials, cost, privacy/data-egress review absent |
| C7 | AWS Textract Layout | deferred: credentials, cost, privacy/data-egress review absent |
| C8 | ABBYY product selected with exact version/license | deferred: procurement/runtime absent |

Capability documentation is not a benchmark result. Deferred variants remain `NOT_RUN`.

## Metrics

All variants must use identical ground truth and matching policy.

1. Text detection: precision, recall, F1.
2. Transcription: CER and WER after truth-aligned matching, with unmatched and extra text penalized.
3. Spanish slice: diacritic CER.
4. Small text: recall where annotated height ≤14 px.
5. Localization: mean bbox IoU for accepted matches.
6. Layout: pairwise reading-order accuracy, cross-column merges, field-boundary merges.
7. Grouping: exact membership for document, number, phone, and email groups.
8. Compact material: precision, recall, F1; checkbox cardinality exact match.
9. Evidence: duplicate-owner rate and relevant-material orphan rate.
10. Robustness: escaped mutations per family.
11. Operation: wall latency and max RSS delta; future service variants also record request cost and egress.
12. Atomicity: count of `ATOMIC_ELEMENT_OVERMERGE`; required value for adoption is zero.

## Matching policy

- Normalize Unicode with NFKC and case-folding only for matching; preserve original text for CER/WER.
- A text match requires spatial compatibility plus normalized edit similarity; source plan threshold is 0.72 similarity.
- A compact match requires same kind and IoU ≥0.25 because tiny icon boxes are sensitive to one-pixel borders.
- One prediction can match at most one truth item and vice versa.
- A source evidence unit can have at most one element owner within an execution.
- Materially independent UI units must map injectively to candidates; a many-to-one match is a blocking atomicity defect even when all text is present.

The last rule is required by EKB `EKB-P0-003 / PRV-P0-003`.

## Adoption gate

A candidate may replace a production stage only if all are true on the same frozen corpus and exact HEAD:

- text F1 improves;
- CER and WER both improve or one improves with the other statistically unchanged;
- no cross-column or field-boundary regression;
- small-text and diacritic metrics do not regress by more than 0.02 absolute;
- compact-control recall/cardinality do not regress when the candidate changes those stages;
- duplicate evidence ownership, orphan relevant evidence, atomic overmerge, and mutation escapes remain zero;
- no new unresolved HIGH/MEDIUM finding;
- latency, memory, privacy, license, and cost are operationally acceptable;
- at least ten authorized real screens exist, including the target layout families;
- five additional real holdout screens not used for tuning complete without escapes before autonomy;
- the candidate was not tuned and evaluated only on the same screen;
- the producer, model/runtime/config hashes, source hash, ground-truth hash, and result artifact are all persistable and reconstructable.

If the candidate changes only OCR/layout, the control detector is held constant as an ablation. If it changes controls, both stages are compared jointly and separately.

## Mutation and adversarial plan

Use deterministic seed `20260812`. Required minimum is 100 mutations in each family:

| Family | Required | Expected detector |
|---|---:|---|
| delete material element | 100 | independent omission sweep |
| delete compact non-text element | 100 | compact/cardinality gate |
| merge sibling evidence | 100 | exclusive-owner + atomicity invariant |
| unjustified text split | 100 | atomicity/partition invariant |

Acceptance requires 400/400 detected and 0 escapes, plus adversarial cases for icon-as-text, checkbox-as-letter, punctuation/accents, missing control children, flat hierarchy, unsupported reader claims, stale hashes, contaminated fixtures, and incomplete-state false PASS.

EKB `EKB-P0-011 / PRV-P0-011` adds a stronger requirement: synthetic mutations are not enough for a critical gate. At least one representative mutation per critical invariant must be executed against a real candidate/source-bound artifact when that current artifact is available, followed by restoration and a positive rerun.

## Reproducible command contract

The source plan defines the following command shape:

```bash
PYTHONPATH=<locked-python-deps>:sandbox/story_creator_p0_visual/v1.1/scripts \
TESSDATA_PREFIX=<locked-tessdata-dir> \
python sandbox/story_creator_p0_visual/v1.1/scripts/ocr_benchmark_ui_v1.py \
  --source <authorized-source.png> \
  --truth sandbox/story_creator_p0_visual/v1.1/ocr_research/ground_truth_real_screen_001.json \
  --output <benchmark-result.json>
```

Current reconciliation result: the referenced runner/truth files are not present in PR #140, so this command is a required producer contract, not an executable command in the current branch. Running a substitute script or silently rebuilding the denominator would violate EKB `AUD-008`, `EKB-P0-002`, and `EKB-P0-011`.

When materialized, the result must record Python, OpenCV, pytesseract, Tesseract, languages, model/runtime hashes where applicable, source/truth hashes, full predictions, matches, metrics, blockers, and governance flags.

## Current result and next experiment

Historical source artifact: C1 improved reading-order pair accuracy but failed the overall adoption gate because text quality/localization regressed; B0 was retained.

Current verified statement for PR #140: `NO_SUPERIOR_CANDIDATE_PROVEN` and `BLOCKED_MISSING_BENCHMARK_PRODUCER_ARTIFACTS`.

The next legitimate experiment is C2 or C4 only after governed model artifacts and a sufficient real-screen corpus exist. Additional same-screen threshold tuning is not accepted as evidence of general improvement.