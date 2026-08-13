# ADR — OCR/UI pipeline decision, 2026-08-12

Status: accepted technical decision. Production adoption remains blocked.

## Context

The real onboarding screenshot exposed cross-column grouping, evidence contamination, compact-control omission, small-text recognition errors, and correlated Tesseract assumptions. Only one authorized real screen is available; residual calibration requires more data.

The original ADR is preserved here as the architectural decision record, with two reconciliation clarifications for PR #140:

1. the current repo/PR does not yet contain the referenced `ground_truth_real_screen_001.json` or `ocr_benchmark_ui_v1.py`; therefore historical one-screen B0/C1 results are not re-declared as a fresh same-HEAD rerun in this lot;
2. persistence verification has advanced from the original 11-check V1 contract to the executed 20-check V2 contract.

## Decision

1. Retain the current strict Tesseract reader and the independent OpenCV compact detector as the operational baseline.
2. Do not adopt the experimental proportional-zone PSM6 cascade. The historical source artifact reports improved reading order but worse required text and bbox metrics, and it was tuned on the evaluation screen. This lot does not re-execute that benchmark because the referenced truth/runner artifacts are not present in PR #140.
3. Preserve the architectural separation of text detection/recognition, layout grouping, control/icon detection, semantic association, omission audit, and residual analysis.
4. Require exclusive persisted evidence ownership and a reconstructable append-only execution graph.
5. Require mutation strength of at least 100 deterministic mutations per material family: delete material element, delete compact non-text element, merge sibling evidence, and unjustified text split — 400 minimum total.
6. Evaluate a genuinely different OCR/UI family only after model hashes/runtime are governed and the real corpus reaches ten screens. Preferred next candidates remain PaddleOCR PP-OCRv5/PP-StructureV3 for text/layout and an OmniParser-like UI detector for independent omission auditing.
7. Keep `autonomous_system_ready=false`, P0-5 blocked, and production blocked. This technical annotation is not human adjudication.
8. Treat historical engine results as stale for a newer HEAD unless re-executed against the exact current source/configuration/HEAD. This applies EKB `ARC-006` and prevents old PASS from becoming current authority.
9. Do not describe Tesseract PSM3/11/12 as independent OCR families. EKB `EKB-P0-017` / `ADR-P0-008` requires explicit disclosure that they share one engine family; OpenCV Canny remains a genuinely different visual detector family.
10. Any future adoption claim must preserve the atomicity invariant from `EKB-P0-003`: one candidate/evidence owner cannot satisfy two materially independent UI units.

## Alternatives rejected or deferred

| Alternative | Decision | Reason |
|---|---|---|
| full-page PSM6 | rejected | observed column/field mixing |
| proportional-zone PSM6 | rejected | historical artifact reports worse CER/WER/F1/small-text/IoU; same-screen tuning |
| second Tesseract PSM as independent audit | rejected | same engine family, correlated failure modes |
| PaddleOCR / docTR immediate replacement | deferred | no pinned weights/runtime or ten-screen comparison |
| OmniParser-like UI parser immediate promotion | deferred | model/runtime not governed and real corpus insufficient |
| cloud OCR immediate use | deferred | no credentials, cost benchmark, or privacy/data-egress approval |
| ABBYY immediate use | deferred | exact product/version/license and benchmark unavailable |
| raw residual pixel threshold | rejected | shadows, borders, gradients, and antialiasing are not material elements by default |

## Acceptance evidence and current status

### Present and verified in PR #140 / Supabase

- `P0_EXECUTION_PERSISTENCE_CONTRACT_V2.md`
- `supabase/tests/p0_execution_persistence_v2_contract.sql`
- 20/20 transactional V2 persistence checks, rollback-clean
- real normalized execution `EXEC-P0-REAL-PERSIST-NORM-20260812-001`
- `OCR_RESEARCH_REPORT.md`
- `OCR_GAP_MATRIX.md`
- `OCR_BENCHMARK_PLAN.md`

### Historical/source-referenced but not present in PR #140 at reconciliation time

- `ground_truth_real_screen_001.json`
- `ocr_benchmark_ui_v1.py`
- generated B0/C1 benchmark result bound to source and truth hashes

Because these benchmark producer artifacts are absent, their historical results remain informative but are not a fresh same-HEAD benchmark proof. `AUD-008` requires producer + verifier, and `ARC-006` forbids promoting stale evidence.

## Consequences

The production OCR reader is unchanged by this ADR reconciliation. Persistence hardening proceeds because it is independently implemented and testable. The next OCR decision requires new real evidence, the missing benchmark producer/truth artifacts or their governed replacement, and a current exact-HEAD run — not more rules fitted to this one screen.

Current gate: `BLOCKED_REAL_EVIDENCE`.