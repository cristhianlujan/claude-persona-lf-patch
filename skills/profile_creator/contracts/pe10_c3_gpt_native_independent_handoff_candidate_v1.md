# PE10_C3 — GPT Native independent-review handoff (candidate, fail-closed)

Canonical subject: `PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10`.
Canonical review: `EXEC-PE10C3-INDEP-e983544d2ee0aeb9`.
Next step: `semantic_review`.

## Existing sources (do not duplicate)

- Frozen subject digest, source SHA and source receipt: `programacion.engineering_plan_units.unit_metadata.source_pack_v2.checkpoint_inputs.PE10_C3.review_request`
- Existing dispatcher: `private.lf_orchestrator_dispatch_receipts_v1`
- Existing operation: `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`
- Existing reviewer entrypoint: `public.lf_record_independent_review_step_v3`
- Existing judge: `JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1`
- EKB: `LF-PROFILE-GPT-NATIVE-DISPATCH-MISSING-001`

## Safe handoff contract

1. Bind exact live `review_execution_id`, `subject_sha256`, `source_head_sha`, producer receipt and orchestrator dispatch. Reject absent or contradictory identifiers.
2. The reviewer is a genuinely separate GPT Native execution receiving frozen evidence, **not** the producer chat reused under a different label.
3. Require reviewer-produced `PASS|FAIL`, `rationale_summary`, `evidence_refs`, `utility_dimensions_checked=[dependency,data,author]`, and measured `independence_measure` with all three dimensions positively independent.
4. Bind authentic provider/orchestrator provenance to that actual reviewer execution. A chat-transcribed answer or local content SHA **does not provide provider attestation**.
5. Validate the receipt against LF authority at readback; submit to the existing governed reviewer RPC only if provenance, subject, reviewer identity, and independence are verified.
6. Advance `judge_record`, `reviewer_readback`, `report_output` only after canonical `semantic_review` is clean. Require real terminal receipt before completing PE10_C3.

## Failure semantics

Any missing source / mismatched hash / unverified provenance / unproven independence / missing evidence / self-review => BLOCK. Do not update `lf_operation_execution`, policy, profiles, or C3/C4 checkpoints; do not activate v0.2.

The associated local handoff validator is candidate-only. It prepares a bound packet and can validate reply *shape* but cannot itself invoke GPT Native, validate provider-signed identity, or authorize a DB write. In particular, `provider_attestation_verification` values supplied by a reviewer are untrusted unless LF checks an independent provider/orchestrator record.

## Verification

Positive: separate authentic reviewer execution, exact frozen digest and dispatch, three independently measured dimensions, semantic evidence refs and canonical receipt/readback.

Negative: same producer, altered subject, stale dispatch, fabricated provider claim, missing source reference, UNPROVEN dependency/data/author, and a correct-looking verdict with no server-side provenance.

**Status: interface candidate only; not an operational bridge or admission.**