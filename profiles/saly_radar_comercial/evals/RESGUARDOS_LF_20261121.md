# SALY Ventas PTE / Radar — revisión de resguardos B1–B32 y 1–14

Objeto: candidato `PERFIL-RADAR-COMERCIAL-SALY` y flujo PE-PTE. Referencia: `LF_resguardos_construccion.md` versión 2026-11-20. No se declara ejecución autónoma completada.

## Verificaciones materiales
- B1/B2/B3/B5/B31: esquema y constraints leídos del Supabase real antes de cambios; migraciones #4493, #4505 y #4508 por Train con ledger y SELECT. Los 519 hallazgos de la primera ingesta siguen comprobados.
- B6/B11/B25/B26/B28: GitHub Actions [run 44901335603](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44901335603), job `136837683060`: `PASS_RADAR_JUDGE 19 functional cases, 4 guard mutations killed by intended assertions`; `PASS_RADAR_JUDGE_CURRENTNESS 4 checks; mutation of current-verdict hash caught`. Cada negativo exige código propio; el juez recalcula los hashes de captura/veredicto. No autentica por sí mismo un recibo proporcionado por un cliente.
- A11: el juez no muta los dos objetos de entrada; se comprueba mediante deep copy.
- A1: forma completa antes de examinar el contenido. Cambios incompatibles requerirán contrato v2 y suite completa.
- B13/B32: la política territorial activa está en `public.lf_global_config` `SALY_DISCOVERY/PTE_POLICY_V1`, resuelta por `public.lf_saly_discovery_pte_policy_v1()`; PR #4535 MERGED, readback 519. `config/pte_pilot.v1.json` sigue como contrato de pack, no es autoridad operativa. El adaptador `normalizePteCsv(text,policy)` recibe el alcance desde fuera; no trasladar valores SALY al núcleo compartido.
- A3/A4/B7: **VERIFICADO PG17.12 REAL (solo base efímera)**, GitHub Actions `44901335603`, job `136837683060`: `PASS_PTE_TWO_SESSIONS_ONE_EFFECT`, `PASS_PTE_TWO_RUNS_ONE_SNAPSHOT_ONE_EFFECT_REAL_PG17`, `PASS_PTE_SECOND_SESSION_TARGET_CONSTRAINT_saly_pte_source_batch_once_v1` y `PASS_PTE_PG17_REAL_TWO_SESSIONS_CLEANUP`. Se observó competencia real por `pg_stat_activity.wait_event_type=Lock`; efecto único y cleanup. Se utilizaron el escritor original y el índice exacto de L45; no datos reales ni entorno SALY compartido.

## Pendientes que BLOQUEAN la ejecución autónoma
1. A7/A8/A13/A14 y B10: padre/hijos, lease, timeout, cierre garantizado y recuperación de ejecutores abandonados en el motor comercial — no demostrado.
2. B12: `saly.ventas_pte_ingesta_core_v1` es la única puerta implementada del piloto, pero no existe una operación comercial y perfil Radar nativos con efecto WRITE admitido. No conceder EXECUTE a roles cliente ni servicio para omitir ese paso.
3. B13: territorio registrado en `lf_global_config`, pero **límites, timeouts, leases y reintentos operativos no están definidos**; no inventar valores. El contrato del pack no concede runtime.
4. B21: registrar recurrencia de `PE10_C6_UNAUTHORIZED_GITHUB_WORKFLOW_ENTRYPOINT_V1` por el primer fallo al añadir workflow sin admisión exacta, y aprendizaje de clasificación de paths. El writer gobernado `public.lf_write_pipeline_ekb_v1` no se puede invocar desde este conector READ_ONLY; el contrato PRE_EKB_GATE no está activo para `ACTUALIZACION_DB_LF`. No afirmar escritura EKB sin readback.
5. B30: registro documental Radar no es promoción ni habilitación; no existe Radar en `public.lf_profile_selection_registry_v1` ni `public.lf_activos`. Los callers actuales permiten solo `PERFIL-PRODUCT-DIRECTOR-SALY`. ACT-0001 rechazó target Radar con `BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED`; el literal `ok continuar` no atesta un target.
6. B19: no introducir restricciones no aprobadas. Mantener las limitaciones técnicas de RLS, contrato y fuente; cualquier cambio de política/producción debe tener procedencia explícita.

## Criterio de cierre
- **Concurrencia de doble sesión cumplida solo para escritor e índice.** Quedan por verificar configuración de límites; RUN SALY admitido por el Router y perfil Radar existente; workflow real; lectura de `lf_operation_execution`, `ventas_discovery_runs`, `ventas_discovery_ingestas` y `ventas_hallazgos`; idempotencia con segundo RUN; 519 filas preservadas sin duplicados; EKB gobernada.
- Mientras falte cualquiera, usar `NO_VERIFICADO` y no declarar 100% de motor autónomo.
