# L29 — Resultado REAL de E2E PG18 con datos de muestra y NO-GO

## Dictamen

**SANDBOX_VERIFIED para el alcance experimental de L29:** 22/22 controles PASS, tres caminos de regla LF distintos medidos en tres bases PG18 desechables, rollback y protección adicional de solicitud/SoD/idempotencia. **Producción/IG nativo: NO-GO / UNVERIFIED**; **bloqueos B01..B14 cerrados: 0/14**.

**Evidencia primaria:** [GitHub Actions #43336082581](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43336082581), job `131592483828`, HEAD probado `39b7ebcbf56d76f65b821376e8893650dd0e567b`, conclusión `success`. PG servidor: **PostgreSQL 18.7** dentro del contenedor de CI, sin conexiones productivas. Artifact `l29-e2e-pg18-raw` id `13997605666` (retención 14 días), SHA-256 del ZIP `5ec6781482fcd9f5dbf97dea579c15feb9a4a0fde76f027eec748662041959dc`.

**SHA-256 JSON RAW exacto (emitido por runner CI):** `122712edfb41308417ab2a2b3f5e76089e078239e5dd161be0967c6e4e7c0ca8`. Guardado en artifact `lote29_e2e_runtime.json`; no recomponer ni sustituir por un JSON de esta documentación.

## Conteos realmente ejecutados

| Grupo | Casos | Estado |
|---|---:|---|
| Bootstrap aislado PG18 (tres DB) | 3 | PASS |
| Positivos completos NEW / MODIFY_CANDIDATE / CORRECT_VIGENTE | 3 | PASS |
| Negativos y readback adversariales | 10 | PASS |
| MD5 antes y después, por DB | 6 | PASS |
| **Total** | **22/22** | **PASS** |

La misma corrida ejecutó las tres trayectorias, y los seis tests de MD5 compararon contra el inventario congelado. La prueba no ejecutó todo el inventario de 21 scripts de L26 nuevamente; no inflar los denominadores.

## Tres recorridos completos

| Prueba | Modelo de datos | Evidencia objetiva en PG18 | Cierre |
|---|---|---|---|
| **A_NEW** | Nuevo candidato sin conflicto real en fixture A | Solicitud HMAC de no-owner; owner L17 distinto; Curator `ACEPTAR`; wrapper L14 `APPLIED/READY`; L20 VIGENTE y divergencia 0; promoción y cierre L24/L26 con SHA | PASS y ROLLBACK, 0 filas temporales |
| **B_MODIFIED_CANDIDATE** | Candidata existente del fixture con `valor_config.l29_revision: absent → "2"` ANTES de capturar evidencia | SHA preimage ≠ postimage; luego misma cadena de validación/captura/owner/Curator/Promoción/Cierre sin modificar la evidencia congelada a posteriori | PASS y ROLLBACK |
| **C_CORRECTED_VIGENTE** | Sucesora explícita de `RULE-DEPENDENCY-001` VIGENTE | Curator detecta configuración distinta pero admite sólo con lineage de corrección y owner HMAC; L20 marca anterior `SUCEDIDA` en ambas fuentes y nueva `VIGENTE` | PASS y ROLLBACK |

**No confundir:** `MODIFY_CANDIDATE` es edición de un **CANDIDATO previo a aprobación** en fixture PG18, NO mutación en caliente de una regla VIGENTE. `CORRECT_VIGENTE` usa sucesora explícita: no se editó la VIGENTE in-place. Los tres escenarios fueron LF, **no prueban la ruta SALY**; el cambio de denominador respecto al escenario C SALY de L26 se declara en el tablero.

## Diez negativas con evidencia SQL

| Control exacto en JSON | Efecto observado |
|---|---|
| `NO_EVIDENCE` | `BLOCK_L29_EVIDENCE_REQUIRED` |
| `NO_PERMISSION_APPROVE` | Reader sin owner: `BLOCK_L17_NOT_PROJECT_OWNER` |
| `SUPER_ADMIN_DENIED` | `BLOCK_SUPER_ADMIN_APPROVAL` |
| `OWNER_CANNOT_CREATE_REQUEST` | ACL PG18: `permission denied for function l29_submit_request_v1` |
| `SAME_ACTOR_CREATOR_APPROVER_BLOCKED` | Una solicitud forjada sólo por superuser de fixture como mismo actor no supera trigger `BLOCK_L29_SAME_ACTOR_CREATOR_APPROVER` |
| `REQUEST_MISSING_BLOCKS_OWNER` | `BLOCK_L29_REQUEST_REQUIRED` |
| `REQUEST_IDEMPOTENCY_CONFLICT` | Mismo ID con cuerpo diferente: `BLOCK_L29_IDEMPOTENCY_KEY_CONFLICT` |
| `DIRECT_REQUEST_DML_DENIED` | `permission denied for table l29_request_evidence` |
| `POST_PROMOTION_FAULT_ROLLBACK` | Fallo inducido `L26_INJECTED_AFTER_PROMOTION_BEFORE_CLOSURE` |
| `NO_PARTIAL_ROWS_AFTER_FAILURE` | 0 filas en solicitud, owner intent, Curator, promoción, cierre y candidato |

**Repetición idempotente positiva en los tres caminos:** solicitud idéntica → `ALREADY_REQUESTED_NOOP`; promoción → `ALREADY_PROMOTED_VERIFIED_NOOP`; cierre → `ALREADY_CLOSED_VERIFIED_NOOP`. Se observa **1 sola solicitud + 1 intención + 1 promoción + 1 cierre** dentro de cada transacción, seguida de **0** filas tras rollback. Esto demuestra idempotencia del **wrapper PG18 por clave lógica**, no replay de RUN nativo de producción.

## Gates congelados — MD5 antes/después por escenario

| Función de PG18 | MD5 antes = MD5 después |
|---|---|
| apply L11B | `86b0494984edf95cf0f9c0a0df67000b` |
| capture_record | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| citation_verify | `773a62783baa5edbe967200cac66b8c3` |
| l8 guard | `522d12f0843be1da3c785cef3c0bf3fc` |

**SQL no tocados:** L7/L8/L11B, L14, L17, L23, L24, L26. L29 añadió `17_l29_e2e_request_sod_retry_pg18.sql` separado y un script runner. El md5 legado del apply de Supabase no se compara con este gate PG18; son objetos distintos.

## Honradez de autoría, autoridad y producción

- **Modelo:** GPT-6, mismo autor/juez, **NO** Claude independiente. Curator L23 es SQL determinista de prueba; no Curator oficial ni auditor externo.
- **JWT:** JSON firmado con HMAC de fixture L17, no Supabase Auth/JWT real; rol PG18 simulado con `SET SESSION AUTHORIZATION`.
- **Solicitud / propuestas / autorizaciones:** asientos en PG18 desechable, no actividad oficial de ACT-0001, perfil, IG, Step70/OIDC o firma del dueño.
- **Cierre:** L24/L26 append-only verificado en sandbox, no `lf_profile_execution_terminal_authority_receipt_v1` de RUN real.
- **Cambio productivo:** 0; **RUN alterados/cerrados/reintentados:** 0; DML/DDL Supabase: 0.
- **B09_E2E/B07/B08/B12/B02/B03:** ninguno recibe GO por este laboratorio, **14/14 bloqueos productivos abiertos**.

**Límite final: SANDBOX_VERIFIED / PRODUCTION NO-GO / UNVERIFIED.**
