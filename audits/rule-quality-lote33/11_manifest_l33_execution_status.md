# L33 — manifiesto ejecutado de B02/G01, PR #3803 y PG18 (read-only)

**Estado:** DRAFT / G01 pendiente de autoridad+custodia+auditor. B02/B03 ABIERTOS. No declarar PASS de gate, GO ni firma de dueño. Proyecto Supabase temporal `mhwmirqcgxxukpctffuv`. Autor: GPT-6, no auditor independiente.

## Lote y ejecución
1. Se releyeron EKB V1.4, L28 doc 12 blob `130d474921e0ad010e94a645a8f350f3ca86e611` y L32 SQL 05 blob `9a015ed8b6c18c52bd642f91de32796d8c305afc`. Decisión de dueño: universo total `IN_PROGRESS`, 32 solo prioridad, `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`, identidad humana no verificada.
2. Supabase SQL SELECT real en una transacción `REPEATABLE READ READ ONLY`, rollback al final; rol `supabase_read_only_user`, PG17.6. **as_of `2026-11-13 08:36:22.461152+00`**, MVCC `619221:619221:`, **235 IDs únicos**. Fuente SQL exacta del corte en `10_sql_capture_exact_executed_readonly.sql`. Implementa F0-F2 de L32/05 y agrega perfil 61 en mismo snapshot. No se ejecutó el L32/05 íntegro sin parametrizar porque R1-R3 tienen manifiestos `[]` deliberadamente sin completar; se adaptó su comparación al manifiesto real.
3. Hashes byte a byte PostgreSQL origen: membresía JSONB `92655adfadaa16478f3fcd14daae78a7b614907444d176ae26c04fbc431dbdb3`; preimágenes `04ef6f1448e18a39ef5754b284e802bae265a0a54832feb11f1e5700a3b9b9f2`; CSV `02007addfbb1bb5858eec98a4f065f14a6125ec9dd0d3efdedc6d1ded67bab16`. Los 235 ID literales están en `02_cohorte_frozen_ids.csv`, fuente RAW completa de resumen/preimágenes hashes en `01_supabase_freeze_snapshot_raw.json`.
4. Comparación con L19 **232/232 presentes**, L31 **234/234 presentes**, TOP32 L19 **32/32 presentes**. Tres altas frente a 232, una frente a L31 234 (`EXEC-DB-TRAIN-PR3807-20261113083527-R43394317535`); listas completas en `04_delta_and_pr3803_set_reconciliation.json`. El 235 transitorio mencionado anteriormente no tiene su lista literal y por ello no se puede demostrar igualdad con la foto L33 aunque el conteo sea el mismo.
5. Reconstrucción PR #3803: en snapshot se encuentran **61** RUN con `operation_code='EJECUCION_PERFIL_LF'` **sin filtro de estado**: 12 dentro de 235, 49 fuera. CSV literal `03_pr3803_61_candidate_runs.csv` y delta exacto en `04_delta_and_pr3803_set_reconciliation.json`. **Provenance pendiente**: PR afirma 61 históricos pero no aporta la lista ni el SQL/`as_of` de su corte original. DBA/Merge Train debe validar identidad del conjunto, no solo coincidencia numérica.
6. **PG18.7 copia parcial de manifiesto, no tabla completa**: GitHub Actions [run #43395172974](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43395172974), job `131784235763`, artifact `14021798813`, 13/13 PASS. SHA-256 de resultado runtime `d3fd303e753711daec4f73f1f0e7cbfc2af4d961557e5f512dc6b3529cf485a7`. Incluye source SHA en PostgreSQL 18, importación literal, referencias 232/234/32/61, positivos/negativos, read-only y destrucción del DB PG18 efímero. No exigir igualdad de JSONB reserializado PG18 con origen PG17.6; se verificaron bytes originales como TEXT y membresía semántica.
7. Supabase readback posterior `2026-11-13 08:43:03.858075+00`: 235/235 IDs todavía existentes, **0 ausentes**, **0 altas ajenas todavía `IN_PROGRESS`** en ese instante; **1 RUN cambió estado y preimagen**: `EXEC-DB-TRAIN-PR3807-20261113083527-R43394317535` se volvió `COMPLETED` a `2026-11-13 08:36:51.996201+00`. `07_live_readback_vs_freeze.json` conserva resultado. Negativo detectado: no dar G01 válido como corte vigente sin reconciliar ese cambio. Snapshot original permanece histórico y firmado por hash, no alterado.
8. Borradores G01: `08_g01_borrador_datos_reales_pendiente_firma_ops.md` y `09_g01_candidate_receipt_unissued.json`: evidencia rellenada; `emission_status=NOT_ISSUED`, `verdict=PENDING`. Sin firmas, sin auditor acreditado.

## Evidencia vs aceptación
| Control | Resultado |
|---|---|
| SQL origen READ ONLY / timestamp / MVCC / IDs | **PASS TÉCNICO LIVE** |
| Hash canónico / CSV / corte literal | **PASS TÉCNICO** |
| 232/234/32 y 61 por conjunto actual | **PASS TÉCNICO** |
| PG18 copia de manifiesto + 4 negativos | **13/13 PASS CI** |
| Recibo de Operaciones G01 | **PENDIENTE, NO EMITIDO** |
| Atribución de los 61 a consulta exacta histórica PR #3803 | **PENDIENTE DBA/TRAIN** |
| Estado cambiado RUN PR3807 posterior al corte | **PENDIENTE CONCILIAR POR OPS** |
| Firma formal de dueño y readback independiente | **PENDIENTES** |
| G01/B02 + G02/B03 | **ABIERTOS, 0/2** |
| L21 total | **0/14 CERRADOS** |

## Pendientes asignados
- **Dueño LF:** ratificar/firma formal según canal aplicable de alcance ya decidido; NO autoriza escrituras.
- **Operaciones:** custodio del snapshot 235 as_of+hash+lista, explicar y firmar delta de RUN PR3807 después del corte; emitir G01 oficial por ruta autorizada y readback.
- **DBA/Merge Train #3803:** exportar/validar lista fuente exacta de los 61, SQL, `as_of`, estado/commit y diferencia por ID vs los 235 de L33.
- **Operaciones/DBA/custodios externos:** `EFFECT_RECON_RECEIPT` por RUN del universo, confirmar sinks DB/GitHub/servicios y guards, idempotencia; no deducir ausencia de efecto de falta de log.
- **Responsables de workers:** `LIVENESS_RECEIPT` por RUN; priorizar 8 leases vencidos de L31 (revalidar en cohorte L33).
- **Auditor independiente/registrador oficial:** firma, identidad/competencia, negativos, SHA, RAW y readback de G01/G02 antes de dictamen.

**Prohibición comprobable de alcance de este lote:** sin escritores de Supabase, sin reintentos/cierres/cambios de RUN, sin merge productivo, sin aprobación G01/G02. GitHub recibió solo archivos nuevos L33 y un workflow de CI para el PG18 descartable.
