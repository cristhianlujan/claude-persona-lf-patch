# B06 G03 — Readback HASH de 2456 RUNs históricos

## Fuente y cohorte

- Normativa literal: [Documento 12 L28](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote28-blocker-closure-plan-v1/audits/rule-quality-lote28/12_criterios_cierre_motor_7.md), apartado **B06_OWNER · G03**.
- Entorno: Supabase LF actual, SQL **solo SELECT**. Corte: `started_at < 2026-11-13 07:20:12.513028+00` (comienzo del RUN de backfill `EXEC-DB-TRAIN-PR3806-20261113071927-R43384804628`).
- Se congelaron **2456 IDs únicos de RUN** y se incluyeron **8244 pasos** de `public.lf_operation_execution_steps`. Los pasos no se ignoran: `steps_count` y `steps_bundle_sha256` pertenecen a cada ID; la fila de RUN usa **todas** sus columnas.
- 13 lotes, **200 + 200 + 200 + 200 + 200 + 200 + 200 + 200 + 200 + 200 + 200 + 200 + 56** filas.
- SHA256 root conjunto (RUN completo + SHA de todos sus pasos): `7bae2d2952c1dae06bbe32e498421a3752f9802078d29da4e218d62749512a02`.
- SHA256 root antes del freeze, tras la extracción y **después del readback independiente**: `7bae2d2952c1dae06bbe32e498421a3752f9802078d29da4e218d62749512a02`, sin variaciones.
- **READBACK INDEPENDIENTE** comparó cada CSV congelado contra SELECT actual por `execution_id`, campos completos y pasos: 2456/2456 IDs, 2456/2456 hash RUN, 2456/2456 conteos pasos, 2456/2456 hash bundle pasos, diferencias **0**.

## Evidencia de 13 blobs Git de preimagen

| Chunk | Filas | Git blob SHA-1 |
|---|---:|---|
| [00](frozen_historical_run_hashes_00.csv) | 200 | `bb1d711ee40ec39e3a35b7c17116c9e8c269a139` |
| [01](frozen_historical_run_hashes_01.csv) | 200 | `8bf636c0ee85b7a444d4f4db4c015a611a2d1f7c` |
| [02](frozen_historical_run_hashes_02.csv) | 200 | `dc68c45d305ec8e904ffe536a3cc232ff10adc52` |
| [03](frozen_historical_run_hashes_03.csv) | 200 | `744ac7c98a6e8bcaca8d6717f2b782ff5f467830` |
| [04](frozen_historical_run_hashes_04.csv) | 200 | `c40df409c2bb2584847ba3b6c1f9842b45a6d679` |
| [05](frozen_historical_run_hashes_05.csv) | 200 | `045565506cddc36f0a6199ab16745d86d960fc13` |
| [06](frozen_historical_run_hashes_06.csv) | 200 | `e4362ab9c8d1c7b3481eaa5e9856bce42228485b` |
| [07](frozen_historical_run_hashes_07.csv) | 200 | `3f4e074f763f963d6b3cbaaf999e75cc060e6717` |
| [08](frozen_historical_run_hashes_08.csv) | 200 | `532313b8a2e93b8488f0c442b11a8d4169fb3d6d` |
| [09](frozen_historical_run_hashes_09.csv) | 200 | `8fc08c42872ad09267095952a7cabb54647f2f02` |
| [10](frozen_historical_run_hashes_10.csv) | 200 | `909b16ac1f56a780813742b28eef1065214f88b0` |
| [11](frozen_historical_run_hashes_11.csv) | 200 | `4d2675e4931f926e4c8966374350f8e8712074f4` |
| [12](frozen_historical_run_hashes_12.csv) | 56 | `2b45b0206d62e6c01d098c28c45aec573e966093` |

## Algoritmo reproducible

- RUN: `SHA256(UTF8((to_jsonb(e))::text))`; **sin excluir** status, manifest, idempotency, leases, checkpoint, timestamps, auditoría.
- Cada paso: `SHA256(UTF8((to_jsonb(s))::text))`. Bundle por RUN: `SHA256(UTF8(string_agg(step_order TAB step_id TAB paso_sha256, LF ORDER BY step_order, step_id COLLATE "C")))`; `NULL` si 0 pasos.
- Root: `SHA256(UTF8(string_agg(execution_id TAB run_sha256 TAB steps_count TAB coalesce(steps_bundle_sha256,'-'), LF ORDER BY execution_id COLLATE "C")))`.
- El script `04_readback_run_history_SELECT_only.sql` devuelve el root y recuentos. Los 13 CSV contienen cada par ID/SHA; el readback de este lote hizo además `VALUES` de cada chunk en un SELECT contra Supabase, con resultado 0 mismatches en los 13.

## Límite que NO se puede omitir

Esta preimagen fue tomada **POST-BACKFILL**. **PASS** significa solo igualdad entre freeze de este lote y readback posterior, no igualdad retroactiva con las filas de RUN anteriores a la operación #3806. Para demostrar **cero RUN antiguos alterados desde antes del backfill**, falta un snapshot de antes del 2026-11-13 07:20:12.513028+00 con el mismo universo/esquema o prueba equivalente de backup/log de auditoría full-row que se pueda reconciliar por ID y SHA. No se encontró una tabla de historial/preimagen integral entre `public`, `lf_ops` y `transversal` (búsqueda SELECT realizada). El recuento de `updated_at` es solo indicio secundario, **NO sustituye** SHA preoperación.
