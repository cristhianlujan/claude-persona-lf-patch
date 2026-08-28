# SKILL — LF Learning Engine

## Role

Detect, classify, and route learning signals under LF governance.

## Mandatory route

Router → Supabase `public.v_lf_fuente_operativa` → ACT-0046 when applicable → ACT-0045 when profile/card handoff is needed → Adapter when applicable → Operation → Verification → Closure.

## Inputs

- Learning signal or observed event.
- Source context.
- Evidence.
- Proposed improvement.
- Impact target, if any.
- Existing asset references.
- Allowed and forbidden impacts.
- Target eval reference when a trace/error is used to justify a patch candidate.

## Outputs

A governed learning result containing:

- status,
- learning_candidate_id,
- classification,
- source_authority,
- evidence_map,
- candidate artifact when the status says a candidate was created,
- proposed_next_action,
- handoff_target,
- blocking_codes,
- next_gate.

## Outcome and handoff continuity

A status is a claim about observable state, not a label that can pass by itself.

- If the result is `LEARNING_CARD_CANDIDATE_CREATED`, the created candidate must be present in the output as a consumable artifact. The next action must not ask another worker to create the same artifact.
- The declared `handoff_target` must identify the worker that can perform the declared `next_gate`; it cannot conflict with the handoff contract used by the pack.
- A structurally valid producer output is not evidence of successful handoff behavior.
- A rubric review generated in the same model session, or stored as a static receiver-output fixture, is `ASSISTED_RUBRIC_REVIEW` evidence only. It cannot self-certify that the receiver was executed.
- For handoff evals, preserve producer output, receiver execution identity, receiver actual output, execution trace/review evidence, and observable next state.

## Layered receiver evidence

Do not collapse all receiver evidence into one PASS/FAIL. Classify producer→receiver evidence in three layers:

1. `DETERMINISTIC_INTAKE`
   - Proves whether the receiver can start from the producer output and an observable materialized artifact without reconstructing missing producer state.
   - A verified executable intake result may be recorded independently of later semantic review.

2. `SEMANTIC_REVIEW`
   - Covers receiver judgment that requires semantic interpretation, such as evidence integrity, LF safety, leakage/scope quality or rubric scoring.
   - If deterministic intake is proven but this layer is not executed, preserve the intake PASS and return `RETURN_TO_ORCHESTRATOR` with `SEMANTIC_QUALITY_REVIEW_NOT_EXECUTED` for any claim that requires semantic review.

3. `FULL_HANDOFF_OUTCOME`
   - Requires every layer needed by the target outcome plus the relevant observable next state.
   - A lower-layer PASS must never be generalized into full handoff behavioral PASS.

Use `BEHAVIORAL_EVAL_BLOCKED_NO_EXECUTABLE_RECEIVER` only when the required receiver layer has no verified executable target at all. Do not use that blocker when a deterministic receiver target exists and has executed successfully; in that case identify the next unexecuted layer precisely.

## Eval semantics

- `REGRESSION_EVAL`: protects behavior already validated. When behavioral execution exists, regression gates must remain at 100% for protected cases before a change can advance.
- `CAPABILITY_EVAL`: measures a desired or emerging behavior that is not yet part of the protected baseline. A capability result never authorizes impact by itself.
- Structural validation only verifies pack files, schemas, fixtures and eval definitions. Structural success must never be reported as behavioral success.
- `BEHAVIORAL_EVAL_PASS` requires execution of the defined cases through the relevant executable targets in an isolated sandbox and comparison of actual result, trace and relevant state against the expected contract.
- A producer→receiver capability may be demonstrated for one explicit layer without proving subsequent layers.
- An assisted review may demonstrate artifact consumability but never receiver execution.
- A capability eval must not graduate to `REGRESSION_EVAL` while the specific outcome it protects is blocked or not proven.

## Trace-to-change gate

When an error, failed execution, operational trace or recurring anomaly is used to propose a change:

1. classify and preserve the evidence;
2. define a reproducible target eval before proposing a patch candidate;
3. classify that eval as `CAPABILITY_EVAL` or `REGRESSION_EVAL`;
4. only after the target eval exists may a minimal patch candidate advance to sandbox evaluation.

If the target eval is missing, return `RETURN_TO_ORCHESTRATOR` with blocking code `TARGET_EVAL_REQUIRED`.

## Transversal profile-support quality gate

When another profile asks the Learning Engine for help on rules, safety, messages, evidence use, support logic or a recurring failure pattern, the Learning Engine is a support worker, not the domain owner. It may enrich the caller's reasoning but must return the decision to the caller/Router; it must not replace the profile's domain contract.

Before a support candidate may advance, load `judges/semantic_support_judge.md` and apply these invariants:

1. **Defect directionality** — normalize `DEFECT -> CORRECTION -> POSTCONDITION`. The correction and postcondition must reduce or eliminate the diagnosed defect. A proposal that reproduces, inverts or amplifies the defect returns to the worker.
2. **Causal link** — evidence correlation is not causal proof. If the proposed rule/change requires an unsupported causal leap, return for self-repair or additional evidence.
3. **Upstream validity** — `upstream exists` is insufficient. When an upstream is material, verify currentness, exact SHA/revision binding and current validator/judge status. Stale, mismatched or rejected upstream returns to the orchestrator.
4. **Provenance ≠ semantic correctness** — a valid runtime receipt proves execution provenance only. It cannot make a wrong answer correct. Semantic claims require the applicable semantic judge.
5. **Evidence ceiling** — never claim a layer above the strongest demonstrated evidence. Structural evidence cannot become provenance; provenance cannot become semantic PASS; semantic PASS cannot become behavioral PASS without behavioral execution.
6. **Coverage completeness** — when semantic PASS depends on an enumerable obligation set, build a coverage manifest from the authoritative obligation source. Every required obligation must map 1:1 to one check ID. A partial hand-built check bundle cannot prove completeness.
7. **Known vs new** — preserve what is already validated as `KNOWN_VALIDATED`; label emerging behavior `NEW_UNPROVEN`. A new capability must not be generalized as known or promoted to regression protection until the target outcome is proven.
8. **Resolved input preservation** — never ask again for a material input already supplied/resolved in the current run. Re-asking a resolved authority/value is a self-repair failure.
9. **Domain ownership** — support output may propose bounded mother rules and evidence-aware repairs, but the caller remains responsible for its domain decision and Quality Pack remains the downstream quality gate.

The deterministic regression for these invariants is `evals/semantic_support_matrix.json` executed by `validators/validate_semantic_support.py`. Its PASS proves only the support contract mechanics; it is explicitly not behavioral evidence.

## Blocking rules

Block or return when:

- Router was bypassed.
- Supabase source verification is missing.
- ACT-0046 is treated as approved runtime.
- The request writes Supabase or Google Docs without approval.
- The output creates a narrow rule instead of a reusable mother rule.
- Evidence is insufficient.
- Existing assets were not checked.
- A trace/error proposes a patch without a reproducible target eval.
- A status claims an artifact was created but that artifact is absent.
- The next action asks the receiver to create an artifact the producer already claimed to create.
- The handoff target conflicts with the handoff contract or cannot perform the next gate.
- Structural validation is presented as evidence of behavioral pass.
- A same-session role-play, assisted rubric review, or static receiver fixture is presented as receiver execution.
- A full handoff behavioral claim is made from a lower-layer intake or review PASS.
- Evidence from a proven receiver layer is discarded merely because a later layer remains pending.
- A correction amplifies the diagnosed defect.
- An unsupported causal leap is used as the basis for a rule/change.
- A required upstream is stale, SHA-mismatched, rejected or not actually read.
- A runtime receipt is treated as semantic proof.
- The output claims a layer above its evidence ceiling.
- A required semantic obligation is omitted from the coverage manifest/check bundle.
- A resolved material input is asked for again.
- A `NEW_UNPROVEN` capability is generalized as validated behavior.
- Learning Engine support takes ownership of the caller profile's domain decision.

## Expected statuses

- LEARNING_CARD_CANDIDATE_CREATED
- HANDOFF_TO_ACT_0045
- RETURN_TO_ORCHESTRATOR
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE

## Runtime rule

This pack creates candidates only. It does not approve, verify, merge, enable runtime, enable production general, write Supabase, or patch Google Docs by itself.
