# S31 — LF Reusable Capability & Governed Development Platform — Master Plan v0.2

Status: ACTIVE / PRODUCER-HARDENED / INDEPENDENT-REVIEW-PENDING
Supersedes for forward execution: `S31_STRATEGY_BOOTSTRAP_V0_1.md`
Historical bootstrap preserved: yes
Branch: `lf/s31-bootstrap`
Base main currently bound: `d4051d9c57fdfd09741da5ba2718c032eac56c92`
Runtime activation: false
Production activation: false
Main merge authority: false
Golden promotion authority: false

## 1. Objective

Build an LF-owned reusable capability and governed-development platform by generalizing proven patterns from S30, S26, Learning Engine and Creating Integral User Stories through stable contracts, compatibility layers and ports/adapters.

S31 generalizes; owning strategies keep ownership of their internal implementations. No code is moved merely because a common abstraction is desirable. The sequence is contract -> compatibility -> deterministic/adversarial regression -> independent semantic review -> extraction/refactor candidate -> controlled cutover.

## 2. What changed since bootstrap

The bootstrap plan assumed a mostly linear progression from A through G and then independent review. Execution evidence showed that this is insufficient. S31 v0.2 therefore makes the following observed learnings first-class planning rules:

1. A deterministic PASS is not sufficient before semantic review; an adversarial bypass audit is mandatory.
2. Work Package is not only a task envelope. It is also the anti-close/currentness/execution-evidence contract.
3. `safe_parallel_work`, its count, `next_safe_batch`, blockers and close-guard must be mutually coherent.
4. An unresolved causal blocker with no independent safe work is `BLOCKED_CAUSAL_NO_SAFE_WORK`, never successful closure.
5. A discovered safe unit is an execution obligation; it cannot be left merely as a suggested next step.
6. `safe_work=0` is valid only after a global remaining-work discovery proves exhaustion.
7. Card fallback must use known, unique, ordered attempts with typed failure evidence. Manual fallback requires explicit readiness evidence and `blocker_unresolved=false`.
8. Lifecycle cannot be represented as one invented ordered enum. Artifact maturity, evidence level, runtime activation and promotion authority are separate dimensions.
9. Evidence must be monotonic: structural evidence cannot promote semantic/behavioral claims; provenance alone does not imply correctness.
10. S31 does not create a parallel semantic-review receipt. It reuses canonical Quality Pack and may extend it without replacing its contract.
11. Review freezes are scope-specific. A change in ABC does not invalidate DG unless a bound dependency actually changed.
12. Any transversal defect that materially changes architecture must, where applicable, produce: repair + regression + plan/contract evolution.
13. Within already-authorized scope, S31 continues safe work without micro-approval. Approval remains required for scope change, merge, Golden, production, destructive actions, external spend or external deployment.

## 3. EKB controls incorporated into this plan

Fresh preflight for this plan update found the following active controls materially applicable:

- `EKB-AUTONOMY-ROOTCAUSE-001`: recover autonomously inside authorized scope; retries require a new causal hypothesis/evidence.
- `SAFE_WORK_DISCOVERED_BUT_NOT_EXECUTED`: discovered safe work is an execution obligation and blocks close until drained or invalidated.
- `SCHEDULED-TASK-PREMATURE-ZERO-SAFE-WORK-001`: zero-safe-work claims require global safe-work discovery/exhaustion proof.
- `GOV-OPERATION-LIFECYCLE-MATERIALIZATION-GAP-001`: evidence class must match the class of the claim; development evidence cannot silently become promotion/live evidence.

These rules are consumed as planning controls; S31 does not mutate their owning EKB records.

## 4. Stable architecture target

```text
LF CONTROL PLANE
  Work Package / causal frontier
  Capability Registry
  Authority + Currentness
  Card / Capability Resolution
  Pre-execution Assurance
  Evidence / Receipts / Replay
  Lifecycle dimensions + promotion authority
  Learning -> repair -> regression -> plan/contract evolution
       |
       v stable ports/adapters
LF EXECUTION PLANE
  Deterministic workers
  Current S26/Profile Runtime adapter
  Future model/framework adapters
  Future durable-execution adapter
  Eval/quality adapters
       |
       v
Supabase/PostgreSQL authoritative state where applicable
Versioned repository manifests/contracts as design authority where declared
Observability as mapping/telemetry, never authority
```

## 5. Lane plan and current status

| Lane | Responsibility | Current state | Next causal gate |
|---|---|---|---|
| S31-A | Canonical Capability Model | Deterministic PASS; lifecycle v0.2 hardened | Independent ABC review |
| S31-B | LF Work Package evolution / anti-close | PASS 18/18 | Independent ABC review |
| S31-C | Canonical Cards/Fallback | PASS 19/19 | Independent ABC review |
| S31-D | Shared Authority + Typed Context | DG deterministic matrix PASS | Independent DG review |
| S31-E | Capability Registry / Manifest | DG deterministic matrix PASS | Independent DG review |
| S31-F | Evidence / Receipt / Lifecycle | DG deterministic matrix PASS | Independent DG review |
| S31-G | Runtime Ports & Adapters | DG deterministic matrix PASS | Independent DG review |
| S31-H | External Standards / bounded PoCs | PLAN ONLY | Wait for internal contracts to become semantically stable |

## 6. Mandatory execution lifecycle for every material S31 candidate

```text
Admission / Work Package
    -> fresh EKB + authority/currentness binding
    -> source/schema/contract resolution
    -> material implementation or contract change
    -> deterministic validation
    -> adversarial bypass audit
    -> repair + regression when defect found
    -> global safe-work rescan
    -> scope-specific freeze
    -> independent semantic review
       -> FAIL/BLOCKED: repair affected scope + new regression + refreeze only affected dependency scope
       -> PASS: cross-lane reconciliation
    -> integration/replay gate
    -> promotion decision only by explicit authority
```

No step may infer a stronger claim from a weaker evidence class.

## 7. Anti-close and frontier rules

Close is forbidden when any of the following is true:

- `safe_parallel_work` is non-empty;
- `remaining_safe_scope_count > 0`;
- `next_safe_batch` is present;
- an unresolved blocker still affects the targeted causal chain;
- safe-work list/count/next-batch disagree;
- frontier and close-guard disagree;
- global remaining-work discovery did not PASS;
- currentness or EKB final readback is stale/missing;
- required evidence/receipt is absent;
- a targeted scope has no terminal disposition.

A blocked scope does not hide unrelated safe scope. Freeze only the affected causal chain, recompute the frontier and continue safe parallel work.

A blocker with no independent safe work returns a causal BLOCKED state. It is not equivalent to successful strategy closure.

## 8. Adversarial audit rule

Before every semantic freeze, S31 must attempt to falsify the candidate rather than only rerun happy-path tests.

Minimum adversarial categories when applicable:

- schema bypass;
- stale/exact-head mismatch;
- merge-ref mislabeled as branch head;
- validator present but not executed;
- safe-work count/list/batch inconsistency;
- blocker hidden by zero-safe-work claim;
- duplicate/out-of-order fallback attempts;
- manual fallback without blocker-clearance evidence;
- evidence-level inflation;
- self-certification;
- authority leak to model/framework/registry discovery;
- silent provider/framework fallback;
- mutable/unfrozen review source;
- cross-scope snapshot substitution.

Any reproduced bypass becomes a regression before the affected scope can be refrozen.

## 9. Lifecycle and evidence model

S31 keeps four separate dimensions:

1. Artifact maturity label — descriptive state of the artifact; canonical vocabulary currently unresolved.
2. Evidence level — STRUCTURAL / PROVENANCE_EXECUTION / SEMANTIC / BEHAVIORAL or owner-compatible equivalent.
3. Runtime activation — whether a capability is actually active in a governed runtime.
4. Promotion authority — who/what may authorize Golden, merge, production or equivalent promotion.

Rules:

- no self-certification raises evidence level;
- provenance does not imply semantic correctness;
- deterministic PASS does not imply independent semantic PASS;
- semantic PASS does not imply behavioral/live PASS;
- CI green does not imply promotion authorization;
- no lifecycle canonical ordering is invented until an authoritative resolver exists.

## 10. Scope-specific freeze and review policy

Independent review is bound to immutable scope snapshots.

Current frozen scopes:

- ABC snapshot: `bbcd9056443059cf1da4782551a85b3a70bd2910`
- DG snapshot: `d268fd871f2e18588f9b8084e6a3f6c6e07aa438`

A later change refreezes only the minimal causally affected review scope plus any directly bound dependent scope. Unchanged scopes keep their valid frozen snapshot.

Independent review uses canonical Quality Pack `INDEPENDENT_CHAT_CONTEXT`. Producer-authored target verdicts and parallel custom receipt contracts are forbidden.

## 11. Repair -> regression -> plan evolution rule

For every material defect discovered during execution:

1. Reproduce and identify the earliest sufficient cause.
2. Repair the earliest deterministic point that owns the defect.
3. Add a positive and/or negative regression that would have caught it before the failure.
4. Decide whether the finding is lane-local or transversal.
5. If transversal, update the governing contract and this master plan or its successor.
6. Refreeze only causally affected scopes.
7. Re-run exact-head deterministic suite and required CI.

A workaround without causal repair does not count as closure.

## 12. Work Package evolution status

The original `S31_WORK_PACKAGE_EVOLUTION_CANDIDATES_V0_1.md` is historical bootstrap evidence. Its first four candidates are no longer `NEW_UNPROVEN` in forward planning because their semantics were incorporated and regression-tested in Work Package v0.2:

- frozen material source bindings;
- executed validation evidence;
- branch-head vs synthetic merge-ref distinction;
- fresh EKB execution binding.

Subsequent execution additionally proved the need for:

- schema-first validation;
- typed executed SHA;
- safe-work list/count/next-batch coherence;
- frontier <-> close-guard coherence;
- unresolved blocker cannot close.

Future Work Package evolution must continue to be evidence-driven; no speculative field additions.

## 13. S31-H — external standards / frameworks

S31-H remains deliberately after internal semantic stability. No external framework becomes LF authority or LF source of truth.

Bounded PoC order after A-G semantic reconciliation:

1. OpenTelemetry mapping — observability only.
2. MCP — capability/tool interoperability adapter.
3. A2A — typed inter-agent handoff transport.
4. One agent-framework adapter comparison (e.g. LangGraph or OpenAI Agents SDK) behind `RuntimeExecutionPort`.
5. Durable-execution comparison (Temporal/DBOS/Dapr or equivalent) only if a measured recovery/idempotency need justifies it.

Adoption requires baseline comparison, negative controls, reconstructibility without framework-internal state, independent review and explicit promotion authority.

## 14. Refactoring / extraction policy

Refactoring is not hidden inside feature validation and does not block current safe operation. Extraction happens only after contracts and compatibility are proven.

Required order:

`contract -> compatibility adapter -> existing regression replay -> shared candidate -> equivalence/dual-run -> controlled cutover -> cleanup`

No big-bang migration of S26/S30 implementations into S31.

## 15. Current review frontier

Producer-side material hardening is exhausted for the frozen candidate scopes.

Pending external evidence:

- S31 ABC independent semantic receipt;
- S31 DG independent semantic receipt.

When receipts arrive:

1. validate wrapper deterministically against frozen Quality Pack;
2. verify source refs/digests and correct scope snapshot;
3. reconcile lane findings;
4. if any lane FAIL/BLOCKED, repair only causally affected scope and add regression;
5. if reviewed lanes PASS, execute cross-lane reconciliation and integration/replay;
6. only then decide whether a new candidate is eligible for promotion discussion.

No current receipt may authorize merge, Golden, runtime activation or production.

## 16. Completion definition for S31 core

S31 core A-G is not complete merely when schemas/tests exist. Completion requires:

- contracts stabilized from observed evidence;
- deterministic and adversarial suites PASS;
- scope-specific independent semantic review PASS;
- cross-lane compatibility/reconciliation PASS;
- currentness and evidence reconstructibility PASS;
- no unresolved High/Critical applicable governance blocker;
- no safe work remaining after global discovery;
- explicit terminal disposition for every targeted core scope.

S31-H PoCs and any promotion/cutover remain separate subsequent gates.
