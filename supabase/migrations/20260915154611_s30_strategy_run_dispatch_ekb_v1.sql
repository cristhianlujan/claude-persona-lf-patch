-- S30 R19: immediate owner dispatch + per-run EKB for Strategy execution.
-- A2R reconciliation: EKB writes remain governed by ESCRITURA_BASE_CONOCIMIENTO_LF.
-- Reuse-first: no parallel runtime, no parallel backlog, no parallel EKB store/writer.

DO $pre$
DECLARE
  c integer;
BEGIN
  SELECT count(*) INTO c FROM public.lf_operation_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
    AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
    AND status='ACTIVE_ENFORCEMENT';
  IF c<>1 THEN RAISE EXCEPTION 'S30_R19_STRATEGY_EXECUTOR_CONTRACT_NOT_EXACT:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_steps
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND active;
  IF c<>15 THEN RAISE EXCEPTION 'S30_R19_UNEXPECTED_PRE_STEP_COUNT:%',c; END IF;

  IF to_regprocedure('public.lf_write_pipeline_ekb_v1(text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'S30_R19_CANONICAL_EKB_WRITER_MISSING';
  END IF;
  IF to_regprocedure('public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'S30_R19_CANONICAL_EXECUTION_RESERVATION_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND lifecycle_state_code='OP_OPERATIONAL'
      AND status='APROBADO_PRODUCCION_CONTROLADA'
  ) THEN RAISE EXCEPTION 'S30_R19_KB_WRITE_OPERATION_NOT_OPERATIONAL'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
      AND coalesce((required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_R19_KB_WRITE_PRE_EKB_CONTRACT_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.lf_backlog_errores_operativos'::regclass
      AND conname='lf_backlog_errores_operativos_error_key_key'
  ) THEN RAISE EXCEPTION 'S30_R19_DISPATCH_CARRIER_IDEMPOTENCY_CONSTRAINT_MISSING'; END IF;
END
$pre$;

-- Keep the single Strategy-executor contract. It requires an EKB child-dispatch receipt,
-- but does NOT grant direct PRE_EKB writer authority to the Strategy operation.
UPDATE public.lf_operation_contracts
SET allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      'ekb_child_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'ekb_child_dispatch_required_per_run',true,
      'owner_dispatch_writer','public.lf_strategy_owner_work_dispatch_v1',
      'owner_dispatch_required_per_run',true,
      'ekb_incremental_checkpoint_required_per_run',true,
      'blocked_return_exit_hook_required',true
    ),
    blocked = coalesce(blocked,'[]'::jsonb) || '["OWNER_WORK_DISPATCH_BYPASS","EKB_CHILD_DISPATCH_BYPASS","EKB_INCREMENTAL_CHECKPOINT_BYPASS","CHAT_ONLY_OWNER_HANDOFF"]'::jsonb,
    required_after_write = coalesce(required_after_write,'[]'::jsonb) || '["OWNER_DISPATCH_RECEIPT","EKB_CHILD_EXECUTION_RECEIPT","PER_RUN_EKB_RECEIPT"]'::jsonb,
    updated_by_execution_id='EXEC-S30-R19-AUTONOMOUS-20260915-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
  AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
  AND status='ACTIVE_ENFORCEMENT';

CREATE OR REPLACE FUNCTION public.lf_strategy_owner_work_dispatch_v1(
  p_execution_id text,
  p_dispatch_key text,
  p_target_owner text,
  p_work_package_id text,
  p_target_strategy_ref text,
  p_description text,
  p_priority text DEFAULT 'ALTA',
  p_source_step_id text DEFAULT 'safe_work_discovery',
  p_affected_asset text DEFAULT NULL,
  p_affected_operation text DEFAULT NULL,
  p_finding_fingerprint text DEFAULT NULL,
  p_remediation_handoff_ref text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  r public.lf_backlog_errores_operativos%rowtype;
  v_owner text;
  v_priority text;
  v_meta jsonb;
BEGIN
  IF btrim(coalesce(p_execution_id,''))='' OR btrim(coalesce(p_dispatch_key,''))=''
     OR btrim(coalesce(p_work_package_id,''))='' OR btrim(coalesce(p_target_strategy_ref,''))=''
     OR btrim(coalesce(p_description,''))='' THEN
    RAISE EXCEPTION 'S30_R19_DISPATCH_REQUIRED_INPUT_MISSING';
  END IF;
  IF length(p_dispatch_key)>220 OR p_dispatch_key !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]+$' THEN
    RAISE EXCEPTION 'S30_R19_DISPATCH_KEY_INVALID:%',p_dispatch_key;
  END IF;

  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF'
     OR x.status NOT IN ('IN_PROGRESS','BLOCKED','FAILED') THEN
    RAISE EXCEPTION 'S30_R19_DISPATCH_EXECUTION_BINDING_INVALID:%',p_execution_id;
  END IF;

  v_owner:=upper(btrim(coalesce(nullif(p_target_owner,''),'UNASSIGNED_OWNER')));
  v_priority:=upper(btrim(coalesce(nullif(p_priority,''),'ALTA')));
  IF v_priority NOT IN ('BAJA','MEDIA','ALTA','CRITICA') THEN
    RAISE EXCEPTION 'S30_R19_DISPATCH_PRIORITY_INVALID:%',v_priority;
  END IF;

  v_meta:=jsonb_build_object(
    'dispatch_schema','LF_STRATEGY_OWNER_WORK_DISPATCH_V1',
    'source_execution_id',p_execution_id,
    'source_step_id',coalesce(nullif(btrim(p_source_step_id),''),'safe_work_discovery'),
    'target_owner',v_owner,
    'work_package_id',p_work_package_id,
    'target_strategy_ref',p_target_strategy_ref,
    'affected_asset',p_affected_asset,
    'affected_operation',p_affected_operation,
    'finding_fingerprint',p_finding_fingerprint,
    'remediation_handoff_ref',coalesce(nullif(btrim(p_remediation_handoff_ref),''),p_dispatch_key),
    'dispatch_disposition',case when v_owner='UNASSIGNED_OWNER' then 'UNASSIGNED_OWNER' else 'DISPATCHED_DURABLY' end,
    'chat_handoff_required',false
  );

  PERFORM pg_advisory_xact_lock(hashtextextended('lf-strategy-owner-dispatch:'||p_dispatch_key,0));
  SELECT * INTO r FROM public.lf_backlog_errores_operativos WHERE error_key=p_dispatch_key FOR UPDATE;
  IF FOUND THEN
    IF coalesce(r.metadata->>'source_execution_id','')<>p_execution_id
       OR coalesce(r.metadata->>'target_owner','')<>v_owner
       OR coalesce(r.metadata->>'work_package_id','')<>p_work_package_id
       OR coalesce(r.metadata->>'target_strategy_ref','')<>p_target_strategy_ref THEN
      RAISE EXCEPTION 'S30_R19_DISPATCH_IDEMPOTENCY_CONFLICT:%',p_dispatch_key;
    END IF;
    RETURN jsonb_build_object(
      'result','REPLAY_EXISTING_DISPATCH','dispatch_id',r.id,'dispatch_key',r.error_key,
      'target_owner',v_owner,'work_package_id',p_work_package_id,'state',r.estado,
      'readback',jsonb_build_object('metadata',r.metadata,'evidencia_ref',r.evidencia_ref)
    );
  END IF;

  INSERT INTO public.lf_backlog_errores_operativos(
    error_key,proyecto_codigo,frente_codigo,caso_codigo,tipo_error,categoria,estado,prioridad,
    activo_relacionado,descripcion,regla_no_regresion,fuente_origen,evidencia_ref,metadata,
    created_by_execution_id,updated_by_execution_id
  ) VALUES (
    p_dispatch_key,'LF',v_owner,p_work_package_id,'OWNER_WORK_DISPATCH','STRATEGY_EXECUTION_DISPATCH',
    'ABIERTA',v_priority,p_affected_asset,p_description,
    'Every discovered owner-bound work item must have one durable idempotent dispatch before downstream Strategy effects.',
    'EJECUCION_ESTRATEGIA_LF',
    coalesce(nullif(btrim(p_remediation_handoff_ref),''),'supabase://public/lf_operation_execution/'||p_execution_id),
    v_meta,p_execution_id,p_execution_id
  ) RETURNING * INTO r;

  RETURN jsonb_build_object(
    'result','DISPATCHED_NEW','dispatch_id',r.id,'dispatch_key',r.error_key,
    'target_owner',v_owner,'work_package_id',p_work_package_id,'state',r.estado,
    'readback',jsonb_build_object('metadata',r.metadata,'evidencia_ref',r.evidencia_ref)
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_strategy_owner_work_dispatch_v1(text,text,text,text,text,text,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_strategy_owner_work_dispatch_v1(text,text,text,text,text,text,text,text,text,text,text,text) TO service_role;

-- One canonical child-dispatch for EKB writes. Parent Strategy/Assurance execution is
-- lineage only; writer authority always comes from ESCRITURA_BASE_CONOCIMIENTO_LF.
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
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      AND status='ACTIVE_ENFORCEMENT'
      AND coalesce((required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_R19_EKB_CHILD_AUTHORITY_NOT_ACTIVE'; END IF;

  payload_sha:=encode(extensions.digest(convert_to(p_finding::text,'UTF8'),'sha256'),'hex');
  child_seed:=encode(extensions.digest(convert_to(p_parent_execution_id||'|'||p_finding_fingerprint,'UTF8'),'sha256'),'hex');
  child_execution_id:='EXEC-EKB-S30-'||upper(substr(child_seed,1,32));
  idem_key:='S30-EKB-WRITE:'||child_seed;
  request_sha:=encode(extensions.digest(convert_to(
    p_parent_execution_id||'|ESCRITURA_BASE_CONOCIMIENTO_LF|'||code||'|'||p_finding_fingerprint||'|'||payload_sha,
    'UTF8'),'sha256'),'hex');

  reserve_receipt:=public.fn_lf_operation_reserve_execution_v1(
    child_execution_id,
    'ESCRITURA_BASE_CONOCIMIENTO_LF',
    'EKB_FINDING',
    code,
    idem_key,
    request_sha,
    p_parent_execution_id,
    NULL,
    NULL,
    jsonb_build_object(
      'dispatch_schema','LF_STRATEGY_EKB_CHILD_DISPATCH_V1',
      'parent_execution_id',p_parent_execution_id,
      'parent_operation_code',parent_row.operation_code,
      'child_operation_code','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'finding_fingerprint',p_finding_fingerprint,
      'finding_payload_sha256',payload_sha,
      'error_code',code
    )
  );

  SELECT * INTO child_row FROM public.lf_operation_execution WHERE execution_id=reserve_receipt->>'execution_id';
  IF NOT FOUND OR child_row.operation_code<>'ESCRITURA_BASE_CONOCIMIENTO_LF'
     OR child_row.manifest->>'parent_execution_id'<>p_parent_execution_id
     OR child_row.manifest->>'finding_fingerprint'<>p_finding_fingerprint
     OR child_row.request_sha256<>request_sha THEN
    RAISE EXCEPTION 'S30_R19_EKB_CHILD_READBACK_MISMATCH';
  END IF;

  SELECT * INTO prior_writer_event
  FROM public.lf_eventos
  WHERE evento_tipo='REMEDIACION_GOBERNANZA'
    AND created_by_execution_id=child_row.execution_id
    AND origen='LF_PIPELINE_EKB_WRITER_V1'
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
        'finding_fingerprint',p_finding_fingerprint,
        'writer_receipt',writer_receipt,
        'readback_result','PASS'
      ),
      updated_at=clock_timestamp(),
      updated_by_execution_id=child_row.execution_id
  WHERE execution_id=child_row.execution_id
    AND status='IN_PROGRESS';

  SELECT * INTO child_row FROM public.lf_operation_execution WHERE execution_id=child_row.execution_id;
  IF child_row.status<>'COMPLETED' THEN
    RAISE EXCEPTION 'S30_R19_EKB_CHILD_NOT_COMPLETED:%',child_row.status;
  END IF;

  RETURN jsonb_build_object(
    'result',case when reserve_receipt->>'result'='RESERVED_NEW_EXECUTION' then 'EKB_CHILD_DISPATCHED' else 'EKB_CHILD_REPLAYED' end,
    'parent_execution_id',p_parent_execution_id,
    'parent_operation_code',parent_row.operation_code,
    'child_execution_id',child_row.execution_id,
    'child_operation_code',child_row.operation_code,
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

CREATE OR REPLACE FUNCTION public.lf_strategy_ekb_incremental_checkpoint_v1(
  p_execution_id text,
  p_findings jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  item jsonb;
  fp text;
  payload_sha text;
  prior_event public.lf_eventos%rowtype;
  child_receipt jsonb;
  receipts jsonb:='[]'::jsonb;
  dispositions jsonb:='[]'::jsonb;
  checkpoint_event bigint;
  v_count integer:=0;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code NOT IN ('EJECUCION_ESTRATEGIA_LF','ACTUALIZACION_ESTRATEGIA_LF')
     OR x.status NOT IN ('IN_PROGRESS','BLOCKED','FAILED') THEN
    RAISE EXCEPTION 'S30_R19_EKB_EXECUTION_BINDING_INVALID:%',p_execution_id;
  END IF;
  IF p_findings IS NULL OR jsonb_typeof(p_findings)<>'array' THEN
    RAISE EXCEPTION 'S30_R19_EKB_FINDINGS_MUST_BE_ARRAY';
  END IF;

  IF jsonb_array_length(p_findings)=0 THEN
    RETURN jsonb_build_object(
      'result','NO_FINDINGS','execution_id',p_execution_id,'finding_count',0,
      'finding_dispositions','[]'::jsonb,'receipts','[]'::jsonb,
      'child_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
      'durable_receipt_surface','lf_operation_execution/child+lf_eventos'
    );
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(p_findings) LOOP
    v_count:=v_count+1;
    IF jsonb_typeof(item)<>'object' THEN RAISE EXCEPTION 'S30_R19_EKB_FINDING_NOT_OBJECT'; END IF;
    IF NOT (item ?& array[
      'codigo','categoria','titulo','descripcion','causa_raiz','prevencion','validacion','severidad',
      'lifecycle_phase','consumer_role','root_cause_family','detectability','source_context','source_ref','evidencia',
      'source_step_id','affected_asset','affected_operation','target_owner','target_strategy_ref',
      'finding_fingerprint','remediation_handoff_ref'
    ]) THEN RAISE EXCEPTION 'S30_R19_EKB_ENRICHED_SHAPE_INCOMPLETE'; END IF;

    fp:=lower(btrim(coalesce(item->>'finding_fingerprint','')));
    IF fp !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'S30_R19_EKB_FINGERPRINT_INVALID:%',fp; END IF;
    payload_sha:=encode(extensions.digest(convert_to(item::text,'UTF8'),'sha256'),'hex');
    PERFORM pg_advisory_xact_lock(hashtextextended('lf-strategy-ekb:'||p_execution_id||':'||fp,0));

    SELECT * INTO prior_event
    FROM public.lf_eventos e
    WHERE e.evento_tipo='REMEDIACION_GOBERNANZA'
      AND e.created_by_execution_id=p_execution_id
      AND e.payload->>'producer'='S30_STRATEGY_EKB_CHECKPOINT_V2'
      AND e.payload->>'finding_fingerprint'=fp
    ORDER BY e.id DESC LIMIT 1;

    IF prior_event.id IS NOT NULL THEN
      IF prior_event.payload->>'finding_payload_sha256' IS DISTINCT FROM payload_sha THEN
        RAISE EXCEPTION 'S30_R19_EKB_RETRY_PAYLOAD_CONFLICT:%',fp;
      END IF;
      receipts:=receipts||jsonb_build_array(jsonb_build_object(
        'result','REPLAY_EXISTING_EKB_CHECKPOINT','finding_fingerprint',fp,
        'checkpoint_event_id',prior_event.id,
        'child_execution_id',prior_event.payload->>'child_execution_id'
      ));
      dispositions:=dispositions||jsonb_build_array(jsonb_build_object('finding_fingerprint',fp,'disposition','REPLAY'));
      CONTINUE;
    END IF;

    child_receipt:=public.lf_strategy_ekb_child_dispatch_v1(p_execution_id,item,fp);

    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) VALUES (
      'REMEDIACION_GOBERNANZA','LF_STRATEGY_EKB_CHECKPOINT',coalesce(child_receipt->'writer_receipt'->>'error_code',item->>'codigo'),
      'Per-run idempotent Strategy/Assurance EKB checkpoint receipt via governed KB child execution',
      case when upper(item->>'severidad')='CRITICAL' then 'CRITICAL' when upper(item->>'severidad')='HIGH' then 'WARN' else 'INFO' end,
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2','execution_id',p_execution_id,
        'producer','S30_STRATEGY_EKB_CHECKPOINT_V2',
        'purpose','Bind one enriched finding to one parent Strategy/Assurance execution and one governed ESCRITURA_BASE_CONOCIMIENTO_LF child execution',
        'occurred_at',clock_timestamp(),'acceptance_declared',false,
        'parent_operation_code',x.operation_code,
        'child_operation_code','ESCRITURA_BASE_CONOCIMIENTO_LF',
        'child_execution_id',child_receipt->>'child_execution_id',
        'finding_fingerprint',fp,'finding_payload_sha256',payload_sha,
        'source_step_id',item->>'source_step_id','affected_asset',item->>'affected_asset',
        'affected_operation',item->>'affected_operation','target_owner',coalesce(nullif(item->>'target_owner',''),'UNASSIGNED_OWNER'),
        'target_strategy_ref',item->>'target_strategy_ref','remediation_handoff_ref',item->>'remediation_handoff_ref',
        'child_receipt',child_receipt
      ),
      'S30_STRATEGY_EKB_CHECKPOINT_V2',p_execution_id
    ) RETURNING id INTO checkpoint_event;

    receipts:=receipts||jsonb_build_array(child_receipt||jsonb_build_object('checkpoint_event_id',checkpoint_event));
    dispositions:=dispositions||jsonb_build_array(jsonb_build_object(
      'finding_fingerprint',fp,
      'disposition',child_receipt->'writer_receipt'->>'classification',
      'child_execution_id',child_receipt->>'child_execution_id'
    ));
  END LOOP;

  RETURN jsonb_build_object(
    'result','EKB_CHECKPOINTED','execution_id',p_execution_id,'finding_count',v_count,
    'child_operation','ESCRITURA_BASE_CONOCIMIENTO_LF',
    'finding_dispositions',dispositions,'receipts',receipts
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_strategy_ekb_incremental_checkpoint_v1(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_strategy_ekb_incremental_checkpoint_v1(text,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.lf_strategy_ekb_on_block_return_or_exception_v1(
  p_execution_id text,
  p_source_step_id text,
  p_block_code text,
  p_message text,
  p_target_owner text DEFAULT NULL,
  p_work_package_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  v_owner text;
  v_wp text;
  v_code text;
  v_fp text;
  v_dispatch_key text;
  dispatch_receipt jsonb;
  ekb_receipt jsonb;
  finding jsonb;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' THEN
    RAISE EXCEPTION 'S30_R19_EXIT_HOOK_EXECUTION_INVALID:%',p_execution_id;
  END IF;
  v_owner:=upper(btrim(coalesce(nullif(p_target_owner,''),nullif(x.manifest->>'owner',''),'UNASSIGNED_OWNER')));
  v_wp:=coalesce(nullif(btrim(p_work_package_id),''),nullif(x.manifest->>'work_package_id',''),'UNASSIGNED_WORK_PACKAGE');
  v_code:=upper(btrim(coalesce(nullif(p_block_code,''),'STRATEGY_EXECUTION_UNCLASSIFIED_BLOCK')));
  v_fp:=encode(extensions.digest(convert_to(p_execution_id||'|'||v_code,'UTF8'),'sha256'),'hex');
  v_dispatch_key:='STRATEGY-EXIT-'||upper(substr(v_fp,1,24));

  dispatch_receipt:=public.lf_strategy_owner_work_dispatch_v1(
    p_execution_id,v_dispatch_key,v_owner,v_wp,x.target_code,
    coalesce(nullif(p_message,''),'Strategy execution produced a blocking, return or failed disposition.'),
    'ALTA',coalesce(nullif(p_source_step_id,''),'unknown_step'),x.target_code,x.operation_code,v_fp,
    'supabase://public/lf_operation_execution/'||p_execution_id
  );

  finding:=jsonb_build_object(
    'codigo','STRATEGY-EXECUTION-TERMINAL-DISPOSITION-001',
    'categoria','STRATEGY_EXECUTION','titulo','Strategy execution durable terminal disposition',
    'descripcion',coalesce(nullif(p_message,''),'Strategy execution produced a blocking, return or failed disposition.'),
    'causa_raiz','A Strategy execution reached a blocking/return/failure path requiring durable owner disposition.',
    'patron',v_code,
    'prevencion','Require owner dispatch and per-run EKB checkpoint before a blocked/failed Strategy run can be considered durably handled.',
    'validacion','Read back the idempotent owner-dispatch row plus governed KB child execution and EKB checkpoint receipt for the same execution/fingerprint.',
    'severidad','High','lifecycle_phase','EXECUTION',
    'consumer_role',jsonb_build_array('STRATEGY_EXECUTOR','GOVERNANCE'),
    'root_cause_family','R5_EROSION_PROCESO','detectability','LOUD_EARLY',
    'source_context','EJECUCION_ESTRATEGIA_LF_EXIT_HOOK','source_ref','supabase://public/lf_operation_execution/'||p_execution_id,
    'evidencia',coalesce(nullif(p_message,''),v_code),'source_step_id',coalesce(nullif(p_source_step_id,''),'unknown_step'),
    'affected_asset',x.target_code,'affected_operation',x.operation_code,'target_owner',v_owner,
    'target_strategy_ref',x.target_code,'finding_fingerprint',v_fp,'remediation_handoff_ref',v_dispatch_key
  );
  ekb_receipt:=public.lf_strategy_ekb_incremental_checkpoint_v1(p_execution_id,jsonb_build_array(finding));

  RETURN jsonb_build_object('result','EXIT_DISPOSITION_PERSISTED','dispatch_receipt',dispatch_receipt,'ekb_receipt',ekb_receipt,'finding_fingerprint',v_fp);
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_strategy_ekb_on_block_return_or_exception_v1(text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_strategy_ekb_on_block_return_or_exception_v1(text,text,text,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION private.fn_lf_strategy_execution_step_exit_hook_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $fn$
DECLARE
  op text;
  block_code text;
BEGIN
  IF NEW.status NOT IN ('BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER') THEN RETURN NEW; END IF;
  SELECT operation_code INTO op FROM public.lf_operation_execution WHERE execution_id=NEW.execution_id;
  IF op<>'EJECUCION_ESTRATEGIA_LF' THEN RETURN NEW; END IF;
  block_code:=coalesce(NEW.evidence_payload->'blocking_codes'->>0,NEW.status);
  PERFORM public.lf_strategy_ekb_on_block_return_or_exception_v1(
    NEW.execution_id,NEW.step_id,block_code,
    coalesce(NEW.evidence_payload->>'notes','Strategy execution step returned '||NEW.status),NULL,NULL
  );
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_lf_strategy_execution_step_exit_hook_v1 ON public.lf_operation_execution_steps;
CREATE TRIGGER trg_lf_strategy_execution_step_exit_hook_v1
AFTER INSERT OR UPDATE OF status ON public.lf_operation_execution_steps
FOR EACH ROW EXECUTE FUNCTION private.fn_lf_strategy_execution_step_exit_hook_v1();

CREATE OR REPLACE FUNCTION private.fn_lf_strategy_execution_terminal_exit_hook_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $fn$
DECLARE
  block_code text;
BEGIN
  IF OLD.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR OLD.status<>'IN_PROGRESS' OR NEW.status NOT IN ('BLOCKED','FAILED') THEN RETURN NEW; END IF;
  block_code:=coalesce(NEW.checkpoint_payload->>'blocking_code',NEW.manifest->>'blocking_code',NEW.status);
  PERFORM public.lf_strategy_ekb_on_block_return_or_exception_v1(
    NEW.execution_id,'execution_terminal_status',block_code,
    'Strategy execution terminal status transition: '||NEW.status,NULL,NULL
  );
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_lf_strategy_execution_terminal_exit_hook_v1 ON public.lf_operation_execution;
CREATE TRIGGER trg_lf_strategy_execution_terminal_exit_hook_v1
AFTER UPDATE OF status ON public.lf_operation_execution
FOR EACH ROW EXECUTE FUNCTION private.fn_lf_strategy_execution_terminal_exit_hook_v1();

-- Insert the two required stages, reusing the active executor mini-judge.
INSERT INTO public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,
  created_by_execution_id,updated_by_execution_id
) VALUES
('EJECUCION_ESTRATEGIA_LF',65,'owner_work_dispatch',true,'dispatch_receipts,owner_resolution_manifest,dispatch_idempotency_readback',
 'supabase/migrations/20260915154611_s30_strategy_run_dispatch_ekb_v1.sql',NULL,true,65,
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001'),
('EJECUCION_ESTRATEGIA_LF',105,'ekb_incremental_checkpoint',true,'ekb_run_receipt,ekb_child_execution_receipt,finding_dispositions,no_findings_or_receipts',
 'supabase/migrations/20260915154611_s30_strategy_run_dispatch_ekb_v1.sql',NULL,true,105,
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001');

INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,
  pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
  execution_sql,fail_condition,created_by_execution_id,updated_by_execution_id
) VALUES
('EJECUCION_ESTRATEGIA_LF','owner_work_dispatch',65,65,'CONTRACT-EJECUCION-ESTRATEGIA-LF-v1',
 'Durably dispatch every discovered owner-bound work item before downstream Strategy effects; unknown owner becomes UNASSIGNED_OWNER.',
 '{}'::jsonb,'public.lf_strategy_owner_work_dispatch_v1',
 '["dispatch_receipts","owner_resolution_manifest","dispatch_idempotency_readback"]'::jsonb,
 '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true,"chat_only_handoff":true}'::jsonb,
 'BLOCK_EXECUTOR_OWNER_WORK_DISPATCH','JUDGE-EJECUCION-ESTRATEGIA-LF-SOURCE-BOUNDARY-v1',
 '["dispatch_receipts","owner_resolution_manifest","dispatch_idempotency_readback"]'::jsonb,
 'pre_write_execution_binding_gate','RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
 'R19 durable idempotent owner dispatch. No chat-only handoff and no silent cross-asset creation.',NULL,'{}'::jsonb,
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001'),
('EJECUCION_ESTRATEGIA_LF','ekb_incremental_checkpoint',105,105,'CONTRACT-EJECUCION-ESTRATEGIA-LF-v1',
 'Persist or disposition enriched EKB findings through one idempotent governed ESCRITURA_BASE_CONOCIMIENTO_LF child execution before checkpoint.',
 '{}'::jsonb,'public.lf_strategy_ekb_incremental_checkpoint_v1',
 '["ekb_run_receipt","ekb_child_execution_receipt","finding_dispositions","no_findings_or_receipts"]'::jsonb,
 '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true,"ekb_not_dispositioned":true}'::jsonb,
 'BLOCK_EXECUTOR_EKB_INCREMENTAL_CHECKPOINT','JUDGE-EJECUCION-ESTRATEGIA-LF-SOURCE-BOUNDARY-v1',
 '["ekb_run_receipt","ekb_child_execution_receipt","finding_dispositions","no_findings_or_receipts"]'::jsonb,
 'checkpoint_progress','RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
 'R19 per-run EKB checkpoint. Writer authority is never granted directly to Strategy; child operation is ESCRITURA_BASE_CONOCIMIENTO_LF. Retry is idempotent by parent+finding fingerprint+payload SHA.',NULL,'{}'::jsonb,
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001');

INSERT INTO public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
) VALUES
('EJECUCION_ESTRATEGIA_LF',65,'owner_work_dispatch','JUDGE-EJECUCION-ESTRATEGIA-LF-SOURCE-BOUNDARY-v1',
 'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',
 '["dispatch_receipts","owner_resolution_manifest","dispatch_idempotency_readback"]'::jsonb,'ACTIVE_ENFORCEMENT',
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001'),
('EJECUCION_ESTRATEGIA_LF',105,'ekb_incremental_checkpoint','JUDGE-EJECUCION-ESTRATEGIA-LF-SOURCE-BOUNDARY-v1',
 'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',
 '["ekb_run_receipt","ekb_child_execution_receipt","finding_dispositions","no_findings_or_receipts"]'::jsonb,'ACTIVE_ENFORCEMENT',
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001');

UPDATE public.lf_operation_step_contracts
SET next_if_pass='owner_work_dispatch',updated_by_execution_id='EXEC-S30-R19-AUTONOMOUS-20260915-001',updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='safe_work_discovery' AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET next_if_pass='ekb_incremental_checkpoint',updated_by_execution_id='EXEC-S30-R19-AUTONOMOUS-20260915-001',updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='deterministic_and_semantic_judge' AND status='ACTIVE_ENFORCEMENT';

DO $post$
DECLARE
  c integer;
  writer_def text;
BEGIN
  SELECT count(*) INTO c FROM public.lf_operation_steps WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND active;
  IF c<>17 THEN RAISE EXCEPTION 'S30_R19_POST_STEP_COUNT_FAIL:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_contracts
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>1 THEN RAISE EXCEPTION 'S30_R19_SINGLE_ACTIVE_CONTRACT_REGRESSION:%',c; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
      AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
      AND allowed->>'ekb_child_operation'='ESCRITURA_BASE_CONOCIMIENTO_LF'
      AND coalesce((allowed->>'ekb_child_dispatch_required_per_run')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_R19_EKB_CHILD_BINDING_MISSING'; END IF;

  IF (SELECT next_if_pass FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='safe_work_discovery')<>'owner_work_dispatch' THEN
    RAISE EXCEPTION 'S30_R19_DISPATCH_SEQUENCE_NOT_WIRED';
  END IF;
  IF (SELECT next_if_pass FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='deterministic_and_semantic_judge')<>'ekb_incremental_checkpoint' THEN
    RAISE EXCEPTION 'S30_R19_EKB_SEQUENCE_NOT_WIRED';
  END IF;

  IF to_regprocedure('public.lf_strategy_owner_work_dispatch_v1(text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.lf_strategy_ekb_child_dispatch_v1(text,jsonb,text)') IS NULL
     OR to_regprocedure('public.lf_strategy_ekb_incremental_checkpoint_v1(text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_strategy_ekb_on_block_return_or_exception_v1(text,text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'S30_R19_REQUIRED_FUNCTION_MISSING';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_lf_strategy_execution_step_exit_hook_v1' AND tgenabled<>'D')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_lf_strategy_execution_terminal_exit_hook_v1' AND tgenabled<>'D') THEN
    RAISE EXCEPTION 'S30_R19_EXIT_HOOK_TRIGGER_MISSING';
  END IF;

  SELECT pg_get_functiondef('public.lf_write_pipeline_ekb_v1(text,jsonb,text)'::regprocedure) INTO writer_def;
  IF strpos(writer_def,'CONTRACT-EJECUCION-ESTRATEGIA-LF-v1')>0 THEN
    RAISE EXCEPTION 'S30_R19_DIRECT_STRATEGY_EKB_AUTHORITY_FORBIDDEN';
  END IF;
END
$post$;
