# OCR gap matrix

Date: 2026-08-12. Evidence is bound to source SHA `e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7`. “Proposed”, “historical”, “deferred” and “NOT_RUN” are not PASS.

| Gap | Evidence on the real screen | Candidate technique | Experiment / metric | Risk | Current decision |
|---|---|---|---|---|---|
| Cross-column merge | prior PSM6 observation joined left marketing and right form text | token-first boxes + container layout graph; PP-Structure/UI parser later | cross-column merges; reading-order pairs | manual zones overfit one screen | current geometric split retained; learned layout deferred |
| Field-pair merge | phone/email and document pairs can share a Tesseract line | field/control boundaries before text grouping | field-boundary merge count; field exact match | hard split can fail responsive layouts | same-screen zone candidate historical; not promoted |
| Duplicate evidence ownership | same OCR token/region could support siblings | immutable evidence unit + unique `(execution_id,evidence_unit_id)` owner | DB negative test and duplicate-owner rate | incorrect early tokenization can over-fragment | implemented + V2 contract-tested |
| Relevant material with zero owner | third checkbox, locks, compact icons | independent connected-component/control detector | compact recall/F1 and orphan-material rate | CV shapes can confuse text glyphs | current CV detector retained; real-corpus expansion pending |
| Small controls lost by area threshold | fixed object filter can miss compact controls | separate compact detector with size/shape/cardinality rules | recall by size band; repeated-group exact count | infinite special cases | invariant-based control detector retained; threshold changes must be policy-bound |
| Tautological coverage | reader and omission sweep can share assumptions | denominator from independent CV/binary/edge modality | producer-family audit; omission mutations | correlated preprocessing still possible | independent modalities required; source/candidate separation remains mandatory |
| Noisy residual visual | shadows, borders, antialiasing create components | calibrated component classifier and ignore policy | residual FP/FN curve by rendering class | one screen cannot calibrate | `BLOCKED_UNCALIBRATED` |
| Single OCR family | PSM3/11/12 share Tesseract errors | PaddleOCR/docTR or UI parser as independent audit | disagreement precision and escaped defects | weights, runtime, license/privacy | `NOT_RUN`; do not claim multi-engine independence |
| Spanish/diacritics | pale small text and `@` produced substitutions | pinned `spa`; language-specific crop variants | CER/WER, diacritic CER, email/number slice | mixed-language model can lose accents | historical baseline better overall; fresh benchmark blocked |
| Reading order | global y/x order interleaves left/right columns | container-first order graph | pairwise order accuracy | semantic order differs by responsive view | historical candidate improved only this metric; insufficient |
| Truncation | tooltip/disabled/badge variants absent from current screen | visible-only policy + state fixtures | exact visible substring, no autocomplete | synthetic fixtures do not count as real corpus | regression fixtures only |
| Icons and semantic intent | shape visible, intent sometimes unknowable | detect geometry; classify intent only with corroboration | shape recall vs semantic precision | hallucinated business meaning | `NOT_OBSERVABLE` intent retained |
| Corpus deficit | only one authorized real screen | acquire nine more versioned screens and five unseen holdouts | corpus count; escaped defects/screen | privacy and representativeness | `BLOCKED_REAL_EVIDENCE` 1/10 + 0/5 holdout |
| Weak aggregate mutation count | prior campaign used 100 total with 40/20/20/20 distribution | 100 deterministic mutations per material family | 400/400 overall and 100/100 each family | repetitive targets reduce diversity | 400 minimum required; real-artifact mutation still required by EKB |
| Execution not reconstructable | previous closure event did not contain the complete graph | private normalized append-only persistence + atomic RPC | reconstruction, retry, rollback, isolation | schema drift / ACL exposure | implemented; V2 contract 20/20 PASS |
| PASS with validation FAIL | V1 persistence contract did not enforce semantic validation status | V2 fail-close on every VALIDATION for PASS | negative validation mutation | status vocabulary drift | implemented; C13 PASS |
| PASS without complete artifact family | V1 test had only RECEIPT | require SOURCE/CONFIGURATION/RECEIPT/MANIFEST/AUDIT | missing-artifact negatives | artifact produced but semantically stale | implemented; C14 + hash binding C18/C19 |
| Element without evidence | V1 fixture ROOT had no linked evidence | require every PASS element to own evidence | element-without-evidence mutation | over-fragmented evidence graph | implemented; C12 PASS |
| Stale historical success | real packet can be valid but bound to prior HEAD | latest-authoritative exact-HEAD rule | same evidence against changed HEAD | confusing historical quality with current authority | `ARC-006`: historical packet remains BLOCKED for current acceptance |
| Benchmark producer missing | uploaded plan references ground truth and runner absent from PR #140 | materialize exact governed producer/truth or replacement | source/truth hash + executable producer | silently rebuilding denominator creates tautology | `BLOCKED_MISSING_BENCHMARK_PRODUCER_ARTIFACTS` |

## EKB controls bound to this matrix

- `EKB-P0-003 / PRV-P0-003`: injective atomic matching; many-to-one candidate coverage blocks.
- `EKB-P0-011 / PRV-P0-011`: critical invariants require real-artifact mutation when current source-bound artifact is available.
- `EKB-P0-017 / PRV-P0-017`: PSM variants from Tesseract are not separate OCR families.
- `EKB-P0-018 / PRV-P0-018`: every denominator-changing threshold must be versioned, justified and boundary-tested.
- `EKB-P0-020 / PRV-P0-020`: short/ambiguous OCR requires corroboration; positive short labels remain protected.
- `AUD-008 / PRV-AUD-008`: contract fields require live producers and verifiers.
- `ARC-006 / PRV-ARC-006`: stale external success cannot dominate the current SHA/HEAD.
- `AUD-009 / PRV-AUD-009`: canonical logical digest and persisted-byte digest are different evidence concepts.

## Trace links

- Research basis: `OCR_RESEARCH_REPORT.md`
- Benchmark plan: `OCR_BENCHMARK_PLAN.md`
- Decision: `ADR_OCR_UI_PIPELINE_20260812.md`
- Persistence contract: `P0_EXECUTION_PERSISTENCE_CONTRACT_V2.md`
- Persistence executable test: `../../supabase/tests/p0_execution_persistence_v2_contract.sql`

Historical source references not yet materialized in PR #140:

- `ground_truth_real_screen_001.json`
- `ocr_benchmark_ui_v1.py`

Their absence is explicit and does not get converted into PASS.