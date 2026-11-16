-- P3: source-bound pantalla_id transport for the existing signed skill runtime ticket.
-- No history rewrite. No direct product DML. Four EKB incidents record memory-only evidence.
BEGIN;
DO $screen_patch$
DECLARE d text; old text;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)'::regprocedure);
 old:=d;
 d:=replace(d,
 $a$'runtime_slug',v_req->>'runtime_slug',
   'expires_at',v_exp,'transport'$a$,
 $b$'runtime_slug',v_req->>'runtime_slug',
   'pantalla_id',CASE WHEN p_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' THEN v_screen ELSE NULL END,
   'expires_at',v_exp,'transport'$b$);
 IF d=old OR position('THEN v_screen ELSE NULL END' IN d)=0 THEN
   RAISE EXCEPTION 'LF_P3_TICKET_SCREEN_TRANSPORT_PATCH_NOT_APPLIED';
 END IF;
 EXECUTE d;

 d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
 old:=d;
 d:=replace(d,
 $a$'skill_code',v_skill_code),
              'terminal_statuses'$a$,
 $b$'skill_code',v_skill_code) ||
                CASE WHEN v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
                     THEN jsonb_build_object('pantalla_id',v_ig_ticket->'pantalla_id')
                     ELSE '{}'::jsonb END,
              'terminal_statuses'$b$);
 IF d=old OR position('pantalla_id'',v_ig_ticket->''pantalla_id''' IN d)=0 THEN
   RAISE EXCEPTION 'LF_P3_BRIDGE_SCREEN_TRANSPORT_PATCH_NOT_APPLIED';
 END IF;
 EXECUTE d;
END $screen_patch$;

DO $ekb$
DECLARE
 v_pr text:='#4052';
 v_source text:='https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4052';
 v_codes text[]:=ARRAY[
'LF-PROFILE-READONLY-REPAIR-AUTHORITY-NULL-20261116-001',
   'LF-PROFILE-NEEDS-INPUT-SCHEMA-MISMATCH-20261116-001',
   'LF-PROFILE-PANTALLA-ID-LOCAL-GUARD-INACTIVE-20261116-001',
   'LF-PROFILE-BASELINE-NULL-NO-CONTINUATION-20261116-001'
 ]::text[];
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes)) THEN
   RAISE EXCEPTION 'LF_E21_PROFILE_REPAIR_EKB_DUPLICATE';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,
  created_at,updated_at)
 VALUES
 (gen_random_uuid(),'LF-PROFILE-READONLY-REPAIR-AUTHORITY-NULL-20261116-001','PROFILE_EXECUTION',
  'READ_ONLY recibió rechazo por repair_execution_authority nula','En Step50 se exigía autoridad de reparación incluso en modo READ_ONLY, bloqueando un análisis sin efectos.','Un único gate mezcló READ_ONLY con GOVERNED_REPAIR_WRITE.','READONLY_WRITE_BRANCH_COLLAPSE','Separar READ_ONLY sin efecto de GOVERNED_REPAIR_WRITE manteniendo los controles de Train/SHA y receipt.',
  'PG17/18 BEGIN/ROLLBACK, CI real, SELECT EKB tras Train','HIGH',1,
  clock_timestamp(),clock_timestamp(),'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
  'prueba en memoria, sin corrida real','PROFILE_EXECUTION',
  ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],'R5_EROSION_PROCESO','LOUD_EARLY',
  'IG 08:30 2026-11-16, hallazgo comunicado por el dueño',v_source,
  clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-PROFILE-NEEDS-INPUT-SCHEMA-MISMATCH-20261116-001','PROFILE_EXECUTION',
  'Step60 transportó NEEDS_INPUT con esquema PRODUCT_DIRECTION_SPEC','Product Director valida semánticamente PRODUCT_MISSING_INPUT_STATE/NEEDS_INPUT pero el validador de transporte fijaba PRODUCT_DIRECTION_SPEC.','Selección de esquema por perfil en lugar del tipo de salida admitido.','OUTPUT_MODE_SCHEMA_MISMATCH','Resolver el schema canonico por output_type con binding hash y denegar tipos no declarados.',
  'PG17/18 BEGIN/ROLLBACK, CI real, SELECT EKB tras Train','HIGH',1,
  clock_timestamp(),clock_timestamp(),'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
  'prueba en memoria, sin corrida real','PROFILE_EXECUTION',
  ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],'R5_EROSION_PROCESO','LOUD_EARLY',
  'IG 08:30 2026-11-16, hallazgo comunicado por el dueño',v_source,
  clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-PROFILE-PANTALLA-ID-LOCAL-GUARD-INACTIVE-20261116-001','PROFILE_EXECUTION',
  'Step40 perdió pantalla_id en request_body del ticket','lf_profile_native_bridge_prepare_v1 construye profile_skill_runtime_v1 sin pantalla_id aunque lf_profile_skill_runtime_ticket_issue_v1 tiene la solicitud canónica, inutilizando el guard local del retorno IG bloqueado.','Campo de alcance firmado por ticket no fue propagado al transporte de continuación.','REQUIRED_FIELD_NOT_TRANSPORTED','Transportar pantalla_id solo desde ticket SQL autorizado y verificar igualdad en Python y Edge.',
  'PG17/18 BEGIN/ROLLBACK, CI real, SELECT EKB tras Train','MEDIUM',1,
  clock_timestamp(),clock_timestamp(),'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
  'prueba en memoria, sin corrida real','PROFILE_EXECUTION',
  ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],'R5_EROSION_PROCESO','SILENT',
  'IG 08:30 2026-11-16, hallazgo comunicado por el dueño',v_source,
  clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-PROFILE-BASELINE-NULL-NO-CONTINUATION-20261116-001','PROFILE_EXECUTION',
  'Paso47 congelado de baseline exige sobre pero el flujo envía NULL','lf_profile_native_bridge_prepare_v1 llama research_baseline_v1 con NULL; para modalidad obligatoria devuelve BASELINE_REQUIRED pero el bridge responde BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY y no expone una continuación tipada del mismo RUN.','Orquestación no expuso entrada específica para el sobre de baseline.','TYPED_CONTINUATION_MISSING','Exponer BASELINE_REQUIRED como continuación tipada y aceptar sobre de fuente en la misma ejecución por Edge gobernado.',
  'PG17/18 BEGIN/ROLLBACK, CI real, SELECT EKB tras Train','HIGH',1,
  clock_timestamp(),clock_timestamp(),'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
  'prueba en memoria, sin corrida real','PROFILE_EXECUTION',
  ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],'R5_EROSION_PROCESO','LOUD_EARLY',
  'IG 08:30 2026-11-16, hallazgo comunicado por el dueño',v_source,
  clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes))<>4 THEN
   RAISE EXCEPTION 'LF_E21_PROFILE_REPAIR_EKB_COUNT_NOT_FOUR';
 END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes)
   AND estado='ACTIVO' AND frecuencia=1 AND pr=v_pr
   AND source_ref=v_source AND categoria='PROFILE_EXECUTION'
   AND lifecycle_phase='PROFILE_EXECUTION' AND root_cause_family='R5_EROSION_PROCESO'
   AND consumer_role=ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[]
   AND lote_origen='LF_E21_PROFILE_CONTRACT_20261116'
   AND evidencia='prueba en memoria, sin corrida real')<>4
 THEN RAISE EXCEPTION 'LF_E21_PROFILE_REPAIR_EKB_FIELDS_DRIFT'; END IF;
END $ekb$;
COMMIT;
