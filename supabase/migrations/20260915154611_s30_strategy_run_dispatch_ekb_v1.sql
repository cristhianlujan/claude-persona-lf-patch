-- S30 R19: immediate owner dispatch + per-run EKB for EJECUCION_ESTRATEGIA_LF.
-- Reuse-first: no parallel runtime, no parallel backlog, no parallel EKB store.
-- Durable dispatch uses public.lf_backlog_errores_operativos.
-- EKB uses public.lf_write_pipeline_ekb_v1 with an idempotent Strategy wrapper.

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

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.lf_backlog_errores_operativos'::regclass
      AND conname='lf_backlog_errores_operativos_error_key_key'
  ) THEN RAISE EXCEPTION 'S30_R19_DISPATCH_CARRIER_IDEMPOTENCY_CONSTRAINT_MISSING'; END IF;
END
$pre$;

-- Bind PRE_EKB semantics inside the one canonical Strategy-executor contract.
-- We deliberately do NOT add a second ACTIVE operation contract because executor begin
-- requires exactly one ACTIVE_ENFORCEMENT contract.
UPDATE public.lf_operation_contracts
SET allowed = coalesce(allowed,'{}'::jsonb) || jsonb_build_object(
      'pre_ekb_gate_required',true,
      'pre_ekb_contract_code','CONTRACT-PRE-EKB-GATE-LF-v0.1',
      'ekb_writer','public.lf_write_pipeline_ekb_v1(text,jsonb,text)',
      'owner_dispatch_writer','public.lf_strategy_owner_work_dispatch_v1',
      'owner_dispatch_required_per_run',true,
      'ekb_incremental_checkpoint_required_per_run',true,
      'blocked_return_exit_hook_required',true
    ),
    blocked = coalesce(blocked,'[]'::jsonb) || '["OWNER_WORK_DISPATCH_BYPASS","EKB_INCREMENTAL_CHECKPOINT_BYPASS","CHAT_ONLY_OWNER_HANDOFF"]'::jsonb,
    required_after_write = coalesce(required_after_write,'[]'::jsonb) || '["OWNER_DISPATCH_RECEIPT","PER_RUN_EKB_RECEIPT"]'::jsonb,
    updated_by_execution_id='EXEC-S30-R19-AUTONOMOUS-20260915-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
  AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
  AND status='ACTIVE_ENFORCEMENT';

-- Extend the canonical EKB writer guard so the Strategy executor can bind PRE_EKB
-- without violating its single-active-contract invariant. Existing PRE_EKB consumers
-- keep their original standalone-contract path.
DO $patch_writer$
DECLARE
  f text;
  f2 text;
  before_sha text;
BEGIN
  SELECT pg_get_functiondef('public.lf_write_pipeline_ekb_v1(text,jsonb,text)'::regprocedure) INTO f;
  before_sha:=encode(extensions.digest(convert_to(f,'UTF8'),'sha256'),'hex');
  IF before_sha<>'ab007064d530ff88479add10411e8404c0de7107423bcc07f7db9251fef97b2a' THEN
    RAISE EXCEPTION 'S30_R19_EKB_WRITER_SOURCE_DRIFT:%',before_sha;
  END IF;

  f2:=replace(f,
$old$  if not exists (
    select 1
    from public.lf_operation_contracts c
    where c.operation_code=p_operation_code
      and c.contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      and c.status='ACTIVE_ENFORCEMENT'
      and coalesce((c.required_before_write->>'pre_ekb_gate_required')::boolean,false)
  ) then
    raise exception using errcode='42501', message=format('pipeline EKB writer operation is not governed by active PRE_EKB_GATE: %s',p_operation_code);
  end if;$old$,
$new$  if not exists (
    select 1
    from public.lf_operation_contracts c
    where c.operation_code=p_operation_code
      and c.status='ACTIVE_ENFORCEMENT'
      and (
        (
          c.contract_code='CONTRACT-PRE-EKB-GATE-LF-v0.1'
          and jsonb_typeof(c.required_before_write)='object'
          and coalesce((c.required_before_write->>'pre_ekb_gate_required')::boolean,false)
        )
        or
        (
          c.contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
          and coalesce((c.allowed->>'pre_ekb_gate_required')::boolean,false)
          and c.allowed->>'pre_ekb_contract_code'='CONTRACT-PRE-EKB-GATE-LF-v0.1'
        )
      )
  ) then
    raise exception using errcode='42501', message=format('pipeline EKB writer operation is not governed by active PRE_EKB_GATE: %s',p_operation_code);
  end if;$new$);

  IF f2=f OR strpos(f2,'CONTRACT-EJECUCION-ESTRATEGIA-LF-v1')=0 THEN
    RAISE EXCEPTION 'S30_R19_EKB_WRITER_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE f2;
END
$patch_writer$;

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

CREATE OR REPLACE FUNCTION public.lf_strategy_ekb_incremental_checkpoint_v1(
  p_execution_id text,
  p_findings jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  item jsonb;
  enriched jsonb;
  fp text;
  prior_event bigint;
  writer_receipt jsonb;
  receipts jsonb:='[]'::jsonb;
  dispositions jsonb:='[]'::jsonb;
  checkpoint_event bigint;
  v_count integer:=0;
BEGIN
  SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF'
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
      'durable_receipt_surface','lf_operation_execution_steps/ekb_incremental_checkpoint'
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
    PERFORM pg_advisory_xact_lock(hashtextextended('lf-strategy-ekb:'||p_execution_id||':'||fp,0));

    SELECT e.id INTO prior_event
    FROM public.lf_eventos e
    WHERE e.evento_tipo='REMEDIACION_GOBERNANZA'
      AND e.created_by_execution_id=p_execution_id
      AND e.payload->>'producer'='S30_STRATEGY_EKB_CHECKPOINT_V1'
      AND e.payload->>'finding_fingerprint'=fp
    ORDER BY e.id DESC LIMIT 1;

    IF prior_event IS NOT NULL THEN
      receipts:=receipts||jsonb_build_array(jsonb_build_object(
        'result','REPLAY_EXISTING_EKB_CHECKPOINT','finding_fingerprint',fp,'event_id',prior_event
      ));
      dispositions:=dispositions||jsonb_build_array(jsonb_build_object('finding_fingerprint',fp,'disposition','REPLAY'));
      CONTINUE;
    END IF;

    enriched:=item||jsonb_build_object('source_execution_id',p_execution_id);
    writer_receipt:=public.lf_write_pipeline_ekb_v1('EJECUCION_ESTRATEGIA_LF',enriched,p_execution_id);

    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
    ) VALUES (
      'REMEDIACION_GOBERNANZA','LF_STRATEGY_EKB_CHECKPOINT',coalesce(writer_receipt->>'error_code',item->>'codigo'),
      'Per-run idempotent Strategy EKB checkpoint receipt',
      case when upper(item->>'severidad')='CRITICAL' then 'CRITICAL' when upper(item->>'severidad')='HIGH' then 'WARN' else 'INFO' end,
      jsonb_build_object(
        'evidence_schema_version','operational-event/v2','execution_id',p_execution_id,
        'producer','S30_STRATEGY_EKB_CHECKPOINT_V1','purpose','Bind one enriched finding to one Strategy execution without retry double-counting',
        'occurred_at',clock_timestamp(),'acceptance_declared',false,'operation_code','EJECUCION_ESTRATEGIA_LF',
        'finding_fingerprint',fp,'source_step_id',item->>'source_step_id','affected_asset',item->>'affected_asset',
        'affected_operation',item->>'affected_operation','target_owner',coalesce(nullif(item->>'target_owner',''),'UNASSIGNED_OWNER'),
        'target_strategy_ref',item->>'target_strategy_ref','remediation_handoff_ref',item->>'remediation_handoff_ref',
        'writer_receipt',writer_receipt
      ),
      'S30_STRATEGY_EKB_CHECKPOINT_V1',p_execution_id
    ) RETURNING id INTO checkpoint_event;

    receipts:=receipts||jsonb_build_array(writer_receipt||jsonb_build_object('checkpoint_event_id',checkpoint_event,'finding_fingerprint',fp));
    dispositions:=dispositions||jsonb_build_array(jsonb_build_object('finding_fingerprint',fp,'disposition',writer_receipt->>'classification'));
    prior_event:=NULL;
  END LOOP;

  RETURN jsonb_build_object(
    'result','EKB_CHECKPOINTED','execution_id',p_execution_id,'finding_count',v_count,
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
SET search_path TO 'pg_catalog','public'
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
    'validacion','Read back the idempotent owner-dispatch row and Strategy EKB checkpoint receipt for the same execution/fingerprint.',
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
 'supabase/migrations/20260915142414_s30_strategy_run_dispatch_ekb_v1.sql',NULL,true,65,
 'EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-AUTONOMOUS-20260915-001'),
('EJECUCION_ESTRATEGIA_LF',105,'ekb_incremental_checkpoint',true,'ekb_run_receipt,finding_dispositions,no_findings_or_receipts',
 'supabase/migrations/20260915142414_s30_strategy_run_dispatch_ekb_v1.sql',NULL,true,105,
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
 'Persist or disposition enriched EKB findings in the same Strategy run after deterministic/semantic judging and before checkpoint.',
 '{}'::jsonb,'public.lf_strategy_ekb_incremental_checkpoint_v1',
 '["ekb_run_receipt","finding_dispositions","no_findings_or_receipts"]'::jsonb,
 '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true,"ekb_not_dispositioned":true}'::jsonb,
 'BLOCK_EXECUTOR_EKB_INCREMENTAL_CHECKPOINT','JUDGE-EJECUCION-ESTRATEGIA-LF-SOURCE-BOUNDARY-v1',
 '["ekb_run_receipt","finding_dispositions","no_findings_or_receipts"]'::jsonb,
 'checkpoint_progress','RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
 'R19 per-run EKB checkpoint. Uses canonical EKB writer; retry is idempotent by execution+finding_fingerprint.',NULL,'{}'::jsonb,
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
 '["ekb_run_receipt","finding_dispositions","no_findings_or_receipts"]'::jsonb,'ACTIVE_ENFORCEMENT',
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
  f text;
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
      AND allowed->>'pre_ekb_contract_code'='CONTRACT-PRE-EKB-GATE-LF-v0.1'
      AND coalesce((allowed->>'pre_ekb_gate_required')::boolean,false)
  ) THEN RAISE EXCEPTION 'S30_R19_PRE_EKB_BINDING_MISSING'; END IF;

  IF (SELECT next_if_pass FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='safe_work_discovery')<>'owner_work_dispatch' THEN
    RAISE EXCEPTION 'S30_R19_DISPATCH_SEQUENCE_NOT_WIRED';
  END IF;
  IF (SELECT next_if_pass FROM public.lf_operation_step_contracts WHERE operation_code='EJECUCION_ESTRATEGIA_LF' AND step_id='deterministic_and_semantic_judge')<>'ekb_incremental_checkpoint' THEN
    RAISE EXCEPTION 'S30_R19_EKB_SEQUENCE_NOT_WIRED';
  END IF;

  IF to_regprocedure('public.lf_strategy_owner_work_dispatch_v1(text,text,text,text,text,text,text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.lf_strategy_ekb_incremental_checkpoint_v1(text,jsonb)') IS NULL
     OR to_regprocedure('public.lf_strategy_ekb_on_block_return_or_exception_v1(text,text,text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'S30_R19_REQUIRED_FUNCTION_MISSING';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_lf_strategy_execution_step_exit_hook_v1' AND tgenabled<>'D')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_lf_strategy_execution_terminal_exit_hook_v1' AND tgenabled<>'D') THEN
    RAISE EXCEPTION 'S30_R19_EXIT_HOOK_TRIGGER_MISSING';
  END IF;

  SELECT pg_get_functiondef('public.lf_write_pipeline_ekb_v1(text,jsonb,text)'::regprocedure) INTO f;
  IF strpos(f,'CONTRACT-EJECUCION-ESTRATEGIA-LF-v1')=0 OR strpos(f,'pre_ekb_contract_code')=0 THEN
    RAISE EXCEPTION 'S30_R19_EKB_WRITER_BINDING_PATCH_MISSING';
  END IF;
END
$post$;
