# RW1-06_C1 — independent sealed holdout handoff (V1)

## Authority and isolation
- Plan: `LF_ROUTER_ARCHITECTURE_WAVE_V1`; unit `RW1-06`; checkpoint `RW1-06_C1`.
- Repository: `cristhianlujan/claude-persona-lf-patch`; frozen source snapshot `ec5d8ce5637c2d118941cfe4b3c88ae4fd325024`.
- Source/policy: `docs/programming-agent/router_wave/RW1_06_C1_SOURCE_POLICY_FREEZE_V1.json` (Git blob `138efc3285ee5226c107827c66f84ced6be4afcb`).
- Reviewer must be materially independent from contract, Router and checker author; use a **new GPT Native chat** with no producer conversation context or hidden answer keys.
- Review RW1-01 needs oracles, RW1-03 ABI and RW1-05 consumer evidence as fixed authority, **not** as reusable secrets. Discard RW1-01 H01–H12 burned holdouts.
- Keep `provider_attested=false` and `independent_review=false` until independent provider-bound evidence actually exists.

## Reviewer task (not executed by this handoff)
1. Validate the exact source and oracle applicability. Stop on source currentness, cross-project or hash mismatch.
2. Independently author a fresh, **sealed** corpus of at least **12 valid**, **24 invalid** and **2 novel** falsifiers, covering all applicable F01–F13 families. Include typed multi-target scope, exclusions, new assets, clarification, Router authority, read-only, executor modes, migration Train and same-request consumer evidence.
3. Pre-register a case-level expected action/verdict and failure severity *before* observing candidate/producers' outputs. Fail on any authorization bypass, lost exclusion, invented effect authority or false terminal receipt.
4. Use independently chosen seed/nonce. Commit `source_snapshot_sha`, `holdout_manifest_sha256`, `holdout_content_sha256`, counts, reviewer attestation/limits and timestamp **before** any C2 evaluation. Keep unrevealed cases outside producer context until its RAW commitment.
5. Emit only a commitment receipt first. Do not expose case bodies to implementer/producer before commitment. Store eventual review and exposure records separately, with exact hashes.
6. Do **not** close C1 or claim C2/C3 PASS. Any missing independent proof remains GAP/BLOCKER. Overhead must be measured; no invented numeric SLA.

## Required first receipt (template, no values invented)
```json
{
  "schema_version": "RW106_C1_INDEPENDENT_HOLDOUT_COMMITMENT_V1",
  "checkpoint": "RW1-06_C1",
  "source_snapshot_commit": "ec5d8ce5637c2d118941cfe4b3c88ae4fd325024",
  "source_policy_git_blob": "138efc3285ee5226c107827c66f84ced6be4afcb",
  "reviewer_method": "GPT_NATIVE_NEW_CHAT",
  "reviewer_reference": null,
  "reviewer_separation": "NOT_YET_ATTESTED",
  "holdout_counts": {
    "valid": null,
    "invalid": null,
    "novel_falsifiers": null
  },
  "holdout_manifest_sha256": null,
  "holdout_content_sha256": null,
  "committed_at_utc": null,
  "committed_before_evaluation": false,
  "case_bodies_revealed": false,
  "producer_raw_observed": false,
  "provider_attested": false,
  "checkpoint_done": false
}
```

## Mechanical receipt verification (not independence proof)
- When the reviewer emits a non-template commitment, run `python3 sandbox/lf_contract_gate_test/router_wave/validate_rw106_c1_holdout_commitment_v1.py <commitment.json>`.
- Requires `reviewer_separation=OWNER_PROVIDED_SEPARATE_CHAT_UNATTESTED`, a genuine reviewer chat reference, UTC timestamp, and 12 valid + 24 invalid + 2 novel holdouts. The reviewer must keep every case body, seed, nonce and oracle answer secret until the governed reveal.
- Validator `STRUCTURAL_PASS_INDEPENDENCE_NOT_PROVEN` is **never** independent attestation, an actual holdout content-hash verification, or C1 DONE.
- Persist the commitment before any C2 producer output, then verify its Git blob and ordering in a separate readback.

## Contract boundary
This handoff is an *instruction and commitment template*, not a generated holdout, provider receipt, source admission, merge authorization, checkpoint completion or production activation. A real independent reviewer must produce distinct material evidence in a separate invocation.
