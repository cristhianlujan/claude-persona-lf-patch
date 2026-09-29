-- S30 R19 / A2R correction: Router-bound child execution for canonical EKB write.
-- Child execution carrier: EJECUCION_SKILL_LF targeting ACT-0057.
-- EKB writer authority remains ESCRITURA_BASE_CONOCIMIENTO_LF.
-- No direct PRE_EKB authority is granted to Strategy operations.

DO $pre$
DECLARE c integer;
BEGIN
  SELECT count(*) INTO c FROM public.lf_router_action_registry
  WHERE asset_type='SKILL' AND action_code='SKILL_EXECUTION'
    AND operation_code='EJECUCION_SKILL_LF' AND operation_resolution='STATIC'
    AND requires_existing_target AND NOT write_allowed AND status='ACTIVE';
  IF c<>1 THEN RAISE EXCEPTION 'S30_A2R_SKILL_EXECUTION_ROUTE_NOT_EXACT:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_activos
  WHERE codigo_activo='ACT-0057' AND nombre_canonico='SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF'
    AND tipo_activo='SKILL' AND estado_operativo='APROBADO'
    AND runtime_estado='APROBADO_PRODUCCION_CONTROLADA';
  IF c<>1 THEN RAISE EXCEPTION 'S30_A2R_KB_WRITE_SKILL_NOT_CURRENT:%',c; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
      AND coalesce((required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_A2R_KB_WRITER_AUTHORITY_NOT_ACTIVE'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_operation_policy_snapshot
    WHERE operation_code='EJECUCION_SKILL_LF'
      AND policy_role='GOVERNANCE_LIFECYCLE'
      AND policy_code='POL-LF-OPERATION-LIFECYCLE'
      AND required AND policy_sha IS NOT NULL
  ) THEN RAISE EXCEPTION 'S30_A2R_SKILL_EXECUTION_LIFECYCLE_POLICY_MISSING'; END IF;

  IF to_regprocedure('public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_strategy_ekb_child_dispatch_v1(text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'S30_A2R_REQUIRED_CHILD_DISPATCH_PRIMITIVE_MISSING';
  END IF;
END
$pre$;

UPDATE public.lf_operation_contracts
SET allowed=(coalesce(allowed,'{}'::jsonb)-'ekb_child_operation') || jsonb_build_object(
      'ekb_child_execution_operation','EJECUCION_SKILL_LF',
      'ekb_child_target_asset','ACT-0057',
      'ekb_writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'ekb_child_dispatch_required_per_run',true
    ),
    updated_by_execution_id='EXEC-S30-R19-AUTONOMOUS-20260915-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
  AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
  AND status='ACTIVE_ENFORCEMENT';

CREATE OR REPLACE FUNCTION public.lf_strategy_ekb_child_dispatch_v1(
  p_parent_execution_id text,
  p_finding jsonb,
  p_finding_fingerprint text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  parent_row public.lf_operation_execution%rowtype;
  child_row public.lf_operation_execution%rowtype;
  reserve_receipt jsonb;
  writer_receipt jsonb;
  prior_writer_event public.lf_eventos%rowtype;
  child_seed text;
  child_execution_id text;
  idem_key text;
  request_sha text;
  payload_sha text;
  code text;
  enriched jsonb;
BEGIN
  SELECT * INTO parent_row FROM public.lf_operation_execution WHERE execution_id=p_parent_execution_id;
  IF NOT FOUND OR parent_row.operation_code NOT IN ('EJECUCION_ESTRATEGIA_LF','ACTUALIZACION_ESTRATEGIA_LF')
     OR parent_row.status NOT IN ('IN_PROGRESS','BLOCKED','FAILED') THEN
    RAISE EXCEPTION 'S30_R19_EKB_PARENT_OPERATION_UNAUTHORIZED:%',p_parent_execution_id;
  END IF;
  IF p_finding IS NULL OR jsonb_typeof(p_finding)<>'object' THEN
    RAISE EXCEPTION 'S30_R19_EKB_FINDING_NOT_OBJECT';
  END IF;
  IF coalesce(p_finding_fingerprint,'') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'S30_R19_EKB_FINGERPRINT_INVALID:%',coalesce(p_finding_fingerprint,'');
  END IF;
  code:=upper(btrim(coalesce(p_finding->>'codigo','')));
  IF code='' THEN RAISE EXCEPTION 'S30_R19_EKB_CODE_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='SKILL' AND action_code='SKILL_EXECUTION'
      AND operation_code='EJECUCION_SKILL_LF' AND operation_resolution='STATIC'
      AND requires_existing_target AND NOT write_allowed AND status='ACTIVE'
  ) THEN RAISE EXCEPTION 'S30_R19_EKB_CHILD_ROUTER_BINDING_INVALID'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='ACT-0057' AND nombre_canonico='SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND tipo_activo='SKILL' AND estado_operativo='APROBADO'
      AND runtime_estado='APROBADO_PRODUCCION_CONTROLADA'
  ) THEN RAISE EXCEPTION 'S30_R19_EKB_TARGET_SKILL_NOT_CURRENT'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
      AND coalesce((required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_R19_EKB_WRITER_AUTHORITY_NOT_ACTIVE'; END IF;

  payload_sha:=encode(extensions.digest(convert_to(p_finding::text,'UTF8'),'sha256'),'hex');
  child_seed:=encode(extensions.digest(convert_to(p_parent_execution_id||'|'||p_finding_fingerprint,'UTF8'),'sha256'),'hex');
  child_execution_id:='EXEC-EKB-S30-'||upper(substr(child_seed,1,32));
  idem_key:='S30-EKB-WRITE:'||child_seed;
  request_sha:=encode(extensions.digest(convert_to(
    p_parent_execution_id||'|EJECUCION_SKILL_LF|ACT-0057|ESCRITURA_BASE_CONOCIMIENTO_LF|'||code||'|'||p_finding_fingerprint||'|'||payload_sha,
    'UTF8'),'sha256'),'hex');

  reserve_receipt:=public.fn_lf_operation_reserve_execution_v1(
    child_execution_id,
    'EJECUCION_SKILL_LF',
    'SKILL',
    'ACT-0057',
    idem_key,
    request_sha,
    p_parent_execution_id,
    'cristhianlujan/claude-persona-lf-patch',
    'skills/escritura_base_conocimiento_lf/',
    jsonb_build_object(
      'dispatch_schema','LF_STRATEGY_EKB_CHILD_DISPATCH_V2',
      'parent_execution_id',p_parent_execution_id,
      'parent_operation_code',parent_row.operation_code,
      'router_asset_type','SKILL',
      'router_action_code','SKILL_EXECUTION',
      'child_execution_operation','EJECUCION_SKILL_LF',
      'target_skill_code','ACT-0057',
      'target_skill_name','SKILL_ESCRITURA_BASE_CONOCIMIENTO_LF',
      'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'finding_fingerprint',p_finding_fingerprint,
      'finding_payload_sha256',payload_sha,
      'error_code',code
    )
  );

  SELECT * INTO child_row FROM public.lf_operation_execution WHERE execution_id=reserve_receipt->>'execution_id';
  IF NOT FOUND OR child_row.operation_code<>'EJECUCION_SKILL_LF'
     OR child_row.target_type<>'SKILL' OR child_row.target_code<>'ACT-0057'
     OR child_row.manifest->>'parent_execution_id'<>p_parent_execution_id
     OR child_row.manifest->>'writer_authority_operation'<>'ESCRITURA_BASE_CONOCIMIENTO_LF'
     OR child_row.manifest->>'finding_fingerprint'<>p_finding_fingerprint
     OR child_row.request_sha256<>request_sha
     OR NOT (child_row.manifest ? 'operation_policy_snapshots') THEN
    RAISE EXCEPTION 'S30_R19_EKB_CHILD_READBACK_MISMATCH';
  END IF;

  SELECT * INTO prior_writer_event
  FROM public.lf_eventos
  WHERE evento_tipo='REMEDIACION_GOBERNANZA'
    AND created_by_execution_id=child_row.execution_id
    AND origen='LF_PIPELINE_EKB_WRITER_V1'
    AND payload->>'operation_code'='ESCRITURA_BASE_CONOCIMIENTO_LF'
    AND payload->>'error_code'=code
  ORDER BY id DESC LIMIT 1;

  IF prior_writer_event.id IS NOT NULL THEN
    writer_receipt:=jsonb_build_object(
      'classification','REPLAY_EXISTING_WRITER_RECEIPT',
      'error_code',code,
      'ekb_id',prior_writer_event.payload->>'ekb_id',
      'event_id',prior_writer_event.id,
      'readback',prior_writer_event.payload
    );
  ELSE
    enriched:=p_finding||jsonb_build_object(
      'source_execution_id',p_parent_execution_id,
      'parent_operation_code',parent_row.operation_code,
      'ekb_child_execution_id',child_row.execution_id,
      'ekb_child_execution_operation','EJECUCION_SKILL_LF',
      'ekb_target_skill_code','ACT-0057',
      'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'finding_fingerprint',p_finding_fingerprint
    );
    writer_receipt:=public.lf_write_pipeline_ekb_v1(
      'ESCRITURA_BASE_CONOCIMIENTO_LF',enriched,child_row.execution_id
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'lot_code','EKB_CHILD_WRITE',
        'parent_execution_id',p_parent_execution_id,
        'router_action','SKILL_EXECUTION',
        'target_skill_code','ACT-0057',
        'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
        'finding_fingerprint',p_finding_fingerprint,
        'writer_receipt',writer_receipt,
        'readback_result','PASS'
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=child_row.execution_id
  WHERE execution_id=child_row.execution_id AND status='IN_PROGRESS';

  SELECT * INTO child_row FROM public.lf_operation_execution WHERE execution_id=child_row.execution_id;
  IF child_row.status<>'COMPLETED' THEN
    RAISE EXCEPTION 'S30_R19_EKB_CHILD_NOT_COMPLETED:%',child_row.status;
  END IF;

  RETURN jsonb_build_object(
    'result',case when reserve_receipt->>'result'='RESERVED_NEW_EXECUTION' then 'EKB_CHILD_DISPATCHED' else 'EKB_CHILD_REPLAYED' end,
    'parent_execution_id',p_parent_execution_id,
    'parent_operation_code',parent_row.operation_code,
    'router_asset_type','SKILL',
    'router_action_code','SKILL_EXECUTION',
    'child_execution_id',child_row.execution_id,
    'child_execution_operation',child_row.operation_code,
    'target_skill_code',child_row.target_code,
    'writer_authority_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
    'child_status',child_row.status,
    'idempotency_key',child_row.idempotency_key,
    'request_sha256',child_row.request_sha256,
    'finding_fingerprint',p_finding_fingerprint,
    'finding_payload_sha256',payload_sha,
    'reserve_receipt',reserve_receipt,
    'writer_receipt',writer_receipt
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_strategy_ekb_child_dispatch_v1(text,jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_strategy_ekb_child_dispatch_v1(text,jsonb,text) TO service_role;

DO $post$
DECLARE d text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
      AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
      AND allowed->>'ekb_child_execution_operation'='EJECUCION_SKILL_LF'
      AND allowed->>'ekb_child_target_asset'='ACT-0057'
      AND allowed->>'ekb_writer_authority_operation'='ESCRITURA_BASE_CONOCIMIENTO_LF'
  ) THEN RAISE EXCEPTION 'S30_A2R_FINAL_BINDING_NOT_MATERIALIZED'; END IF;

  SELECT pg_get_functiondef('public.lf_strategy_ekb_child_dispatch_v1(text,jsonb,text)'::regprocedure) INTO d;
  IF strpos(d,'EJECUCION_SKILL_LF')=0 OR strpos(d,'ACT-0057')=0 OR strpos(d,'ESCRITURA_BASE_CONOCIMIENTO_LF')=0 THEN
    RAISE EXCEPTION 'S30_A2R_CHILD_DISPATCH_SOURCE_INCOMPLETE';
  END IF;
  IF strpos(pg_get_functiondef('public.lf_write_pipeline_ekb_v1(text,jsonb,text)'::regprocedure),'CONTRACT-EJECUCION-ESTRATEGIA-LF-v1')>0 THEN
    RAISE EXCEPTION 'S30_A2R_DIRECT_STRATEGY_EKB_AUTHORITY_FORBIDDEN';
  END IF;
END
$post$;
