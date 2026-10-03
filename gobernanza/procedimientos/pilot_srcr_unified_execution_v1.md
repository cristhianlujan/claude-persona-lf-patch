# PILOT-SRCR-UNIFIED-EXECUTION-V1

Status: CANDIDATE_SPEC_FREEZE
Scope: SPEC_AND_GOVERNANCE_ONLY

## Canonical authority

- Supabase handoff: `public.lf_eventos.id=15186`
- Governance amendment: `public.lf_eventos.id=15188`
- Protocol EKB: `GOV-SRCR-PILOT-EXECUTION-PROTOCOL-001`
- Pilot profile: `PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF`
- Profile pack: `SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6`
- Frozen profile source: `cb455027df2d2e2795ab66d41a539e217a04966f`
- Post-freeze profile head excluded by authority: `e0e8a40b`
- Canonical profile contract for the frozen source: `profiles/systemic_root_cause_repair_lf/contracts/main_contract.md`

This file is a repository representation of the already-authorized pilot plus its strict-sequencing amendment. It does not supersede Supabase/EKB. Any contradiction fails closed to events 15186/15188, the active EKB, and the exact frozen profile source.

## Explicit limits

- No code implementation in this PR.
- No merge.
- No runtime activation.
- No production mutation.
- No changes to `CREACION_PERFIL_LF`.
- One solution per PR; this PR is PR-A only.
- ZIP artifacts are forbidden.

## Mandatory pre-run protocol

Before every run, in this order:

1. Read the exact current PR head, diff, and checks for the solution being exercised.
2. Read matched EKB for the exact scope.
3. Read the current canonical contract.
4. Verify synchronized coupled surfaces at exact identities.
5. Report global progress, every gate progress/status, and blocker count.

After each solution or run, persist material new or recurrent learning in EKB before closure. A gate reaches 100% only after required evidence and readback are clean and coupled surfaces are synchronized.

Global progress is the arithmetic mean of the 15 gate percentages.

## Strict sequential execution

Gate order is exactly `G01 -> G02 -> G03 -> G04 -> G05 -> G06 -> G07 -> G08 -> G09 -> G10 -> G11 -> G12 -> G13 -> G14 -> G15`.

`G(n+1)` MUST NOT START until `G(n)` is 100% with clean evidence/readback, EKB synchronized, coupled surfaces synchronized, and blocker count 0. No parallel gate advancement.

Any observed work concerning a later gate before its predecessor closes is diagnostic only and MUST be reported as `OUT_OF_ORDER_PROGRESS`; it is not valid gate advancement until reconciled.

Every run summary MUST include all 15 gates with: gate id/name, percentage, status, what changed, evidence refs, PR ref when applicable, EKB status, coupled-surface sync, and blockers; plus global percentage, current gate, blocker count, and out-of-order flag.

## Invariants

- `INV-01`: only `advance_execution` determines the next executable task.
- `INV-02`: only a result carrying the current `lease_fence` may advance execution state.
- `INV-03`: terminal execution implies zero executable pending task.
- `INV-04`: operation spec, profile source, and executor bindings are frozen at execution start.

## Gates

| Gate | Name | Requires | Closure intent |
|---|---|---|---|
| G01 | EXECUTION_SPEC_FREEZE | — | Freeze exact pilot spec and its identities. |
| G02 | EXECUTION_IDENTITY | G01 | Define one canonical execution identity binding operation spec, profile source and executor binding. |
| G03 | TASK_ENVELOPE | G01,G02 | Freeze the generic task envelope consumed by executors. |
| G04 | RESULT_ENVELOPE | G03 | Freeze the generic result envelope bound to execution/task/attempt/fence. |
| G05 | CLAIM_LEASE_FENCE | G03 | Claim is durable and fence-protected; stale workers cannot advance state. |
| G06 | SUBMIT_RESULT | G04,G05 | Result submission is idempotent and rejects stale/mismatched identity or fence. |
| G07 | ADVANCE_EXECUTION | G06 | Sole authority computes and persists the next task. |
| G08 | CHECKPOINT | G06,G07 | Durable monotonic checkpoint bound to current fence and execution identity. |
| G09 | TERMINALITY | G07,G08 | Terminal state proves no executable pending task and transport is non-authoritative. |
| G10 | RETRY_ATTEMPT_POLICY | G05,G08,G09 | Retry creates a bounded attempt without reusing stale result/fence identity. |
| G11 | FAILURE_INJECTION_AND_247_ACCEPTANCE | G01-G10 | Failure injection + all 247 step results; independent semantic judge mandatory; aggregate PASS cannot hide misses. |
| G12 | STATE_AUTHORITY | G11 | `public.lf_operation_execution` is sole state authority; queues are transport/projection only. |
| G13 | PROFILE_SOURCE_BINDING | G12 | Profile SHA is independent of runtime release SHA; capability preflight happens before model call. |
| G14 | DB_CHANGE_PROVENANCE | G13 | Every DB mutation records repo, branch, source SHA, migration path/digest, execution ID, environment and authorization. |
| G15 | RUNTIME_OWNERSHIP | G14 | Generic runtime contains no profile-specific SRCR/baseline/operation-routing logic and is not modified from profile branches. |

The sequential amendment governs progression even where the original dependency list did not explicitly name the immediately preceding gate.

## PR partition

- PR-A — Execution spec and task contract.
- PR-B — Supabase durable task advancement.
- PR-C — Generic runtime task consumer.
- PR-D — Semantic judge as generic executor.
- PR-E — SRCR pilot binding and config.

A solution may not share a PR with another solution.

## Separate verdicts

### Architecture verdict
Independent. Determines standard eligibility. Measures at minimum:

- orphan count
- stale fence rejection
- checkpoint recovery
- terminal-state consistency
- runtime profile-literal count
- spec-freeze integrity
- single next-task owner

### SRCR V0.6 quality verdict
Independent from the architecture verdict and does not decide standard eligibility. Measures at minimum:

- 247 individual step results
- mandatory independent semantic judge
- no aggregate result may conceal a missed step

A profile candidate freeze or deterministic/pre-quality PASS is not SRCR semantic acceptance.

## Frozen task/result contract

The machine-readable contract is `gobernanza/contratos/pilot_srcr_unified_execution_task_contract_v1.json` in the same PR. Its sections for later gates are frozen contract content, not later-gate execution progress. Runtime/database implementation and exact readback remain separate sequential gates.
