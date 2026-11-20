# L34 — RUN PR3807 después del corte L33

- RUN: `EXEC-DB-TRAIN-PR3807-20261113083527-R43394317535`.
- Corte histórico L33 `2026-11-13 08:36:22.461152 UTC`: `IN_PROGRESS`, SHA fila `816fd126b14f6904dc468d69df679e2462aff843be1fc0425317f0a7a76a1e57`.
- Readback Supabase SELECT `2026-11-13 13:51:37.065582 UTC`: `COMPLETED`, `completed_at=2026-11-13 08:36:51.996711 UTC`, SHA fila nueva `2be5bd14fd90479cc6e4ee9ec83aa255ff6ca773ab461fbe1f6daeaa4e3b78cf`.
- Ledger `supabase_migrations.schema_migrations`: version `20261113083527`, nombre `lf_router_scope_receipt_consumer_v2`, `statement_count=1`.
- Manifest del RUN: `pr=3807`, `train_run_id=43394317535`. Path exacto `supabase/migrations/20261113083527_lf_router_scope_receipt_consumer_v2.sql`.
- Evidencia GitHub Train previa: [Run 43394317535](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43394317535).
- Guard local: 1 entrada `SUCCEEDED` con recibo no vacío; pasos 3 con evidencia ref; idempotencia no duplicada en lectura de cohorte.
- **CLASE DOCUMENTAL D** por cambio de estado respecto al corte. **NO sustituir** por un RUN nuevo, no reabrir, no repetir ni sobrescribir.
- **Operaciones/DBA/Merge Train**: firmar cotejo causal entre ledger, PR SHA, RUN, guard receipt y ejecución oficial; adjuntar PK/tx/commit con firmas y auditor independiente. Sin prueba externa completa, `EFFECT_RECON_RECEIPT=NOT_ISSUED`, `safe_to_close=false`.
- Este contraste prueba ledger y transición temporal, **NO** la identidad humana del proponente ni la firma G01/G02.

Consulta SELECT ejecutada:
```sql
SELECT m.version,m.name,coalesce(array_length(m.statements,1),0) AS statement_count,
r.execution_id,r.operation_code,r.status,r.completed_at,r.manifest->>'train_run_id' AS manifest_train_run,
(r.manifest->>'pr') AS manifest_pr,r.target_path,clock_timestamp() AS readback_at_utc
FROM public.lf_operation_execution r
LEFT JOIN supabase_migrations.schema_migrations m ON m.version='20261113083527'
WHERE r.execution_id='EXEC-DB-TRAIN-PR3807-20261113083527-R43394317535';
```
