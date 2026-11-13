# B02/G01 — BORRADOR CANDIDATO DE RECIBO (NO EMITIDO) · L33

> **DRAFT_PENDING_OPERATIONS_SIGNATURE / DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA / NO-GO.**
> Recibo propuesto con datos reales. NO_ES_RECIBO_EMITIDO. Ni el dueño ni Operaciones ni auditor han firmado este texto; no permite cierre de B02/B03 ni autoriza mutaciones o reintentos RUN.

## Datos acreditados del corte de solo lectura

| Campo de plantilla G01 | Valor real o estado |
|---|---|
| `receipt_type` | `G01_SCOPE_FREEZE_RECEIPT` |
| `schema_version` | `L32_DOCUMENTAL_DRAFT_V1` |
| `blocker/gate` | `B02_RUN_SCOPE / G01` |
| `project/environment` | `LF / SUPABASE_TEMPORAL` |
| `supabase_project_ref` | `mhwmirqcgxxukpctffuv` |
| `database / PG` | `postgres / 17.6` |
| `role` | `supabase_read_only_user` |
| `isolation / mode` | `REPEATABLE READ / READ ONLY` |
| `as_of_utc` | `2026-11-13 08:36:22.461152+00` |
| `mvcc_snapshot_literal` | `619221:619221:` |
| `scope predicate` | `public.lf_operation_execution WHERE status='IN_PROGRESS'`; todos los IDs del instante, sin excluir otros grupos |
| `scope decision` | Dueño decidió en conversación: **universo completo**; 32 son orden de prioridad, no subconjunto excluyente |
| `scope signature` | **PENDIENTE**, actor físico NO autenticado `identity_verified=false` |
| `count / distinct` | **235 / 235** |
| `historic232 overlap` | **232 / 232**, cero ausentes |
| `L31 234 overlap` | **234 / 234**, cero ausentes |
| `TOP32 L19` | **32 / 32** dentro de cohorte, aún propuesta histórica de prioridad |
| `new vs 232` | **3**, lista exacta en 04 |
| `new vs L31 234` | **1**, RUN PR3807 |
| `membership_jsonb_sha256` | `92655adfadaa16478f3fcd14daae78a7b614907444d176ae26c04fbc431dbdb3` |
| `preimage_manifest_jsonb_sha256` | `04ef6f1448e18a39ef5754b284e802bae265a0a54832feb11f1e5700a3b9b9f2` |
| `ids_csv_sha256_utf8` | `02007addfbb1bb5858eec98a4f065f14a6125ec9dd0d3efdedc6d1ded67bab16` |
| `raw_export_ref` | `audits/rule-quality-lote33/01_supabase_freeze_snapshot_raw.json` (blob `3b64b8eea966b7f5a625572bc5603300fb1e3f15`) |
| `literal_csv_ref` | `audits/rule-quality-lote33/02_cohorte_frozen_ids.csv` (blob `5b5247a2823ac1576c95bbe6c39878b308ae464c`) |
| `delta_set_ref` | `audits/rule-quality-lote33/04_delta_and_pr3803_set_reconciliation.json` (blob `4254f11e56766fb589bd813c6504ab8e52c552d8`) |
| `source_sql_ref` | L32 `05_freeze_cohorte_asof_readonly.sql` blob `9a015ed8b6c18c52bd642f91de32796d8c305afc` |
| `executed SQL method` | F0/F1/F2 equivalentes combinados en una consulta SELECT, dentro de transacción `BEGIN ... REPEATABLE READ READ ONLY ... ROLLBACK`; **no ejecución literal íntegra de R1–R3 del archivo 05** |
| `scope exclusions` | Ningún RUN `IN_PROGRESS` del MVCC excluido. Las altas/cambios posteriores no modifican membresía congelada |
| `run mutations` | Ninguna operación escritora RUN invocada en este lote |

## 61 RUN atribuibles a lectura #3803 — comparación técnica

- PR de referencia: [#3803](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3803). Su texto afirma **61 RUN históricos de perfil**, pero NO aporta lista literal, SQL ni `as_of` originales para certificar identidad del conjunto.
- La base actual reproduce **61** filas con `operation_code='EJECUCION_PERFIL_LF'`, sin filtrar estado: **12** `IN_PROGRESS` incluidos en los 235; **49** fuera (otros estados: `COMPLETED 31`, `CANCELLED 16`, `BLOCKED 1`, `PASS_PRE_INDEPENDENT_REVIEW 1`).
- Candidato literal de 61 IDs: `audits/rule-quality-lote33/03_pr3803_61_candidate_runs.csv` (blob `96351ba3a6c18ad12dfb1191300bcad6c5cf827e`).
- Resultado por conjuntos (12/49 + 223 RUN que no son del perfil): `04_delta_and_pr3803_set_reconciliation.json`.
- **PENDIENTE DBA/Merge Train:** acreditar que el filtro, 61 IDs, `as_of` y versión usados originalmente en #3803 coinciden con esta reconstrucción. No confundir coincidencia de conteos con readback histórico.

## Pruebas ejecutadas y límites

**Supabase live, SELECT:**
- Corte `235/235`, source SHA, timestamp MVCC, rol y aislamiento: **PASS de captura**.
- Conciliación literal L19/L31: **232/232 + 234/234 presentes**, 32/32 propuestos: **PASS de conjuntos**.
- Readback posterior `2026-11-13 08:43:03.858075+00`: **235/235 IDs presentes**, 0 faltantes, 0 nuevas altas fuera del conjunto en ese momento, pero **1 cambio de status/preimagen**: `EXEC-DB-TRAIN-PR3807-20261113083527-R43394317535`; pasó de `IN_PROGRESS` a `COMPLETED`, actualizado `2026-11-13 08:36:51.996201+00` (READBACK `07_live_readback_vs_freeze.json`, blob `337620fc6a34edacab28b62b58fe57e0d69945af`). **G01 no aceptado; requiere delta explicado por Operaciones**.
  
**Copia PG18.7 (fixture parcial con texto JSONB canónico original y preimágenes SHA, no copia de todos los campos de filas):**
- GitHub Actions [run #43395172974](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43395172974), job `131784235763`, artifact `14021798813`.
- **13/13 PASS**: hashes UTF-8 originales en PG18, CSV SHA, 235/61/232/234/32, intersección 12/49, transacción read-only, negativos ID faltante/duplicado/preimagen alterada/alta posterior, fuente sin cambios tras los negativos. Base PG18 descartable eliminada.
- SHA-256 del JSON RAW del runner: `d3fd303e753711daec4f73f1f0e7cbfc2af4d961557e5f512dc6b3529cf485a7`.
- No demuestra restauración completa, exactitud de la antigua foto transitoria de 235 sin IDs, integridad de todos los sinks, ni equivalencia de serialización JSONB PG17 vs PG18. No valida B03 ni se probó sobre RUN reales en PG18.

## Declaración documental de decisión del dueño — no autenticada

- `decision_status: DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`.
- `owner_decisor: Cristhian Luján`.
- `owner_decision_literal`: «SÍ se congela el universo completo de RUN IN_PROGRESS, usando los 32 solo para ordenar. Alcance: solo inventario y conciliación; sin escrituras, reintentos ni cierres de RUN».
- `identity_verified: false`, `identity_mode: UNVERIFIED_CHAT_DECLARATION`.
- `decision_exact_utc: NOT_ATTESTED`; la fecha de trabajo no sustituye la hora de firma.
- `owner_approval_receipt_ref: null`.

## Aceptación G01 — NO MARCAR COMO CERRADO

| Criterio | Estado |
|---|---|
| Decisión documental sobre cobertura | **RECIBIDA EN CHAT, PENDIENTE FIRMA** |
| Corte completo de IDs y fuente RAW | **PASS técnico 235/235** |
| Comparación histórica 232, 234 y 32 | **PASS técnico** |
| PR #3803: lista y filtro originales de 61 | **PENDIENTE DBA/TRAIN** |
| Deriva de estado de 1 RUN y custodia de delta | **PENDIENTE OPERACIONES** |
| Firma/recibo de custodia Operaciones | **PENDIENTE** |
| Firma autenticada del dueño (si exigible para G01) | **PENDIENTE** |
| Auditor independiente/readback de G01 | **PENDIENTE** |
| `G01 acceptance verdict` | **PENDING / NO-GO** |
| `B02/B03 closed` | **0/2** |

**Próxima operación permitida:** sólo documentar causa del cambio, validar el filtro histórico de #3803 y obtener recibo de Operaciones, revisión y firmas por vía oficial. **Prohibido** modificar RUN existentes, compensar, cerrar, reintentar o promover por este borrador.
