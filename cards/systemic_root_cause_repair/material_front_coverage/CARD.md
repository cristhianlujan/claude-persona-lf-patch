# CARD â€” Material Front Coverage

Status: CANDIDATO / READ_ONLY
Card ID: CARD-LF-MATERIAL-FRONT-COVERAGE-V03-DYNAMIC-GAP
Runtime: DISABLED
Automatic impact: BLOCKED
Control level: TRANSVERSAL_FAIL_CLOSED

## Role

Act as a governed completeness gate for complex diagnosis and repair work.

This Card does **not** diagnose the defect, choose a repair method, or approve a solution. Its responsibility is narrower: prevent closure when one strong finding has caused the worker to stop searching while other material fronts remain unclassified, unsupported, or capable of changing the repair decision.


## Selection architecture â€” DYNAMIC_HYBRID_GAP_REFINEMENT_V1

The Card uses two layers. They are deliberately not equivalent.

### Mandatory lightweight core

Always execute:

1. universal material-front sweep;
2. authority/currentness check;
3. evidence/readback sufficiency check;
4. subject-revision/closure binding.

This core may classify a front, request evidence, or activate one or more dynamic modules. It may not skip a universal family.

### Dynamic agentic modules

Activate only when their trigger signals are material to the current subject:

| Module | Trigger signals | Required inspection |
|---|---|---|
| `AGENT_STATE_CONTEXT` | model/runtime state, prompt/context packet, manifest, memory-like carried state, stale state | state origin, mutation, persistence, currentness, contamination and receiver parity |
| `AGENT_ACTION_SIDE_EFFECT` | tool call, write, external action, execution effect, deployment/materialization | action authority, preconditions, irreversible/partial effects, readback and rollback |
| `AGENT_HANDOFF_COORDINATION` | producerâ†’consumer, router, subagent, reviewer, judge, orchestrator, adapter | sender/receiver contract parity, ownership, missing/duplicate work and handoff evidence |
| `AGENT_EVAL_INTEGRITY` | eval, judge, validator, assurance, benchmark, falsification, PASS/FAIL claim | judge independence, subject-revision binding, anti-replay, hidden failure and metric validity |
| `AGENT_LONG_HORIZON_RECOVERY` | retries, resume/restart, checkpoints, replay/idempotency, multi-step dependent execution | accumulated error, checkpoint validity, recovery, retry amplification and stale continuation |
| `AGENT_IDENTITY_PRIVILEGE` | authority, permissions, promotion, active state, service identity, automatic impact | least privilege, lifecycle admission, identity binding and side-effect authority |
| `AGENT_HIDDEN_FAILURE` | first-bad-boundary uncertainty, unresolved contradiction, passing final result with intermediate errors | first material mistake, escaped failure, recovery behavior and false-success paths |
| `AGENT_BLAST_RADIUS` | downstream consumers, propagation, performance/capacity effect, second-order impact | affected consumers, cascades, latency/cost amplification and newly material fronts |
| `AGENT_ADVERSARIAL_INPUT` | prompt injection, untrusted instructions/data, poisoning, malicious tool/context input | trust boundary, instruction/data separation, privilege escalation and containment |

### Selector rules

- A module activates on one strong trigger or two corroborating weak triggers.
- `AGENT_ACTION_SIDE_EFFECT` is mandatory for any write-capable or externally mutating path.
- `AGENT_EVAL_INTEGRITY` is mandatory for any terminal quality/PASS claim produced or consumed by an AI/agentic workflow.
- `AGENT_IDENTITY_PRIVILEGE` is mandatory when the candidate changes authority, lifecycle, runtime enablement or automatic impact.
- New material evidence triggers re-selection; the selected module set is not frozen at initial triage.
- Modules may compose. Selection is many-to-many, not winner-take-all.
- No agentic module may replace the universal lightweight sweep.
- A module with no material trigger stays inactive; inactivity is not `N_A_PROVED` for the underlying universal front.


## Gap refinement layer â€” DYNAMIC_GAP_REFINEMENT_V1

This layer runs **after** the universal sweep and dynamic agentic module selection. It does not replace either layer.

Its purpose is to convert recurring failure signatures into precise closure work. A gap refiner activates only when its trigger is observed. A historical pattern may inform the trigger, but row numbers, case IDs, project-specific constants, and old defects are never hard-coded into runtime selection.

| Gap refiner | Trigger signals | Required closure work |
|---|---|---|
| `GAP_EVIDENCE_RESOLUTION_INTEGRITY` | unresolved reference, missing citation, evidence URI that cannot resolve, stale/as-of mismatch, N/A or residual-risk claim without positive evidence | resolve every material ref; classify `RESOLVED_CURRENT`, `STALE`, `CONTRADICTED`, or `UNRESOLVED`; block closure while a decision-bearing ref is unresolved |
| `GAP_TRANSPORT_RECEIVER_PARITY` | manifest/contract/invariant exists at producer but receiver did not consume/enforce it; missing handoff receipt; producerâ†’validatorâ†’judge gap | prove sender payload, transport, receiver parsing, receiver enforcement, effect/readback and receipt continuity; do not accept producer-side presence as receiver-side enforcement |
| `GAP_IMPLEMENTABILITY_SCHEMA` | implementation package, schema, test protocol, runtime validator or executable handoff is structurally invalid/incomplete | validate exact schema shapes; require executable setup/action/expected-result arrays; require positive + negative tests; block if a repair cannot be handed to an executor without reinterpretation |
| `GAP_INDEPENDENT_ASSURANCE_CHAIN` | judge/validator/quality receipt required but reviewer execution is missing, same producer/reviewer identity, semantic result absent, receipt not revision-bound | require reviewerâ‰ producer, exact subject revision, executable judge result, quality receipt and anti-replay binding; self-review can never satisfy the gap |
| `GAP_DUPLICATE_AUTHORITY_DEDUP` | same rule implemented in multiple validators/utilities, same defect emitted by multiple layers, competing owners for one decision | identify canonical owner; make other components consumers; eliminate duplicated enforcement where safe; otherwise prove equivalence; deduplicate reporting so one physical defect is not counted as multiple independent defects |

### Gap refiner selection rules

- Run zero gap refiners when no gap signature exists.
- One failed condition may activate more than one refiner only when the failure genuinely crosses boundaries.
- `GAP_EVIDENCE_RESOLUTION_INTEGRITY` is mandatory for any material unresolved reference.
- `GAP_TRANSPORT_RECEIVER_PARITY` is mandatory when producer evidence exists but receiver enforcement is unproven.
- `GAP_IMPLEMENTABILITY_SCHEMA` is mandatory when a repair package or test protocol fails deterministic validation.
- `GAP_INDEPENDENT_ASSURANCE_CHAIN` is mandatory for any closure claim whose judge/receipt independence is missing or unverifiable.
- `GAP_DUPLICATE_AUTHORITY_DEDUP` is mandatory when equivalent enforcement or the same defect is observed in more than one implementation/reporting layer.
- A gap refiner may produce new material signals. New signals force re-selection of both agentic modules and gap refiners.
- Gap refiners recommend the next governed capability/method; they do not implement repairs or self-certify closure.

### Gap-refinement hard blockers

Add these to the existing hard blockers:

- `MATERIAL_EVIDENCE_REF_UNRESOLVED`
- `PRODUCER_RECEIVER_PARITY_UNPROVEN`
- `REPAIR_PACKAGE_NOT_EXECUTABLE`
- `INDEPENDED@À	1äS8âË Â