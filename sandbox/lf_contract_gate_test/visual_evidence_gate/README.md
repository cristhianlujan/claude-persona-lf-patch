# VISUAL_EVIDENCE_GATE

## Purpose

`VISUAL_EVIDENCE_GATE` is the pass-level visual evidence control. It answers one bounded question:

> Does already-produced, source-bound visual evidence satisfy the required fail-closed pass conditions strongly enough for the pass to continue?

It is not the visual producer/runtime and it is not Human Review.

## Current v1 vs candidate v2

### v1 — current registered source, not cut over

`visual_evidence_gate_v1.py` is retained unchanged for lineage/currentness. It executes historical P0 visual helpers and `P0_VISUAL_QUALITY_REGRESSION_BUNDLE_V1.py`.

That transfer solved the previous E.16 ownership leak, but it also moved producer/runtime, Human Review and integration regressions under the new gate identity. EKB: `PASE-VISUAL-EVIDENCE-GATE-OWNER-OVERLOAD-001`.

The v1 carrier is still `REGISTERED_NOT_CUTOVER`; do not cut it over while this ownership defect remains.

### v2 — evidence-only candidate

`visual_evidence_gate_v2.py` does not execute the visual producer or any historical P0 regression bundle. It consumes a pre-existing source-bound convergence receipt and validates:

1. receipt schema and cryptographic identities;
2. at least two clean passes;
3. 100% grader coverage;
4. zero open material visual findings;
5. exact four gate proofs: regression, adversarial, source binding and artifact hash chain;
6. each proof is bound to the same source SHA, code HEAD and configuration SHA;
7. upstream convergence result is PASS.

The proof validator is reused from the existing pure convergence contract. No second OCR/visual engine is created.

## Ownership boundary

| Responsibility | Owner |
|---|---|
| Determine whether a changeset has visual impact | Changeset Governance / pass applicability |
| Repository/path admission | Changeset Governance |
| Read/parse visual source, OCR, geometry, structure and semantics | Existing visual producer/runtime assets |
| Producer visual regression execution | Producer/runtime owner, not this gate |
| Validate source-bound visual evidence receipt | `VISUAL_EVIDENCE_GATE` |
| Exact-head source retrieval / SHA binding | Evidence/currentness infrastructure |
| Durable evidence persistence/readback | Evidence infrastructure |
| Human Review rendering/authentication/decision persistence | Human-review authority |
| P0-5 annotation/benchmark contracts | P0-5 owner, not this gate |
| Runtime/merge/production authorization | Explicit downstream authority |

## Fail-closed rules for v2

- Missing or unreadable receipt: block.
- Wrong receipt schema: block.
- Invalid source/config/code digest: block.
- Fewer than two clean passes: block.
- Coverage below 100%: block.
- Any material finding counter non-zero: block.
- Missing/extra gate proof: block.
- Mutated, cross-source, cross-head or cross-config proof: block.
- Upstream result other than `PASS_P0_V4_CLOSED_LOOP`: block.
- v2 has no subprocess execution seam and no canonical helper bundle.

## Historical assets

Historical `P0_*` files are preserved for lineage and regression coverage. They are not deleted, renamed or automatically reassigned by this candidate. Their final owner transfer is a separate sequential lot so coverage is not lost while responsibilities are separated.

`P0_VISUAL_RUNTIME` remains a legacy orchestration alias until the producer/runtime and evidence gate transitions are complete.

## Verification

Current v1 lineage:

```bash
python3 sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v1.py --self-test
python3 sandbox/lf_contract_gate_test/visual_evidence_gate/test_visual_evidence_gate_v1.py
```

Evidence-only v2 candidate:

```bash
python3 sandbox/lf_contract_gate_test/visual_evidence_gate/visual_evidence_gate_v2.py --self-test
python3 sandbox/lf_contract_gate_test/visual_evidence_gate/test_visual_evidence_gate_v2.py
```

## Cutover rule

Do not change the capability current pointer, CI carrier or production/runtime state in this lot. Required sequence:

1. verify v2 exact-head;
2. materialize/verify the producer-runtime owner for historical execution coverage;
3. reconcile capability registration/version metadata;
4. only then prepare carrier cutover;
5. perform exact-head CI/readback before any activation.
