# VISUAL_EVIDENCE_GATE v2 ownership transfer map

## Scope of this candidate

This file records the ownership split discovered while cleaning `VISUAL_EVIDENCE_GATE` v1. It does not activate, move or delete historical assets.

| Historical execution currently reachable from v1 | Correct owner class | v2 action |
|---|---|---|
| `P0_HUMAN_REVIEW_CONVERGENCE_V1.py` | Human Review authority | Not executed |
| `P0_DUAL_OCR_RECONCILIATION_CONTRACT_V1.py` | Visual producer/runtime | Not executed |
| `P0_ICON_STRUCTURAL_ROLE_REGRESSION_V1.py` | Visual producer/runtime | Not executed |
| `P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V3.py` | Visual producer/runtime regression | Not executed |
| `P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py` | Historical mixed regression bundle; must be partitioned by producer/Human Review/integration/P0-5 ownership before any deletion or reassignment | Not executed |
| exact-head source transport/persistence | Evidence/currentness infrastructure | Not owned |
| pass applicability/path admission | Changeset Governance | Not owned |

## Candidate invariant

`VISUAL_EVIDENCE_GATE` v2 may consume source-bound evidence and validate its proof chain. It must not call the producer that generated that evidence.

## Historical bundle transfer rule

The 24-command legacy bundle stays physically present until its execution coverage is proven under the correct owners. No command is deleted merely because v2 stops invoking the bundle.

This prevents the previous failure mode: moving a complete mixed bundle from one contaminated owner into a new owner and reproducing the same contamination under a different name.
