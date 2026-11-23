# SALY · V14 serial queue infrastructure — governed deployment

## Authorized purpose
- One order = one screen.
- Home must be TERMINADO before Solicitar adelanto can be claimed.
- The queue uses **QUEUE_MAX=1** from `saly.config_global` as a capacity constraint and `creative_order_sequence_dependency_met_v1` as the independent predecessor gate.
- No manual generation and no fake delivery; Native host is explicitly **not integrated** in this lot.

## Source and delta
- Consolidates the already reviewed candidate SQL sources `queue_v02` (blob `a4462eb62e2c19015d9da57c41a9d0664ba2bbc6`) + `queue_v06` (blob `e348d6a46079bd421234f80fd0d8dccaab8795d7`) into one governed migration.
- Adjustments: `FOR UPDATE OF i SKIP LOCKED`, predecessor check at claim, and single-screen terminal state `TERMINADO` after **both** independent QA and host-attested VERIFIED delivery. Synthetic text receipt always rejected. Single-screen closure errors roll back transaction.
- `creative_queue_claims_v1` and `creative_queue_native_delivery_evidence_v1` are **private** (RLS FORCE, no policies or grants). Revokes explicit on all queue RPCs and application roles. No privileged host connection was fabricated.
- Existing two orders stay `PLANIFICADO` + their items `PENDIENTE`, `review_only=true`, `render_authorized=false`, `rendering_authority=false`. No RUN or claim occurs on deploy.
- No change to historic creative orders or brand records. No provider call, no asset movement.

## Verified PG17
- GitHub Actions run **[45125052737](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45125052737)** on head `1bb0c902473a81d5c94ef03644b79557799a9b5f`: **SUCCESS**. PostgreSQL 17 isolated, no Supabase credentials.
- PG17 log: `PASS_QUEUE_V14_7_POSITIVE_NEGATIVE_AND_ACL` + `PASS_CREATIVE_QUEUE_STAGING_PG17_LIVE_DEPENDENCY_ACL_AND_2_WORKERS`. Cases: initial EMPTY without render auth, HOME first in test fixture, BLOCKED while active, text receipt rejected, false DONE rejected, Adelanto EMPTY until Home TERMINADO, then Adelanto claimed, ACLs denied, zero RUNs/artifacts and two physical workers with only one claim.
- The test harness is a selective fixture based on V02 with user order sequence. **It is not a clone of production**. Real DB apply needs unchanged-preflight, migration ledger and postdeployment readback. No E2E Native success is claimed.
- The temporary workflow was removed after the CI PASS.

## Critical next stages — not satisfied by this deployment
1. Trusted host Native adapter for image-gen invocation in the same chat. A repository function alone cannot send ChatGPT Native commands.
2. V05 render wire, V07-V11 archive and reservation ports, V12 admission+completion conditioned on independent QA, and authenticated host evidence `message_id` + actual image bytes. Everything tested before any grant to a worker.
3. Only once trustworthy credentials, actual host adapter, and QA are operational should the order flags transition through a **separately governed activation**. Do not falsely flip `render_authorized` or `review_only` without these.
4. Automatic follow-on is derived from predecessor status: the worker must requery eligible queue items after Home `TERMINADO`. A DB-only queue without a running worker does not act autonomously.

## Constraints
B1/B2/B3/B4/B6/B7/B8/B11/B13/B18/B19/B20/B25/B27/B28/B30/B31.
