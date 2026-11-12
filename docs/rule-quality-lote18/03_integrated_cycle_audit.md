# LOTE 18 — Demostración única del ciclo gobernado en PostgreSQL 18 aislado

**Resultado:** `SANDBOX_VERIFIED`. **Producto y producción: `NO-GO/UNVERIFIED`**.

Fuente de referencia: EKB `INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4` (CANDIDATO VERIFICADO PARCIALMENTE), jerarquía de fuentes y contratos L7/L8/L11B/L13/L14/L17 ya construidos. **No son evidencia de un Router ni de un Step70 real**, que no se ejecutaron.

- Rama de trabajo: `lf/issue-3779-lote18-integrated-cycle-v1`.
- Base EXACTA: `6a48eb1eee436793d28c90dad1dcabc1c58ae5a2`.
- Commit ejecutado en CI: `abeea154a559759dcf2f56f42c8fd106ca768b64`.
- [Runner GitHub Actions #43299324221](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43299324221) · Job `131466394761` · conclusión `success`.
- Un solo script integrado `test_pg18_lote18_integrated_cycle.py` ejecutó A, B y SALY en la misma base aislada, con transacciones independientes y **ROLLBACK verificado** en los tres casos.
- Implementaciones nuevas **solo en sandbox**: `11_l18_integrated_cycle_sandbox.sql`, test L18 y workflow CI L18. El SQL de los gates existentes NO se edita.

## 1. Diseño de secuencia y límites de autoridad

```text
              FUENTE SINTÉTICA LF CANDIDATO
                             │
           Solicitud L11B y contexto de perfil fixture
                             │
          Familia L13 válida + next_review_at L14
                             │
       Authenticator -> SET LOCAL ROLE + JWT HMAC L17
                             │
             Propuesta IG (mock #3682 / L11B)
                             │
    Publicación de caso + cita EXACTA L7 + guard L8
                             │
                VERIFIED_CAPTURE_BINDING
                             │
        Owner JWT -> l18_owner_intent_v1 (sandbox)
          Revalida L7 y estado IG READY antes de registrar
                             │
        Owner Step70 sintético L11B (NO nativo)
                             │
    quality_apply_envelope_v2 -> apply LF CONGELADO
                             │
              APPLIED -> VIGENTE -> READY
                             │
      Profile return/readback SQL -> RECEIPT CLOSE sandbox
                             │
         Propuesta de vencimiento STABLE read-only
                             │
       OWNER JWT decide RENOVAR / CADUCAR / SUCEDER
                             │
                   ROLLBACK completo
```

La cita contiene el literal de procedencia **`OFFICIAL_STEP70_VERIFIED_NATIVE_IG` en un campo de fixture**, pero el metadato verdadero declara `MECHANICAL_ONLY_SYNTHETIC_PROVENANCE_NOT_E2E` y `system_attestation=false`. El texto del fixture **no acredita** Step70, IG real o juez independiente.

El registro de cierre `CLOSED_SANDBOX_SIMULATION` **NO equivale** al cierre de los 11 pasos reales del perfil.

## 2. Tableros de 12 etapas — evidencia real por escenario

Estados admitidos: `REAL_EN_SANDBOX` = SQL realmente ejecutado en PG18, sin autoridad productiva; `SINTETICO` = stub/dato preparado expresamente; `NO_PROBADO` = no se ejecutó una ruta equivalente.

### A_NEW

| Etapa | Estado | Evidencia y alcance |
|---|---|---|
| Router | `SINTETICO` | Synthetic parent manifest and handoff; ACT-0001 NOT run |
| Perfil | `SINTETICO` | Synthetic source/owner profile; not a native profile execution |
| RUN | `SINTETICO` | Synthetic PG18 execution rows; no native RUN |
| IG | `SINTETICO` | L11B stub + simulated Step70 field, not native IG |
| Curator | `NO_PROBADO` | No authentic Curator invocation |
| Validator | `REAL_EN_SANDBOX` | Frozen L7/L8 SQL capture/verification executed; verdict has synthetic provenance |
| Retorno perfil | `REAL_EN_SANDBOX` | Frozen profile_return_readback SQL returned READY; no real transport |
| Ejecucion | `SINTETICO` | SQL stub parent + owner execution, not complete 11-step execution |
| Promocion | `REAL_EN_SANDBOX` | Frozen apply returned APPLIED in PG18 transaction |
| VIGENTE | `REAL_EN_SANDBOX` | PG18 source and quality row activated within transaction |
| Readback | `REAL_EN_SANDBOX` | SQL readback and quality metadata checked before ROLLBACK |
| Cierre | `SINTETICO` | L18 sandbox-only closure receipt; native profile closure NOT proven |

### B_CORRECTED

| Etapa | Estado | Evidencia y alcance |
|---|---|---|
| Router | `SINTETICO` | Synthetic parent manifest and handoff; ACT-0001 NOT run |
| Perfil | `SINTETICO` | Synthetic source/owner profile; not a native profile execution |
| RUN | `SINTETICO` | Synthetic PG18 execution rows; no native RUN |
| IG | `SINTETICO` | L11B stub + simulated Step70 field, not native IG |
| Curator | `NO_PROBADO` | No authentic Curator invocation |
| Validator | `REAL_EN_SANDBOX` | Frozen L7/L8 SQL capture/verification executed; verdict has synthetic provenance |
| Retorno perfil | `REAL_EN_SANDBOX` | Frozen profile_return_readback SQL returned READY; no real transport |
| Ejecucion | `SINTETICO` | SQL stub parent + owner execution, not complete 11-step execution |
| Promocion | `REAL_EN_SANDBOX` | Frozen apply returned APPLIED in PG18 transaction |
| VIGENTE | `REAL_EN_SANDBOX` | PG18 source and quality row activated within transaction |
| Readback | `REAL_EN_SANDBOX` | SQL readback and quality metadata checked before ROLLBACK |
| Cierre | `SINTETICO` | L18 sandbox-only closure receipt; native profile closure NOT proven |

### C_SALY_NEW

| Etapa | Estado | Evidencia y alcance |
|---|---|---|
| Router | `NO_PROBADO` | No SALY native Router path |
| Perfil | `NO_PROBADO` | No native SALY profile |
| RUN | `NO_PROBADO` | No SALY RUN |
| IG | `NO_PROBADO` | LF frozen L7/L8 not a SALY adapter; no SALY IG receipt |
| Curator | `NO_PROBADO` | No SALY Curator |
| Validator | `REAL_EN_SANDBOX` | L17 signed identity and L13 family review mechanically verified |
| Retorno perfil | `SINTETICO` | Synthetic SALY fixture READY; no real return |
| Ejecucion | `REAL_EN_SANDBOX` | SALY SQL fixture executed via same quality_apply_envelope_v2 |
| Promocion | `REAL_EN_SANDBOX` | SALY fixture apply executed, NOT native production apply |
| VIGENTE | `REAL_EN_SANDBOX` | PG18 synthetic SALY source and quality activated |
| Readback | `REAL_EN_SANDBOX` | PG18 state, family and next_review_at checked |
| Cierre | `SINTETICO` | L18 sandbox-only closure ledger, no native close |


## 3. Caso A — Nueva regla LF

- Fuente candidata: `REG_SEG_004`.
- Familia: `IDENTIDAD_SEGURIDAD`; próxima revisión: `2027-02-10T20:22:23.282553+00:00`.
- L7: `VERIFIED_CAPTURE_BINDING`; etiqueta `SINTETICA` en fixture.
- IG: `READY_FOR_PROFILE_APPROVAL`; **no aprobado por un IG real**.
- Intención del owner: `OWNER_JWT_SANDBOX_APPROVED`; `official_step70_attested=false`.
- Aprobación Step70 L11B: `APPROVED` **solo mecánica/sintética**.
- Apply sin editar: `APPLIED`; perfil-return readback: `READY`.
- Fuente LF: `VIGENTE`; calidad L13 al concluir el experimento temporal: `CADUCADA`; el estado temporal debe interpretarse después de la promoción, no como fallo del READY anterior.
- Cierre registrado: `CLOSED_SANDBOX_SIMULATION` **solo laboratorio**.
- ROLLBACK final: `{"close_receipts":0,"correction_links":0,"owner_intents":0,"quality_candidate_rows":0,"source_candidate_rows":0}`.

## 4. Caso B — Regla corregida LF con sucesora explícita

- Regla previa del fixture: `RULE-DEPENDENCY-001`, originalmente VIGENTE.
- Regla sucesora explícita: `REG_SEG_004`, preparada en `EN_REVISION`, nunca editada en sitio por coincidencia textual.
- L7/L8, captura, JWT owner, owner Step70 sintético, apply, VIGENTE y profile-return READY se ejecutaron como en A.
- Decisión posterior del owner JWT: `SUPERSEDE`, apuntando a `REG_SEG_004`.
- **Readback positivo del registro de calidad:** anterior `SUCEDIDA`; sucesora `VIGENTE`.
- **Límite importante:** fuente LF heredada anterior `VIGENTE`. La fuente sintética `lf_ops.reglas` de L11B no admite `SUCEDIDA` en su CHECK; por tanto **NO se probó propagación al sistema fuente ni deben considerarse sincronizados ambos estados**.
- Cierre registrado: `CLOSED_SANDBOX_SIMULATION` **solo laboratorio**.
- ROLLBACK final: `{"close_receipts":0,"correction_links":0,"owner_intents":0,"quality_candidate_rows":0,"source_candidate_rows":0}`.

## 5. Caso SALY — Misma capa de calidad y actor, sin fingir un gate LF

- El adaptador `saly` usa las mismas funciones `quality_prepare_new_v2`, `quality_apply_envelope_v2`, `l18_owner_intent_v1` y `l18_close_sandbox_cycle_v1`.
- JWT HMAC firmado de `saly_owner_role`; familia `MOTOR_DISPONIBLE`.
- Apply es **`SALY_SYNTHETIC_APPLY`**, no una aplicación nativa SALY.
- Estado fuente `true`, calidad `VIGENTE`, próxima revisión `2027-01-11T20:22:23.453499+00:00`.
- IG y citas L7/L8 para SALY están **NO_PROBADO**, no `REAL_EN_SANDBOX`: los gates congelados L7/L8 corresponden a LF.
- ROLLBACK final: `{"closures":0,"owner_intents":0,"quality":0}`.

## 6. Fecha simulada: revisión vencida → renovación → caducidad

El contrato `list_review_due(project,as_of)` es de lectura; `as_of` se calcula como `next_review_at + 1 segundo` **en el sandbox**, sin alterar reloj del servidor ni activar cambios automáticos.

| Punto de control | Evidencia readback |
|---|---|
| Revisión vencida original | `due=1`, estado `VIGENTE`, propuesta solamente |
| Owner JWT RENOVAR | `KEEP_VIGENTE`; nuevo `next_review_at=2027-05-11T20:22:24.282553+00:00` |
| Siguiente vencimiento | `due=1`, continúa `VIGENTE` antes de la decisión |
| Owner JWT CADUCAR | `EXPIRE`, estado `CADUCADA`; `next_review_at=null` |
| Regla original fuente LF | Sigue `VIGENTE` porque la caducidad aquí es del modelo L13, no una escritura oficial de la fuente |

## 7. Negativos del flujo integrado

| Negativo obligatorio | Resultado observado | Test |
|---|---|---|
| `N1_NO_FAMILY` | Falta familia en regla nueva, bloqueo 23514 | **PASS** |
| `N2_EXACT_CITATION_1_CHAR_TAMPER` | Cita alterada un carácter: HUMAN_DECISION_REQUIRED, apply BLOCKED | **PASS** |
| `N3_JWT_BAD_SIGNATURE` | JWT HMAC modificado: 42501 | **PASS** |
| `N4_OWNER_EQUALS_IG_DENIED` | El owner coincide con IG: registro canónico rechaza, promoción BLOCKED | **PASS** |
| `N5_SUPER_ADMIN_CANNOT_APPROVE` | SUPER_ADMIN firmado: 42501 | **PASS** |
| `N6_DIRECT_DML_FORBIDDEN` | Owner autenticado intenta DML en rules: 42501 | **PASS** |

**Bloqueo adicional G1:** un owner con JWT válido que intenta aprobar sin captura L7 previamente verificada recibe `42501 BLOCK_L18_OWNER_WITHOUT_VERIFIED_CAPTURE`. Prueba **PASS**; no forma parte del conteo de los seis negativos solicitados.

## 8. Regresión completa y no pérdida de cobertura

| Suite o subconjunto | Resultado |
|---|---|
| L13: 28 tests | **28 PASS** |
| L14: 18 tests | **18 PASS** |
| L17: 25 tests | **25 PASS** |
| L18: 16 controles (3 escenarios, 3 tableros, 6 negativos, 1 guard adicional, checks de MD5) | **16 PASS** |
| Inventario exhaustivo `test_pg18_*.py` | **17/17 scripts PASS** |

**Los conteos por script contienen los casos L14/L17/L18:** no sumar como pruebas independientes ni acreditar E2E oficial. Cada script se ejecutó en base desechable limpia.

| Script | CI | SHA-256 del log |
|---|---|---|
| `test_pg18_lote10_owner_declared_e2e_attestation_limits.py` | **PASS** | `38acafe8ad6b986933cf3a8c09d31795d5d938275e39ca38b016df66ffe11cc1` |
| `test_pg18_lote11_synthetic_positive_reachability.py` | **PASS** | `7e1adbf2ba08aba771f1217aba2ec44449d093f6730ebe71f48fd3a7e6d64112` |
| `test_pg18_lote11b_mechanical_positive.py` | **PASS** | `1838ae8506f82d66accee399dbd8471b96e7ccebb57a3c652713af699a1110f3` |
| `test_pg18_lote14_quality_wrapper.py` | **PASS** | `4c693eddc2720bfa5c9f2d88efa519757653f48a01e41f626e04de5e750e08d2` |
| `test_pg18_lote17_actor_identity_adapter.py` | **PASS** | `e9a1d2cf5dd47695cfb6c814c5b1e30043549cac8ed6378646b5ad5a0ae81151` |
| `test_pg18_lote18_integrated_cycle.py` | **PASS** | `08d26878ce43618a67ce14375c5cf0101d7e412c252c445ce01ce812277cf824` |
| `test_pg18_lote4_mutation_measurement.py` | **PASS** | `37145e146930f0ac78357b8d1c298c51db852dccf48491604fa377bc4b6241b6` |
| `test_pg18_lote4_semantic_gate.py` | **PASS** | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4b_validator_reuse.py` | **PASS** | `9c1bb3dc0b9e0f11f22fc4805561a09946944a2a10924ab7a5fd3a2df48f281a` |
| `test_pg18_lote4d_profile_owner_approval.py` | **PASS** | `32a38d6c68d16cfffc39509d60af3090374a6fb3d5d01a258031b66b5caf1a7a` |
| `test_pg18_lote5_real_verdict_profile_return.py` | **PASS** | `0455e266085b6579c5ca09c97b618c4e9b0f1abaf6c9e61883c31ced930ab8e0` |
| `test_pg18_lote6_claude_blind_5pass_uncited.py` | **PASS** | `f04e7b0f2d50c21395f11dff95029297b6a0fbc87b60f7f23bb0fdcb0a777680` |
| `test_pg18_lote7_exact_citation_capture.py` | **PASS** | `f33594571d0f411a1bf9eda5adcbe32b36a66bb35727c9ea7759888d1981e2b9` |
| `test_pg18_lote8_quote_reuse_scoped.py` | **PASS** | `15f076c5623ea208dae9422d3c8efed0256a86c180aad904ee21762e176fce0b` |
| `test_pg18_lote9_real_chat_export_citation_measurement.py` | **PASS** | `bd58aeefa9374a829b3e6f785b02318309a555cf07db3dab9789d8ff1341f4b5` |
| `test_pg18_one_rule_promotion.py` | **PASS** | `ea6da642e9747866160b2195279b1a544b2da84df22d387b0bec446e1e6df217` |
| `test_pg18_step40_rule_scope.py` | **PASS** | `0d6abe0e13835bec20df46bb41ba832d4b4e58644ea1a1f4037274c6dae533d5` |

## 9. Integridad criptográfica y readback

MD5 obtenidos de `pg_get_functiondef` en PostgreSQL antes y después del ciclo:

| Gate congelado | MD5 antes = después |
|---|---|
| `apply` | `86b0494984edf95cf0f9c0a0df67000b` |
| `capture_record` | `89cbfac4162dbc9f8ecca59f2c3ab4c3` |
| `citation_verify` | `773a62783baa5edbe967200cac66b8c3` |
| `l8_guard` | `522d12f0843be1da3c785cef3c0bf3fc` |

SHA-256 original del JSON integrado emitido por el runner: `934d6a99d4c5382c4dd33aeb4894639233d34a9173ba78bafeffc6a2122e08b3`.

| Archivo nuevo | SHA-256 recalculado |
|---|---|
| `11_l18_integrated_cycle_sandbox.sql` | `2837ad69a85d46f70626a881df26cd88020a51db419735eca50cce7feb4ca68e` |
| `test_pg18_lote18_integrated_cycle.py` | `085ec4971dd4835087af79fd8e3589dd1a767e95c1b551c96963a2fa4b266ff1` |
| `l18-integrated-governance-cycle-pg18.yml` | `577daaa2599f4e81909bd06f30708bf39901b1a8cc7ec468000458f889a00b14` |
| `01_pg18_integrated_real_results.json` | `283af48887063c16cf5f09803181efba8f2837b906e362d32c34b1762cf20823` |

Los Git blobs de los tres artefactos de código/CI son idénticos a los del commit efectivamente probado `abeea154a559759dcf2f56f42c8fd106ca768b64`. El diff L14→L18 contiene exclusivamente archivos nuevos de L18 (sandbox, workflow y documentación): **cero DDL/DML de Supabase, cero edición de gates, cero PR merge y cero producción**.

## 10. Riesgos, decisión y siguiente acción del dueño

**BLOQUEA_PRODUCCION / NO-GO / UNVERIFIED** hasta acreditar:

1. **Supabase Auth real:** `request.jwt.claims` firmado con HMAC del fixture no equivale a JWT real; se requieren validación/autorización server-side, permisos, mapeo `sub`→actor, roles PostgREST reales, tokens y pooler.
2. **Router, Perfil, RUN, Step70 y OIDC oficiales:** datos/manifiestos del ensayo son simulaciones; no se acredita ACT-0001, transporte Gate-2, RUN oficial, aprobación real de owner, IG independiente ni cierre nativo.
3. **Fuente de reglas:** las transiciones `SUCEDIDA` y `CADUCADA` comprobadas ocurren en el modelo L13. La fuente LF heredada conserva VIGENTE; necesita reconciliación gobernada, sin ampliar el alcance de este lote.
4. **SALY:** los gates L7/L8 de LF y el retorno de perfil no están implementados en SALY; el adaptador es solo sintético.
5. **Gobernanza y semántica:** familias, sucesores, aprobación de regla y autenticación auténtica deben ser decididos por el dueño. Los fixtures de cita no son evidencias de auditoría nativa.
6. **Independencia del auditor:** el asistente ejecutor fue GPT-6, no una identidad Claude ni juez externo acreditados.

**Avance:** 100% del alcance ejecutable **sandbox**; 0% autorización de despliegue. No hay eliminación de bloqueos de producción.
