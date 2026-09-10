# SKILL — LF Learning Engine

## Role

Detect, discover, classify, prioritize, and route learning signals under LF governance, while preserving evidence, tool-use efficiency, self-enrichment, and verified repair continuity.

## Mandatory route

Router → Supabase `public.v_lf_fuente_operativa` → ACT-0046 when applicable → ACT-0045 when profile/card handoff is needed → Adapter when applicable → Operation → Verification → Closure.

## Inputs

- Learning signal or observed event, **or an explicit open-discovery request** where the Motor is expected to identify the best case itself.
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

When applicable, the result or execution evidence must additionally expose:

- discovery/ranking trace,
- exact tool/query trace,
- deficiency ledger,
- EKB writer/readback receipts,
- fix receipts and same-input replay evidence.

## Autonomous discovery when no case is supplied

A missing preselected case is not automatically a missing-input condition.

When the request is open-ended but the Motor has governed read-only access to relevant knowledge/case inventory, it must discover and select a candidate autonomously before asking the human to choose.

Required sequence:

1. `DISCOVERY_PLAN` — state what inventory/metadata is needed and what would constitute a material blocker.
2. `INVENTORY_QUICK_SCAN` — dimension the universe using bounded, low-cost metadata rather than hydrating full records.
3. `CANDIDATE_SHORTLIST` — narrow to a bounded set using observable criteria.
4. `PRIORITIZE` — rank by justified criteria such as severity, recurrence, transversal impact, detectability, unresolved risk, evidence quality, learning value or other explicit factors.
5. `RECOMMEND_AND_SELECT` — recommend one case and select it for the sandbox when the choice is safe and reversible.
6. `SELECTED_CASE_DETAIL_READ` — only then hydrate the selected case, or a justified top-k, with the fields needed for diagnosis.
7. `CASE_FREEZE` — freeze exact case/provenance/hash before behavioral evaluation.

Do not delegate a safe reversible selection to the human merely because several candidates exist. Ask only for a material ambiguity, unavailable authority, new scope/impact decision, irreversible action, spending, merge/promotion, or other approval boundary.

## Tool and data-access efficiency

A semantically correct answer can still fail if it reaches the answer through wasteful, opaque or unsafe data access.

Apply progressive disclosure:

`identity/scale -> lightweight metadata -> shortlist -> selected detail -> additional detail only if needed`.

For every material tool call, preserve an observable trace with as many of these fields as the tool actually exposes:

- gate,
- tool name,
- purpose,
- source object/resource,
- operation kind,
- query/request digest,
- exact columns/fields requested,
- filters,
- limit/range,
- rows/items returned,
- result bytes when observable,
- server/client elapsed time when observable,
- round-trip index,
- retry count,
- error code when present,
- cache/reuse status,
- read scope (`FOCAL`, `BOUNDED`, `BROAD`, `SCHEMA_ONLY`, `NON_DATA_TOOL`),
- output digest.

Never invent latency, byte or token measurements that the tool did not expose; use `NOT_OBSERVED`/null.

The following are performance red flags and must be surfaced rather than hidden:

- `SELECT *` or equivalent full-object hydration without explicit need,
- unbounded collection reads without explicit need,
- full EKB/body scans before a shortlist when metadata can narrow the universe,
- repeated identical queries with no new hypothesis,
- retrieving large JSON/blobs when specific paths/columns suffice,
- avoidable retries or SQL/tool errors.

A correct semantic result does not erase an efficiency failure. Quality/autonomy and tool-efficiency are scored separately.

## Blind-search integrity

In a blind capability test, the evaluator must not formulate or improve the Motor's search signature.

The Motor must produce its own diagnosis/search signature. Freeze that exact output and digest before retrieval. The retrieval stage must consume that signature byte-for-byte (or through a deterministic documented normalization) without adding oracle codes, keywords or evaluator hints. If the evaluator injects target terms, the blind gate is invalid even when the correct EKB ranks first.

## Self-enrichment of errors and deficiencies

A detected deficiency is not complete merely because it was noticed in chat or corrected locally.

Whenever the Motor, evaluator or an observed tool result exposes a meaningful deficiency, `FAIL`, `BLOCKED`, `ERROR`, tool error or performance red flag, the run must execute:

`DETECT -> NORMALIZE_SIGNATURE -> EKB_LOOKUP -> CLASSIFY_NEW_OR_RECURRENCE -> GOVERNED_EKB_WRITE -> READBACK -> OWNER_ISOLATION`.

Use the governed `ESCRITURA_BASE_CONOCIMIENTO_LF` / `public.lf_write_pipeline_ekb_v1` path for EKB persistence. This is not permission for arbitrary Supabase DML.

If the causal error already exists, enrich the existing record as `RECURRENCE`; do not create a duplicate identity. Preserve provenance of who detected/persisted the finding (`MOTOR_SELF`, `EVALUATOR_FALLBACK`, `TOOL_OBSERVED`, `USER_OBSERVED`). Never claim self-enrichment when the evaluator performed the write.

No repair and no next gate may proceed after a discovered deficiency until the EKB writer receipt and readback are durable. If EKB persistence fails, return/block with `BLOCKED_EKB_PERSISTENCE`.

## Repair-in-loop: fix before next gate

The pilot is not complete if it merely catalogs defects. Every in-scope deficiency must be implemented and verified before the run advances past the affected gate.

Required sequence after EKB persistence:

1. isolate the causal owner/layer;
2. create or bind the reproducible target eval for the defect;
3. route the correct governed update operation;
4. implement the smallest candidate fix that addresses the cause;
5. read back the exact candidate source/revision/head;
6. run deterministic validation and required semantic/behavioral checks;
7. rerun the **same affected gate with the same input/fixture**;
8. compare BEFORE vs AFTER;
9. only then continue to the next gate.

For ACT-0046 source changes, the governed update operation is `ACTUALIZACION_SKILL_LF`. Candidate source may be written in a controlled branch/PR, but merge, production promotion and runtime enablement remain separate approval boundaries.

A gate that discovers a deficiency cannot be marked complete while its fix receipt or same-input replay is missing. At pilot closure, `open_unimplemented_deficiencies` and `open_unverified_fixes` must both be zero for in-scope findings.

If the causal owner is outside ACT-0046 and fixing it requires a new asset/scope write, preserve and persist the finding, block only that cross-scope fix for explicit approval, and never report the pilot as fully implemented while it remains open.

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
2. perform EKB lookup and persist/enrich the error through the governed writer;
3. define a reproducible target eval before proposing a patch candidate;
4. classify that eval as `CAPABILITY_EVAL` or `REGRESSION_EVAL`;
5. only after the target eval exists may a minimal patch candidate advance to sandbox evaluation;
6. verify the patch and rerun the affected gate before continuing.

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
- The request writes Supabase or Google Docs without approval, except the explicitly governed EKB writer path when its operation contract authorizes the write.
- The output creates a narrow rule instead of a reusable mother rule.
- Evidence is insufficient.
- Existing assets were not checked.
- A safe open-discovery request asks the human to choose a case before the Motor has attempted governed inventory/shortlist/prioritization.
- A blind retrieval uses evaluator-added oracle terms or a search signature not produced by the Motor.
- A material tool call is hidden or its observable query/access scope is omitted from evidence.
- A performance red flag is ignored because the final semantic answer happened to be correct.
- A discovered deficiency proceeds to repair/next gate without EKB lookup, governed persistence and readback.
- A known causal error is duplicated instead of enriched as a recurrence.
- EKB persistence performed by the evaluator is claimed as `MOTOR_SELF`.
- A gate with a discovered deficiency advances before its in-scope candidate fix is implemented, verified and replayed with the same input.
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

This pack remains candidate/read-only for general runtime and does not approve, merge, enable production general or patch official documents by itself. It may use the explicitly governed EKB persistence operation when the active operation contract authorizes it, and candidate source corrections may flow through `ACTUALIZACION_SKILL_LF`. Neither path authorizes arbitrary Supabase writes, merge, runtime enablement or production promotion.
