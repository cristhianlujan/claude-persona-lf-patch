-- IG M10.13 CP3: clean stale, broad *inventory queries only*.
-- No function DROP/CREATE/REPLACE, ACL or runtime changes; CP3 remains PENDING.
-- M10.9 event 20161 and M10.10 event 20193 remain historical anchors.
BEGIN;
DO $cp3_inventory_cleanup$
DECLARE
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.13';
  v_item constant bigint := 474;
  v_old jsonb;
  v_new jsonb;
  v_old_meta jsonb;
  v_after jsonb;
  v_action jsonb;
  v_ready jsonb;
  v_count int;
  v_n int;
  v_query1 text;
  v_query2 text;
BEGIN
  -- Scope and live prestate: never mutate an already-closed checkpoint.
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_item)
      IS DISTINCT FROM 'IN_PROGRESS'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_item AND checkpoint_code='GIT_RUNTIME_PARITY')
      IS DISTINCT FROM 'DONE'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_item AND checkpoint_code='ZERO_LEGACY_CALLERS')
      IS DISTINCT FROM 'PENDING'
    OR NOT EXISTS (SELECT 1 FROM public.lf_eventos WHERE id=20193
                   AND jsonb_array_length(payload->'matrix')=147)
  THEN RAISE EXCEPTION 'M1013_CP3_INVENTORY_PRESTATE_DRIFT'; END IF;

  SELECT u.unit_metadata, u.unit_metadata#>'{source_pack_v1,checkpoint_inputs,ZERO_LEGACY_CALLERS,inputs,queries}'
  INTO STRICT v_old_meta,v_old
  FROM programacion.engineering_plan_units u
  WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND u.work_item_id=v_item
    AND u.disposition='ASSIGNED'
  FOR UPDATE;

  IF jsonb_typeof(v_old) <> 'array' OR jsonb_array_length(v_old) <> 2
    OR (v_old->>0) NOT LIKE '%left join lateral regexp_matches%'
    OR (v_old->>1) NOT LIKE '%fn_input_readiness_%'
    OR v_old_meta ? 'cp3_exact_callers_cleanup_v1'
  THEN RAISE EXCEPTION 'M1013_CP3_SOURCE_PACK_UNEXPECTED'; END IF;

  -- The original WHERE matched any prosrc containing a broad token and could
  -- create rows with null callees. Enumerate *only actual invocation matches*.
  v_query1 := $read_exact$
select n.nspname||'.'||p.proname caller,
       string_agg(distinct m[1],', ') callees
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
cross join lateral regexp_matches(
  p.prosrc,
  '(fn_input_governance_(?:semantic_probe_v[123]|bootstrap_classify_v[12]|field_reference_probe_v1)(?:_cached_v[12])?)[[:space:]]*[(]',
  'g'
) m
where n.nspname in ('public','programacion','lf_ops')
group by n.nspname,p.proname
order by 1
$read_exact$;

  -- Full, non-destructive liveness report. Never infer retirement from v1 in
  -- the name: classes come from the frozen M10.10 registry, and new callers
  -- not covered by its 2026-10-04 snapshot remain REVIEW_NEW_CALLER.
  v_query2 := $read_classified$
with live as (
  select n.nspname||'.'||p.proname caller,
         p.oid::regprocedure::text signature,
         m[1] callee
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  cross join lateral regexp_matches(
    p.prosrc,
    '(fn_input_governance_(?:semantic_probe_v[123]|bootstrap_classify_v[12]|field_reference_probe_v1)(?:_cached_v[12])?)[[:space:]]*[(]',
    'g'
  ) m
  where n.nspname in ('public','programacion','lf_ops')
), historical as (
  select split_part(x->>'item_identity','(',1) caller,
         x->>'class' historical_class
  from public.lf_eventos e
  cross join lateral jsonb_array_elements(e.payload->'matrix') x
  where e.id=20193
)
select l.caller,l.signature,l.callee,
       coalesce(h.historical_class,'OUTSIDE_CLASSIFIED_INVENTORY') historical_class,
       case
         when h.historical_class='ACTIVE_VNEXT' then 'RETAIN_CURRENT'
         when h.historical_class='STABLE_FACADE' then 'RETAIN_FACADE'
         when h.historical_class='LEGACY_REFERENCED' then 'REHOME_BEFORE_RETIRE'
         when h.historical_class='LEGACY_UNREFERENCED' then 'REVIEW_RETIREMENT_GOVERNANCE'
         when h.historical_class='SHADOW_TOOL' then 'RETAIN_NON_DECISIONAL'
         when h.historical_class='TEST_HELPER' then 'RETAIN_TEST_HELPER'
         else 'REVIEW_NEW_CALLER'
       end cleanup_action
from live l
left join historical h on h.caller=l.caller
order by l.caller,l.callee
$read_classified$;

  -- Current live population has 21 genuine caller functions, not 21 legacy
  -- deletion targets. Exact first-query semantics verified at apply time.
  select count(distinct p.oid) into v_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join lateral regexp_matches(
    p.prosrc,
    '(fn_input_governance_(?:semantic_probe_v[123]|bootstrap_classify_v[12]|field_reference_probe_v1)(?:_cached_v[12])?)[[:space:]]*[(]',
    'g'
  ) m
  where n.nspname in ('public','programacion','lf_ops');
  IF v_count <> 21 THEN
    RAISE EXCEPTION 'M1013_CP3_LIVE_CALLER_GRAPH_CHANGED:%',v_count;
  END IF;

  v_new := jsonb_build_array(v_query1,v_query2);
  UPDATE programacion.engineering_plan_units
  SET unit_metadata = jsonb_set(
    jsonb_set(unit_metadata,
      '{source_pack_v1,checkpoint_inputs,ZERO_LEGACY_CALLERS,inputs,queries}',
      v_new,true
    ),'{cp3_exact_callers_cleanup_v1}',
    jsonb_build_object(
      'scope','SOURCE_PACK_ONLY',
      'prior_queries_sha256',programacion.fn_v09_sha256_jsonb(v_old),
      'm109_inventory_event_id',20161,
      'm1010_classification_event_id',20193,
      'observed_sql_callers',v_count,
      'classification','RETAIN_OR_REHOME_OR_REVIEW_NOT_AUTO_REMOVE',
      'remove_ready_claim',false,
      'production_activation',false,
      'checkpoint_terminal',false
    ),true
  )
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_item
    AND disposition='ASSIGNED';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n<>1 THEN RAISE EXCEPTION 'M1013_CP3_SOURCE_PACK_WRITE_NOT_UNIQUE'; END IF;

  SELECT unit_metadata#>'{source_pack_v1,checkpoint_inputs,ZERO_LEGACY_CALLERS,inputs,queries}'
  INTO STRICT v_after
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit;
  IF v_after IS DISTINCT FROM v_new
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_item AND checkpoint_code='ZERO_LEGACY_CALLERS')
        IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'M1013_CP3_INVENTORY_CLEANUP_READBACK_FAIL'; END IF;

  v_action:=programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,'ZERO_LEGACY_CALLERS');
  v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,'ZERO_LEGACY_CALLERS');
  IF v_action->>'status' IS DISTINCT FROM 'READY'
    OR v_action->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
    OR v_ready->>'status' IS DISTINCT FROM 'READY'
    OR v_ready->>'execution_ready' IS DISTINCT FROM 'true'
    OR jsonb_array_length(v_action->'verification_queries') <> 2
  THEN RAISE EXCEPTION 'M1013_CP3_READONLY_COMPILED_CONTRACT_DRIFT'; END IF;
END
$cp3_inventory_cleanup$;
COMMIT;
