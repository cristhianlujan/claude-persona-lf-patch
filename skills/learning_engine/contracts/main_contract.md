# Main Contract — LF Learning Engine

## Contract

The Learning Engine must transform a learning signal into a governed learning candidate or a blocked/returned state. When the request intentionally does not provide a preselected case, the Motor must first perform governed autonomous discovery instead of treating the absent case as a missing input.

It must not create final operational changes directly. Candidate corrections to ACT-0046 may be implemented only through the governed `ACTUALIZACION_SKILL_LF` path; EKB persistence may use the governed `ESCRITURA_BASE_CONOCIMIENTO_LF` writer path. Neither path authorizes merge, production promotion, runtime enablement, arbitrary Supabase writes or official-document impact.

A status is a claim about observable state. If the engine says a candidate was created, that candidate must be delivered as part of the result and be usable by the declared receiver.

## Required output fields

- `status`
- `learning_candidate_id`
- `classification`
- `source_authority`
- `evidence_map`
- `proposed_next_action`
- `handoff_target`
- `blocking_codes`
- `next_gate`

When `status = LEARNING_CARD_CANDIDATE_CREATED`, `candidate_artifact` is also required and its `artifact_id` must match `learning_candidate_id`.

When the run performs autonomous discovery, material tool use or repair, the execution evidence must additionally preserve the applicable `discovery_trace`, `tool_trace`, `deficiency_ledger`, EKB writer/readback receipts and fix receipts.

## Autonomous discovery acceptance

A no-case/open-discovery request is valid when governed read-only inventory is available. Before asking the human to choose a case, the Motor must execute:

`DISCOVERY_PLAN -> INVENTORY_QUICK_SCAN -> CANDIDATE_SHORTLIST -> PRIORITIZE -> RECOMMEND_AND_SELECT -> SELECTED_CASE_DETAIL_READ -> CASE_FREEZE`.

The Motor must prefer a defensible autonomous choice for safe, reversible sandbox work. Human selection is required only when a material ambiguity, unavailable authority, new scope/impact decision, irreversible action, spending, merge/promotion or other approval boundary prevents a safe choice.

The inventory path must use progressive disclosure. It should dimension the universe with bounded metadata first, narrow to a shortlist, and hydrate detailed records only for the selected case or a justified top-k. A semantically correct answer does not excuse wasteful or opaque data access.

## Tool-access evidence

Every material tool call must preserve its observable access shape: tool/resource, purpose, operation, exact fields/columns, filters, limit/range, returned rows/items, round-trip/retry/error information, cache/reuse and read scope. Bytes, latency and token counts must be stored only when actually observable; otherwise use null/`NOT_OBSERVED`.

`SELECT *` without need, unbounded collection reads, full-body EKB scans before shortlist, repeated identical queries without a new hypothesis, and large JSON/blob hydration when specific fields suffice are explicit performance red flags.

Quality/autonomy and tool-efficiency are separate acceptance dimensions.

## Blind-search integrity

For blind capability evaluation, the evaluator may not formulate or enrich the Motor's search signature. The Motor must generate the diagnosis/search signature, which is frozen before retrieval and consumed byte-for-byte or through a documented deterministic normalization. Oracle codes or keywords added by the evaluator invalidate the blind gate even when retrieval returns the expected result.

## Self-enrichment and repair continuity

Every meaningful deficiency, `FAIL`, `BLOCKED`, `ERROR`, tool error or performance red flag discovered by the Motor, evaluator or tool path must be processed before repair or continuation:

`DETECT -> NORMALIZE_SIGNATURE -> EKB_LOOKUP -> CLASSIFY_NEW_OR_RECURRENCE -> GOVERNED_EKB_WRITE -> READBACK -> OWNER_ISOLATION`.

If an equivalent causal EKB record already exists, update it as a recurrence rather than creating a duplicate. Preserve provenance of who actually detected/persisted the finding and never claim `MOTOR_SELF` when the evaluator performed the write.

After durable EKB readback, every in-scope deficiency must follow:

`TARGET_EVAL_BOUND -> CORRECT_UPDATE_OPERATION_ROUTED -> MINIMAL_CANDIDATE_FIX_IMPLEMENTED -> SOURCE_OR_HEAD_READBACK -> DETERMINISTIC_VALIDATION -> SAME_INPUT_GATE_REPLAY -> BEFORE_AFTER_VERIFIED -> CONTINUE`.

A gate that discovers a deficiency cannot be marked complete until its in-scope fix has a durable receipt and clean same-input replay. A pilot cannot claim completion with `open_unimplemented_deficiencies > 0` or `open_unverified_fixes > 0`.

When the causal owner is outside ACT-0046 and the fix requires a new asset/scope write, persist the finding and block that cross-scope fix for explicit approval. Do not hide it and do not claim the full pilot is implemented while it remains open.

## Acceptance criteria

A valid output must show Router-first routing, Supabase source verification, ACT-0046 awareness, evidence sufficiency, duplicate/asset check, and blocked impact unless explicit approval exists.

For open discovery it must additionally show inventory strategy, bounded shortlist, explicit prioritization, autonomous recommendation/selection when safe, and progressive detail hydration.

For any discovered deficiency it must show EKB lookup/persistence/readback, causal owner, target eval, implemented in-scope candidate fix, exact source/readback, deterministic validation and same-input replay before advancing.

For cross-profile support/remediation, the candidate must additionally satisfy:

- `DEFECT -> CORRECTION -> POSTCONDITION` is explicit and directionally improves the diagnosed defect;
- any causal claim used to justify a rule/change is supported rather than inferred from correlation alone;
- material upstream dependencies are verified for existence, currentness, exact revision/SHA binding and compatible current validator/judge status;
- provenance and semantic correctness are separate gates;
- the claim level does not exceed the evidence ceiling;
- every enumerable required semantic obligation is represented in a coverage manifest and maps 1:1 to a check ID before semantic PASS can be claimed;
- already resolved material inputs are consumed rather than asked for again;
- `KNOWN_VALIDATED` and `NEW_UNPROVEN` behavior are kept distinct;
- Learning Engine remains a support worker and does not take ownership of the caller profile's domain decision.

For a handoff behavioral claim to pass:

- the producer's claimed state must be observable in the delivered output;
- the next action cannot ask the receiver to recreate an artifact the producer already claimed to create;
- `handoff_target` must agree with the handoff contract used by the pack;
- a verified executable receiver target must exist;
- that receiver target must actually execute the assigned gate against the producer artifact;
- the captured receiver output, trace and relevant next state must demonstrate that the receiver continued without inventing missing intent, structure, evidence or artifact content;
- authentic receiver execution alone is not a semantic PASS; the applicable semantic judgment must also be independently evidenced;
- coverage completeness must be proven before a semantic PASS is generalized to all required obligations.

A same-session role-play, assisted rubric review, static receiver-output fixture, or structural validator may demonstrate that an artifact is inspectable or consumable. It is not receiver execution and cannot authorize a behavioral handoff PASS or capability→regression promotion.

When the producer artifact is consumable but no executable receiver target is verified, preserve that partial evidence and return `RETURN_TO_ORCHESTRATOR` with `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER`.

A schema-valid output that fails these continuity or support-quality conditions is not an acceptable behavioral handoff.

## Evidence ceiling

Use the strongest demonstrated layer only:

`STRUCTURAL_ONLY < PROVENANCE_ONLY < SEMANTIC_SUPPORTED < BEHAVIORAL_PROVEN`

A candidate may preserve lower-layer PASS evidence while a higher layer remains blocked. It must never promote itself above the demonstrated layer.

## Invalid outputs

- Direct official document patch.
- Direct arbitrary Supabase write outside a governed writer path.
- Runtime enablement.
- Production general enablement.
- One-off rule sprawl.
- Learning without evidence.
- Asking the human to choose a safe read-only case before attempting governed discovery/prioritization.
- Blind retrieval whose search signature contains evaluator-added oracle terms.
- Material tool access without observable trace when the tool exposes that trace.
- Ignoring overfetch/performance red flags because semantic output is correct.
- Repair or next-gate continuation before EKB writer receipt/readback for a discovered deficiency.
- Duplicate new EKB identity when an equivalent causal error is already present.
- Claiming Motor self-enrichment when persistence was performed by evaluator fallback.
- Advancing from a deficient gate before implementing and verifying the in-scope fix with same-input replay.
- Pilot completion with open in-scope unimplemented or unverified fixes.
- `LEARNING_CARD_CANDIDATE_CREATED` without a delivered candidate artifact.
- A handoff whose declared receiver cannot perform the next gate without inventing missing content.
- A producer output that claims completion and then asks the receiver to perform the same creation step.
- A behavioral handoff PASS based only on an assisted review, same-session receiver role, static fixture, structural validator or runtime receipt.
- Regression promotion while the receiver execution target is missing or the target outcome remains unproven.
- A correction that increases the diagnosed defect.
- A rule/change based on an unsupported causal leap.
- A PASS that depends on a stale, hash-mismatched or rejected upstream.
- A semantic PASS inferred from provenance alone.
- A PASS over a partial semantic check bundle whose coverage manifest is incomplete.
- Re-asking a material input already explicitly resolved in the current run.
- Generalizing `NEW_UNPROVEN` behavior as validated capability.
- Learning Engine taking over the caller profile's domain decision.
