DO $pre$ DECLARE v text; op text; rev text; qstate text; BEGIN
 SELECT max(version) INTO v FROM supabase_migrations.schema_migrations; IF v IS DISTINCT FROM '20260914064618' THEN RAISE EXCEPTION 'S30_QUAL_GATE_LEDGER_DRIFT:%',v; END IF;
 qstate:=public.lf_lifecycle_action_target_state_v1('QUALIFICATION_LIFECYCLE','PASS_QUALIFICATION');
 FOREACH op IN ARRAY ARRAY['CREACION_ESTRATEGIA_LF','ACTUALIZACION_ESTRATEGIA_LF','EJECUCION_ESTRATEGIA_LF','CIERRE_ESTRATEGIA_LF'] LOOP
   rev:=public.lf_operation_revision_sha256_v1(op);
   IF NOT EXISTS(SELECT 1 FROM public.lf_qualification_receipts q WHERE q.subject_type='OPERATION' AND q.subject_code=op AND q.revision_sha256=rev AND q.lifecycle_state_code=qstate AND q.invalidated_at IS NULL) THEN
     RAISE EXCEPTION 'S30_OPERATION_QUALIFICATION_MISSING:%:%',op,rev;
   END IF;
 END LOOP;
END $pre$;

DO $activate$ DECLARE gate_at timestamptz:=clock_timestamp(); BEGIN
 UPDATE public.lf_test_requirement_bindings
 SET status='ACTIVE',effective_from=gate_at,updated_at=gate_at,updated_by_execution_id='EXEC-S30-STRATEGY-QUALIFICATION-FRAMEWORK-20260914-001'
 WHERE binding_code LIKE 'BIND-OP-STRATEGY-%-V1' OR binding_code LIKE 'BIND-STRATEGY-%-V1';

 UPDATE lf_ops.estados_transiciones
 SET condition_config=condition_config || jsonb_build_object(
       'requires_qualification',true,
       'qualification_scope','OPERATION',
       'exact_revision',true,
       'legacy_projection',jsonb_build_object('status','PRODUCCION_CONTROLADA')
     ),updated_at=gate_at
 WHERE entity_type='OPERATION_LIFECYCLE' AND action_code='PROMOTE_OPERATION' AND status='VIGENTE';

 UPDATE lf_ops.estados_transiciones
 SET condition_config=condition_config || jsonb_build_object(
       'requires_qualification',true,
       'qualification_scope','STRATEGY',
       'exact_revision',true
     ),updated_at=gate_at
 WHERE entity_type='STRATEGY_LIFECYCLE' AND action_code='START_EXECUTION' AND status='VIGENTE';
END $activate$;

DO $router_gate$
DECLARE d text; needle text; replacement text;
BEGIN
 SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO d;
 needle:=$x$if v_operation.applies_to_asset_type is not null and v_operation.applies_to_asset_type<>v_type_hint then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_ASSET_TYPE_MISMATCH','router','ACT-0001','asset_type',v_type_hint,'operation_code',v_operation.operation_code,'applies_to_asset_type',v_operation.applies_to_asset_type); end if;$x$;
 replacement:=needle||$x$

  if exists (
    select 1 from public.lf_test_requirement_bindings b
    where b.subject_type='OPERATION' and b.subject_code=v_operation.operation_code
      and b.status='ACTIVE' and b.required and b.effective_from<=clock_timestamp()
  ) then
    if v_operation.lifecycle_state_code is distinct from public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION') then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_OPERATIONAL','router','ACT-0001','operation_code',v_operation.operation_code,'operation_lifecycle_state',v_operation.lifecycle_state_code);
    end if;
    if not public.lf_qualification_current_v1('OPERATION',v_operation.operation_code,public.lf_operation_revision_sha256_v1(v_operation.operation_code)) then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_QUALIFICATION_REQUIRED','router','ACT-0001','operation_code',v_operation.operation_code,'operation_revision_sha256',public.lf_operation_revision_sha256_v1(v_operation.operation_code));
    end if;
  end if;$x$;
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'S30_ROUTER_QUAL_GATE_SOURCE_DRIFT'; END IF;
 EXECUTE replace(d,needle,replacement);
END $router_gate$;

DO $promote$
DECLARE r jsonb;
BEGIN
 r:=public.lf_promote_operation_v1('CREACION_ESTRATEGIA_LF','EXEC-S30-CREATE-STRATEGY-QUAL-HARDEN-20260914-001');
 IF r->>'to_state' IS DISTINCT FROM public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION') THEN RAISE EXCEPTION 'S30_CREATE_PROMOTION_FAIL:%',r; END IF;
 r:=public.lf_promote_operation_v1('CIERRE_ESTRATEGIA_LF','EXEC-S30-CLOSE-STRATEGY-PROMOTE-20260914-001');
 IF r->>'to_state' IS DISTINCT FROM public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION') THEN RAISE EXCEPTION 'S30_CLOSE_PROMOTION_FAIL:%',r; END IF;
END $promote$;

UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=execution_id,manifest=manifest||jsonb_build_object('result','QUALIFICATION_CONTRACT_HARDENED_AND_OPERATION_PROMOTED') WHERE execution_id='EXEC-S30-CREATE-STRATEGY-QUAL-HARDEN-20260914-001';
UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=execution_id,manifest=manifest||jsonb_build_object('result','QUALIFICATION_CONTRACT_HARDENED') WHERE execution_id='EXEC-S30-UPDATE-STRATEGY-QUAL-HARDEN-20260914-001';
UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=execution_id,manifest=manifest||jsonb_build_object('result','QUALIFICATION_CONTRACT_HARDENED') WHERE execution_id='EXEC-S30-EXEC-STRATEGY-QUAL-HARDEN-20260914-001';
UPDATE public.lf_operation_execution SET status='COMPLETED',completed_at=clock_timestamp(),updated_at=clock_timestamp(),updated_by_execution_id=execution_id,manifest=manifest||jsonb_build_object('result','QUALIFIED_OPERATION_PROMOTED') WHERE execution_id='EXEC-S30-CLOSE-STRATEGY-PROMOTE-20260914-001';

DO $post$ DECLARE op text; rev text; target_op text; v jsonb; c int; BEGIN
 target_op:=public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION');
 FOREACH op IN ARRAY ARRAY['CREACION_ESTRATEGIA_LF','ACTUALIZACION_ESTRATEGIA_LF','EJECUCION_ESTRATEGIA_LF','CIERRE_ESTRATEGIA_LF'] LOOP
   rev:=public.lf_operation_revision_sha256_v1(op);
   IF NOT public.lf_qualification_current_v1('OPERATION',op,rev) THEN RAISE EXCEPTION 'S30_POST_OPERATION_QUAL_NOT_CURRENT:%:%',op,rev; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry WHERE operation_code=op AND lifecycle_state_code=target_op) THEN RAISE EXCEPTION 'S30_POST_OPERATION_NOT_OPERATIONAL:%',op; END IF;
 END LOOP;
 SELECT count(*) INTO c FROM public.lf_test_requirement_bindings WHERE status='ACTIVE' AND (binding_code LIKE 'BIND-OP-STRATEGY-%-V1' OR binding_code LIKE 'BIND-STRATEGY-%-V1'); IF c<>13 THEN RAISE EXCEPTION 'S30_POST_ACTIVE_BINDING_COUNT:%',c; END IF;
 v:=public.lf_router_resolve_v1('crear estrategia',NULL,NULL,'STRATEGY','ROUTER'); IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'CREACION_ESTRATEGIA_LF' THEN RAISE EXCEPTION 'S30_POST_CREATE_ROUTER_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('actualizar estrategia',NULL,NULL,'STRATEGY','ROUTER'); IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'ACTUALIZACION_ESTRATEGIA_LF' THEN RAISE EXCEPTION 'S30_POST_UPDATE_ROUTER_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('ejecutar estrategia',NULL,'STRATEGY_EXECUTION','STRATEGY','ROUTER'); IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'EJECUCION_ESTRATEGIA_LF' THEN RAISE EXCEPTION 'S30_POST_EXEC_ROUTER_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('cerrar estrategia',NULL,NULL,'STRATEGY','ROUTER'); IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'CIERRE_ESTRATEGIA_LF' THEN RAISE EXCEPTION 'S30_POST_CLOSE_ROUTER_FAIL:%',v; END IF;
END $post$;