# SALY Ventas PTE / Radar — revisión de resguardos B1–B32 y 1–14

Objeto: candidato `PERFIL-RADAR-COMERCIAL-SALY` y flujo PE-PTE. Referencia: `LF_resguardos_construccion.md` versión 2026-11-20. No se declara ejecución autónoma completada.

## Verificaciones materiales
- B1/B2/B3/B5/B31: esquema y constraints leídos del Supabase real antes de cambios; migraciones #4493, #4505 y #4508 por Train con ledger y SELECT. Los 519 hallazgos de la primera ingesta siguen comprobados.
- B6/B11/B25/B26/B28: `node profiles/saly_radar_comercial/evals/test_judge.mjs` ejecutado sobre archivos con SHA Git `71f8df697c5d7478c614b430d6eb9f197eb546ee` (judge) y `3068bbd3bc0db29ee29ce76d99f0af0687ecf657` (tests); resultado `PASS_RADAR_JUDGE 19 functional cases, 4 guard mutations killed by intended assertions`. Cada negativo exige código propio. El juez recalcula hash de captura y del veredicto. No autentica por sí mismo el supuesto readback.
- A11: el juez no muta los dos objetos de entrada; se comprueba mediante deep copy.
- A1: forma completa antes de examinar el contenido. Cambios incompatibles requerirán contrato v2 y suite completa.
- B32: los valores de la instancia SALY están en `config/pte_pilot.v1.json` y se entregan como política independiente; no trasladarlos al núcleo compartido.

## Pendientes que BLOQUEAN la ejecución autónoma
1. A3/A4/B7: dos sesiones Postgres 17 reales en competencia, incluida prueba de replay simultáneo entre RUN diferentes. El script `supabase/tests/saly_ventas_pte_writer_core_v1_concurrency.py` existe pero no posee PASS ejecutado; no inferir PASS por el merge de la migración.
2. A7/A8/A13/A14 y B10: padre/hijos, lease, timeout, cierre garantizado y recuperación de ejecutores abandonados en el motor comercial — no demostrado.
3. B12: `saly.ventas_pte_ingesta_core_v1` es la única puerta implementada del piloto, pero no existe una operación comercial y perfil Radar nativos con efecto WRITE admitido. No conceder EXECUTE a roles cliente ni servicio para omitir ese paso.
4. B13: `public.lf_global_config` todavía no tiene configuración SALY para límites/timeout/reintentos; no inventar umbrales numéricos. El JSON de producto en este pack no sustituye configuración operativa en Supabase.
5. B21: EKB debe recibir hallazgo de concurrencia no acreditada y veredicto enmascarado mediante su escritor gobernado `public.lf_write_pipeline_ekb_v1`; el conector SQL disponible es READ_ONLY. CANDIDATO de EKB no equivale a escritura verificada.
6. B30: registro documental Radar no es promoción ni habilitación; no existe Radar en `public.lf_profile_selection_registry_v1` ni `public.lf_activos`. Los callers actuales permiten solo `PERFIL-PRODUCT-DIRECTOR-SALY`.
7. B19: no introducir restricciones no aprobadas. Mantener las limitaciones técnicas de RLS, contrato y fuente; cualquier cambio de política/producción debe tener procedencia explícita.

## Criterio de cierre
- Evidencia de sesión dual real Postgres; configuración de límites; RUN SALY admitido por el Router y perfil Radar existente; workflow real; lectura de `lf_operation_execution`, `ventas_discovery_runs`, `ventas_discovery_ingestas` y `ventas_hallazgos`; idempotencia con segundo RUN; 519 filas preservadas sin duplicados; EKB gobernada.
- Mientras falte cualquiera, usar `NO_VERIFICADO` y no declarar 100% de motor autónomo.
