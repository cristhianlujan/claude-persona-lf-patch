DO $pre$ DECLARE v text; BEGIN SELECT max(version) INTO v FROM supabase_migrations.schema_migrations; IF v IS DISTINCT FROM '20260914063742' THEN RAISE EXCEPTION 'S30_STATE_WRITER_LEDGER_DRIFT:%',v; END IF; END $pre$;

CREATE OR REPLACE FUNCTION public.fn_lf_strategy_closed_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
BEGIN
  IF public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',OLD.lifecycle_state_code) THEN
    RAISE EXCEPTION 'LF_STRATEGY_TERMINAL_READ_ONLY:%:%',OLD.snapshot_code,OLD.lifecycle_state_code USING errcode='23514';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_update_write_v1(p_execution_id text,p_snapshot_id bigint,p_expected_revision_sha256 text,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public','extensions' AS $fn$
DECLARE x public.lf_operation_execution%rowtype; s public.lf_strategy_snapshots%rowtype; a public.lf_strategy_snapshots%rowtype; before_sha text; after_sha text; nowv timestamptz:=clock_timestamp(); old_progress_keys text[]; new_progress_keys text[]; patch_key text; new_metadata jsonb;
BEGIN
 IF btrim(coalesce(p_execution_id,''))='' OR p_snapshot_id IS NULL OR coalesce(p_expected_revision_sha256,'') !~ '^[0-9a-f]{64}$' OR p_patch IS NULL OR jsonb_typeof(p_patch)<>'object' THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_INPUT_INVALID'; END IF;
 FOR patch_key IN SELECT jsonb_object_keys(p_patch) LOOP IF patch_key NOT IN ('progress','metadata_merge','backlog','evidence_refs_append','change_log_append') THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_PATCH_KEY_NOT_ALLOWED:%',patch_key; END IF; END LOOP;
 IF jsonb_typeof(p_patch->'progress') IS DISTINCT FROM 'object' OR jsonb_typeof(coalesce(p_patch->'metadata_merge','{}'::jsonb)) IS DISTINCT FROM 'object' OR jsonb_typeof(p_patch->'backlog') IS DISTINCT FROM 'array' OR jsonb_typeof(p_patch->'evidence_refs_append') IS DISTINCT FROM 'array' OR jsonb_typeof(p_patch->'change_log_append') IS DISTINCT FROM 'array' OR jsonb_array_length(p_patch->'evidence_refs_append')=0 OR jsonb_array_length(p_patch->'change_log_append')=0 THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_PATCH_SHAPE_INVALID'; END IF;
 IF coalesce(p_patch->'metadata_merge','{}'::jsonb) ?| array['progress','strategy_close'] THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_PROTECTED_METADATA_KEY'; END IF;
 SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id; IF NOT FOUND OR x.operation_code<>'ACTUALIZACION_ESTRATEGIA_LF' OR x.status<>'IN_PROGRESS' OR x.target_type<>'STRATEGY' THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_EXECUTION_BINDING_MISMATCH'; END IF;
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id FOR UPDATE; IF NOT FOUND OR x.target_code<>s.snapshot_code OR x.target_path IS DISTINCT FROM format('supabase://public/lf_strategy_snapshots/%s',s.id) THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_TARGET_MISMATCH'; END IF;
 IF public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) OR coalesce(s.metadata->'strategy_close'->>'status','')='CLOSED' THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_TERMINAL_SNAPSHOT'; END IF;
 PERFORM public.lf_lifecycle_resolve_transition_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code,'UPDATE_STRATEGY');
 IF s.impact_policy NOT IN ('BLOQUEADO','NO_AUTOMATIC_PROMOTION') THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_IMPACT_POLICY_NOT_ALLOWED'; END IF;
 before_sha:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex'); IF before_sha<>p_expected_revision_sha256 THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_STALE_REVISION'; END IF;
 IF jsonb_typeof(s.metadata->'progress')<>'object' OR s.metadata->'progress'->>'contract_version'<>'STRATEGY_PROGRESS_CONTRACT_V1' THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_BASELINE_PROGRESS_CONTRACT_INVALID'; END IF;
 IF p_patch->'progress'->>'contract_version'<>'STRATEGY_PROGRESS_CONTRACT_V1' THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_PROGRESS_CONTRACT_INVALID'; END IF;
 SELECT array_agg(k ORDER BY k) INTO old_progress_keys FROM jsonb_object_keys(s.metadata->'progress') k; SELECT array_agg(k ORDER BY k) INTO new_progress_keys FROM jsonb_object_keys(p_patch->'progress') k; IF old_progress_keys IS DISTINCT FROM new_progress_keys THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_PROGRESS_KEYSET_MISMATCH'; END IF;
 IF p_patch->'progress'->>'strategy_id' IS DISTINCT FROM s.id::text OR p_patch->'progress'->>'strategy_code' IS DISTINCT FROM s.snapshot_code OR p_patch->'progress'->>'strategy_version' IS DISTINCT FROM s.version OR p_patch->'progress'->>'snapshot_status' IS DISTINCT FROM s.status OR p_patch->'progress'->>'runtime_state' IS DISTINCT FROM s.runtime_state OR p_patch->'progress'->>'impact_policy' IS DISTINCT FROM s.impact_policy OR p_patch->'progress'->>'claim_ceiling' IS DISTINCT FROM s.metadata->'progress'->>'claim_ceiling' THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_PROGRESS_IDENTITY_OR_CEILING_MISMATCH'; END IF;
 new_metadata:=(coalesce(s.metadata,'{}'::jsonb)||coalesce(p_patch->'metadata_merge','{}'::jsonb)); new_metadata:=jsonb_set(new_metadata,'{progress}',p_patch->'progress',true);
 UPDATE public.lf_strategy_snapshots SET metadata=new_metadata,backlog=p_patch->'backlog',evidence_refs=coalesce(evidence_refs,'[]'::jsonb)||p_patch->'evidence_refs_append',change_log=coalesce(change_log,'[]'::jsonb)||p_patch->'change_log_append',updated_at=nowv,updated_by_execution_id=p_execution_id WHERE id=s.id RETURNING * INTO a;
 IF a.lifecycle_state_code IS DISTINCT FROM s.lifecycle_state_code OR a.status IS DISTINCT FROM s.status OR a.visibility IS DISTINCT FROM s.visibility OR a.runtime_state IS DISTINCT FROM s.runtime_state OR a.impact_policy IS DISTINCT FROM s.impact_policy OR a.content_payload IS DISTINCT FROM s.content_payload OR a.risks IS DISTINCT FROM s.risks OR a.snapshot_code IS DISTINCT FROM s.snapshot_code OR a.version IS DISTINCT FROM s.version OR coalesce(a.metadata->'strategy_close','null'::jsonb) IS DISTINCT FROM coalesce(s.metadata->'strategy_close','null'::jsonb) THEN RAISE EXCEPTION 'LF_STRATEGY_UPDATE_POSTWRITE_INVARIANT'; END IF;
 after_sha:=encode(extensions.digest(to_jsonb(a)::text,'sha256'),'hex'); RETURN jsonb_build_object('result','STRATEGY_UPDATED_WITH_EVIDENCE','snapshot_id',a.id,'snapshot_code',a.snapshot_code,'before_revision_sha256',before_sha,'after_revision_sha256',after_sha,'progress_key_count',coalesce(array_length(new_progress_keys,1),0),'changed_paths',jsonb_build_array('metadata.progress','metadata.merge','backlog','evidence_refs.append','change_log.append','updated_at','updated_by_execution_id'),'status_runtime_impact_preserved',true);
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_close_write_v1(p_execution_id text,p_snapshot_id bigint,p_expected_revision_sha256 text,p_reason text,p_disposition text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public','extensions' AS $fn$
DECLARE x public.lf_operation_execution%rowtype; s public.lf_strategy_snapshots%rowtype; a public.lf_strategy_snapshots%rowtype; bh text; ah text; cl jsonb; nowv timestamptz:=clock_timestamp(); sw int; oc int; spec jsonb; target_state text;
BEGIN
 IF btrim(coalesce(p_execution_id,''))='' OR p_snapshot_id IS NULL OR p_expected_revision_sha256 !~ '^[0-9a-f]{64}$' OR btrim(coalesce(p_reason,''))='' OR p_disposition NOT IN ('TERMINAL_COMPLETE','TERMINAL_BLOCKED') OR jsonb_typeof(p_evidence)<>'object' THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_INPUT_INVALID'; END IF;
 SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=p_execution_id; IF NOT FOUND OR x.operation_code<>'CIERRE_ESTRATEGIA_LF' OR x.status<>'IN_PROGRESS' OR x.target_type<>'STRATEGY' THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_EXECUTION_BINDING_MISMATCH'; END IF;
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE id=p_snapshot_id FOR UPDATE; IF NOT FOUND OR x.target_code<>s.snapshot_code THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_TARGET_MISMATCH'; END IF;
 IF public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code) OR coalesce(s.metadata->'strategy_close'->>'status','')='CLOSED' THEN IF s.metadata->'strategy_close'->>'execution_id'=p_execution_id THEN RETURN jsonb_build_object('result','ALREADY_CLOSED_IDEMPOTENT','snapshot_id',s.id,'close_receipt',s.metadata->'strategy_close'); END IF; RAISE EXCEPTION 'LF_STRATEGY_CLOSE_ALREADY_TERMINAL'; END IF;
 spec:=public.lf_lifecycle_transition_spec_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code,'CLOSE_STRATEGY'); target_state:=spec->>'to_state_code';
 bh:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex'); IF bh<>p_expected_revision_sha256 THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_STALE_REVISION'; END IF;
 IF coalesce(p_evidence->>'safe_work_remaining_count','') !~ '^[0-9]+$' OR coalesce(p_evidence->>'open_executable_causal_chains','') !~ '^[0-9]+$' THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_ELIGIBILITY_COUNTS_REQUIRED'; END IF; sw:=(p_evidence->>'safe_work_remaining_count')::int; oc:=(p_evidence->>'open_executable_causal_chains')::int;
 IF sw<>0 OR oc<>0 OR coalesce((p_evidence->>'no_supersede_requested')::boolean,false) IS NOT TRUE OR jsonb_typeof(p_evidence->'backlog_disposition_map')<>'object' OR jsonb_typeof(p_evidence->'risk_disposition_map')<>'object' THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_NOT_ELIGIBLE'; END IF;
 IF p_evidence ? 'open_blockers' AND jsonb_typeof(p_evidence->'open_blockers')<>'array' THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_BLOCKERS_INVALID'; END IF; IF p_disposition='TERMINAL_COMPLETE' AND jsonb_array_length(coalesce(p_evidence->'open_blockers','[]'::jsonb))>0 THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_FALSE_COMPLETE'; END IF; IF p_disposition='TERMINAL_BLOCKED' AND jsonb_array_length(coalesce(p_evidence->'open_blockers','[]'::jsonb))=0 THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_BLOCKED_REQUIRES_BLOCKER'; END IF;
 cl:=jsonb_build_object('status','CLOSED','disposition',p_disposition,'reason_code',p_reason,'execution_id',p_execution_id,'closed_at',nowv,'safe_work_remaining_count',sw,'open_executable_causal_chains',oc,'open_blockers',coalesce(p_evidence->'open_blockers','[]'::jsonb),'backlog_disposition_map',p_evidence->'backlog_disposition_map','risk_disposition_map',p_evidence->'risk_disposition_map','baseline_revision_sha256',bh,'superseded',false);
 UPDATE public.lf_strategy_snapshots SET lifecycle_state_code=target_state,metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{strategy_close}',cl,true),evidence_refs=coalesce(evidence_refs,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('type','STRATEGY_CLOSE','execution_id',p_execution_id,'refs',coalesce(p_evidence->'evidence_refs','[]'::jsonb))),change_log=coalesce(change_log,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('change_type','STRATEGY_CLOSE','execution_id',p_execution_id,'closed_at',nowv,'reason_code',p_reason,'disposition',p_disposition,'superseded',false)),runtime_state='NO_HABILITADO',impact_policy='BLOQUEADO',visibility='READ_ONLY_INTERNAL',updated_at=nowv,updated_by_execution_id=p_execution_id WHERE id=s.id RETURNING * INTO a;
 ah:=encode(extensions.digest(to_jsonb(a)::text,'sha256'),'hex'); IF a.lifecycle_state_code<>target_state OR a.status IS DISTINCT FROM s.status OR a.archived_at IS DISTINCT FROM s.archived_at OR a.archived_reason IS DISTINCT FROM s.archived_reason OR a.runtime_state<>'NO_HABILITADO' OR a.impact_policy<>'BLOQUEADO' OR a.visibility<>'READ_ONLY_INTERNAL' THEN RAISE EXCEPTION 'LF_STRATEGY_CLOSE_POSTWRITE_INVARIANT'; END IF;
 RETURN jsonb_build_object('result','STRATEGY_CLOSED_WITH_EVIDENCE','snapshot_id',a.id,'snapshot_code',a.snapshot_code,'close_receipt',a.metadata->'strategy_close','before_revision_sha256',bh,'after_revision_sha256',ah,'changed_paths',jsonb_build_array('lifecycle_state_code','metadata.strategy_close','evidence_refs.append','change_log.append','runtime_state','impact_policy','visibility','updated_at','updated_by_execution_id'));
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_strategy_lifecycle_from_execution_step_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE x public.lf_operation_execution%rowtype; s public.lf_strategy_snapshots%rowtype; target_state text; gate_from timestamptz; rev text;
BEGIN
 IF NEW.step_id<>'strategy_resolve' OR NEW.status<>'PASS_CLEAN' THEN RETURN NEW; END IF;
 SELECT * INTO x FROM public.lf_operation_execution WHERE execution_id=NEW.execution_id; IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR x.target_type<>'STRATEGY' THEN RETURN NEW; END IF;
 SELECT * INTO s FROM public.lf_strategy_snapshots WHERE snapshot_code=x.target_code ORDER BY id DESC LIMIT 1 FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_TARGET_MISSING:%',x.target_code; END IF;
 gate_from:=public.lf_qualification_gate_effective_from_v1('STRATEGY');
 IF gate_from IS NOT NULL AND x.started_at>=gate_from THEN rev:=public.lf_strategy_revision_sha256_v1(s.id); IF NOT public.lf_qualification_current_v1('STRATEGY',s.snapshot_code,rev) THEN RAISE EXCEPTION 'LF_STRATEGY_EXECUTION_QUALIFICATION_REQUIRED:%:%',s.snapshot_code,rev; END IF; END IF;
 target_state:=public.lf_lifecycle_resolve_transition_v1('STRATEGY_LIFECYCLE',s.lifecycle_state_code,'START_EXECUTION');
 IF target_state IS DISTINCT FROM s.lifecycle_state_code THEN UPDATE public.lf_strategy_snapshots SET lifecycle_state_code=target_state,updated_at=clock_timestamp(),updated_by_execution_id=x.execution_id WHERE id=s.id; END IF;
 RETURN NEW;
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_promote_operation_v1(p_operation_code text,p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE r public.lf_operation_registry%rowtype; spec jsonb; target_state text; projected_status text; rev text;
BEGIN
 IF btrim(coalesce(p_operation_code,''))='' OR btrim(coalesce(p_execution_id,''))='' THEN RAISE EXCEPTION 'LF_OPERATION_PROMOTION_INPUT_INVALID'; END IF;
 SELECT * INTO r FROM public.lf_operation_registry WHERE operation_code=p_operation_code FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'LF_OPERATION_PROMOTION_TARGET_MISSING:%',p_operation_code; END IF;
 spec:=public.lf_lifecycle_transition_spec_v1('OPERATION_LIFECYCLE',r.lifecycle_state_code,'PROMOTE_OPERATION'); target_state:=spec->>'to_state_code'; rev:=public.lf_operation_revision_sha256_v1(p_operation_code);
 projected_status:=coalesce(spec->'condition_config'->'legacy_projection'->>'status',r.status);
 UPDATE public.lf_operation_registry SET lifecycle_state_code=target_state,status=projected_status,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id WHERE operation_code=p_operation_code;
 RETURN jsonb_build_object('result','OPERATION_PROMOTED','operation_code',p_operation_code,'to_state',target_state,'legacy_status',projected_status,'qualified_revision_sha256',rev);
END $fn$;

DO $router_patch$
DECLARE d text; old_create text; new_create text;
BEGIN
 SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO d;
 old_create:=$x$elsif v_type_hint='PERFIL' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_CREATE';$x$;
 new_create:=$x$elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then v_action:='STRATEGY_CREATE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then v_action:='STRATEGY_UPDATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_CREATE';$x$;
 IF strpos(d,old_create)=0 THEN RAISE EXCEPTION 'S30_ROUTER_STRATEGY_CREATE_UPDATE_PATCH_SOURCE_DRIFT'; END IF;
 EXECUTE replace(d,old_create,new_create);
END $router_patch$;

DO $post$ DECLARE v text; c int; BEGIN
 SELECT pg_get_functiondef('public.lf_strategy_update_write_v1(text,bigint,text,jsonb)'::regprocedure) INTO v; IF v LIKE '%''STRATEGY_PLANNED''%' OR v LIKE '%''STRATEGY_ACTIVE''%' OR v LIKE '%''STRATEGY_CLOSED''%' OR v LIKE '%''STRATEGY_SUPERSEDED''%' THEN RAISE EXCEPTION 'S30_POST_UPDATE_STATE_LITERAL_REMAINS'; END IF;
 SELECT pg_get_functiondef('public.lf_strategy_close_write_v1(text,bigint,text,text,text,jsonb)'::regprocedure) INTO v; IF v LIKE '%lifecycle_state_code=''STRATEGY_%' OR v LIKE '% IN (''STRATEGY_%' THEN RAISE EXCEPTION 'S30_POST_CLOSE_LIFECYCLE_LITERAL_REMAINS'; END IF;
 SELECT pg_get_functiondef('public.lf_strategy_lifecycle_from_execution_step_v1()'::regprocedure) INTO v; IF v LIKE '%''STRATEGY_PLANNED''%' OR v LIKE '%''STRATEGY_ACTIVE''%' OR v LIKE '%''STRATEGY_CLOSED''%' OR v LIKE '%''STRATEGY_SUPERSEDED''%' THEN RAISE EXCEPTION 'S30_POST_EXEC_STATE_LITERAL_REMAINS'; END IF;
 SELECT count(*) INTO c FROM pg_trigger t JOIN pg_class cl ON cl.oid=t.tgrelid JOIN pg_namespace n ON n.oid=cl.relnamespace WHERE n.nspname='public' AND cl.relname IN ('lf_operation_registry','lf_strategy_snapshots') AND t.tgname IN ('trg_lf_operation_registry_initial_lifecycle_v1','trg_lf_strategy_snapshots_initial_lifecycle_v1') AND NOT t.tgisinternal; IF c<>2 THEN RAISE EXCEPTION 'S30_POST_INITIAL_STATE_TRIGGER_COUNT:%',c; END IF;
END $post$;