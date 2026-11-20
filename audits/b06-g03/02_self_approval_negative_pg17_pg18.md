# B06 G03 — Negativo proponente = decisor, guard desplegado

**Entorno:** PostgreSQL Docker **17.6** (server_version_num 170006) y **18.7** (180007), CI GitHub Actions; NO Supabase vivo.
**Guard usado:** `supabase/migrations/20261113070051_lf_asset_owner_one_name_guard_v1.sql`, desplegado mediante #3804. Suite `sandbox/lf_contract_gate_test/edge_function_operation/test_ig_asset_owner_one_name_pg18.py`, prueba `test_025_b06_proposer_is_decisor_denied`.
**CI RAW:** https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43389881318, job `131766978735`: 234 tests/234 PASS, incluye caso nuevo heredado para las dos versiones.

| Negativo probado | PG17.6 | PG18.7 |
|---|---|---|
| Actor de propuesta sintético `manifest.proposer_actor=Cristhian Luján` igual a `p_decision.decisor=Cristhian Luján` | PASS | PASS |
| Error literal `LF_IG_ASSET_SELF_APPROVAL_FORBIDDEN` para activo no archivado | PASS | PASS |
| Mismo error para activo archivado, writer `approve_archived_v3` | PASS | PASS |
| Recibos nuevos para cada ID | **0** | **0** |
| Conteo total de recibos, SHA de activo y `manifest.proposer_actor` intactos tras excepción/rollback | PASS | PASS |

Marcadores RAW:
`PASS_B06_SELF_APPROVAL_PROPOSER_EQ_DECISOR_ACTIVE_REJECTED_ZERO_NEW_RECEIPTS`
`PASS_B06_SELF_APPROVAL_PROPOSER_EQ_DECISOR_ARCHIVED_REJECTED_ZERO_NEW_RECEIPTS`
Ambos aparecen por separado en los dos motores.
No se invocó el escritor en Supabase real y no se alteraron los RUNs reales. La suite tiene test de replay y stale SHA ya ejecutados en CI.

**PASE:** corrida inicial de este PR `43389881301` FAIL solo por `FAIL_CI_PLAN_APPLICABILITY_UNRESOLVED:CLASSIFICATION_REQUIRED` al incluir nuevos artefactos `audits/b06-g03`; se agregó changeset de clasificación exact-path en este PR para reejecutar CI y NO confundir PASE con resultado del negativo PG.
