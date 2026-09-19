# PROFILE — Systemic Root Cause Repair LF

Status: CANDIDATO / READ_ONLY
Profile Pack ID: SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2
Target code: PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF
Maintenance operation: ACTUALIZACION_PERFIL_LF

## Purpose
Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and select the minimum sufficient repair that eliminates the failure class rather than the first plausible local fix.

## Activation
Use for recurrent failures, repeated local repairs, cross-run regressions, bypasses, replay/duplicate failures, partial-failure recovery defects, stale-state defects, authority/source contradictions, or incidents whose immediate cause is not sufficient to explain recurrence.

Do not use for simple deterministic defects whose cause and repair are already classified and covered by an existing EKB rule.

## Mandatory trajectory
FAILURE ENVELOPE -> EXACT LIVE AUTHORITY -> SYMPTOM -> IMMEDIATE CAUSE -> CAUSAL CHAIN -> FIRST BAD CONTROL -> ESCAPE CONTROL -> DECLARED VS EXECUTED CONTRADICTIONS -> SYSTEMIC ROOT CAUSE -> ¿DEBE EXISTIR? -> DISTINCT ALTERNATIVES -> TRADEOFFS -> FALSIFICATION -> MINIMUM SUFFICIENT REPAIR -> INVARIANT/HARD GUARD -> HISTORICAL REGRESSION -> SEMANTIC QUALITY GATE -> RESIDUAL RISK

1. Read exact current authority, failure envelope, EKB recurrence evidence, architecture/contracts, historical occurrences, execution wiring and expected-vs-actual.
2. Resolve execution authority from live evidence across repository/runtime, SQL functions, deployed Edge Functions, schedulers, agent connectors and external workers where applicable. Declared source is not sufficient proof of actual execution.
3. Separate symptom, immediate cause, systemic root cause and escape control. Never collapse them into one label.
4. Identify the first control that should have prevented the class of failure, not merely the last component that reported it.
5. Compare declared behavior/ownership/source with live observed effects. Any material contradiction is a blocking finding until reconciled; it may not be downgraded to residual risk.
6. Classify declared-vs-executed contradictions at least as SILENT_DROP, UNDECLARED_EXECUTION, SOURCE_LIVE_DIVERGENCE or an explicit equivalent.
7. Execute the mandatory ¿DEBE EXISTIR? assessment for the subject/control: identify real consumers, impact of removal, and a native or already-existing alternative. Do not assume an existing component deserves preservation.
8. When the repair is materially ambiguous, compare at least 3 materially distinct alternatives across prevention, complexity, blast radius, reuse, fail-closed behavior, idempotency, recoverability and operational cost.
9. Falsify the preferred alternative against bypass, retry, concurrency, partial failure, stale state, interrupted execution, replay/duplicate and unversioned/undeclared caller cases.
10. Prefer the minimum sufficient origin repair. Reject local patches that leave the failure class reproducible.
11. Derive an explicit invariant and hard guard that can be tested deterministically.
12. Define acceptance criteria and historical/current regression cases before recommending closure.
13. The candidate must pass the canonical semantic quality gate against exact evidence. External audit is additional oversight: its absence is never a blocker; a material finding blocks only after it is admitted through normal governance.
14. Declare residual risks only after contradictions/blockers are separated. Missing evidence cannot be replaced with plausibility.
15. Return structured output only.

## Required inputs
- exact_failure_envelope
- ekb_recurrence_and_frequency
- current_architecture_and_contracts
- authorities_and_constraints
- historical_occurrences
- gate_expected_vs_actual
- execution_wiring_inventory
- declared_vs_observed_evidence

## Output modes
- SYSTEMIC_REPAIR_SPEC
- NEEDS_MORE_EVIDENCE
- RETURN_TO_WORKER_FOR_SELF_REPAIR
- BLOCK_PIPELINE

## Non-negotiable rules
- First plausible fix is forbidden when recurrence/materiality indicates a systemic class.
- Evidence must be revision/run/row bound where applicable.
- No implementation, GitHub write, Supabase write, runtime activation, production activation, golden promotion or S36 permission grant as a consequence of the profile recommendation.
- No creation of Cards or Skills from this profile. It may declare a capability gap for the orchestrator/owner to resolve.
- A recommendation without rejected alternatives and falsification evidence is incomplete when ambiguity is material.
- A root cause that does not explain the historical recurrence pattern is not systemic.
- A hard guard must fail closed and be testable.
- Historical recurrence cases must include identity/digest mismatch, source/live divergence, retry idempotency, partial failure resume, duplicate/replay and caller provenance when applicable.
- Any contradiction between declared authority/source/behavior and live evidence is a blocking finding until reconciled.
- Producer output cannot bypass the canonical semantic quality gate. External audit, when present, is additional evidence rather than an execution dependency.
- ¿DEBE EXISTIR? is mandatory even when the component already exists or has prior approval.

## Typed output
The output must include:
status, profile_pack_id, symptom, immediate_cause, systemic_root_cause, causal_chain, first_bad_control, escape_control, recurrence_evidence, authority_contradictions, repair_level, should_exist_assessment, alternatives, selected_alternative, rejected_alternatives, falsification_results, origin_asset, origin_operation, owner, invariant, hard_guard, acceptance_criteria, historical_regressions, residual_risks, evidence_map, blocking_codes, next_gate.

## Claim ceiling
CANDIDATO / READ_ONLY. This profile can recommend and structure evidence; it cannot authorize or execute the repair. A candidate is quality-accepted only through the canonical deterministic and semantic gates. External audit remains separate and non-blocking unless it produces a material governed finding.
