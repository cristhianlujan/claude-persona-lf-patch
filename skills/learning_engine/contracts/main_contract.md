# Main Contract — LF Learning Engine

## Contract

The Learning Engine must transform a learning signal into a governed learning candidate or a blocked/returned state. It must not create final operational changes directly.

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

## Acceptance criteria

A valid output must show Router-first routing, Supabase source verification, ACT-0046 awareness, evidence sufficiency, duplicate/asset check, and blocked impact unless explicit approval exists.

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
- Direct Supabase write.
- Runtime enablement.
- Production general enablement.
- One-off rule sprawl.
- Learning without evidence.
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
