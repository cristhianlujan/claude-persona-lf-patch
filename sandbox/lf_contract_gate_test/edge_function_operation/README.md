# EDGE_FUNCTION_DEPLOY — Operation route (candidate)

M10.5/CP2, reusable scope: single existing Supabase Edge Function. Migration Train remains exclusively DB migration transport. This operation is not a profile runtime refresh.

## Boundaries
- Current authority: public.lf_operation_registry, public.lf_operation_execution and public.lf_operation_effect_guard. Do not create duplicate operation/effect stores.
- Target: SUPABASE_EDGE_FUNCTION with canonical path \`supabase/functions/<slug>\` from a **single exact main commit**.
- Required before effect: R17 runtime preflight **canonical event**, prior deployed source byte-parity with rollback Git SHA, source exact-main parity, approved change scope, preserved JWT verification behavior, operation in current admitted state, effect guard reserved exact, and signed human authorization for runtime deployment.
- Required after effect: Supabase-managed deployed function files and version independently read back against expected source; fresh real GitHub OIDC preflight with no \`OIDC_ACTION_SCOPE_MISMATCH\`; reject fake pass from local tests; readback receipt; rollback verified if deploy fails.
- No app release promotion, no CP2 verdict fabrication, no SQL write, no modification of Curator/Validator or any other Edge Function, no auto-deployment on merge.

## Stage 1 — validated preflight
\`edge_deploy_guard_v1.py\` is a *pure, deterministic gate*, not a deployer. It returns \`READY_FOR_GOVERNED_DEPLOY\` only after an **authenticated operation** has retrieved independent proofs. Caller-supplied booleans/JSON do not grant authority; the authenticated Operations entrypoint must derive these values from canonical readbacks and signed receipts. \`DRY_RUN_ONLY\` has zero effects.

Positive and negative tests: \`python -m unittest discover -s sandbox/lf_contract_gate_test/edge_function_operation -p 'test_*.py' -v\`.

## M10.5 exact evidence (non-authoritative snapshots)
- Old Edge v23 has \`index.ts\` + \`caller.ts\`; both are exact-equal to rollback SHA \`cbaecd8d154b593f7d16126e9f3097797f31a7aa\`.
- Merged source includes \`cp2_edge_bridge.ts\` in Git, and newer \`caller.ts\`; PR 2561 CI green, PR 2562 EKB registered.
- Current release is INPUT_GOVERNANCE@1.0.0 with no previous version; real CP2 runs remain forbidden while canonical vNext authorization is absent.
- R17 before deploy: current telemetry had only two measured samples (~49924 ms). Need adequate current preflight evidence for actual runtime effect, not an invented success.
- Deployment credential needed for Supabase Edge Management API; no access token is asserted to exist in GitHub Environments.

## Stage 2 — not implemented or authorized by this candidate
1. Bind target to existing ACT-0001 Operations routing plus candidate registry/contract, using a separate Train-managed registry migration with readback.
2. Bind the authenticated, protected Operations transport to canonical R17/event/effect-guard readbacks. Must *not* trust arbitrary JSON preflight fields or use the profile deployment carrier as a generic Edge carrier.
3. Authorize controlled runtime deploy, execute only target via official Supabase CLI / Management API, preserve existing JWT mode, compare exact deployed source independently, and record an effect receipt through the existing operation-effect guard.
4. Run single OIDC preflight and verify deliberate \`VNEXT_RELEASE_OR_SIGNED_AUTHORITY_MISSING\` denial until real release is signed. Never trigger the 13-screen execution from deployment itself.

**Status:** Candidate code and unit tests; NO deployment, NO operation route activation, NO CP2 completion.