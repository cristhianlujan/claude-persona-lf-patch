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

### Candidato implementado (sin alterar el RUN)
- `caller.ts`: si IG BLOCKED aporta evidencia canónica y el manifest
  del mismo RUN leído de Supabase autoriza exclusivamente lectura,
  devolver `TERMINAL_WITH_FINDINGS`, HTTP200, `terminal_status=BLOCKED`
  (nunca READY). Fuera de read-only o sin evidencia: el HTTP409 se mantiene.
- `scripts/lf_profile_native_resume.py`: solo acepta esa respuesta
  restringida; reinvoca el bridge oficial y **exige** Step40 registrado
  / Step50 `NATIVE_MODEL_INPUT_READY` con IG original
  `BLOCKED` + `READ_ONLY_WITH_IG_FINDINGS`; si falla, bloquea.
  No transporta el hallazgo sensible a logs.
- La SQL vigente `lf_profile_native_bridge_prepare_v1` ya incluye
  Step40 `input_governance` íntegro para el contexto del paso 50.
- Candidato SQL en
  `20261114023000_lf_profile_readonly_ig_findings_report_v1.sql`:
  preserva función oficial `lf_profile_native_bridge_record_report_v1`,
  exige MD5 preimagen exacta `cafaaff15eb0751a9af0cfb67db3c30b`
  (readback `pg_get_functiondef`), conserva Step80 histórico sin cambios
  para READY/no findings y añade únicamente cuando aplica
  `ig_findings.input_governance` completo + decisión RAW
  `profile_output.traceability.ig_open_work_resolution` realmente
  observada. No crea otra función escritora ni promueve acciones.
- `caller_test.ts` incorpora casos 200 lectura, 409 escritura,
  409 sin evidencia; en workflow
  `ig-m105-cp2-oidc-bridge-tests.yml` sin modificar el workflow protegido;
  las tres pruebas nuevas se incluyen en el filtro OIDC existente `^CP2:`.
  `test_profile_resume_issue_request.py` verifica continuación OIDC
  del mismo RUN y step40 verificado antes de step50.

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
aplicar la migración de `report_output` y desplegar
`lf-profiles-governance-caller-v1` por el flujo OIDC/Edge oficial.
La regla previa de EKB `BLOCKED: no avanzar` requiere reconciliación
documental gobernada. Hasta superar ese gate, NO-GO.
