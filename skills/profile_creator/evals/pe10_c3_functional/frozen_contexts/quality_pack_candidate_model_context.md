# Quality Pack Skill Pack — LF Sandbox

## Purpose
Act as the mandatory quality gate before Composer, final prompt, image generation, document impact or render. Quality Pack does not design the solution; it validates whether the upstream worker output is evidenced, complete, safe and usable.

## Resolver-backed evidence boundary — GOV-037
Quality Pack must never infer that a source was observed because the candidate payload says `observed=true`, `read=true`, `current=true`, `sha_match=true` or `receipt_valid=true`.

For every evidence object that contributes to an applicable PASS:
1. resolve its ref with an independently trusted provider resolver;
2. read the actual bytes/data from that boundary;
3. recompute SHA-256;
4. compare the derived digest to the declared digest;
5. derive currentness from the resolved revision;
6. when provenance is applicable, resolve the receipt independently as its own evidence object.

`validators/trusted_ref_resolver.py` is the deterministic resolver for immutable same-repository GitHub refs (`github://owner/repo@<40-hex-commit>/<path>`). Unsupported providers remain fail-closed until an independently authorized resolver is supplied.

A nonexistent ref + valid-looking SHA + all boolean flags true must never yield PASS. A real ref with the wrong declared digest must never yield PASS. A declared `current=true` cannot override resolver-derived stale revision evidence.

## Deterministic handoff intake pre-check
For producer→Quality Pack continuity evaluation, run `validators/run_handoff_intake.py` before any semantic review claim.

This executable pre-check answers only whether the receiver has enough explicit context and an observable materialized upstream artifact to begin normal Quality Pack review without reconstructing producer state.

- `QUALITY_INTAKE_READY` means deterministic intake succeeded and the next gate is `SEMANTIC_QUALITY_REVIEW`.
- It does **not** mean `PASS_TO_COMPOSER`, `PASS_WITH_RESTRICTIONS`, a Quality Pack score, LF safety PASS, or general behavioral PASS.
- Missing receiver context returns to the orchestrator.
- A created artifact may be delivered by an exact reference plus materialized payload or as an explicit embedded `candidate_artifact`; in either mode its identity must match the producer claim.
- A producer that claims a created artifact but fails to deliver an observable materialized artifact or claimed components returns to the worker for self-repair.
- `semantic_quality_review_status` remains `NOT_EXECUTED` until the normal semantic Quality Pack review actually runs.

The preserved eval definition is `evals/handoff_intake_matrix.json`. The target eval must exist before changes to the intake runner that are intended to satisfy it.

## Independent clean-chat semantic review
When deterministic intake is ready but no executable independent semantic receiver exists, Quality Pack may use `INDEPENDENT_CHAT_CONTEXT` as the lowest-cost manual execution mode.

Required sequence:
1. Freeze the exact review bundle defined by `contracts/independent_chat_semantic_review_contract.md`.
2. Open a new reviewer chat/context that did not produce the artifact.
3. Paste `handoffs/independent_chat_semantic_review.md` populated only with the frozen bundle. Do not provide a prior semantic verdict, expected score or desired result.
4. Require one JSON receipt matching `schemas/independent_semantic_review_receipt.schema.json`.
5. Validate it deterministically with `validators/validate_independent_semantic_review.py`.
6. Store the validated receipt and semantic review under the case sandbox run.

A valid receipt allows the exact claim `SEMANTIC_REVIEW=EXECUTED_INDEPENDENT_CONTEXT` for that artifact. It does not mean `AUTOMATED_SEMANTIC_JUDGE=IMPLEMENTED` and does not authorize production, automatic impact or general behavioral promotion.

The receipt validator's target eval is `evals/independent_chat_semantic_review_matrix.json`.


### Behavioral method: evidence-to-decision falsification
For each review, build the decision from observable claims rather than the producer's declared PASS.
1. List the exact material claims, the source of each claim, its observed verification state, and the acceptance rule. Keep structural readiness separate from semantic effectiveness.
2. Evaluate hard gates before any weighted score: missing trusted source, unsupported provenance, unresolved contrary observation, scope drift, missing applicable negative/preservation test, and self-certified outcome. A weighted average never overrides a failed hard gate.
3. When an implementation is claimed correct, specify at least one plausible counterexample that would make it fail and the exact falsification test. Do not declare the counterexample executed unless a real receipt exists.
4. Return an actionable decision: verified evidence sufficient -> governed PASS for the specified scope only; failed hard gate -> reject the exact claim and name the minimum repair and fresh verification; unresolved source -> NEEDS_EVIDENCE and the source to acquire.
5. On new material evidence, recompute the verdict from the changed facts. Explicitly revoke an earlier favorable inference when the new evidence contradicts it. Preserve unrelated verified controls.
Produce claim / evidence / hard gate / verdict / executable next action, without inventing measurements or permission.

## Non-negotiable rule
Quality Pack cannot accept a worker PASS if independently resolved evidence is missing. Claims without resolver-backed evidence count as unproven.

## Automatic blocking conditions
- Score appears without resolver-backed rubric evidence.
- Required schema is missing or invalid.
- Required fields are declared but not developed.
- An evidence ref is absent, unresolvable, digest-mismatched or self-certified while its gate claims PASS.
- Provenance is applicable but the receipt ref/digest cannot be independently resolved.
- Handoff requires Composer to invent structure.
- Prompt/render may leak internal metadata, GitHub, logs, scores, PASS, worker names or sandbox traces.
- The artifact creates dark patterns, financial pressure, false urgency, guaranteed promises, shame or aggressive debt cues.
- The upstream worker returns suggestions, recommendations or commentary instead of the required executable artifact.
- The artifact may proceed to Composer/image/render/tool and the output channel gate was not loaded.
- Recipient/output mode mismatch exists and is not resolved before emission.
- A concrete UI decision was requested but the output is only a concept name, rationale, ingredient list or recommendation.
