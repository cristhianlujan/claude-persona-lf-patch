# Lote 20 — Sincronización de estados de ciclo de vida con fuentes

**Estado de PG18:** `SANDBOX_VERIFIED`. **Autorización real: `NO-GO/UNVERIFIED`.**

**Superficie:** rama `lf/issue-3779-lote20-lifecycle-source-sync-v1` creada desde commit `9956c2ffaf695030919fa23bb5f83519fcdd23a9`. Todas las escrituras se limitaron a SQL/CI/docs en esta rama y transacciones de PostgreSQL 18 efímero. Consultas Supabase reales: solo `SELECT` como `supabase_read_only_user`. Cero SQL de gates modificado.

### Diseño de una operación atómica

```text
ACTOR (PostgREST simulado)
    authenticator + SET LOCAL ROLE + request.jwt.claims (HMAC TEST)
  → L17: JWT firmado, sub/proyecto/rol/owner y SUPER_ADMIN block
  → l20_owner_decide_and_sync_v1
      │ Bloquea estado previo distinto de VIGENTE
      │ Si SUCEDIDA, exige correction_request y sucesora VIGENTE
      │ L18 owner review: L13 decide + review_decisions + readback
      │ l20_list_divergences_v1: 1 divergencia transitoria
      ├─ LF:  UPDATE source.estado → CADUCADA / SUCEDIDA
      └─ SALY: UPDATE source.vigente → false + marker terminal JSONB
      │ Verifica fila actualizada = 1 y estado recuperado de fuente
      │ l20_list_divergences_v1: 0 divergencias de la regla afectada
      │ INSERT recibo inmutable de sincronización
      └─ retorna SYNCED_ATOMIC_PG18
           SI CUALQUIER PASO FALLA → ROLLBACK DEL COMANDO COMPLETO
```

El fragmento entre decisión L13 y escritura de fuente ocurre **dentro de la misma llamada SQL de PostgreSQL**, sin commit intermedio. La inyección de fallo se ubica DESPUÉS de escribir la fuente y demuestra que registro L13, tabla fuente, `review_decisions` y recibos vuelven al estado inicial.

La operación NO modifica `public.lf_rule_promotion_apply_v1`, `citation_record`, `citation_verify` ni el L8 guard.

**Seguridad:** las funciones leen por adaptadores project-scoped y usan `SECURITY DEFINER` únicamente en PG18 aislado. La consulta de readback `l20_target_readback_v1` valida el JWT; no se abrieron GRANT de DML directo. `p_inject_failure_after_source` es un parámetro exclusivamente de laboratorio, NO desplegable.

### Resultados de los tres escenarios

| Escenario | L13 después | Fuente después | Detector afectado | Readback |
|---|---|---|---|---|
| B. Corregida LF | **SUCEDIDA** anterior; sucesora **VIGENTE** | **SUCEDIDA** anterior; sucesora **VIGENTE** | 1 → 0 | `SYNCED_ATOMIC_PG18` |
| A. Caducidad LF | **CADUCADA** | **CADUCADA** en `lf_ops.reglas.estado` (sandbox) | 1 → 0 | `SYNCED_ATOMIC_PG18` |
| SALY | **CADUCADA** | `vigente=false`; metadata `l20_lifecycle_state=CADUCADA` | 1 → 0 | `SYNCED_ATOMIC_PG18` |

Todos los escenarios fueron probados en una transacción propia, con **ROLLBACK confirmado**; no hubo escrituras persistentes fuera del PG18 de prueba.

- B original: `RULE-DEPENDENCY-001`; sucesora `REG_SEG_004`; `source=SUCEDIDA`, `registry=SUCEDIDA`, `successor_registry=VIGENTE`, `successor_source=VIGENTE`.
- LF caducidad: `source=CADUCADA`, `registry=CADUCADA`, `effective_to=2027-02-10T20:58:06.700229+00:00`, `next_review_at=null`. `as_of` es un reloj simulado para ensayo.
- SALY: `source_vigente=false`, `source_terminal=CADUCADA`, `registry=CADUCADA`. SALY utiliza su motor de apply **sintético**, no aplica gates LF L7/L8 en el producto.

**No se reclama convergencia global del esquema:** el detector puede encontrar otras discrepancias de datos sintéticos; el 0 posterior corresponde a la regla objetivo evaluada.

### Detector de divergencias: solo lectura

`l20_list_divergences_v1(project)` lista `project_code`, `rule_code`, `registry_state`, `source_state` y `classification`. Controles:

- Antes de sync, una decisión L18 aislada produjo `registro=CADUCADA`, `fuente=VIGENTE`, clasificación `LIFECYCLE_STATE_MISMATCH`. El detector la encontró sin modificar filas.
- Después de sync transaccional, el detector del mismo código devolvió **0**.
- Revertida la prueba adversarial, registro y fuente quedaron nuevamente `VIGENTE`, `review_decisions=0`.

### Seis controles negativos exigidos

| Control | Resultado |
|---|---|
| Sync sin decisión del owner | **PASS**: `BLOCK_L20_OWNER_DECISION_REQUIRED` |
| SUPER_ADMIN con JWT firmado | **PASS**: `BLOCK_SUPER_ADMIN_APPROVAL` |
| Sucesora aún no VIGENTE | **PASS**: `BLOCK_L20_SUCCESSOR_NOT_VIGENTE` |
| Fallo tras escribir fuente | **PASS**: `L20_INJECTED_MIDWAY_FAIL_ROLLBACK_ALL` |
| DML directo desde actor sin permisos | **PASS**: `42501`, acceso al esquema LF denegado |
| Segundo sync idéntico | **PASS**: `ALREADY_SYNCED_NOOP`; 0 updates, 0 decisiones, 0 recibos nuevos |

Controles adicionales: DML directo SALY rechazado; tras fallo inyectado `source=VIGENTE`, `registry=VIGENTE`, `decision_rows=0`, `receipts=0`, `target_divergences=0`.

### Inspección de Supabase en modo lectura: tamaño real y límites

**Fecha:** 2026-11-12. **Rol:** `supabase_read_only_user`, servidor PostgreSQL 17.6.

| Tabla viva | Total | Estado / activa |
|---|---:|---|
| `lf_ops.reglas` | **578** | 412 `VIGENTE`, 166 `CANDIDATO` |
| `saly.reglas` | **14** | 14 `vigente=true`; 14 `estado=VALIDADO` |

El número **426** es el total de reglas activas cuya conciliación puede ser relevante. **No es un conteo de divergencias**; no se dispone de un registro L13 oficial comparable ni de los campos temporales y de sucesión en ambas fuentes. La cantidad de divergencias actuales es **NO DETERMINABLE** con las fuentes disponibles. `next_review_at` ausente implica que **no es posible inferir caducidad**.

Campos faltantes constatados en las dos tablas: `reviewed_at`, `next_review_at`, `successor_rule_code`, `effective_to`. En SALY, `estado=VALIDADO` es un estado de validación y **no** debe reutilizarse para `CADUCADA` o `SUCEDIDA`; se propone también `lifecycle_state` como campo autónomo.

En la base PG18 de L11B, el `CHECK` histórico `reglas_estado_check` impedía estados terminales. L20 amplió **solo ese CHECK del fixture** a `CADUCADA/SUCEDIDA`. En la inspección real de `lf_ops.reglas` no se encontró dicho CHECK. Ningún constraint vivo fue alterado.

### Borrador de migración: NO EJECUTADO EN SUPABASE

- `13_l20_proposed_columns_UP_DRAFT_NOT_DEPLOY.sql`: LF añade cuatro campos nullable; SALY añade los mismos cuatro más `lifecycle_state`.
- `14_l20_proposed_columns_DOWN_DRAFT_NOT_DEPLOY.sql`: revierte exactamente las columnas propuestas, **únicamente seguro antes de poblar datos**.
- En PG18: `BASE → UP → DOWN` (LF 0→4→0, SALY 0→5→0). El segundo `UP → ROLLBACK TO SAVEPOINT` también restauró las columnas iniciales.
- Rowcounts en la prueba: LF 4→4; SALY 1→1. **No hubo impacto en la base viva.**
- Se requieren contrato de backfill, homologación de eventos, triggers, permisos/RLS, consumidores, test de compatibilidad y estrategia de reversión no destructiva antes de plantear una migración gobernada real.

### Pruebas y hashes

| Bloque | Verificado |
|---|---:|
| L13 | 28/28 PASS |
| L14 | 18/18 PASS |
| L17 | 25/25 PASS |
| L18 | 16/16 PASS |
| L20 | **17/17 PASS** |
| Scripts `test_pg18_*.py` completos | **18/18 PASS** |

**Nota de no confusión:** los casos L13/L14/L17/L18/L20 están contenidos en los scripts; no se suman como pruebas independientes. El script L4 de medición semántica completó su medición, lo que NO significa que el detector semántico sea confiable en producción.

| Script | Resultado | SHA-256 del log |
|---|---|---|
| `test_pg18_lote10_owner_declared_e2e_attestation_limits.py` | PASS | `38acafe8ad6b986933cf3a8c09d31795d5d938275e39ca38b016df66ffe11cc1` |
| `test_pg18_lote11_synthetic_positive_reachability.py` | PASS | `7e1adbf2ba08aba771f1217aba2ec44449d093f6730ebe71f48fd3a7e6d64112` |
| `test_pg18_lote11b_mechanical_positive.py` | PASS | `1838ae8506f82d66accee399dbd8471b96e7ccebb57a3c652713af699a1110f3` |
| `test_pg18_lote14_quality_wrapper.py` | PASS | `531a3fbc0907efe0da4f0a040636617d6a309eac286b25d09089dcef57561c47` |
| `test_pg18_lote17_actor_identity_adapter.py` | PASS | `c7c9a0caa3ca02510aa4fe7a95a5353464e1358c8c7f7dfbe531a74a13fa3f63` |
| `test_pg18_lote18_integrated_cycle.py` | PASS | `2af223512fb6a7edd7673601b5daadf80c7220207f034f1a19d3af11dbd9cab1` |
| `test_pg18_lote20_source_sync.py` | PASS | `d6e333eaf8bea2c6e0954bc19e5e5526f243b6a310e3c90dbc9dca7902736fad` |
| `test_pg18_lote4_mutation_measurement.py` | PASS | `37145e146930f0ac78357b8d1c298c51db852dccf48491604fa377bc4b6241b6` |
| `test_pg18_lote4_semantic_gate.py` | PASS | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4b_validator_reuse.py` | PASS | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4d_profile_owner_approval.py` | PASS | `32a38d6c68d16cfffc39509d60af3090374a6fb3d5d01a258031b66b5caf1a7a` |
| `test_pg18_lote5_real_verdict_profile_return.py` | PASS | `0455e266085b6579c5ca09c97b618c4e9b0f1abaf6c9e61883c31ced930ab8e0` |
| `test_pg18_lote6_claude_blind_5pass_uncited.py` | PASS | `f04e7b0f2d50c21395f11dff95029297b6a0fbc87b60f7f23bb0fdcb0a777680` |
| `test_pg18_lote7_exact_citation_capture.py` | PASS | `f33594571d0f411a1bf9eda5adcbe32b36a66bb35727c9ea7759888d1981e2b9` |
| `test_pg18_lote8_quote_reuse_scoped.py` | PASS | `15f076c5623ea208dae9422d3c8efed0256a86c180aad904ee21762e176fce0b` |
| `test_pg18_lote9_real_chat_export_citation_measurement.py` | PASS | `bd58aeefa9374a829b3e6f785b02318309a555cf07db3dab9789d8ff1341f4b5` |
| `test_pg18_one_rule_promotion.py` | PASS | `527586730f54c86ed8ca3fd68a0ce08bfe5f2dd1bd3ed99bba440cc4d9f25418` |
| `test_pg18_step40_rule_scope.py` | PASS | `0d6abe0e13835bec20df46bb41ba832d4b4e58644ea1a1f4037274c6dae533d5` |

MD5 **antes y después**, leídos de las definiciones reales PG18:

| Gate congelado | MD5 |
|---|---|
| `apply` | `86b0494984edf95cf0f9c0a0df67000b` |
| `capture_record` | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| `citation_verify` | `773a62783baa5edbe967200cac66b8c3` |
| `l8_guard` | `522d12f0843be1da3c785cef3c0bf3fc` |

**SHA-256 original del JSON runtime L20 emitido por CI:** `a6f84763a00f6f5f1b521d4d9b6bd013a39b93d2a369a84d719ce873bdc1eaca`.

- [Ejecución CI #43305361826](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43305361826), job `131487095734`.
- Commit que CI probó: `b7e362b36e82b4075bc9effc363ec777c6756d87`.
- Evidencia con casos y logs: `docs/rule-quality-lote20/01_pg18_evidence_actual_results.json`.
- Inspección SELECT real: `docs/rule-quality-lote20/00_live_readonly_inventory.json`.

### Riesgos y cierre del dueño — BLOQUEA_PRODUCCION

1. Los JWT de L17 son claims JSON/HMAC **sintéticos**; Supabase Auth, PostgREST real y permisos quedan pendientes de acreditación.
2. El flujo L11B incluye citas y owner/IG simulados; **Router, Perfil, RUN, Step70, OIDC, juez independiente y cierre productivo NO_PROBADO**.
3. **El dueño debe aprobar** el contrato de nuevos campos en `lf_ops.reglas` y `saly.reglas` antes de cualquier migración gobernada. Sin ello, no se puede declarar resuelto el defecto en las fuentes reales.
4. SALY necesita distinguir tipo terminal en una columna explícita; el marcador JSONB en sandbox NO reemplaza diseño canónico.
5. Las funciones L20 son fixtures experimentales y no endurecimiento de producción: `SECURITY DEFINER` de superusuario, reloj simulado y parámetro de inyección no son aptos para despliegue directo.
6. Auditor ejecutor en este chat: **GPT-6, no Claude autenticado**, y cero evidencia de veredicto independiente nativo.

**Resultado:** 100% del alcance de sandbox probado, **0% aprobación de cambio en fuente oficial**, producción `NO-GO/UNVERIFIED`.
