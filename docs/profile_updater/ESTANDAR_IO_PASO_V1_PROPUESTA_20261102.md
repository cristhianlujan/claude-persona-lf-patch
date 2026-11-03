# LF — Estándar propuesto de entrada, proceso, salida y recepción para Profile Updater
**Estado: PROPUESTA DOCUMENTAL / SOLO LECTURA / SIN ENFORCEMENT.**
**Fecha de levantamiento:** 2026-11-02.
**Operación:** `ACTUALIZACION_PERFIL_LF`. **Run observado:** `EXEC-ACTUALIZACION-PERFIL-LF-OIDC-a4b04585-e518-482c-ab02-855a807ee0ae`.
**Repositorio:** `cristhianlujan/claude-persona-lf-patch`. **Fuente inspeccionada:** Supabase LIVE + `main@6863ce07a3be4a74c1ca2fd307c2799fcdae0e2a`.
**Prioridad de autoridad:** política y contratos LIVE + snapshot congelado de cada run; este documento NO los reemplaza.

## 1. Diagnóstico verificable (no propuesta)
- Hay 17 pasos activos con contratos `ACTIVE_ENFORCEMENT`, evidencia y juez vinculados.
- `input_required` es `[]` en **15/17**; solo `method_selection` (35) y `evolution_decision` (37) lo pueblan.
- `public.lf_record_profile_operation_step_v1` **no referencia `input_required` ni `output_payload`** en la función LIVE inspeccionada. Sí verifica `public.lf_operation_step_judge_bindings.required_evidence_keys`, orden, estado y controles específicos.
- El fallo de paso 90 se origina en la verificación server-side del **`evolution_proof_run_id`** oficial `compare`, anclado a `bound_revision` del 60, `commit_sha` servidor del 70 y hora posterior al write. Un run Python de validación no sustituye ese comprobante.
- La ruta técnica actual es **GitHub Issue `LF_PROFILE_UPDATE_REQUEST_V1` + etiqueta `lf-profile-update-governed` → GitHub Actions/OIDC → Edge `run-creacion-perfil-lf` → `lf_record_profile_operation_step_v1` → recibo `lf_operation_execution_steps`**; Router ACT-0001 no escribe ni lanza directamente el perfil.
- El catálogo muestra `baseline_read.next_if_pass=change_scope` pese a la ruta evolutiva real 30→35→37→40. `evolution_decision.next_if_pass=null` depende del outcome. **La ruta efectiva/snapshot, no ese enlace estático, determina la continuación.**
- Caso actual: pasos 00–80 = 11 PASS; 90–130 = sin registro, run `IN_PROGRESS`. No se modifica este estado por documentarlo.

## 2. Contrato transversal propuesto (documentación, NO payload nuevo)
```text
ENTRADA
  execution_id, operation_code, step_id, required_source_refs[]
  input_required[] (campos tipados que el paso CONSUME)
  input_bindings[] = {name, producer_step_id|external_source, source_ref,
                       source_sha256|revision, verification_method}
  previous_receipt_ref / policy_snapshot_ref / exact_head cuando apliquen
        ↓
PROCESO
  resolver_ref + versión, método ejecutado, condiciones PASS/BLOCK
  identidad / currentness / consistencia de SHA / pruebas negativas
        ↓
SALIDA
  output_payload{} (resultados del paso)
  evidence_ref + evidence_payload{} (prueba fuente, no declaración del productor)
  blocking_codes[] + status derivado por juez
        ↓
TRANSPORTE
  LF_PROFILE_UPDATE_REQUEST_V1 / profile_update_record_batch
  GitHub Issue + etiqueta → GitHub Actions/OIDC → Edge → RPC
        ↓
RECEPCIÓN
  mismo execution_id + step_id; resultado STEP_RECORDED / BLOCKED
  recorded_by_rpc, server_trust_context, hash/ref, readback de ledger
        ↓
SIGUIENTE ETAPA
  solo por ruta efectiva del snapshot + gates oficiales, sin segundo orquestador
```

### Campos comunes y autoridad
`execution_id`, `step_id`, `evidence_ref`, `evidence_payload`, `step_result`, `blocking_codes` ya forman parte del request de transporte; NO agregarlos obligatoriamente como campos top-level nuevos al request actual.
`input_bindings` es **especificación documental futura**, no una columna ni contrato LIVE implementado; su persistencia debe resolverse dentro de la fuente de definición bajo proceso gobernado.
`input_required` describe **lo que hay que consumir/validar antes de procesar**, mientras `required_evidence_keys` define **lo que hay que presentar al juez al registrar**. NO son sinónimos ni deberían copiarse a ciegas.
Cada entrada enlazada debe indicar: fuente productora, ubicación, revisión/hora, verificación, tratamiento de faltantes, condición de invalidez y destinatario.

## 3. Matriz propuesta — 17 etapas
En la columna «entrada» se describen **dependencias propuestas**, NO valores ya escritos en `input_required` LIVE. «Salida» resume evidencia requerida hoy y campos derivados observados. Los `next` dinámicos son indicativos; decide el snapshot gobernado.

| Orden | Paso | Entrada consumida (PROPUESTA) | Proceso/verificador | Salida/recibo | Continuación |
|---|---|---|---|---|---|
| 00 | `init_execution` | Solicitud literal + target + política + identidad del caller | Resolver operación y congelar snapshot | execution_id_created, target_code, target_path | router |
| 10 | `router` | run ID + solicitud literal + recibo semántico ACT-0001 | Validar clasificación, transporte y ausencia de autoridad de escritura | router_read, action | profile_resolve |
| 20 | `profile_resolve` | recibo Router + catálogo y código objetivo | Resolver exactamente un perfil y su fuente | codigo_activo, profile_slug, repo_path, exact_profile_resolved | baseline_read |
| 30 | `baseline_read` | perfil resuelto + HEAD/árbol de referencia | Congelar BEFORE y archivos exactos | baseline_revision, baseline_files, before_evidence | method_selection (según ruta efectiva) |
| 35 | `method_selection` | medición oficial, SHA de baseline, assessment receipt y selector | Cotejar capacidad vigente, métodos cualificados o vacío justificado | profile_slug, source_head_sha, profile_assessment_receipt_id, profile_assessment_sha256, selector_version, selected_methods, method_execution_permitted | evolution_decision |
| 37 | `evolution_decision` | recibo paso 35 + snapshot de política + assessment SHA | Fijar UPDATE/PATCH o NO_CHANGE; elegir ruta del snapshot | profile_slug, source_head_sha, receipt/sha, decision, evolution_mode, decision_evidence_ref, github_write_permitted=false | ruta efectiva por outcome |
| 40 | `change_scope` | decisión/assessment + BEFORE + defectos y EKB | Delimitar parche mínimo y preservaciones | defect, root_cause, minimal_patch_scope, preserved_constraints | regression_plan |
| 50 | `regression_plan` | alcance + controles S26 y Group2 + caso literal | Definir positivos, negativos, adversariales y holdout | positive_cases, negative_cases, adversarial_cases, holdout | pre_write_execution_binding_gate |
| 60 | `pre_write_execution_binding_gate` | run+target+plan+política+SHA actual + recibo 50 | Servidor verifica binding/continuidad y autoridad de escritura | execution_id, target_code, target_path, write_plan, pre_write_gate_passed + server_trust_context | github_write |
| 70 | `github_write` | binding 60 + parche autorizado + rama y árbol base | Crear/inspeccionar commit; servidor contrasta GitHub exacto | branch, written_files[blob_sha], commit_sha, identity_preserved + server_trust_context | github_readback |
| 80 | `github_readback` | commit 70 y lista exacta de blobs | Releer SHA/archivos desde GitHub, sin aceptar HEAD autodeclarado | exact_head, readback_files, sha_match, identity_preserved + server_trust_context | deterministic_validation |
| 90 | `deterministic_validation` | bound_revision del 60 + commit verificado 70/80 + evolution_proof_run_id de compare oficial + negativos | Edge verifica workflow/fecha/title/SHAs/annotation; RPC valida resultados y contrato | validator_result, malformed_input_result, negative_regressions + proof_run_id/evolution_proof_verified | semantic_judge |
| 100 | `semantic_judge` | recibos 90 + RAW/procedencia + evaluador independiente + autoridad | Evaluar semántica y consistencia de rutas; no asumir self-review PASS | semantic_judge_result, authority_checks, router_direct_consistency | regression_after |
| 110 | `regression_after` | recibos 90/100 + casos y RAW original/candidato sobre árboles exactos | Rehacer comparador Group2, holdout y adversariales; adjuntar matriz complementaria | before_after_matrix, adversarial_result, holdout_result | post_merge_reconcile |
| 115 | `post_merge_reconcile` | merge Train oficial + nuevo main + árboles pre/post + estado runtime | Readback exacto, reconciliar diferencias y ausencia de promoción | reconciliation_disposition, merge_sha, entrypoint_sha, manifest_sha, profile_pack_id, runtime_state_before/after, operational_state_preserved, automatic_impact_preserved, next_gate | close |
| 120 | `close` | receipts de todos los gates y reconciliación + bloqueos | Validar ruta limpia sin impactos prohibidos | all_required_steps_clean, open_blockers, runtime_unchanged, no_auto_promotion | report_output |
| 130 | `report_output` | cierre 120 + exact main + refs de evidencia y siguiente gate | Emitir respuesta y dejar recibo persistente del mismo execution_id | result, exact_head, evidence_refs, open_blockers, next_gate | terminal |

## 3.1 Dos contratos de entrada distintos: INIT y pasos registrados

**Paso 00 (INIT, antes de existir `execution_id`):** la entrada real es el Issue `LF_PROFILE_UPDATE_REQUEST_V1` con `action=profile_update_init`, `target_code`, `target_path`, `research_baseline_mode` y `research_baseline_contract`. Los tres primeros valores se consumen obligatoriamente; `research_baseline_contract` debe ser `null` cuando el modo es `NOT_REQUIRED`, y debe contener un objeto de versión `PROFILE_RESEARCH_BASELINE_BINDING_V1` cuando el modo es `PRE_RESEARCH_ALWAYS`. El propio paso 00 crea `execution_id`; **no es válido exigir un recibo anterior**. El preflight usa `--init-request-json`.

**Pasos 10–130 (después de INIT):** la entrada real se entrega mediante `profile_update_record_batch`, que posee `execution_id` y `steps[]`; cada item contiene `step_id`, `evidence_ref`, `evidence_payload`. El preflight recibe un contexto de lectura con fila de ejecución y recibos previos del mismo `execution_id`, usando `--step-id` y `--context-json`. No se agregan claves al transporte.

Los 44 bindings propuestos en `skills/profile_creator/contracts/profile_updater_io_bindings_v1.json` declaran `name`, `source`, `path` y `value_type`; la validación de tipos y procedencia es **local/candidata**, no está aún conectada al runtime del Updater. `READY_FOR_GOVERNED_INITIALIZATION` y `READY_FOR_SERVER_VERIFICATION` significan únicamente *preflight satisfecho*, **no** ejecución, autoridad o PASS. El verificador Edge/RPC existente permanece obligatorio.

**Dato de compatibilidad:** en el run observado, 26/29 referencias comprobadas inicialmente contra recibos de 00–80 coincidieron. Las 3 referencias del paso 00 no aparecen en su **recibo de salida**, porque provienen del **Issue de inicialización**; compararlas con la salida de INIT no representa un fallo de transporte. Deben auditarse contra su entrada previa real, sin inventar datos del Issue histórico.

## 4. Paso 90 — comparación explícita del productor anterior

**Entrada contractual documentada (PROPUESTA):**
- `execution_id`, `step_id=deterministic_validation`.
- `step60.bound_revision` — SHA base leído/verificado en servidor.
- `step70.server_trust_context.commit_sha` — commit candidato **de ese mismo run**, no HEAD actual de la rama.
- `step80.exact_head`, `sha_match=true` y blobs exactos, reconciliados con 70.
- `evolution_proof_run_id` — GitHub Actions workflow `lf-profile-evolution-proof.yml`, modo `compare`, creado después del write.
- Evidencia de prueba de casos y RAW coherente con árboles/entrada; separar `RUNTIME_ATTESTED`, `NONE`, `NOT_VERIFIED` y juez independiente.

**Procesamiento realmente implementado:** Edge `run-creacion-perfil-lf/index.ts` obtiene del ledger 60 y 70; `verifyEvolutionProofRun` comprueba ID, workflow, `head_branch=main`, conclusión SUCCESS, título exacto `profile-evolution-proof compare <slug> <bound_revision> <candidate_commit>`, fecha, job, anotación única, hashes, veredicto `EVOLUTION_DEMONSTRATED` y cero regresiones; luego el RPC decide registro. La entrada `input_required=[]` NO activa esa verificación; la activa el código.

**Salida mínima de registro:** `validator_result`, `malformed_input_result`, `negative_regressions`, prueba verificada y `evidence_ref`, con `STEP_PASS_WITH_EVIDENCE` derivado por servidor; si falta `evolution_proof_run_id`, no hay PASS.
**Precaución:** el resultado estructural o Group2 no certifica por sí solo procedencia de ejecución nativa ni independencia semántica.

## 5. Riesgos de implementación y pruebas previas
1. **Lectura/compatibilidad:** antes de poblar `input_required` en LIVE, enumerar consumidores, su esquema real y todos los pasos afectados. Actualmente no lo impone el RPC; no fingir enforcement. Verificar consultas existentes y contratos/snapshots en curso.
2. **No romper transporte:** no añadir claves fuera de `LF_PROFILE_UPDATE_REQUEST_V1` al Issue. Mantener issue→label→OIDC→Edge→RPC; `service_role` nunca viaja por Router ni en el Issue.
3. **Fail-closed:** faltar fuente previa, SHA distinto, step incorrecto, run anterior al write, proof de otro perfil o `NONE` presentado como atestado deben bloquear el PASS correspondiente.
4. **Rutas dinámicas:** preservar `UPDATE` / `NO_CHANGE` de la política; no fijar secuencia 30→40 por un `next_if_pass` estático.
5. **Ciclos históricos:** no reinterpretar ni sobrescribir recibos antiguos; cada run conserva snapshot, política y origen.
6. **Verificación E2E:** capturar requerimientos reales, probar 70→80→90 con una pareja de corridas nativas genuinas, payload de salida, transporte, readback del mismo execution ID y matriz en 110/130.
7. **Integración:** registrar una propuesta versionada de definición, revisar por dueño de fuente, aplicar mediante migración gobernada y canary antes de marcar enforcement. No modificar reglas del comparador para forzar éxito.

## 6. SQL de lectura (no muta)
```sql
select c.step_order, c.step_id, c.input_required, c.resolver_ref,
       c.output_payload, c.required_evidence_keys,
       c.next_if_pass, c.next_if_blocked, c.status
from public.lf_operation_step_contracts c
where c.operation_code='ACTUALIZACION_PERFIL_LF'
order by c.step_order;

select s.step_order, s.step_id, s.status, s.evidence_ref,
       s.evidence_payload->>'recorded_by_rpc' as recorded_by_rpc,
       s.evidence_payload->>'server_trust_context_valid' as server_trust_valid
from public.lf_operation_execution_steps s
where s.execution_id='EXEC-ACTUALIZACION-PERFIL-LF-OIDC-a4b04585-e518-482c-ab02-855a807ee0ae'
order by s.step_order;
```

## 7. Estado de esta propuesta
**Definición documental:** creada para lectura/contraste. **Fuente LIVE:** intacta.
**Código/transporte:** intactos. **Router:** intacto. **Promoción/merge:** no autorizados por este documento.
**Pendiente para implementación real:** mapear `input_required` tipado a fuentes, diseñar verificación por etapa, tests de incompatibilidad, aprobación de cambio de fuente oficial y despliegue canary. 
