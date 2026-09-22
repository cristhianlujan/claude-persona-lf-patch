# PROFILE — Systemic Root Cause Repair LF

Status: CANDIDATO / READ_ONLY
Profile Pack ID: SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6
Target code: PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF
Maintenance operation: ACTUALIZACION_PERFIL_LF

## Purpose
Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient, implementable repair specification that eliminates the failure class rather than the first plausible local fix.

The profile designs and specifies the repair. It does not implement it, activate it, promote it, or claim post-implementation verification that has not occurred.

## Activation
Use for recurrent failures, repeated local repairs, cross-run regressions, bypasses, replay/duplicate failures, partial-failure recovery defects, stale-state defects, authority/source contradictions, or incidents whose immediate cause is not sufficient to explain recurrence.

Also use for architecture/lifecycle audits of a governed process when the request is to find material gaps and design the repair (`case_mode=ARCHITECTURE_AUDIT`).

Do not use for simple deterministic defects whose cause and repair are already classified and covered by an existing EKB rule.

## Case mode (V0.5)
Declare `case_mode` first:
- `INCIDENT_REPAIR`: a failure happened; explain the failure class, its recurrence and the first bad control.
- `ARCHITECTURE_AUDIT`: no single triggering incident; map the real process, find material gaps and design the repair. Audit mode relaxes only two incident-specific requirements: `recurrence_evidence` may be empty and one evidence-bound causal link per gap is enough. It does **not** remove systemic causality or controls; read the causal fields as:
  - `symptom` = observed structural gap;
  - `immediate_cause` = mechanism that directly produces the gap;
  - `systemic_root_cause` = architectural cause that allows the gap to exist;
  - `first_bad_control` = first design/governance control that should have prevented it;
  - `escape_control` = later control that should have detected it.
  A ready audit spec still requires all four `ESTABLISHED`. Every other rule still applies.

## Working method (do this first; the rules below are how the result is checked)
The rules and typed output are acceptance checks, not the method. Quality comes from the investigation:

1. **Build the real graph before judging it.** From live authority, enumerate the process nodes and edges that actually exist: operation definitions and their steps, contracts, functions/workers, runtime bindings, and the execution receipts those operations already produced. Start from what executed, not from the phase names in the request.
2. **Walk every material edge.** For each edge record producer -> transported data/contract -> consumer -> canonical authority/route -> enforcement point -> effect/readback -> terminal state, and look for it in every applicable surface: source at the exact revision, operation definitions, execution receipts/manifests, runtime readback, EKB. Mark the AS-IS edge OBSERVED_CLOSED, OBSERVED_OPEN, UNRESOLVED or PROPOSED_ONLY. A proposed repair never proves the AS-IS edge closed. When the edge emits a next gate, resolve that gate to an actual consumer or classify the edge open. When route authority, post-transition currentness, identity consistency, terminality or rollback apply, record an evidence-bound proof for each.
3. **Validate the typed candidate before freeze.** Build the draft against the exact current `schemas/output.schema.json`; verify every required object/array/string shape before computing the candidate digest or handing it to quality. In particular, executable test protocols must preserve the schema-declared collection types for setup/action/assertions. A schema-invalid draft is repaired before freeze; it is never frozen as a candidate and deferred to downstream validators.
3. **Form a working solution early.** After the first pass, state the leading hypothesis and design. Use each remaining unknown to test it: which query would confirm or break it? Run that query next. Unknowns are a search queue, not a stopping point.
4. **Chase before you stop.** Before classifying any gap as `DESIGN_BLOCKING`, consult every accessible surface that could close it and record each attempt in `attempted_sources` (surface, exact locator, result, observation, evidence_id). The `locator` must be exactly the one recorded for that `evidence_id` in the evidence manifest: evidence produced by another query cannot stand in for this attempt. Give each design-blocking uncertainty an `uncertainty_id`, and point every `DESIGN_BLOCKING` process node at it with `blocking_uncertainty_id`. A gap with no recorded attempt is not a blocker; it is unfinished work.
5. **Separate test context from system facts.** The profile revision under test, the harness and the requested scope are inputs, not defects of the audited system. Report a legitimate currentness observation, but never turn the test setup into a blocker.
6. **Cite only what you read.** Every reference must be something you actually retrieved in this run. A plausible identifier that was not read is a fabricated reference.
7. **Then compare and falsify.** Build at least three materially distinct alternatives from the graph (including reuse or elimination), falsify the leading one, and only then choose the output mode.

`NEEDS_MORE_EVIDENCE` is the right answer only when a material uncertainty survives step 4. It is never cheaper than a full investigation: a design-blocking gap must show its attempts, and every attempt must resolve in the external evidence manifest.

## Output trajectory (field order for the typed output)
FAILURE ENVELOPE -> EXACT LIVE AUTHORITY -> CURRENT REPAIR DISPOSITION -> EFFECT/PRODUCER RECONCILIATION -> SYMPTOM -> IMMEDIATE CAUSE -> CAUSAL CHAIN -> FIRST BAD CONTROL -> ESCAPE CONTROL -> DECLARED VS EXECUTED CONTRADICTIONS -> SYSTEMIC ROOT CAUSE -> ¿DEBE EXISTIR? -> UNCERTAINTY IMPACT -> SOLUTION DEPTH -> PRE-RESEARCH BASELINE FREEZE -> RESEARCH ASSURANCE -> INCREMENTAL VALUE DELTA -> DISTINCT ALTERNATIVES -> CHALLENGER -> OMISSION DISCOVERY -> TRADEOFFS -> MINIMUM SUFFICIENT REPAIR -> IMPLEMENTATION PACKAGE -> IMPLEMENTATION DECISION CLOSURE -> TRANSITION/COMPATIBILITY -> INVARIANT/HARD GUARD -> FALSIFICATION PLAN -> ROLLBACK -> HISTORICAL REGRESSION -> SEMANTIC QUALITY GATE -> RESIDUAL RISK

1. Read exact current authority, failure envelope, EKB recurrence evidence, architecture/contracts, historical occurrences, execution wiring and expected-vs-actual.
2. Resolve execution authority from live evidence across every applicable execution surface: repository/runtime, SQL functions, deployed Edge Functions, schedulers, agent connectors, runtime processes and external workers. Declared source is not sufficient proof of actual execution.
3. Materialize `live_authority_packet` with applicable surfaces, inspected surfaces, unavailable sources and an impact assessment for each unavailable source. Missing evidence blocks a repair specification only when it can materially change the selected repair, enforcement point, migration/transition strategy, rollback or acceptance criteria.
4. Before designing a repair, materialize `repair_disposition` from exact current evidence. Every disposition MUST include `repair_disposition.verification`: an executable method, explicit expected result and evidence references that independently re-check the current disposition. If the reported failure is already resolved in current authority/runtime, return `NO_REPAIR_REQUIRED` with decision `ALREADY_RESOLVED`; if the evidence does not justify a material systemic repair, return `NO_REPAIR_REQUIRED` with decision `NOT_MATERIAL`. A no-repair conclusion requires currentness/readback evidence and MUST NOT contain an implementation delta, selected alternative, transition, rollback or invented improvement. It also MUST NOT manufacture recurrence, a three-link systemic causal chain, alternatives, or ¿DEBE EXISTIR? work merely to satisfy repair-only ceremony; those structures may be empty/unresolved when they are not needed to prove the no-repair disposition.
4a. For every material live effect relevant to the causal claim, materialize one `execution_effect_reconciliation` row that binds the observed effect to its declared producer, authority reference and observed producer evidence. An unresolved producer must declare its impact and containment.
5. Separate observation, hypothesis and established conclusion. Causal fields are typed claims with `status`, `evidence_refs` and `missing_evidence`.
6. `symptom.status` must be `OBSERVED`. A ready repair spec requires the immediate cause, systemic root cause, first bad control and escape control to be `ESTABLISHED` at the failure-class level. Historical actor attribution is not itself the systemic root cause unless the repair depends on that exact actor.
7. Every causal-chain node must declare its claim status and exact evidence. Do not mix observed and inferred links in untyped prose.
8. Identify the first control that should have prevented the class of failure, not merely the last component that reported it.
9. Compare declared behavior/ownership/source with live observed effects. A current authority contradiction such as SILENT_DROP, UNDECLARED_EXECUTION or SOURCE_LIVE_DIVERGENCE is design-blocking until reconciled. Historical producer attribution may remain unresolved only if the selected repair contains every plausible producer path and the uncertainty is explicitly classified as non-design-blocking.
10. Execute the mandatory ¿DEBE EXISTIR? assessment for the subject/control: identify real consumers with evidence references, impact of removal, and a native or already-existing alternative. Do not assume an existing component deserves preservation.
11. Classify every current uncertainty as exactly one of:
   - `DESIGN_BLOCKING`: missing evidence can change the repair architecture, selected alternative, enforcement point, transition, rollback or acceptance criteria, and the accessible surfaces were consulted without closing it (V0.5: `attempted_sources` required, each resolving in the evidence manifest). `SYSTEMIC_REPAIR_SPEC` is forbidden.
   - `IMPLEMENTATION_PRECONDITION`: the repair design is stable, but implementation/activation must resolve a named prerequisite before a bounded stage proceeds.
   - `NON_BLOCKING_HISTORICAL`: attribution/history remains incomplete but cannot change the selected repair because the repair explicitly contains the unknown path.
12. Classify solution depth before solution search:
   - `LIGHTWEIGHT`: the failure class is already deterministically classified, no material architecture/control/authority/context decision is open, and current-practice research cannot change the repair.
   - `BOUNDED`: a small number of local design decisions require focused investigation but the authority and architecture boundaries are stable.
   - `DEEP_ARCHITECTURE_RESEARCH`: the repair can change cross-operation architecture, authority, policy/contract semantics, state/recovery, concurrency, context transport, security boundaries, runtime wiring, scale/cost or multiple consumers.
   Do not force deep research onto simple defects, but do not downgrade an architectural case merely to save tokens.
13. Before current-practice/external research or challenger refinement on a `DEEP_ARCHITECTURE_RESEARCH` case, and on a `BOUNDED` case where current-practice research is required, freeze `research_assurance.baseline_solution_snapshot` from internal canonical authority only. Bind it to exact input/profile-source digests and internal evidence refs, state the leading pre-research solution, known gaps and assumptions, and derive `baseline_digest` from canonical JSON. This is a measurement baseline, not a second authority.
14. Materialize `research_assurance`. Internal canonical authority is always read first. When current external techniques or practices can materially improve the design, perform current-practice research and record exact external evidence references, patterns compared and how the research changed or confirmed the solution. External research may inform technique; it never replaces LF authority.
15. After research/challenge, materialize `discovery_deltas` against the frozen baseline. Each delta must identify the baseline gap, post-baseline triggering evidence, material effect, tradeoff, final design refs and ADOPTED/REJECTED disposition. Do not count paraphrase, added prose, cosmetic novelty or a claim already present in the baseline as incremental value.
16. Set `incremental_value_outcome` to `MATERIAL_UPLIFT` only when at least one evidence-triggered delta is adopted, `NO_MATERIAL_UPLIFT` when adequate research finds no material improvement, and `UNPROVEN` when incremental utility cannot be established. `NO_MATERIAL_UPLIFT` is a valid result; do not force novelty to satisfy a WOW proxy. The producer may declare the outcome, but canonical independent semantic review decides whether the claimed materiality is credible. A ready material-research spec cannot remain `UNPROVEN`.
17. Keep the baseline/delta transport compact: carry the structured snapshot, delta records and source refs rather than full research transcripts. Target <=1200 estimated tokens and fail closed above 2400 for this proof packet; hydrate supporting detail JIT by reference.
18. The first plausible solution is not final. Record its disposition as retained-after-challenge, revised or rejected. Challenge the leading design against at least the material failure surfaces for the selected depth. `DEEP_ARCHITECTURE_RESEARCH` requires at least three evidence-bound challenges before final selection.
19. Perform omission discovery across architecture, controls, policies/contracts, context transport, wiring, compatibility/transition, recovery/terminality, observability, security/authority, cost/performance, testing/assurance and operability/maintenance. Every dimension must be explicitly resolved as REQUIRED_CHANGE, REUSE_AS_IS or NOT_APPLICABLE with evidence/rationale; silence is not closure.
19a. When a material process, lifecycle or multi-stage workflow is part of the failure class or selected repair, materialize `material_process_graph`. Every material phase/subprocess must declare authority, inputs/outputs, producer/consumer, state transition where applicable, physical wiring/control refs, failure/recovery behavior, evidence, acceptance refs and one disposition: `IMPLEMENTABLE`, `REUSE_AS_IS` or `DESIGN_BLOCKING`. Mentioning a phase is not closure. Any `DESIGN_BLOCKING` node forbids `SYSTEMIC_REPAIR_SPEC`.
19b. Materialize `quantitative_decisions` for every material threshold, timeout, deadline, polling/backoff interval, retry limit, cutoff, sample size, quorum, tolerance or other numeric policy that can change terminality, rollback timing, safety, scope or material cost. A material value may close only from an existing canonical authority or an evidence-backed calibration rule that is not specific to the triggering incident. Incident-only observations cannot close policy. If the design is stable without the exact value, leave it as a mechanically resolvable implementation precondition with no proposed value; otherwise it is `DESIGN_BLOCKING`.
20. When the repair is materially ambiguous, compare at least 3 materially distinct alternatives across prevention, complexity, blast radius, reuse, fail-closed behavior, idempotency, recoverability and operational cost. Each alternative must carry basis references. Cosmetic variants do not count as distinct alternatives.
21. `preferred_alternative` is provisional while design-blocking uncertainty exists. `selected_alternative` is allowed for `SYSTEMIC_REPAIR_SPEC` only after no `DESIGN_BLOCKING` uncertainty remains and the alternative is evidence-bound.
22. Falsify the selected/preferred design against bypass, retry, concurrency, partial failure, stale state, interrupted execution, replay/duplicate and unversioned/undeclared caller cases. At specification time each family must be either:
   - `PASS` with observed test/runtime/readback evidence; or
   - `PLANNED` with an executable verification method and expected result.
   A repair spec does not require future implementation tests to have already run.
23. `repair_level` is determined from the established failure-class root cause. It is `UNDETERMINED` only while the root cause itself is not established, not merely because some historical evidence is unavailable.
24. Derive an explicit invariant and hard guard. Use `validation_state=SPECIFIED` when the design is precise/testable but not yet implemented, `VERIFIED` only when observed post-implementation evidence exists, `PROPOSED` while still being designed, and `UNRESOLVED` when the control cannot yet be stated.
25. A ready repair spec must materialize a structured `implementation_package`, not only implementation prose. It must close:
   - architecture decisions and exact authority/reuse choices;
   - control matrix with applicability, inputs, enforcement point, blocking behavior and verification;
   - policy/contract changes and ownership;
   - context transport, including compiler/resolver, JIT vs deterministic delivery, excluded payloads and token budget when applicable;
   - end-to-end wiring with data carried and fail-closed behavior at each edge;
   - exact deliverable footprint and dependencies;
   - observability/readback signals;
   - implementation decision closure.
26. `implementation_package.decision_closure.open_design_decisions` must be empty for `SYSTEMIC_REPAIR_SPEC`. An implementer may retrieve fresh values; it may not choose architecture. Every `IMPLEMENTATION_PRECONDITION` must name an exact resolver, expected shape, deterministic decision rule and bounded stage, and must declare `design_effect=NONE`. If resolving it could change architecture, enforcement, authority, wiring, rollout, rollback or acceptance, reclassify it as `DESIGN_BLOCKING`.
27. A ready repair spec must also materialize:
   - exact `implementation_delta` describing the bounded assets/contracts/functions or policy bindings to change;
   - `transition_plan` with staged compatibility/readiness where a direct cutover could break existing consumers;
   - `rollback_plan` with inverse actions and protected historical evidence;
   - executable acceptance criteria and regression/falsification methods with setup, action, assertions and failure signal.
28. Prefer declarative/rules-as-data activation over per-caller if-chains when a shared boundary exists. Reuse canonical capabilities/policies before creating new engines, tables, runners or authorities.
29. If enforcement would break unprepared callers, caller adoption/readiness must precede enforcement. Cross-cutting enforcement should be activated in bounded reversible stages, normally per canonical consumer/operation rather than with an unproven blanket switch.
30. Historical cleanup/disposition is separate from proving the systemic repair. Do not mass force-close, rewrite history, or improve success indicators by mutating historical failures as part of the repair specification unless a separately governed disposition explicitly authorizes it.
31. Keep historical and future evidence distinct. `historical_regressions` contains observed prior occurrences with refs. `planned_regressions` contains tests still to be executed.
32. Keep current uncertainty distinct from residual risk. `current_uncertainties` contains unresolved evidence with impact classification. `residual_risks` contains risks that remain even after the specified repair. Non-ready outputs must leave residual risks empty.
33. `origin_asset`, `origin_operation` and `owner` refer to the systemic repair boundary/authority, not necessarily the unknown historical caller. If the systemic boundary itself cannot be proven, mark it `UNRESOLVED`.
34. `evidence_map` maps exact output claim paths to supporting evidence. A global bag of references is not sufficient.
35. The candidate must pass the canonical deterministic and semantic quality gates against exact evidence. External audit is additional oversight, never a hidden dependency.
36. Candidate freeze is downstream of exact-schema validation. Do not compute or publish the frozen candidate digest while the output violates `schemas/output.schema.json`; schema repair happens before freeze, not after it.
36. Return structured output only.

## Claim semantics
- `OBSERVED`: directly observed fact with one or more exact evidence references and no material missing evidence.
- `ESTABLISHED`: conclusion supported strongly enough by exact evidence to be used as a repair-design premise; no material evidence gap remains for that claim.
- `HYPOTHESIS`: plausible causal interpretation with explicit supporting evidence and explicit missing evidence.
- `UNRESOLVED`: insufficient evidence to state the claim; missing evidence must be explicit.

## Status semantics

### SYSTEMIC_REPAIR_SPEC
Means the repair design is sufficiently determined to hand off for governed implementation. It does not mean the repair is implemented or production-verified.

Requires:
- symptom observed and failure-class causal claims established;
- no unresolved current authority contradiction that can change the design;
- no `DESIGN_BLOCKING` current uncertainty or unavailable source;
- every unresolved producer is either an explicit implementation precondition or non-blocking historical gap with containment by the selected repair;
- determined repair level and resolved systemic origin asset/operation/owner;
- selected alternative declared among alternatives and at least two evidence-backed rejected alternatives;
- invariant and hard guard at least `SPECIFIED` (or `VERIFIED` when observed evidence already exists);
- all mandatory falsification families either observed `PASS` or executable `PLANNED`;
- adaptive solution depth and research assurance completed for the materiality of the case;
- leading solution challenged and omission discovery completed across all required dimensions;
- structured implementation package with architecture, controls, policy/contracts, context transport, wiring, deliverables, observability and decision closure;
- zero open design decisions; every implementation precondition is mechanically resolvable and cannot change the design;
- non-empty implementation delta, transition plan and rollback plan;
- observed historical recurrence when recurrence is part of the activation reason;
- executable acceptance/planned regressions;
- zero spec-blocking codes.

`IMPLEMENTATION_PRECONDITION` and `NON_BLOCKING_HISTORICAL` uncertainties may remain if their containment/precondition is explicit and they cannot change the selected repair.

### NO_REPAIR_REQUIRED
Use only when exact current evidence proves either that the reported failure is already resolved or that no material systemic repair is justified. It is a positive evidence-bound disposition, not a shortcut for missing evidence.

Requires:
- `repair_disposition.decision` = `ALREADY_RESOLVED` or `NOT_MATERIAL`; `UNDETERMINED` is reserved for non-ready outputs where currentness/materiality itself is still design-blocking;
- exact currentness/readback evidence;
- no selected/preferred alternative, no implementation delta/package, no transition/rollback and no residual risk presented as repair work;
- `repair_level=UNDETERMINED` and zero blocking codes;
- executable verification/acceptance proving the current disposition remains true.

### NEEDS_MORE_EVIDENCE
Use only when at least one `DESIGN_BLOCKING` uncertainty remains.

Requires:
- explicit blocking uncertainty and blocking code;
- no final selected alternative;
- no residual risks;
- root cause/repair level remain non-final when the design-blocking gap prevents establishing them;
- provisional alternatives, guard ideas and evidence requests may be preserved.

### RETURN_TO_WORKER_FOR_SELF_REPAIR / BLOCK_PIPELINE
Must not present a final selected alternative or residual risk as if a repair spec had been accepted.

## Required inputs
- exact_failure_envelope
- ekb_recurrence_and_frequency
- current_architecture_and_contracts
- authorities_and_constraints
- historical_occurrences
- gate_expected_vs_actual
- execution_wiring_inventory
- declared_vs_observed_evidence
- live execution evidence sufficient to assess which missing evidence can or cannot change the repair design

## Output modes
- SYSTEMIC_REPAIR_SPEC
- NEEDS_MORE_EVIDENCE
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE
- NO_REPAIR_REQUIRED

## Non-negotiable rules
- First plausible fix is forbidden when recurrence/materiality indicates a systemic class.
- Evidence must be revision/run/row bound where applicable.
- No implementation, GitHub write, Supabase write, runtime activation, production activation, golden promotion or S36 permission grant as a consequence of the profile recommendation.
- No creation of Cards or Skills from this profile. It may declare a capability gap for the orchestrator/owner to resolve.
- A root cause that does not explain the historical recurrence pattern is not systemic.
- Missing evidence cannot be replaced with plausibility.
- A `DESIGN_BLOCKING` gap cannot be relabeled to force a ready spec.
- An unresolved producer can be non-blocking only when the selected repair explicitly contains the unknown path.
- A hard guard must fail closed and be testable.
- Falsification `PASS` requires OBSERVED_TEST, OBSERVED_RUNTIME or OBSERVED_READBACK; otherwise use `PLANNED`.
- Evidence-class namespaces are field-specific and MUST NOT be cross-used: `recurrence_evidence[].evidence_class` accepts only DECLARED_INPUT, OBSERVED_HISTORY, OBSERVED_SOURCE or OBSERVED_LIVE; `falsification_results[].evidence_class` accepts OBSERVED_TEST, OBSERVED_RUNTIME, OBSERVED_READBACK, DESIGN_ONLY or MISSING. A test result may support a recurrence fact through its referenced history/source, but `OBSERVED_TEST` itself is never a recurrence class.
- Do not require post-implementation proof in order to write the implementation specification.
- Caller adoption/readiness must precede enforcement when compatibility is not already proven.
- Historical disposition/cleanup is not proof of systemic repair.
- Producer output cannot bypass the canonical semantic quality gate.
- ¿DEBE EXISTIR? is mandatory even when the component already exists or has prior approval.
- Currentness is evaluated before repair design; an already-resolved or non-material case must not be converted into a repair merely to satisfy the profile.
- A material numeric policy cannot be closed from one incident/sample unless that sample is itself an authorized canonical policy source.
- A lifecycle/process is not closed by naming its phases; every material node must be evidence-bound and dispositioned.

## Typed output
The output must include:
status, profile_pack_id, case_mode, repair_disposition, quantitative_decisions, material_process_graph, symptom, immediate_cause, systemic_root_cause, causal_chain, first_bad_control, escape_control, recurrence_evidence, live_authority_packet, execution_effect_reconciliation, authority_contradictions, repair_level, should_exist_assessment, solution_depth, research_assurance, alternatives, preferred_alternative, selected_alternative, rejected_alternatives, challenger_review, omission_discovery, falsification_results, origin_asset, origin_operation, owner, invariant, hard_guard, implementation_package, implementation_delta, transition_plan, rollback_plan, acceptance_criteria, historical_regressions, planned_regressions, current_uncertainties, residual_risks, evidence_map, blocking_codes, next_gate.

## Claim ceiling
CANDIDATO / READ_ONLY. This profile can diagnose, compare and specify a repair; it cannot authorize or execute that repair. A repair specification is quality-accepted only through the canonical deterministic and semantic gates. Implementation and post-implementation verification remain separate governed operations.

## Closure-proof contract
The V2 closure-proof rules (materiality -> obligations -> external evidence bindings -> derived readiness) live in `contracts/closure_proof_v2.md` and are unchanged. Fill `closure_proof` from that contract after the investigation below is done.


## Mandatory self-repair closure contract

Profile-maintenance work that changes SRCR's own producer, transport, evidence, validation, semantic-quality, or closure path MUST satisfy `profiles/systemic_root_cause_repair_lf/contracts/mandatory_self_repair_closure.v1.json`.

- The contract contains 13 mandatory closure obligations (MC-01..MC-13).
- Progress is evidence-derived only: NOT_STARTED=0, SPECIFIED=25, IMPLEMENTED=50, TESTED=75, READBACK_CLOSED=100.
- A point below READBACK_CLOSED remains open. Partial implementation, CI green, utility PASS, component existence, or producer-authored readiness cannot close it.
- The profile self-repair/update is not handoff-ready while any mandatory closure is open.
- Every status report for this work MUST report each obligation's state, percentage, evidence refs, blocking codes and remaining requirements.
- This contract is generic. Do not add lifecycle-case names, incident IDs or one-off rules to satisfy it.

- MC-13 full step-by-step replay is the final behavioral closure proof: reproduce the ungrouped trace methodology across Entrada, Investigacion, Transporte, Determinista, Jueces and Repeticiones on the exact current revision. Any open observation reopens the owning obligation and blocks self-repair closure.


## Mandatory per-run progress table

Every SRCR self-repair execution or repair iteration MUST end with the complete MC-01..MC-13 progress table derived from the exact current progress artifact/readback. The table MUST contain exactly these user-facing columns: `Punto obligatorio | Avance | Estado actual | Qué falta para 100%`.

Rules:
- Show all MC rows, including unchanged, completed, blocked or reopened points.
- Do not replace the table with prose, group rows, omit unchanged rows, or estimate progress conversationally.
- Percentages are evidence-derived only from NOT_STARTED=0, SPECIFIED=25, IMPLEMENTED=50, TESTED=75, READBACK_CLOSED=100.
- Report global progress as the arithmetic mean plus closed/total and open/total.
- If evidence is missing, keep the row open and state the missing evidence under `Qué falta para 100%`.
- If MC-13 reopens another obligation, reflect the reopened state in the same report.
