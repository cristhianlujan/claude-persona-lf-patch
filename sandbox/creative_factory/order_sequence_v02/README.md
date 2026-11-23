# SALY Creative · single screen per order (recovery V2)

## Scope / user authorization
Owner authorized exactly **one screen per creative order**, with Home first and Solicitar adelanto as a second, independent order **only after Home reaches TERMINADO**. Automatic succession must be enforced by persisted predecessor dependency, not by QUEUE_MAX=1 alone. No in-chat microapprovals.

## Root cause / fail-forward
- Initial PR #4647 failed production apply at Train run #45121710112 (ledger operation EXEC-DB-TRAIN-PR4647-20261123060457-R45121710112, status BLOCKED, reason APPLY_FAILED_BEFORE_LEDGER_EFFECT). Production readback showed zero new orders and no sequence table.
- Live trigger saly.creative_order_context_guard_l2a requires SEALED context_set_id when inserting PLANIFICADO. The original PG17 fixture omitted the trigger, falsely passed; original PR closed without merge.
- New V2 migration is a distinct version/source, never replays failed target/version. It creates **separate** context sets with current registry identity versions: Home: two approved official + five candidate version refs; Adelanto: two approved official + three candidate refs. L2A seals and order inserts are checked by actual SQL triggers. CANDIDATE remains CANDIDATE.
- SQL transaction introduces APP_SCREEN_SINGLE, strict one item per order, a cross-order immutable dependency, status/RUN block before prior TERMINADO, and two registered order records (Home and Adelanto). Both order scope_json store full reviewed prompt and its verified SHA. Legacy batches unmodified.
- Review-only flag remains true and render authority false; **this migration registers but does not dispatch**. Native dispatch/queue V02, render wire V05, host receipt, and automatic worker are not deployed in Supabase and cannot be claimed as operative.

## Tests
- Source live readbacks: pg_get_functiondef of saly.creative_context_set_guard_l2a(), saly.creative_context_token_guard_l2a(), saly.creative_order_context_guard_l2a(). Definitions are included verbatim in PG17 disposable fixture, not substituted with simplistic mocks.
- PostgreSQL 17.12 disposable database; run [#45122658300](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45122658300), exact HEAD `e9ae0cd0118340b34051de877309512d1e561497`: PASS.
- Readback: one item per new order, 2 SEALED contexts, 12 context token refs, dependency Home→Adelanto, 0 RUN, older batch remains with 2 items.
- Four negative checks: extra screen, cycle, successor EN_PROCESO before Home TERMINADO, successor RUN early. Contract returns exact errors. Full SQL trigger baseline is not cloned; only three context guards reproduced.
- Temporary CI workflow was removed after passing. No mutation of Supabase outside PR/Train.
- Gate before deploy: PASE, migration parity, Merge Train REAL, Supabase schema + rows + immutability readback. No claims of verified deployment before this.
