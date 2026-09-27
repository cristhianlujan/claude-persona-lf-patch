# VISUAL_EVIDENCE_GATE

## Purpose

`VISUAL_EVIDENCE_GATE` is the pass-level visual evidence control. It is the durable orchestration identity that replaces the historical label `P0_VISUAL_RUNTIME` without rewriting historical P0 evidence, schemas, tables, receipts, or helper filenames.

The control answers one bounded question:

> Does the applicable visual change satisfy the existing visual evidence regression bundle strongly enough for the pass to continue?

## Reused implementation

No second visual engine is created. The gate invokes existing historical visual helpers plus one thin regression-bundle carrier that consolidates visual tests previously executed indirectly by E.16:

1. `P0_HUMAN_REVIEW_CONVERGENCE_V1.py`
2. `P0_DUAL_OCR_RECONCILIATION_CONTRACT_V1.py`
3. `P0_ICON_STRUCTURAL_ROLE_REGRESSION_V1.py`
4. `P0_MULTISCREEN_STRUCTURAL_GENERALIZATION_REGRESSION_V3.py`
5. `P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py`

`P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py` reuses the legacy OCR causal, text-group family and P0 V1/V2/V3/V4 quality regressions. It does not create another visual engine. Its purpose is to make those regressions executable by their correct owner so E.16/Contract Check no longer need to provision or execute visual-quality responsibilities.

Historical `P0_*` names remain implementation/evidence lineage only. New orchestration must use `VISUAL_EVIDENCE_GATE`.

## Ownership boundary

| Responsibility | Owner |
|---|---|
| Determine whether a changeset has visual impact | Changeset Governance / pass applicability |
| Repository/path admission | Changeset Governance |
| Read/parse visual source, geometry, structure and semantics | Existing visual runtime assets |
| Visual completeness/fidelity regression bundle | `VISUAL_EVIDENCE_GATE` |
| Legacy P0 visual-quality regression execution | `VISUAL_EVIDENCE_GATE` |
| Exact-head source retrieval / SHA binding | Evidence/currentness infrastructure |
| Durable evidence persistence/readback | Evidence infrastructure |
| Human authentication or decision persistence | Human-review authority, not this gate |
| Runtime/production authorization | Explicit downstream authority, not this gate |
| P0 docs-only fast-lane selection | Pass applicability/orchestration, not this gate |

## E.16 relationship

E.16 remains a CI/GitHub integrity regression surface. It must not own visual-quality dependency provisioning or execute the P0 visual regression bundle. The migration sequence is intentionally two-stage:

1. materialize the visual regression coverage under `VISUAL_EVIDENCE_GATE`;
2. remove the duplicated visual execution from the E.16 integration/runtime-scope matrices.

This ordering prevents a temporary coverage gap.

## Fail-closed rules

- Missing canonical helper: block.
- Duplicate/unsafe helper path: block.
- Any helper returns non-zero: block immediately.
- Foreign exact-head, migration-parity or Contract Check implementation paths cannot be added to this gate's helper bundle.
- The legacy visual regression bundle validates its command inventory and governed visual dependency versions before execution.
- This gate never turns technical PASS into human acceptance, runtime activation, merge authorization or production authorization.

## Compatibility

`P0_VISUAL_RUNTIME` is retained only as a legacy orchestration alias until carrier cutover is completed. Historical `docs/p0/**`, private P0 persistence relations and old evidence identifiers are not renamed because they are lineage-bearing artifacts.

## Verification

```bash
python3 sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py --self-test
python3 sandbox/lf_contract_gate_test/visual_evidence_gate/test_visual_evidence_gate_v1.py
python3 sandbox/lf_contract_gate_test/P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py --self-test
```

The standalone owner is already materialized. Router/carrier cutover remains a separate sequential solution so Contract Check can stop owning the visual control without mixing responsibilities in one PR.
