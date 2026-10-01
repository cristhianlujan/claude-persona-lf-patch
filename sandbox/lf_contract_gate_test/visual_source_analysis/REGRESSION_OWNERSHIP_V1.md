# Historical visual regression ownership map v1

Source bundle: `sandbox/lf_contract_gate_test/P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py`.

This map changes no historical file. It prevents the 24-command mixed bundle from being moved as one unit again.

| # | Historical command | Owner class | Candidate disposition |
|---:|---|---|---|
| 1 | ocr-causal-regression | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 2 | text-group-family-generalization | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 3 | legacy-negative-suite | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 4 | human-binding-selftest | HUMAN_REVIEW_AUTHORITY | Excluded |
| 5 | legacy-integration-verifier | LEGACY_P0_INTEGRATION_GOVERNANCE | Excluded |
| 6 | v2-negative-restore-suite | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 7 | v2-runtime-regressions | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 8 | v2-forward-adversarial | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 9 | v3-schema-contracts | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 10 | v3-negative-restore-regressions | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 11 | v3-forward-adversarial | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 12 | v3-runtime-hash-inventory | VISUAL_SOURCE_ANALYSIS | Producer inventory; currentness itself remains external |
| 13 | v3-premerge-compliance | PREMERGE_RELEASE_GOVERNANCE | Excluded |
| 14 | v4-contracts | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 15 | v4-graders | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 16 | v4-grader-coverage | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 17 | v4-closed-loop | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 18 | v4-durable-state | EVIDENCE_PERSISTENCE_STATE | Excluded |
| 19 | v4-known-failure-regressions | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 20 | v4-forward-adversarial | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 21 | v4-independent-omission-sweep | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 22 | v4-reader-producer-contract | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 23 | v4-grader-producer-field-audit | VISUAL_SOURCE_ANALYSIS | Producer inventory |
| 24 | p0-5-blind-annotation-contract | P0_5_BENCHMARK_ANNOTATION | Excluded |

## Totals

- Producer-owned: **19**
- Foreign to producer: **5**
- Deleted/moved in this candidate: **0**

## Cutover invariant

The legacy mixed bundle remains callable only as historical compatibility coverage until all five foreign owner classes have an explicit safe execution path. `VISUAL_EVIDENCE_GATE` must not be cut over by replacing one mixed bundle with another.
