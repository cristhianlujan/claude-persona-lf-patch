# S30 — OPERATION_BOOTSTRAP_LF candidate

This package isolates the transversal execution-bootstrap gap found across LF operations.

Live readback on 2026-09-14 showed:

- 20 operations with an active `init_execution` step;
- only 3 named `*_begin_v1` functions;
- only 8/20 init topologies with exact active contract + binding + judge coverage;
- 22 `IN_PROGRESS` executions with zero recorded steps across 12 operations;
- 9 of those zero-step executions belong to operations that already have active `init_execution`;
- 13 belong to older operations with no active init topology and therefore require reconciliation, not blind backfill.

The operation-neutral recorder `lf_record_operation_step_core_v1` intentionally blocks `init_execution`, so the correct abstraction is a separate bootstrap core, not a special case in the post-init recorder.

## Candidate model

`lf_operation_bootstrap_policy` provides explicit admission per operation:

- `GENERIC`: the generic service-role-only begin endpoint may initialize it;
- `WRAPPER_REQUIRED`: operation-specific target validation remains mandatory, then the wrapper delegates to the common bootstrap core;
- `DISABLED`: bootstrap is blocked.

The source candidate performs no automatic legacy repair. Existing zero-step rows belong to `EXECUTION_RECONCILIATION_LF` because their historical intent/outcome cannot be inferred safely.

No operation is seeded/admitted by this candidate. Topology and policy must be proven first.

## Security boundary

The new candidate endpoints are invoker functions and explicitly revoke `PUBLIC`, `anon`, and `authenticated` execute rights; only `service_role` receives execute. Existing begin/guard ACL drift discovered during inventory is intentionally left to a separate S30 security hardening lane so this PR remains exclusive.

## Claim ceiling

`SOURCE_CANDIDATE_READ_ONLY` only. No Supabase mutation, migration history write, runtime cutover, production activation, legacy execution backfill, merge-main, or Golden authorization is included.
