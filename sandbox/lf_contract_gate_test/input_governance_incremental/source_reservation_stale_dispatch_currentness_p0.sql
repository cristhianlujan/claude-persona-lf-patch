-- P0 performance hardening: reuse source-stale/no-current proof inside one governed execution request.
-- Safety: ARC-015 remains authoritative whenever freshness is CURRENT or inconclusive.
-- This source-reservation is not a migration until the predecessor #441 lands and the exact bytes are applied to sandbox.

DO $migration$
DECLARE
  v_worker_def text;
  v_worker_sha text;
  v_worker_fast text;
  v_execute_def text;
  v_execute_sha text;
  v_verify text;
  v_old_currentness text := $$select id into v_current from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1;$$;
  v_new_currentness text := $$if p_no_current_proven is not true then raise exception 'INPUT_GOVERNANCE_KNOWN_NO_CURRENT_PROOF_REQUIRED'; end if; v_current:=null;$$;
  v_decl_old text := $$v_stage jsonb; v_prop jsonb; v_internal_summary jsonb; v_eval jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;$$;
  v_decl_new text := $$v_stage jsonb; v_prop jsonb; v_internal_summary jsonb; v_eval jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;
  v_latest_completed bigint; v_dispatch_fresh jsonb; v_dispatch_summary jsonb; v_dispatch_source_stale boolean:=false; v_dispatch_resolution_errors integer:=0;$$;
  v_select_old text := $$select id,family_count into v_run,v_family
  from programacion.input_readiness_runs r
  where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current_cached_v1(r.id)
  order by r.id desc limit 1;$$;
  v_select_new text := $$select id into v_latest_completed
  from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
  order by id desc limit 1;

  if v_latest_completed is not null then
    v_dispatch_fresh:=programacion.fn_input_freshness_delta(v_latest_completed);
    v_dispatch_summary:=v_dispatch_fresh->'summary';
    select count(*) into v_dispatch_resolution_errors
    from jsonb_array_elements(coalesce(v_dispatch_fresh->'source_changes','[]'::jsonb)) x(value)
    where x.value->>'state'='RESOLUTION_ERROR';
    v_dispatch_source_stale:=
      v_dispatch_fresh->>'run_state'='STALE'
      and coalesce((v_dispatch_summary->>'changed_source_count')::integer,0)>0
      and v_dispatch_resolution_errors=0;
  end if;

  if not v_dispatch_source_stale then
    select id,family_count into v_run,v_family
    from programacion.input_readiness_runs r
    where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null
      and programacion.fn_input_readiness_run_is_current_cached_v1(r.id)
    order by r.id desc limit 1;
  end if;$$;
BEGIN
  SELECT pg_get_functiondef('programacion.fn_input_governance_worker_spec(integer,text)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_governance_worker_spec(integer,text)'::regprocedure),'sha256'),'hex')
    INTO v_worker_def,v_worker_sha;
  IF v_worker_sha <> '4b12c066a6a94cbeda7065cdd578a7a5549fddda894b5ba2c7ae057150e5e73d' THEN
    RAISE EXCEPTION 'INPUT_WORKER_SPEC_BASELINE_SHA_MISMATCH:%',v_worker_sha;
  END IF;
  IF position(v_old_currentness in v_worker_def)=0 THEN RAISE EXCEPTION 'INPUT_WORKER_CURRENTNESS_ANCHOR_MISSING'; END IF;

  v_worker_fast:=replace(
    v_worker_def,
    $$fn_input_governance_worker_spec(p_pantalla_id integer, p_consumer text DEFAULT 'STORY_CREATOR'::text)$$,
    $$fn_input_governance_worker_spec_known_no_current_v1(p_pantalla_id integer, p_consumer text, p_no_current_proven boolean)$$
  );
  v_worker_fast:=replace(v_worker_fast,v_old_currentness,v_new_currentness);
  EXECUTE v_worker_fast;
  EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_worker_spec_known_no_current_v1(integer,text,boolean) FROM PUBLIC';
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_worker_spec_known_no_current_v1(integer,text,boolean) FROM anon'; END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_worker_spec_known_no_current_v1(integer,text,boolean) FROM authenticated'; END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_worker_spec_known_no_current_v1(integer,text,boolean) FROM service_role'; END IF;

  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'sha256'),'hex')
    INTO v_execute_def,v_execute_sha;
  IF v_execute_sha <> 'ad3dbd95c1e90002b72eac0179590a790205d0669bce97f469a088a344b4d1f1' THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_EXECUTE_BASELINE_SHA_MISMATCH:%',v_execute_sha;
  END IF;
  IF position(v_decl_old in v_execute_def)=0 THEN RAISE EXCEPTION 'INPUT_STALE_DISPATCH_DECL_ANCHOR_MISSING'; END IF;
  IF position(v_select_old in v_execute_def)=0 THEN RAISE EXCEPTION 'INPUT_STALE_DISPATCH_SELECT_ANCHOR_MISSING'; END IF;

  v_execute_def:=replace(v_execute_def,v_decl_old,v_decl_new);
  v_execute_def:=replace(v_execute_def,v_select_old,v_select_new);
  v_execute_def:=regexp_replace(
    v_execute_def,
    'v_worker:=programacion\\.fn_input_governance_worker_spec_known_current_v1\\(p_pantalla_id,p_consumer,v_run\\);',
    'v_worker:=programacion.fn_input_governance_worker_spec_known_no_current_v1(p_pantalla_id,p_consumer,true);'
  );
  EXECUTE v_execute_def;

  SELECT pg_get_functiondef('programacion.fn_input_governance_worker_spec_known_no_current_v1(integer,text,boolean)'::regprocedure) INTO v_verify;
  IF position('fn_input_readiness_run_is_current' in v_verify)>0 THEN RAISE EXCEPTION 'KNOWN_NO_CURRENT_WORKER_RECOMPUTES_CURRENTNESS'; END IF;
  IF position('p_no_current_proven is not true' in v_verify)=0 THEN RAISE EXCEPTION 'KNOWN_NO_CURRENT_WORKER_PROOF_GUARD_MISSING'; END IF;

  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure) INTO v_verify;
  IF position('v_dispatch_fresh:=programacion.fn_input_freshness_delta(v_latest_completed)' in v_verify)=0 THEN RAISE EXCEPTION 'STALE_DISPATCH_FRESHNESS_PREFLIGHT_MISSING'; END IF;
  IF position($needle$v_dispatch_fresh->>'run_state'='STALE'$needle$ in v_verify)=0 THEN RAISE EXCEPTION 'STALE_DISPATCH_STATE_GUARD_MISSING'; END IF;
  IF position('programacion.fn_input_readiness_run_is_current_cached_v1(r.id)' in v_verify)=0 THEN RAISE EXCEPTION 'ARC015_CURRENTNESS_FALLBACK_MISSING'; END IF;
  IF position('fn_input_governance_worker_spec_known_no_current_v1(p_pantalla_id,p_consumer,true)' in v_verify)=0 THEN RAISE EXCEPTION 'KNOWN_NO_CURRENT_WORKER_NOT_BOUND'; END IF;
END;
$migration$;
