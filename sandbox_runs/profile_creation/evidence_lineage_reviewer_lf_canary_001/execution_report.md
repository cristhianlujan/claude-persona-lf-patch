# Profile Creator Canary — EVIDENCE_LINEAGE_REVIEWER_LF

Operation: CREACION_PERFIL_LF
Mode: candidate/read-only canary
Runtime: NO_HABILITADO
Automatic impact: BLOQUEADO

## Pre-write authority
Read and reconciled:
- ACT-0045
- public.lf_artifact_destination_registry
- contrato_perfil_lf.yaml
- core and validation procedure steps
- applicable EKB prevention: GOV-010, GOV-017, GOV-018, CI-005, SRC-011

## Duplicate check
No profile pack named `evidence_lineage_reviewer_lf` exists under `/profiles/`.
Existing audit/document assets are broader and do not duplicate the proposed narrow evidence-lineage role.

## Research pack
Rules were derived from SLSA provenance/verifying-artifacts guidance, GitHub exact-head status semantics, NIST AI RMF/GAI TEVV-provenance practices, and LF GOV-018.

## Gap discovered by the canary
The active PROFILE_PACK destination requires `manifest.json`, but the current `profiles/_template` does not materialize it and its validator does not require it. This is a creator/template contract-alignment gap, not a reopening of GOV-017 or GOV-018.

## Candidate validation
Local candidate validator: PASS.
Runtime authorization: false.
Automatic impact authorization: false.

## Semantic review
Same-session Quality Pack review: PASS_WITH_RESTRICTIONS, 25/25.
This is not an independent audit and must not be represented as one.

## Closure condition
Do not declare the canary complete or lift the candidate-creation freeze until exact-head CI passes, the PR is merged to main, postmerge readback confirms candidate and template manifest, and EKB records the newly demonstrated template/registry gap in enriched form.
