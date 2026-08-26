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

For a handoff behavioral claim to pass:

- the producer's claimed state must be observable in the delivered output;
- the next action cannot ask the receiver to recreate an artifact the producer already claimed to create;
- `handoff_target` must agree with the handoff contract used by the pack;
- a verified executable receiver target must exist;
- that receiver target must actually execute the assigned gate against the producer artifact;
- the captured receiver output, trace and relevant next state must demonstrate that the receiver continued without inventing missing intent, structure, evidence or artifact content.

A same-session role-play, assisted rubric review, static receiver-output fixture, or structural validator may demonstrate that an artifact is inspectable or consumable. It is not receiver execution and cannot authorize a behavioral handoff PASS or capability→regression promotion.

When the producer artifact is consumable but no executable receiver target is verified, preserve that partial evidence and return `RETURN_TO_ORCHESTRATOR` with `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER`.

A schema-valid output that fails these continuity conditions is not an acceptable behavioral handoff.

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
- A behavioral handoff PASS based only on an assisted review, same-session receiver role, static fixture, or structural validator.
- Regression promotion while the receiver execution target is missing or the target outcome remains unproven.
