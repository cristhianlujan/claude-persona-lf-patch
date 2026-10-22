-- IG M10.13 / ZERO_LEGACY_CALLERS: classify only five CURRENT callers
-- absent from the immutable M10.10 historical inventory 20193.
-- No runtime function change, DROP, REVOKE, Edge deploy or CP3 transition.
-- Source-first via official PASE -> LF Migration Merge Train.
BEGIN;
DO $m1013_cp3_current_overlay$
DECLARE
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.13';
  v_cp constant text := 'ZERO_LEGACY_CALLERS';
  v_old jsonb;
  v_overlay jsonb;
  v_query text;
  v_new jsonb;
  v_rows int;
  v_unclassified int;
  v_total int;
  v_row record;
  v_action jsonb;
  v_ready jsonb;
BEGIN
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=474)
        IS DISTINCT FROM 'IN_PROGRESS'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=474 AND checkpoint_code='GIT_RUNTIME_PARITY') IS DISTINCT FROM 'DONE'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=474 AND checkpoint_code=v_cp) IS DISTINCT FROM 'PENDING'
    OR NOT EXISTS(SELECT 1 FROM public.lf_eventos
                  WHERE id=20193 AND jsonb_array_length(payload->'matrix')=147)
  THEN RAISE EXCEPTION 'M1013_CP3_OVERLAY_PRESTATE_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=474
  AND disposition='ASSIGNED' FOR UPDATE;

  IF v_old ? 'cp3_current_caller_classifications_v1'
   OR v_old#>>'{cp3_exact_callers_cleanup_v1,scope}' IS DISTINCT FROM 'SOURCE_PACK_ONLY'
   OR jsonb_array_length(v_old#>'{source_pack_v1,checkpoint_inputs,ZERO_LEGACY_CALLERS,inputs,queries}')<>2
   OR v_old#>>'{source_pack_v1,checkpoint_inputs,ZERO_LEGACY_CALLERS,inputs,queries,1}'
      NOT LIKE '%OUTSIDE_CLASSIFIED_INVENTORY%'
  THEN RAISE EXCEPTION 'M1013_CP3_OVERLAY_SOURCEPACK_CHANGED'; END IF;

  -- Current source identity pinned per exact signature. Historical source
  -- freeze is not reclassified or rewritten.
  v_overlay:=jsonb_build_array(
    jsonb_build_object('signature',
      'programacion.fn_engineering_ig_validator_mismatch_probe_v1(integer)',
      'source_md5','fb8b4c1fe076277ca4779c275eb5f633',
      'current_class','TEST_HELPER','cleanup_action','RETAIN_TEST_HELPER'),
    jsonb_build_object('signature',
      'programacion.fn_engineering_ig_validator_mutation_campaign_v1(integer)',
      'source_md5','c3671ecca6dc81c4970e2ae8ce47970c',
      'current_class','TEST_HELPER','cleanup_action','RETAIN_TEST_HELPER'),
    jsonb_build_object('signature',
      'programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)',
      'source_md5','bbab65315c5953bc64e60a081d07ab2d',
      'current_class','TEST_HELPER','cleanup_action','RETAIN_TEST_HELPER'),
    jsonb_build_object('signature',
      'programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)',
      'source_md5','2eec94aaeafcd10ac38519d1ca0d53b0',
      'current_class','ACTIVE_VNEXT','cleanup_action','RETAIN_CURRENT'),
    jsonb_build_object('signature',
      'programacion.fn_t_remed_screen_status_v1(integer)',
      'source_md5','71e87f70953e741029d00d8aec0b6339',
      'current_class','ACTIVE_CROSS_WORKSTREAM','cleanup_action','RETAIN_DOWNSTREAM_CURRENT')
  );
  IF jsonb_array_length(v_overlay)<>5 THEN
    RAISE EXCEPTION 'M1013_CP3_WRONG_OVERLAY_CARDINALITY'; END IF;

  FOR v_row IN SELECT x FROM jsonb_array_elements(v_overlay) x LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(v_row.x->>'signature')
       AND md5(p.prosrc)=v_row.x->>'source_md5'
       AND p.prosrc ~ 'fn_input_governance_(semantic_probe_v|bootstrap_classify_v|field_reference_probe_v1)'
    ) THEN RAISE EXCEPTION 'M1013_CP3_CURRENT_SOURCE_DRIFT:%',v_row.x->>'signature'; END IF;
    IF EXISTS (
      SELECT 1 FROM public.lf_eventos e
      CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x
      WHERE e.id=20193
        AND split_part(x->>'item_identity','(',1)=split_part(v_row.x->>'signature','(',1)
    ) THEN RAISE EXCEPTION 'M1013_CP3_OVERLAY_COLLIDES_WITH_FROZEN_HISTORY:%',
      v_row.x->>'signature'; END IF;
  END LOOP;

  -- Check that the ONLY unclassified current caller signatures are these
  -- five. A sixth unknown, a missing helper, or an extra legacy reference
  -- stops the migration instead of silently approving it.
  WITH live AS(
    SELECT DISTINCT p.oid::regprocedure::text sig,
           n.nspname||'.'||p.proname caller
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    CROSS JOIN LATERAL regexp_matches(
      p.prosrc,
      '(fn_input_governance_(?:semantic_probe_v[123]|bootstrap_classify_v[12]|field_reference_probe_v1)(?:_cached_v[12])?)[[:space:]]*[(]','g') m
    WHERE n.nspname IN ('public','programacion','lf_ops')
  ), frozen AS (
    SELECT DISTINCT split_part(x->>'item_identity','(',1) caller
    FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x
    WHERE e.id=20193
  )
  SELECT COUNT(*),COUNT(*) FILTER(WHERE f.caller IS NULL)
    INTO v_total,v_unclassified
  FROM live l LEFT JOIN frozen f ON f.caller=l.caller;
  IF v_total<>21 OR v_unclassified<>5 THEN
    RAISE EXCEPTION 'M1013_CP3_UNEXPECTED_LIVE_GRAPH count=% outside_freeze=%',
      v_total,v_unclassified; END IF;

  v_query := $classified$
with live as (
 select n.nspname||'.'||p.proname caller,
        p.oid::regprocedure::text signature,
        md5(p.prosrc) source_md5,
        m[1] callee
 from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace
 cross join lateral regexp_matches(
   p.prosrc,
   '(fn_input_governance_(?:semantic_probe_v[123]|bootstrap_classify_v[12]|field_reference_probe_v1)(?:_cached_v[12])?)[[:space:]]*[(]','g'
 ) m
 where n.nspname in ('public','programacion','lf_ops')
), historical as (
 select distinct split_part(x->>'item_identity','(',1) caller,
        x->>'class' historical_class
 from public.lf_eventos e
 cross join lateral jsonb_array_elements(e.payload->'matrix') x
 where e.id=20193
), current_overlay as (
 select x->>'signature' signature, x->>'source_md5' source_md5,
        x->>'current_class' current_class,
        x->>'cleanup_action' cleanup_action
 from programacion.engineering_plan_units u
 cross join lateral jsonb_array_elements(
   u.unit_metadata->'cp3_current_caller_classifications_v1') x
 where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   and u.unit_code='M10.13'
)
select l.caller,l.signature,l.callee,
       coalesce(h.historical_class,o.current_class,'OUTSIDE_CLASSIFIED_INVENTORY') current_class,
       case
         when h.historical_class='ACTIVE_VNEXT' then 'RETAIN_CURRENT'
         when h.historical_class='STABLE_FACADE' then 'RETAIN_FACADE'
         when h.historical_class='LEGACY_REFERENCED' then 'REHOME_BEFORE_RETIRE'
         when h.historical_class='LEGACY_UNREFERENCED' then 'REVIEW_RETIREMENT_GOVERNANCE'
         when h.historical_class='SHADOW_TOOL' then 'RETAIN_NON_DECISIONAL'
         when h.historical_class='TEST_HELPER' then 'RETAIN_TEST_HELPER'
         when o.signature is not null then o.cleanup_action
         else 'REVIEW_NEW_CALLER'
       end cleanup_action,
       case when h.caller is not null then 'M10_10_FROZEN'
            when o.signature is not null then 'CURRENT_EXACT_SIGNATURE_AND_SOURCE'
            else 'UNCLASSIFIED_REVIEW_REQUIRED' end provenance
from live l
left join historical h on h.caller=l.caller
left join current_overlay o on o.signature=l.signature
                           and o.source_md5=l.source_md5
order by l.caller,l.callee
$classified$;

  v_new:=jsonb_set(v_old,
   '{source_pack_v1,checkpoint_inputs,ZERO_LEGACY_CALLERS,inputs,queries,1}',
   to_jsonb(v_query),false);
  v_new:=jsonb_set(v_new,'{cp3_current_caller_classifications_v1}',v_overlay,true);
  v_new:=jsonb_set(v_new,'{cp3_current_caller_classification_provenance_v1}',
    jsonb_build_object('scope','CURRENT_CALLERS_NOT_HISTORICAL_REWRITE',
      'm109_event_id',20161,'frozen_m1010_event_id',20193,
      'total_sql_callers',v_total,'new_callers_classified',v_unclassified,
      'cleanup_decision','NO_DELETION_WITHOUT_RETIREMENT_GOVERNANCE',
      'runtime_functions_changed',false,'checkpoint_closed',false),true);

  UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=474
     AND unit_metadata=v_old;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 THEN RAISE EXCEPTION 'M1013_CP3_OVERLAY_WRITE_DRIFT'; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp);
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,v_cp);
  IF v_action->>'status'<>'READY'
     OR v_action->>'action_kind'<>'READBACK_ONCE'
     OR jsonb_array_length(v_action->'verification_queries')<>2
     OR v_action->'verification_queries'->>1 IS DISTINCT FROM v_query
     OR v_ready->>'status'<>'READY'
     OR v_ready->>'execution_ready'<>'true'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=474 AND checkpoint_code=v_cp) <> 'PENDING'
  THEN RAISE EXCEPTION 'M1013_CP3_OVERLAY_COMPILED_CONTRACT_DRIFT'; END IF;
END
$m1013_cp3_current_overlay$;
COMMIT;
