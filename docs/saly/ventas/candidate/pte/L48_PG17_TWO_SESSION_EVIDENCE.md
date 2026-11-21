# SALY Ventas — L48 evidencia de concurrencia real PostgreSQL 17

**Estado B7:** VERIFICADO en el escritor PTE y en el índice de snapshot. **No implica RUN comercial autónomo.**

- Fuente gobernada: PR #4538 (admisión exacta del workflow) → MERGED `20af8d8089325cd9f52eb90d118b44fa2810a838`.
- Código/ejecutor: PR #4540 → MERGED `e9d2ab677e80a08e6300788aa09f49f370be85d1`.
- Workflow: [SALY PTE PG17 real concurrence](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44901335603), run `44901335603`, job `136837683060`, estado **completed / success**.
- Ambiente: `postgres:17`, PostgreSQL **17.12** Docker de GitHub Actions, base desechable `saly_pte_writer_ci`. Sin conectar a `mhwmirqcgxxukpctffuv` ni a ninguna base compartida.
- Test 1: `supabase/tests/saly_ventas_pte_writer_core_v1_concurrency.py`. Evidencia: `PASS_PTE_TWO_SESSIONS_ONE_EFFECT`.
- Test 2: `supabase/tests/saly_ventas_pte_crossrun_pg17_concurrency.py`, dos RUN diferentes compitiendo por `source_id,source_version,scope_key,batch_key`. Evidencia: `PASS_PTE_TWO_RUNS_ONE_SNAPSHOT_ONE_EFFECT_REAL_PG17`, `PASS_PTE_SECOND_SESSION_TARGET_CONSTRAINT_saly_pte_source_batch_once_v1`.
- Se confirmó competencia por bloqueo real `pg_stat_activity.wait_event_type=Lock` y verificación `1 ingesta / 2 hallazgos` sintéticos después del commit.
- Limpieza: `PASS_PTE_PG17_REAL_TWO_SESSIONS_CLEANUP`, sin filas de fixture.
- Tests de integración: `PASS_PTE_SCOPE_CONFIG 11 tests`, `PASS_RADAR_JUDGE 19 functional cases, 4 guard mutations killed by intended assertions` y `PASS_RADAR_JUDGE_CURRENTNESS 4 checks; mutation of current-verdict hash caught`.

**Readback real SALY posterior al CI:** `saly.ventas_hallazgos=519`, `saly.ventas_discovery_ingestas=1`, índice `saly_pte_source_batch_once_v1=1`, Radar nativo `0` RUNs y `0` registros. La integridad del snapshot 2026-08 está preservada.

**No acreditado:** RUN Radar creado por ACT-0001, operación comercial gobernada, escritura operativa recurrente, cierre padre-hijos, timeouts/leases productivos y escritura EKB. No usar los PASS del CI como evidencia de esos controles.
