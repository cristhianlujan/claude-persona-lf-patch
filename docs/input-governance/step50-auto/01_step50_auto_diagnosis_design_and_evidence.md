# #3845 — Selector dinámico de skills desde la operación (DRAFT · NO-GO)

## Disparo único del dueño
> Ejecuta EJECUCION_PERFIL_LF para <solicitud + contexto>

## Evidencia SELECT (13-nov-2026 · Supabase solo lectura)
- **Corrección expresa de diagnóstico:** `public.lf_activo_relaciones` es un grafo documental de activos; su ausencia de vínculos PERFIL→SKILL **NO** prueba falta de un selector de skills. El catálogo/invocador vigentes son `public.lf_skill_catalog_v1` (8 registros) y `public.lf_skill_invocation_v1` (14 invocaciones, 3 RUN padre). IG NO está registrado en el catálogo.
- Patrón canónico de selección del perfil: `public.lf_profile_selection_registry_v1` (descriptor JSONB, `LF_PROFILE_SELECTION_DESCRIPTOR_V1`, `CURRENT/STALE_SOURCE_CHANGED`) + `public.lf_profile_selector_policy_v1` (perfil, channels, entry_policy). Se reutiliza el **patrón**, no se crea Router de skills.
- `public.lf_operation_steps` + `public.lf_operation_step_contracts`: 11 pasos `EJECUCION_PERFIL_LF` `ACTIVE_ENFORCEMENT`. El canal verificado vive en `manifest.router_profile_handoff.channel`, faltante en algunos RUN históricos: esos casos se bloquean, nunca se infiere canal.
- `public.lf_skill_invoke_v1` ya impone perfil y operación autorizada, READY, inputs obligatorios, handler y replay; escribe la tabla oficial de invocación. No reemplazarlo.

## SQL candidato (sin DDL/DML vivo)
`supabase/migrations/20261114020000_lf_profile_skill_dynamic_selection_v1.sql`:
1. `lf_skill_selector_policy_v1`: asociación perfil+skill+operación requerida, canales, efectos autorizados y `DETERMINISTIC_REQUIRED` o `SEMANTIC_OPTIONAL`; solo el perfil ejecutor decide sus skills, Router no participa.
2. `lf_skill_selection_registry_v1`: descriptor `LF_SKILL_SELECTION_DESCRIPTOR_V1`, evidencia, fuente, revisión y `CURRENT/STALE_SOURCE_CHANGED`. Se rechazan entradas stale o catálogo no READY.
3. `lf_profile_skill_selection_prepare_v1`: filtra deterministicamente perfil/canal, operación, efecto, READY, autoridad de escritura gobernada y descriptor CURRENT; obligatorias se seleccionan por política. Para opcionales, entrega `SEMANTIC_SELECTION_REQUIRED` y candidatos al mismo chat nativo. La decisión semántica exige exactamente una skill habilitada, razón, evidencia, source_revision y modo `CURRENT_CONTEXT_REVIEW`; ambigüedad o stale => `BLOCKED`.
4. `lf_profile_execution_plan_v1`: lee los 11 pasos de BD y devuelve skills y `selection_receipt` sin valores codificados para IG en 40/50; no recibe skills del Router.
5. `lf_profile_skill_invoke_selected_v1`: verifica plan contra el RUN existente, llama `lf_skill_invoke_v1` oficial y liga el recibo de selección a `skill_run_id` + `parent_execution_id` en `lf_profile_skill_selection_receipt_v1`. El registro y efecto de la invocación siguen perteneciendo al invocador canónico.
6. IG: `INPUT_GOVERNANCE_CONTEXT_PACK` se añade como **DRAFT**, sin handler habilitado ni descriptor CURRENT hasta comprobación independiente. **No es ejecutable ni READY en Supabase vivo.**

## Candidato Edge/runner, sin API de modelo
- `profile_native_source_bind_v1` consulta el plan en SQL tomando `profile_code` y `channel` del RUN autorizado, nunca del usuario; cuando hay candidatos devuelve `SKILL_SEMANTIC_SELECTION_REQUIRED`. El runner nativo conserva `profile-native-operation-plan.json` cuando READY.
- `profile_native_skill_invoke_v1` usa la función de selección+invocación oficial, que valida de nuevo el perfil, permiso, skill y decisión; autoridad desde Edge OIDC (sin service_role en el chat).
- `scripts/lf_profile_native_resume.py` conserva encadenado 50→60→70→80 en el mismo execution_id, sin modelo externo/API. La resolución semántica real del chat y la invocación integral continúan como **NO-GO** hasta probar workflow nativo sin intervención y validar el handler de IG.

## Pruebas: aislamiento PG17.6/18.7, ROLLBACK
- Fixture 1: IG candidata se habilita `READY`/**CURRENT solo dentro de transacción de prueba**, elegida obligatoria por política, plan 11 pasos y recibo ligado al RUN.
- Fixture 2: skill ficticia elegida por decisión semántica única con descripción y evidencia, plan 11 pasos y recibo ligado al RUN.
- Negativas: elección múltiple => `SKILL_SEMANTIC_SELECTION_AMBIGUOUS`; descriptor `STALE_SOURCE_CHANGED` => `SKILL_DESCRIPTOR_STALE_OR_MISSING`. Ninguna habilita continuación.
- La prueba comprueba SQL y transporte simulado; **NO equivale a ejecutar el modelo ni el handler de IG en la base viva**. Reportar CI solo después de leer el HEAD exacto.

## Matriz candidata: 10 perfiles canónicos (SELECT, sin autoridad adicional)
El SELECT del 14-nov-2026 observó **10 perfiles CURRENT** en
`lf_profile_selection_registry_v1`; canales recuperados de
`lf_profile_selector_policy_v1`. Esta política **no se activa**:
`lf_skill_selector_policy_v1.enabled=false` y
`owner_decision_required=true` en cada asociación nueva.
`INPUT_GOVERNANCE_CONTEXT_PACK` permanece catálogo DRAFT y descriptor STALE.
La selección determinista de IG se permite únicamente después de que la
aplicabilidad oficial de cada solicitud sea positiva; el histórico
`NOT_REQUIRED` nunca se transforma automáticamente en una ejecución.

| Perfil observado | Canal(es) vigente(s) | IG candidata | Otras skills candidatas según rol/fuentes |
|---|---|---|---|
| ACT-0051 — Frontend Prototype Architect | PRODUCTO, PROGRAMACION | Condicional, decisión humana | Ninguna adicional inferible |
| PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING | PRODUCTO | Condicional, decisión humana | SCREEN_RULES_SNAPSHOT, semántica si hay pantalla autorizada |
| PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531 | PRODUCTO | Condicional, decisión humana | SCREEN_RULES_SNAPSHOT, semántica si hay pantalla autorizada |
| PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF | OPERACIONES | Condicional, decisión humana | Ninguna adicional inferible |
| PERFIL-GAMIFICATION-SYSTEM-ARCHITECT | PRODUCTO | Condicional, decisión humana | SCREEN_RULES_SNAPSHOT, semántica si hay pantalla autorizada |
| PERFIL-PRODUCT-DIRECTOR-LF | PRODUCTO | Condicional; 16/17 RUN completados con IG DIRECT_PROFILE | SCREEN_RULES_SNAPSHOT, semántica si hay pantalla autorizada |
| PERFIL-QUALITY-PACK | PRODUCTO, PROGRAMACION, OPERACIONES | Condicional, decisión humana | SCREEN_RULES_SNAPSHOT, semántica si el upstream depende de pantalla |
| PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | PRODUCTO, PROGRAMACION, OPERACIONES | Condicional, decisión humana | PROFILE_UPDATE_APPLY (descriptor actual: operación gobernada específica; nunca autoautoriza write) |
| PERFIL-UI-ARCHITECT | PRODUCTO, PROGRAMACION | Condicional, decisión humana | SCREEN_RULES_SNAPSHOT, semántica si hay pantalla autorizada |
| PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531 | PRODUCTO | Condicional, decisión humana | SCREEN_RULES_SNAPSHOT, semántica si hay pantalla autorizada |

**Fuente de decisiones**: los descriptores de roles y políticas por canal están CURRENT
en el selector de perfiles. `SCREEN_RULES_SNAPSHOT` es la única skill del
catálogo vivo con `required_operation='EJECUCION_PERFIL_LF'`, `READ_ONLY`,
`READY`, con entrada `pantalla_codigo`. `PROFILE_UPDATE_APPLY` exige
`ACTUALIZACION_PERFIL_LF`, `WRITE_GOVERNED` y las autorizaciones existentes.
No se deriva permiso de escritura de un descriptor ni del Router.
Todo uso de IG en los otros 9 perfiles, y la activación de las skills opcionales,
está sujeto a **DECISIÓN HUMANA** con evidencia de aplicabilidad y fuentes actuales.

### Readback de actividad real y prueba de compatibilidad PRODUCT-DIRECTOR
- Corridas COMPLETED por perfil observado: PRODUCT-DIRECTOR **17**,
  SYSTEMIC-ROOT-CAUSE-REPAIR **13**, UI-ARCHITECT **1**,
  EVIDENCE-LINEAGE-REVIEWER **1**; otros 6 sin RUN en el SELECT.
- PRODUCT-DIRECTOR 17 completados: **16 DIRECT_PROFILE** (13 IG READY,
  3 IG BLOCKED) y **1 NOT_REQUIRED**. No afirmar 17 invocaciones materiales.
- Baseline real **solo lectura**:
  `EXEC-PROFILE-GATE2-EA0514AD005350958C4D6E9C` →
  `COMPLETED`, 11/11 STEP_PASS_WITH_EVIDENCE, IG `READY`,
  `CONTEXT_PACK`, `B2B-AUTH-001`, IG run `949`, MD5 JSONB canónico
  `d9c0ac3a8e917fb67c7d24e7d8d2bf7d`.
- PG17.6 y PG18.7: baseline copiado a transacción aislada; el plan genérico
  obtiene los once pasos y conserva sin cambios el MD5 de evidencia previo;
  resultado `SOURCE_PRESERVATION_ONLY_NOT_REEXECUTED`. Es una
  **comparación de transferencia documental y estructura**, **no** una
  re-ejecución del resolver/handler ni una equivalencia funcional E2E.
  La función desplegada todavía tiene la lógica fija de IG en input_validate;
  sustituirla sin la copia de integración y readback del mismo resultado está
  **BLOQUEADO**. No se ha demostrado un RUN nuevo real 0→80 con el
  handler genérico.
- La invocación candidata verifica el `applicability_contract` mediante la ruta de evidencia configurada en política (`input_validate` / `evidence_payload`) **antes de llamar** a `lf_skill_invoke_v1`: sin evidencia → `SKILL_APPLICABILITY_EVIDENCE_NOT_READY`; `applicable=false` → `SKILL_NOT_REQUIRED_BY_INPUT_VALIDATE`. La función no lleva ningún nombre de skill en esta condición. El diseño de **dos fases reales** (primero evidencia de aplicabilidad, después invocación) está pendiente de integración con el Step40 vigente. El antiguo Step40 todavía llama IG fijo y esta prueba NO equivale a sustituirlo.
- Prueba parametrizada de diez perfiles reales en cada PostgreSQL:
  IG por política determinista 10/10; FICTICIA_SEMANTICA por descriptor 10/10;
  ambigüedad bloqueada 10/10 y stale bloqueado 10/10; 20 RUN
  **simulados** × 11 pasos = 220 por motor, con ROLLBACK. Los fixtures
  simulan `enabled=true` y `owner_decision_required=false` **solo dentro
  de la transacción de laboratorio**, nunca como decisión real.

### Decisiones humanas fuera del lote
- Determinar aplicabilidad y perfiles autorizados para IG por canal y operación
  (y cómo conservar el caso histórico `NOT_REQUIRED`).
- Aceptar o rechazar las asociaciones SCREEN_RULES_SNAPSHOT y
  PROFILE_UPDATE_APPLY propuestas; exigir entrada autorizada y origen actual.
- Aprobar fuente, handler, descriptor y política de IG antes de cambiar
  `DRAFT`/`STALE` a READY/CURRENT; sin autorización, no invocar.
- Validar en una copia íntegra el resolver fijo y el handler genérico sobre
  **el mismo** contexto fuente/vigencia para acreditar igualdad de evidencia,
  el RUN 0→80 y el recibo terminal.

## Lote IG BLOCKED sin interrumpir análisis — DRAFT (14-nov-2026)
**Decisión del dueño (posterior a EKB V1.4 §8):** para
`READ_ONLY_WITH_IG_FINDINGS`, reportar el estado IG y conservar la
ejecución de análisis. EKB vigente dice `BLOCKED: no avanzar`; por ello
esto permanece **candidato sin despliegue**, requiere actualización
gobernada de autoridad y pruebas de regresión antes de promoción.

### Revisión del código desplegado/PR y readback SQL
- `caller.ts:603-617`: `input_readiness_context_pack_runtime_v1` (ticket
  del perfil) convierte **cualquier** IG terminal distinto de READY en
  `outcome=BLOCKED, HTTP 409`, aunque contenga 3 hallazgos de predecisión.
  Existe un segundo caso de HTTP 409 para el CONTEXT_PACK legado sin ticket,
  que se mantiene intacto.
- `scripts/lf_profile_native_resume.py`: exige `terminal_status=READY`
  + HTTP200; cualquier 409 corta antes del siguiente
  `lf_profile_native_bridge_prepare_v1`. Ruta directa SQL:
  `public.lf_profile_execution_input_validate_v1` YA distingue la
  autorización de análisis de la autorización de IG para efectos y,
  con manifest read-only/no-write + evidencia actual, devuelve
  `status=READY`, `analysis_scope=READ_ONLY_WITH_IG_FINDINGS` y
  `ig_security_clearance=false`; el escritor oficial registra Step40 PASS.
- SELECT de RUN `EXEC-PROFILE-GATE2-95DFBB22762787B8824EB013`:
  `IN_PROGRESS`, solo 0/10/20/30 registrados; manifest read-only,
  no-write/no-promotion/automatic-impact false. Referencia comprobada
  `EXEC-PROFILE-GATE2-40471E6F661A53D7CE7A4A1B`: COMPLETED 11/11,
  Step40 `STEP_PASS_WITH_EVIDENCE` con IG `BLOCKED`; scope
  `READ_ONLY_WITH_IG_FINDINGS`, IG run 951, 3 hallazgos deterministas
  en `predecision_crosscheck.deterministic_findings`.
- Hallazgos reales leídos: (i) `SEC-B2B-MFA` referencia candidata
  `SEC-B2B-MFA-FACTOR-ELIGIBILITY` por factor_security_policy_id;
  (ii) `SEC-B2B-LOGIN-ANTIBOT` referencia
  `SEC-B2B-AUTH-ABUSE-PROTECTION` por abuse_security_policy_id;
  (iii) `RATE-B2B-LOGIN` requiere prueba de IP_USER composite scope
  bajo `SEC-B2B-AUTH-ABUSE-PROTECTION`. Ninguno se da por resuelto.

### Contraste explícito de los dos RUN — sin regresión de código post-13
| Evidencia | RUN 40471E6F | RUN 95DFBB22 |
|---|---|---|
| Creación UTC | 2026-11-13 01:47:31 | 2026-11-14 05:35:11 |
| Autoridad manifest | read_only=true, no_write=true, no_promotion=true, automatic_impact=false, governed_repair_write=false | **idéntica** |
| Perfil source blob SHA GitHub | c9501679bdcd08d80cebf4a107a6a9a5282084d0 | **mismo SHA** |
| Step40 | PASS 2026-11-13 01:50:00 UTC; IG BLOCKED, IG run951, predecision deterministic_findings=3, remediation_state INTERNAL_REMEDIATION_REQUIRED, no_human_required_count=0, internal_remediation_count=0 | **NO STEP40**; el error IG 409 proviene de la respuesta Edge del ticket, no de una fila SQL |
| Transporte comprobado | SQL `lf_profile_execution_input_validate_v1` → escritor oficial → 11/11 | `input_readiness_context_pack_runtime_v1` → HTTP409 `IG_CONTEXT_PACK_BLOCKED` → resume aborta antes de recomprobar SQL |

- Consulta de historial main del repo: último commit de `caller.ts` antes de este lote fue
  `45f731532741e6f37c20529f8e2d345338fe3f13` (2026-11-06 02:51 UTC,
  solo forward del ticket); último `scripts/lf_profile_native_resume.py`
  `a67176a0b7b381dcbabf6c6e6ce587a8078e2e25` (2026-11-10 01:42 UTC).
  El guard de 409 del runner ya existía en
  `26e26dd5c43d89fe57c73cc718845eff7c1a2bd5` del 8-nov.
  **No hay cambio post-13 de esos archivos en main**. No se atribuye
  falsamente a un PR reciente. La versión Edge desplegada no fue
  certificada por readback de su bundle; certificarla requiere evidencia de despliegue.
- **Tampoco cambió la razón de IG**: el RUN 40471 ya tenía los tres
  hallazgos `VIGENTE_REFERENCES_CANDIDATO` (2) y
  `IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF` (1), con
  `INTERNAL_REMEDIATION_REQUIRED` y 3 deterministic findings.
  `internal_remediation_count=0` es otro contador del crosscheck,
  no prueba ausencia de hallazgos. El RUN nuevo no registró Step40;
  no se presume idéntico payload interno sin el Edge response original.
- La divergencia fue de **ruta de transporte**, latente en el runtime:
  el caller ya emitía 409 para BLOCKED; SQL directo ya lo admitía como
  análisis `READ_ONLY_WITH_IG_FINDINGS`. El runner no repetía
  `lf_profile_native_bridge_prepare_v1` tras 409 del **ticket**.
- **Se descartó y revirtió** la nueva respuesta Edge 200
  `TERMINAL_WITH_FINDINGS`; `caller.ts` / tests se restablecieron idénticos
  a main. No se añade una autorización alternativa, RPC nuevo,
  doble escritor, nuevo status Edge ni segundo RUN.
- **Corrección acotada** en `scripts/lf_profile_native_resume.py`:
  identifica HTTP409 terminal ya existente con hallazgos canónicos
  (identidad del mismo execution_id, pantalla, consumidor, run_id,
  output_sha256, predecision positivo) y reintenta **una sola vez** el
  **bridge SQL canónico existente**. Solo acepta resultado
  `NATIVE_MODEL_INPUT_READY` tras Step40 oficialmente registrado,
  perfil/execution_id exactos, `execution_write_mode=READ_ONLY`, IG
  `BLOCKED` + `READ_ONLY_WITH_IG_FINDINGS` y mismo RUN/hash IG.
  Si el bridge no admite, se detiene; no eleva IG a READY.
- El SQL ya desplegado `lf_profile_native_bridge_prepare_v1` transporta
  a Step50 el `input_governance` de Step40, por lo que no necesita otra
  vía. El candidato SQL
  `20261114020000_lf_profile_skill_dynamic_selection_v1.sql` (sección `INTEGRATED_OFFICIAL_STEP80_REPORT_V1_SINGLE_TRANSACTION`)
  **solo extiende el escritor de informe oficial Step80**, con guard
  de preimagen MD5 `cafaaff15eb0751a9af0cfb67db3c30b`; agrega
  hallazgos íntegros de Step40 y la decisión real de Step50, sin
  alteración si no hay hallazgos. No es nueva vía de continuación.
- Pruebas: `test_profile_resume_issue_request.py` valida el retry
  acotado por HTTP409; `test_governed_profile_operation_bridge.py`
  mantiene laboratorio PG17.6/18.7 con tres escenarios y ROLLBACK.

### Laboratorio: PG17.6 + PG18.7 con ROLLBACK
El fixture copia **identidad/estado 0–30** del RUN afectado; los tres
hallazgos provienen del **RUN de referencia** 40471/IG951, pues el RUN
afectado no llegó a registrar el paso 40. La preparación y pasos
45–70 son simulados; `report_output` llama la definición candidata
real con escritor/terminal aislados de laboratorio. **No prueba una
reanudación real del RUN afectado ni sustituye una prueba integrada**.

| Caso | Esperado | Resultado SQL (ambos PG) |
|---|---|---|
| IG BLOCKED + lectura | 11/11; tres hallazgos intactos al 80 | PASS 11/11, paridad Step40→80 |
| IG BLOCKED + escritura | STOP antes del 40 | PASS BLOCKED, 4 pasos copiados |
| Sin hallazgos (IG READY) | 11/11, esquema histórico igual | PASS 11/11, sin campo nuevo |

SHA-256 del JSONB de la copia (ambos motores):
`before=9f537c508285abbfb6087f7500e9f6d0e425e3fc592c0a85de1b0c8b006d0fd7`,
`during=21320c9196e3f5ab799783e788673d3400a0bf379f53bc35366717b619b054bb`,
`after=9f537c508285abbfb6087f7500e9f6d0e425e3fc592c0a85de1b0c8b006d0fd7`.
Readback: original=restaurado; intra-transaction=distinto; DB de laboratorio
descartada y ningún RUN vivo tocado.

**Despliegue:** PR DRAFT → revisión fuente/authority EKB/contratos,
source-first migration parity y pruebas en clon integrado →
ready-to-merge en HEAD exacto → LF Migration Merge Train →
aplicar la migración de `report_output` si se aprueba y actualizar el runner nativo
por la ruta de GitHub Actions/OIDC existente. **No requiere modificar ni
re-desplegar `lf-profiles-governance-caller-v1`** para corregir el 409.
La regla previa de EKB `BLOCKED: no avanzar` requiere reconciliación
documental gobernada. Hasta superar ese gate, NO-GO.

### Cierre PASE del lote 02:12 — source-first en una migración
- El contrato confiable `_classify_source_first_pending` de `lf_migration_source_parity_ci_context.py` exige `len(local_only)==1` y `migration_changed==[expected_path]`. El Train `lf-migration-merge-train.yml` rechaza más de una migración (`FAIL_MIGRATION_MULTIPLE_PER_PR`).
- Se consolidó íntegramente la SQL de las dos candidatas originales en **una** transacción `BEGIN/COMMIT` y **un** archivo nuevo: `20261114020000_lf_profile_skill_dynamic_selection_v1.sql`. El guard de preimagen de `lf_profile_native_bridge_record_report_v1` sigue exacto; la antigua `20261114023000` fue eliminada de PR y manifiesto.
- Readback de CI exacto HEAD `9c6916fd1e47c1e3c87d18c038c3960e278dab47`: `PASE Merge Gate` run 43570065116 con **pase-merge-gate PASS** y **migration-source-parity PASS**; `PASS_LF_MIGRATION_SOURCE_FIRST_PENDING version=20261114020000 scope=EXACT_ONE_NEW_MIGRATION_PR remote_ahead=false`. `FAIL_LF_MIGRATION_LEGACY_ATTESTATION` aparece como **caso negativo deliberado del self-test**, seguido de `PASS_LF_MIGRATION_SOURCE_FIRST_SELFTEST=7/7` y resultado de job exitoso; no es otro bloqueo activo.
- Esta conformidad **no autoriza** despliegue: PR DRAFT, `ready-to-merge` ausente, revisión integrada y decisión humana pendientes. El archivo candidato solo podría aplicarse vía Train gobernado, nunca SQL directo de inspección.
- GitHub Train (main actual): label `ready-to-merge` por actor GitHub autenticado `cristhianlujan` o `paulozterra` (o allowlist de variable `LF_MIGRATION_TRAIN_ALLOWED_ACTORS`), PR no DRAFT contra main, checks exact HEAD, entorno `lf-merge-train`, identidad bot GitHub App firmando sus operaciones. **No existe firma documental suficiente desde este chat**: `lf_ig_project_owner_v2` observado `TEMP_DOCUMENTARY_ACTIVE/UNVERIFIED_CHAT_DECLARATION`; owner `identity_verified=false` no satisface identidad probada. Protección efectiva de environment/reviewer no fue leída.
- Para registrar Step40 del RUN existente sin ruta nueva: chat **nativo ejecutor de producto** por el Issue/workflow OIDC protegido, mismo `execution_id`; RPC `public.lf_profile_native_bridge_prepare_v1(p_execution_id,p_source_revision,p_source_digest,p_actor_execution_id)` (SECURITY DEFINER, EXECUTE service_role) invoca `lf_profile_execution_input_validate_v1` y `lf_record_profile_execution_step_v1`. Solo la ruta autenticada puede ejercer la autoridad `service_role`; el SQL inspector y el chat de arquitectura no deben escribir directamente. Si retorna `INPUT_GOVERNANCE_RUNTIME_REQUIRED`, usar el ticket existente y reintentar bridge; si se obtiene IG BLOCKED en análisis read-only, respetar el veredicto SQL vigente. No afirmar el paso 40 real registrado sin SELECT.
