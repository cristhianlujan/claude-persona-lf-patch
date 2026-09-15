# S30 — INTERNAL RPC ACL hardening candidate

Read-only/live inventory found four internal LF surfaces executable by client roles without caller authentication inside the function:

- `lf_profile_creation_begin_v1`
- `lf_strategy_execution_begin_v1`
- `lf_operation_execution_qualification_guard_v1`
- `lf_apply_independent_strategy_review_v1`

Reference primitives already follow the desired pattern:

- `fn_lf_operation_reserve_execution_v1` → postgres/service_role only
- `lf_strategy_update_begin_v1` → postgres/service_role only

Router registration is not treated as direct PostgREST authorization. Passing an `actor_execution_id` is provenance input, not authentication of the SQL caller.

Repository search did not find an explicit client caller outside migration definitions, but this is not proof that out-of-repo consumers do not exist. Therefore this branch contains a privilege-only SQL **source candidate**, not a live migration/apply.

The proposed change revokes `PUBLIC`, `anon`, and `authenticated` execute rights from the four internal surfaces and grants `service_role`. It does not recreate or alter function bodies.

Before any live apply: owner call-path review, source-first migration, exact-head CI, and `routine_privileges` readback are mandatory.

Claim ceiling: `SOURCE_CANDIDATE_NO_LIVE_APPLY`.
