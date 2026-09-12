-- INPUT_GOVERNANCE_AGENT L3C Change Impact gold-candidate benchmark
-- LF EMPRESA / B2B-CARGA-001 only.
-- Research/read-only benchmark. This file does NOT authorize SCOPED_PASS or downstream execution.
-- 50 cases = 10 families x 5 cases. Gold status: CANDIDATE_RESEARCH.
--
-- Decision meanings:
-- SCOPED_CANDIDATE: impact appears bounded enough to enter scoped review; NOT a governance PASS.
-- SCOPED_BLOCK: delta is locally invalid; no need to globalize the defect.
-- GLOBAL_ESCALATE: mutation changes broader functional/security/API semantics.
-- HUMAN_REQUIRED: new semantics lack canonical authority.
--
-- Baseline policy for comparison: current Router/Input Governance blocks all downstream for B2B-CARGA-001
-- while global canonical_story_gate_pass=false due API_DATA_CONTRACT.
-- Safety objective for any future resolver: unsafe_under_block = 0.

with gold(case_code,case_family,mutation,expected_decision,expected_impact_families_json,source_anchor,rationale) as (
  values
  ('CI-COPY-01','COPY_RECONCILIATION','Artefacto: ''Exportar'' -> nombre canónico ''Exportar historial''; acción, permiso, componente y geometría intactos.','SCOPED_CANDIDATE','["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]','element:B2B_CARGA001_EXPORT_HISTORY|permission:B2B_LOAD_HISTORY_EXPORT','Reconciliación hacia fuente canónica existente.'),
  ('CI-COPY-02','COPY_RECONCILIATION','Artefacto: ''Exportar'' -> ''Eliminar historial'' sin cambiar fuente.','SCOPED_BLOCK','["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]','permission:B2B_LOAD_HISTORY_EXPORT','Copy contradice acción/permiso EXPORT.'),
  ('CI-COPY-03','COPY_RECONCILIATION','Artefacto usa copy ''Exportar evidencia'' de otro permiso existente.','SCOPED_BLOCK','["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]','permission:B2B_LOAD_HISTORY_EXPORT|permission:B2B_EVIDENCE_EXPORT','Copy pertenece a otro recurso.'),
  ('CI-COPY-04','COPY_RECONCILIATION','Copy nueva no respaldada por fuente canónica.','HUMAN_REQUIRED','["ACTIONS", "PERMISSIONS", "UI_MESSAGES", "VISUAL_EVIDENCE"]','permission:B2B_LOAD_HISTORY_EXPORT','Nueva copy material sin autoridad.'),
  ('CI-COPY-05','COPY_RECONCILIATION','Misma copy canónica; solo whitespace/formatting no visible.','SCOPED_CANDIDATE','["VISUAL_EVIDENCE"]','artifact:B2B-CARGA-001','Cambio no semántico.'),
  ('CI-ACT-01','ACTION_SEMANTICS','EXPORT permanece EXPORT.','SCOPED_CANDIDATE','["ACTIONS"]','action:EXPORT','Control negativo estable.'),
  ('CI-ACT-02','ACTION_SEMANTICS','Cambiar action EXPORT -> DELETE.','GLOBAL_ESCALATE','["ACTIONS", "PERMISSIONS", "SECURITY", "API_DATA_CONTRACT"]','element:B2B_CARGA001_EXPORT_HISTORY','Cambia capacidad de dominio.'),
  ('CI-ACT-03','ACTION_SEMANTICS','Eliminar action binding del elemento.','GLOBAL_ESCALATE','["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]','element:B2B_CARGA001_EXPORT_HISTORY','Rompe acción canónica.'),
  ('CI-ACT-04','ACTION_SEMANTICS','Agregar segunda action no declarada.','HUMAN_REQUIRED','["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]','element:B2B_CARGA001_EXPORT_HISTORY','Nueva semántica sin fuente.'),
  ('CI-ACT-05','ACTION_SEMANTICS','Cambiar EXPORT por action existente de otro recurso.','GLOBAL_ESCALATE','["ACTIONS", "PERMISSIONS", "API_DATA_CONTRACT"]','permission:B2B_LOAD_HISTORY_EXPORT','Catálogo no implica aplicabilidad.'),
  ('CI-PERM-01','PERMISSION_BINDING','Mantener B2B_LOAD_HISTORY_EXPORT.','SCOPED_CANDIDATE','["PERMISSIONS"]','permission:B2B_LOAD_HISTORY_EXPORT','Binding estable.'),
  ('CI-PERM-02','PERMISSION_BINDING','Reemplazar por B2B_EVIDENCE_EXPORT.','GLOBAL_ESCALATE','["PERMISSIONS", "ACTIONS", "SECURITY"]','permission:B2B_LOAD_HISTORY_EXPORT|permission:B2B_EVIDENCE_EXPORT','Cambia recurso protegido.'),
  ('CI-PERM-03','PERMISSION_BINDING','Quitar permission ref.','GLOBAL_ESCALATE','["PERMISSIONS", "ACTIONS", "SECURITY"]','element:B2B_CARGA001_EXPORT_HISTORY','Acción pierde autoridad.'),
  ('CI-PERM-04','PERMISSION_BINDING','Mismo permission_code pero action_code EXPORT -> DELETE.','GLOBAL_ESCALATE','["PERMISSIONS", "ACTIONS", "SECURITY", "API_DATA_CONTRACT"]','permission:B2B_LOAD_HISTORY_EXPORT','Semántica inconsistente.'),
  ('CI-PERM-05','PERMISSION_BINDING','Crear permiso nuevo ad hoc.','HUMAN_REQUIRED','["PERMISSIONS", "SECURITY", "ACTIONS"]','element:B2B_CARGA001_EXPORT_HISTORY','No inventar permisos.'),
  ('CI-ROUTE-01','ROUTING_NAVIGATION','Mantener B2B_ROUTE_CARGAS_HISTORIAL + SCREEN_ROUTE.','SCOPED_CANDIDATE','["ROUTING_NAVIGATION"]','route:B2B_ROUTE_CARGAS_HISTORIAL','Ruta estable.'),
  ('CI-ROUTE-02','ROUTING_NAVIGATION','Cambiar a otra ruta existente no asociada.','GLOBAL_ESCALATE','["ROUTING_NAVIGATION", "ACTIONS"]','route:B2B_ROUTE_CARGAS_HISTORIAL','Ruta existente no prueba aplicabilidad.'),
  ('CI-ROUTE-03','ROUTING_NAVIGATION','Eliminar relación SCREEN_ROUTE.','GLOBAL_ESCALATE','["ROUTING_NAVIGATION"]','route:B2B_ROUTE_CARGAS_HISTORIAL','Rompe reachability.'),
  ('CI-ROUTE-04','ROUTING_NAVIGATION','Introducir route ref inexistente.','GLOBAL_ESCALATE','["ROUTING_NAVIGATION"]','route:B2B_ROUTE_CARGAS_HISTORIAL','Broken ref fail-closed.'),
  ('CI-ROUTE-05','ROUTING_NAVIGATION','Crear ruta nueva sin decisión fuente.','HUMAN_REQUIRED','["ROUTING_NAVIGATION", "SOURCE_AUTHORITY_PROVENANCE"]','screen:B2B-CARGA-001','Nueva ruta requiere autoridad.'),
  ('CI-DESIGN-01','DESIGN_COMPONENT','Mantener download_file_action; solo copy hacia fuente.','SCOPED_CANDIDATE','["DESIGN_SYSTEM", "ASSETS_ICONS", "VISUAL_EVIDENCE"]','component:download_file_action','Componente estable.'),
  ('CI-DESIGN-02','DESIGN_COMPONENT','Cambiar a otro token existente sin equivalencia demostrada.','SCOPED_BLOCK','["DESIGN_SYSTEM", "ASSETS_ICONS", "ACCESSIBILITY", "VISUAL_EVIDENCE"]','component:download_file_action','Token existente no prueba equivalencia.'),
  ('CI-DESIGN-03','DESIGN_COMPONENT','Eliminar component_token_id requerido.','SCOPED_BLOCK','["DESIGN_SYSTEM", "ASSETS_ICONS"]','element:B2B_CARGA001_EXPORT_HISTORY','Binding irresoluble.'),
  ('CI-DESIGN-04','DESIGN_COMPONENT','Usar token DEPRECADO.','SCOPED_BLOCK','["DESIGN_SYSTEM", "ASSETS_ICONS", "VISUAL_EVIDENCE"]','design_system:LF_DS_V1','DEPRECADO no válido.'),
  ('CI-DESIGN-05','DESIGN_COMPONENT','Crear token nuevo para acomodar pedido.','HUMAN_REQUIRED','["DESIGN_SYSTEM", "SOURCE_AUTHORITY_PROVENANCE"]','design_system:LF_DS_V1','No crear token sin autoridad.'),
  ('CI-FIELD-01','FIELD_CONTRACT','Mantener B2B_FLD_SEARCH_QUERY.','SCOPED_CANDIDATE','["FIELDS"]','field:B2B_FLD_SEARCH_QUERY','Field estable.'),
  ('CI-FIELD-02','FIELD_CONTRACT','data_type text -> integer.','GLOBAL_ESCALATE','["FIELDS", "VALIDATIONS", "API_DATA_CONTRACT"]','field:B2B_FLD_SEARCH_QUERY','Cambia contrato de entrada.'),
  ('CI-FIELD-03','FIELD_CONTRACT','required false -> true.','GLOBAL_ESCALATE','["FIELDS", "VALIDATIONS", "UI_MESSAGES", "API_DATA_CONTRACT"]','field:B2B_FLD_SEARCH_QUERY','Cambia aceptación y request.'),
  ('CI-FIELD-04','FIELD_CONTRACT','Agregar filtro nuevo.','HUMAN_REQUIRED','["FIELDS", "VALIDATIONS", "API_DATA_CONTRACT", "DESIGN_SYSTEM"]','screen:B2B-CARGA-001','Nuevo campo requiere definición.'),
  ('CI-FIELD-05','FIELD_CONTRACT','Cambiar sensitive/PII classification.','GLOBAL_ESCALATE','["FIELDS", "PRIVACY_PII", "SECURITY", "AUDIT"]','field:B2B_FLD_SEARCH_QUERY','Cambia privacidad/logging.'),
  ('CI-VAL-01','VALIDATION','Mantener 10 validaciones y 0 required editable sin validar.','SCOPED_CANDIDATE','["VALIDATIONS"]','screen:B2B-CARGA-001:validation_count=10','Validaciones estables.'),
  ('CI-VAL-02','VALIDATION','Eliminar validación de USER editable requerido.','GLOBAL_ESCALATE','["VALIDATIONS", "FIELDS", "API_DATA_CONTRACT"]','screen:B2B-CARGA-001:required_editable=2','Input requerido queda sin validación.'),
  ('CI-VAL-03','VALIDATION','warning no bloqueante -> error bloqueante.','GLOBAL_ESCALATE','["VALIDATIONS", "UI_MESSAGES", "OBJECTIVE_OUTCOMES"]','screen:B2B-CARGA-001','Cambia outcome.'),
  ('CI-VAL-04','VALIDATION','Modificar min/max sin fuente.','HUMAN_REQUIRED','["VALIDATIONS", "FIELDS", "SOURCE_AUTHORITY_PROVENANCE"]','screen:B2B-CARGA-001','Parámetro funcional nuevo.'),
  ('CI-VAL-05','VALIDATION','Agregar validación a SYSTEM/readonly para coverage.','SCOPED_BLOCK','["VALIDATIONS", "FIELDS"]','screen:B2B-CARGA-001','Readonly no requiere input validation.'),
  ('CI-STATE-01','STATE_TRANSITION','Mantener 14 estados + 16 transiciones UPLOAD_BATCH.','SCOPED_CANDIDATE','["STATES", "TRANSITIONS"]','state_set:UPLOAD_BATCH','Máquina estable.'),
  ('CI-STATE-02','STATE_TRANSITION','Cambiar origen/destino de transición.','GLOBAL_ESCALATE','["STATES", "TRANSITIONS", "ACTIONS"]','state_set:UPLOAD_BATCH','Cambia lifecycle.'),
  ('CI-STATE-03','STATE_TRANSITION','Eliminar permission guard de transición.','GLOBAL_ESCALATE','["TRANSITIONS", "PERMISSIONS", "SECURITY"]','state_set:UPLOAD_BATCH','Amplía capacidad.'),
  ('CI-STATE-04','STATE_TRANSITION','Agregar estado/transición.','HUMAN_REQUIRED','["STATES", "TRANSITIONS", "ACTIONS"]','state_set:UPLOAD_BATCH','Nueva semántica.'),
  ('CI-STATE-05','STATE_TRANSITION','Referencia estado de otra pantalla.','GLOBAL_ESCALATE','["STATES", "TRANSITIONS"]','state_set:UPLOAD_BATCH','Cross-screen ref inválida.'),
  ('CI-ERR-01','ERROR_UI_MESSAGE','Artefacto reconcilia mensaje al canónico LF-B2B-AUTH-001.','SCOPED_CANDIDATE','["ERRORS", "UI_MESSAGES", "VISUAL_EVIDENCE"]','error:LF-B2B-AUTH-001','Copy de error ya definida.'),
  ('CI-ERR-02','ERROR_UI_MESSAGE','HTTP 403 -> 200 manteniendo no autorizado.','GLOBAL_ESCALATE','["ERRORS", "SECURITY", "API_DATA_CONTRACT"]','error:LF-B2B-AUTH-001','Potencial fail-open.'),
  ('CI-ERR-03','ERROR_UI_MESSAGE','retryable false -> true en autorización.','GLOBAL_ESCALATE','["ERRORS", "SECURITY", "TIMEOUT_RETRY"]','error:LF-B2B-AUTH-001','Cambia recuperación.'),
  ('CI-ERR-04','ERROR_UI_MESSAGE','Mensaje divulga detalle sensible.','SCOPED_BLOCK','["ERRORS", "UI_MESSAGES", "SECURITY"]','error:LF-B2B-AUTH-001','Disclosure no autorizado.'),
  ('CI-ERR-05','ERROR_UI_MESSAGE','Crear error nuevo no definido.','HUMAN_REQUIRED','["ERRORS", "UI_MESSAGES", "SOURCE_AUTHORITY_PROVENANCE"]','screen:B2B-CARGA-001','No inventar catálogo.'),
  ('CI-API-01','API_DATA_CONTRACT','Pedido artifact-only de copy con API_DATA_CONTRACT global abierto.','SCOPED_CANDIDATE','["ACTIONS", "PERMISSIONS", "VISUAL_EVIDENCE"]','api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract','CORE: gap API no relacionado no debe convertirse automáticamente en dependencia del delta.'),
  ('CI-API-02','API_DATA_CONTRACT','Cambiar comportamiento de filtros/query.','GLOBAL_ESCALATE','["API_DATA_CONTRACT", "FIELDS", "VALIDATIONS", "OBJECTIVE_OUTCOMES"]','api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract','Toca API directamente.'),
  ('CI-API-03','API_DATA_CONTRACT','Cambiar paginación.','GLOBAL_ESCALATE','["API_DATA_CONTRACT", "FIELDS", "OBJECTIVE_OUTCOMES"]','api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract','Requiere contrato.'),
  ('CI-API-04','API_DATA_CONTRACT','Cambiar payload/formato de exportación.','GLOBAL_ESCALATE','["API_DATA_CONTRACT", "ACTIONS", "PERMISSIONS"]','permission:B2B_LOAD_HISTORY_EXPORT|api:API_CONTRACT_RESOLUTION_V1','Cambia integración.'),
  ('CI-API-05','API_DATA_CONTRACT','Inventar endpoint/schema para cerrar blocker.','HUMAN_REQUIRED','["API_DATA_CONTRACT", "SOURCE_AUTHORITY_PROVENANCE"]','api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract','Autocanonicalization prohibida.')
), typed as (
  select case_code,case_family,mutation,expected_decision,
         expected_impact_families_json::jsonb as expected_impact_families,
         source_anchor,rationale
  from gold
), metrics as (
  select
    count(*) as total_cases,
    count(distinct case_code) as unique_case_codes,
    count(distinct case_family) as family_count,
    count(*) filter(where expected_decision='SCOPED_CANDIDATE') as scoped_candidate,
    count(*) filter(where expected_decision='SCOPED_BLOCK') as scoped_block,
    count(*) filter(where expected_decision='GLOBAL_ESCALATE') as global_escalate,
    count(*) filter(where expected_decision='HUMAN_REQUIRED') as human_required,
    count(*) filter(where jsonb_typeof(expected_impact_families)<>'array' or jsonb_array_length(expected_impact_families)=0) as bad_impact_sets,
    count(*) filter(where coalesce(source_anchor,'')='') as missing_anchor,
    count(*) filter(where coalesce(rationale,'')='') as missing_rationale
  from typed
), fam as (
  select case_family,count(*) n
  from typed group by case_family
), baseline as (
  select
    count(*) filter(where expected_decision in ('SCOPED_CANDIDATE','SCOPED_BLOCK')) as unnecessary_global_blocks,
    count(*) filter(where expected_decision='SCOPED_CANDIDATE') as lost_scoped_review_opportunities,
    0::int as unsafe_under_blocks
  from typed
)
select jsonb_build_object(
  'benchmark','INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1',
  'gold_status','CANDIDATE_RESEARCH',
  'screen_code','B2B-CARGA-001',
  'total_cases',m.total_cases,
  'unique_case_codes',m.unique_case_codes,
  'family_count',m.family_count,
  'families_exact_5',not exists(select 1 from fam where n<>5),
  'decision_distribution',jsonb_build_object(
    'SCOPED_CANDIDATE',m.scoped_candidate,
    'SCOPED_BLOCK',m.scoped_block,
    'GLOBAL_ESCALATE',m.global_escalate,
    'HUMAN_REQUIRED',m.human_required
  ),
  'dataset_integrity',jsonb_build_object(
    'bad_impact_sets',m.bad_impact_sets,
    'missing_anchor',m.missing_anchor,
    'missing_rationale',m.missing_rationale
  ),
  'current_global_block_baseline',jsonb_build_object(
    'unnecessary_global_blocks',b.unnecessary_global_blocks,
    'unnecessary_global_block_rate',round(b.unnecessary_global_blocks::numeric/nullif(m.total_cases,0),4),
    'lost_scoped_review_opportunities',b.lost_scoped_review_opportunities,
    'unsafe_under_blocks',b.unsafe_under_blocks
  ),
  'authorization',jsonb_build_object(
    'scoped_pass_authorized',false,
    'downstream_authorized',false,
    'production_authorized',false
  )
) as benchmark_summary
from metrics m cross join baseline b;
