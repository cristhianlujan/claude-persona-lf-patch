# B06 G03 — Matriz literal de criterio de cierre (solo evidencia, NO cierre)

Norma: `audits/rule-quality-lote28/12_criterios_cierre_motor_7.md`, rama `lf/issue-3779-lote28-blocker-closure-plan-v1`. Estado de plantillas Bnn: INTACTO. Evaluación SOLO documental.

| Punto literal B06 | Evidencia ejecutada | Veredicto |
|---|---|---|
| Aplicar por Train autorizado #3803 → #3804 → #3806 | Commits merge y ledger Supabase, RUN #3806 `COMPLETED`, 3/3 etapas `PASS_CLEAN` | PASS |
| Preflight con SHA de cada objeto afectado | 155/155 hashes originales de before_row y 155/155 after_row, checks de SQL oficial; 83 baseline inalterados | PASS |
| 238/238 en public.lf_activos owner canónico y 0 variantes | SELECT real del Supabase actual | PASS |
| Archivo 13/13 intacto | SELECT + SHA/campo archived_at comparado por cada objeto | PASS |
| Los 155 IDs exactos convertidos | Manifest congelado #3804 y 155 recibos #3806; cardinalidad y hashes por ID | PASS |
| Recibos APPLIED con SHA antes/después y execution_id | 155/155 en `public.lf_ig_asset_owner_receipt_v2`, parent RUN real | PASS |
| INSERT fuerza canónico, UPDATE variante rechazada | R17 PG17.6/18.7 guard real `test_01_guard_and_counts` | PASS aislado |
| Negativo stale SHA | R17 PG17.6/18.7 `test_007_backfill_sha_drift_blocks` + `test_02` | PASS aislado |
| Negativo de repetición | R17 PG17.6/18.7 `test_02_authorization_active_and_archived`: segundo apply rechazado | PASS aislado |
| Negativo self-approval documental | R17 run 43389881318: `proposer_actor=decisor`, ACTIVE/ARCHIVED, excepción y 0 recibos | PASS aislado |
| Cero RUN antiguos alterados | Freeze posterior de 2456 RUNs y 8244 pasos, root `7bae2d2952c1dae06bbe32e498421a3752f9802078d29da4e218d62749512a02`, readback per-ID hash 2456/2456, 0 drift posterior | **NO ACREDITADO RETROACTIVAMENTE** (falta preimagen PRE-BACKFILL comparable) |
| Política transversal Bnn: aprobación de cierre | No hay recibo de aceptación de G03; Chat de plan decide | PENDIENTE |

**No declarar B06 CERRADO** con estos datos: los controles de owners, negativos y readback están acreditados; el requisito retrospectivo de no alteración de RUNs históricos queda pendiente de evidencia anterior. No se modificó ningún RUN. Tampoco se afirma firma humana ni restauración PITR.
