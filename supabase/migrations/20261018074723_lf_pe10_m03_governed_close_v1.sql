-- PE10/M03: source-first, exact-version, independently executed method checkpoint.
-- Scope: ONE checkpoint administrative close only. M01/M02 remain PENDING.
-- No domain/runtime/data-plane changes; no grants; no activation of candidate global close operation.
-- This updates common checkpoint functions ONLY to support an explicit, source-bound
-- INDEPENDENT_METHOD_VARIANTS mode. All other plans keep their former sequencing.
-- Immutable RAW pinned to Git blob c6cb821d7e6917a66c0bd657bac1e2ad1b24dab8.
CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_assertion_record_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_result jsonb, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_work_item_id bigint;
  v_checkpoint_id bigint;
  v_current_code text;
  v_spec jsonb;
  v_contract jsonb;
  v_contract_sha text;
  v_mode text;
  v_pass boolean := false;
  v_pass_when jsonb;
  v_result_sha text;
  v_evidence_ref text;
  v_recorded_at timestamptz := clock_timestamp();
  v_receipt jsonb;
  v_receipt_sha text;
  v_observed jsonb;
  v_semantic_ok boolean := true;
  v_fields_ok boolean := true;
  v_nonempty_ok boolean := true;
begin
  if jsonb_typeof(p_result)<>'object' then
    raise exception 'ENGINEERING_ASSERTION_RESULT_OBJECT_REQUIRED:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select pu.work_item_id
    into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'ENGINEERING_ASSERTION_UNIT_NOT_FOUND:%/%',p_plan_code,p_unit_code;
  end if;

  select c.id
    into v_checkpoint_id
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.checkpoint_code=p_checkpoint_code
  for update;

  if v_checkpoint_id is null then
    raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_FOUND:%/%/%',
      p_plan_code,p_unit_code,p_checkpoint_code;
  end if;

  select c.checkpoint_code
    into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  -- Explicit independent-method mode; all other engineering units still
  -- enforce the original linear checkpoint guard without any change.
  IF v_current_code IS DISTINCT FROM p_checkpoint_code
    AND NOT EXISTS (
      SELECT 1 FROM programacion.engineering_plan_units pu
      WHERE pu.work_item_id=v_work_item_id
        AND pu.plan_code=p_plan_code AND pu.unit_code=p_unit_code
        AND pu.disposition='ASSIGNED'
        AND pu.unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
        AND pu.unit_metadata->>'method_execution_contract'='PE10_METHOD_V1'
        AND jsonb_typeof(pu.unit_metadata#>array[
          'action_specs_v1',p_checkpoint_code,'assertion_contract','pass_when'])='object'
    )
  THEN
    raise exception 'ENGINEERING_ASSERTION_CHECKPOINT_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current_code,'<terminal>');
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec
  );

  if coalesce(v_contract->>'status','')<>'READY' then
    raise exception 'ENGINEERING_ASSERTION_CONTRACT_NOT_READY:%',
      coalesce(v_contract::text,'{}');
  end if;

  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);
  v_mode:=v_contract->>'mode';
  v_observed:=p_result->'observed';

  if v_mode='CAPABILITY_TEST_RESULT_CONTRACT' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and p_result->>'test_code'=v_contract->>'test_code'
      and (
        v_contract->>'suite_code' is null
        or p_result->>'suite_code'=v_contract->>'suite_code'
      )
      and jsonb_typeof(v_observed)='object'
      and v_observed @> v_pass_when
      and v_evidence_ref is not null;

  elsif v_mode='REPOSITORY_CAPABILITY_VALIDATED_OUTPUT' then
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'validator_evidence_ref','')),'');

    if jsonb_typeof(v_contract->'pass_when')='object' then
      v_semantic_ok :=
        jsonb_typeof(v_observed)='object'
        and v_observed @> (v_contract->'pass_when');
    end if;

    if jsonb_typeof(v_contract->'output_fields')='array'
       and jsonb_array_length(v_contract->'output_fields')>0 then
      if jsonb_typeof(v_observed)<>'object' then
        v_fields_ok:=false;
      else
        select not exists (
          select 1
          from jsonb_array_elements_text(v_contract->'output_fields') f(field_name)
          where not (v_observed ? f.field_name)
        ) into v_fields_ok;
      end if;
    end if;

    if jsonb_typeof(v_contract->'required_nonempty_fields')='array'
       and jsonb_array_length(v_contract->'required_nonempty_fields')>0 then
      if jsonb_typeof(v_observed)<>'object' then
        v_nonempty_ok:=false;
      else
        select not exists (
          select 1
          from jsonb_array_elements_text(v_contract->'required_nonempty_fields') f(field_name)
          where not (v_observed ? f.field_name)
             or jsonb_typeof(v_observed->f.field_name)='null'
             or nullif(btrim(coalesce(v_observed->>f.field_name,'')),'') is null
        ) into v_nonempty_ok;
      end if;
    end if;

    v_pass :=
      p_result->>'status'='PASS'
      and p_result->>'validator_status'='PASS'
      and p_result->>'capability_code'=v_contract->>'capability_code'
      and p_result->>'version'=v_contract->>'version'
      and p_result->>'manifest_sha256'=v_contract->>'manifest_sha256'
      and p_result->>'result_schema'=v_contract->>'result_schema'
      and p_result->>'validator_ref'=v_contract->>'validator_ref'
      and v_evidence_ref is not null
      and v_semantic_ok
      and v_fields_ok
      and v_nonempty_ok;

  elsif v_mode='EXPLICIT_PASS_WHEN_SUBSET' then
    v_pass_when:=v_contract->'pass_when';
    v_evidence_ref:=nullif(btrim(coalesce(p_result->>'evidence_ref','')),'');
    v_pass :=
      p_result->>'status'='PASS'
      and jsonb_typeof(v_observed)='object'
      and v_observed @> v_pass_when
      and v_evidence_ref is not null;
  else
    raise exception 'ENGINEERING_ASSERTION_MODE_UNSUPPORTED:%',v_mode;
  end if;

  if not v_pass then
    raise exception 'ENGINEERING_ASSERTION_RESULT_FAILED:%/%/% mode=%',
      p_plan_code,p_unit_code,p_checkpoint_code,v_mode;
  end if;

  v_result_sha:=programacion.fn_v09_sha256_jsonb(p_result);

  v_receipt:=jsonb_build_object(
    'schema_version','ENGINEERING_CHECKPOINT_ASSERTION_RECEIPT_V1',
    'passed',true,
    'mode',v_mode,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'contract_sha256',v_contract_sha,
    'result_sha256',v_result_sha,
    'evidence_ref',v_evidence_ref,
    'recorded_at',v_recorded_at,
    'recorded_by',coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER')
  );
  v_receipt_sha:=programacion.fn_v09_sha256_jsonb(v_receipt);

  update programacion.engineering_work_checkpoints
     set assertion_contract_sha256=v_contract_sha,
         assertion_receipt=v_receipt,
         assertion_receipt_sha256=v_receipt_sha,
         assertion_recorded_at=v_recorded_at,
         assertion_recorded_by=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER'),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(btrim(p_actor),''),'ENGINEERING_ASSERTION_RECORDER')
   where id=v_checkpoint_id;

  return v_receipt || jsonb_build_object(
    'assertion_receipt_sha256',v_receipt_sha
  );
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_transition_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_new_status text, p_evidence_ref text, p_actor text, p_detail text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_work_item_id bigint;
  v_current_code text;
  v_existing_status text;
  v_remaining int;
  v_open_blockers int;
  v_unmet_deps int;
  v_result jsonb;
  v_progress text;
  v_next text;
begin
  if p_new_status not in ('DONE','NOT_APPLICABLE','IN_PROGRESS') then
    raise exception using message = (
      programacion.fn_engineering_error_contract_v1('CHECKPOINT_TRANSITION_STATUS_UNSUPPORTED')
      || jsonb_build_object('received',p_new_status)
    )::text;
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if v_work_item_id is null then
    raise exception 'Canonical unit not found: %/%',p_plan_code,p_unit_code;
  end if;

  select c.status into v_existing_status
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id and c.checkpoint_code=p_checkpoint_code;

  if v_existing_status in ('DONE','NOT_APPLICABLE') then
    return programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
      p_plan_code,p_unit_code
    ) || jsonb_build_object(
      'transition',jsonb_build_object(
        'status','NOOP_ALREADY_TERMINAL',
        'checkpoint_code',p_checkpoint_code
      )
    );
  end if;

  select c.checkpoint_code into v_current_code
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  -- Explicit independent-method mode; all other engineering units still
  -- enforce the original linear checkpoint guard without any change.
  IF v_current_code IS DISTINCT FROM p_checkpoint_code
    AND NOT EXISTS (
      SELECT 1 FROM programacion.engineering_plan_units pu
      WHERE pu.work_item_id=v_work_item_id
        AND pu.plan_code=p_plan_code AND pu.unit_code=p_unit_code
        AND pu.disposition='ASSIGNED'
        AND pu.unit_metadata->>'checkpoint_ordering'='INDEPENDENT_METHOD_VARIANTS'
        AND pu.unit_metadata->>'method_execution_contract'='PE10_METHOD_V1'
        AND jsonb_typeof(pu.unit_metadata#>array[
          'action_specs_v1',p_checkpoint_code,'assertion_contract','pass_when'])='object'
    )
  THEN
    raise exception 'Checkpoint % is not current; current=%',p_checkpoint_code,v_current_code;
  end if;

  if p_new_status in ('DONE','NOT_APPLICABLE')
     and coalesce(nullif(btrim(p_evidence_ref),''),nullif(btrim(p_detail),'')) is null then
    raise exception 'Terminal checkpoint transition requires evidence_ref or detail';
  end if;

  update programacion.engineering_work_checkpoints
     set status=p_new_status,
         evidence_ref=coalesce(nullif(p_evidence_ref,''),evidence_ref),
         completed_at=case when p_new_status='DONE' then now() else completed_at end,
         updated_at=now(),
         updated_by_execution_id=coalesce(
           nullif(p_actor,''),
           'ENGINEERING_CHECKPOINT_TRANSITION_V1'
         )
   where work_item_id=v_work_item_id
     and checkpoint_code=p_checkpoint_code;

  if p_new_status='IN_PROGRESS' then
    update programacion.engineering_work_items
       set status='IN_PROGRESS',
           started_at=coalesce(started_at,now()),
           updated_at=now()
     where id=v_work_item_id
       and status not in ('DONE','CANCELLED');
  else
    select count(*) into v_remaining
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id
      and c.required
      and c.status not in ('DONE','NOT_APPLICABLE');

    select programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id)
      into v_open_blockers;

    select count(*) into v_unmet_deps
    from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
    where d.is_unmet;

    if v_remaining=0 and v_open_blockers=0 and v_unmet_deps=0 then
      update programacion.engineering_work_items
         set status='DONE',
             completed_at=coalesce(completed_at,now()),
             started_at=coalesce(started_at,now()),
             updated_at=now()
       where id=v_work_item_id
         and status<>'CANCELLED';
    else
      update programacion.engineering_work_items
         set status='IN_PROGRESS',
             started_at=coalesce(started_at,now()),
             completed_at=null,
             updated_at=now()
       where id=v_work_item_id
         and status not in ('DONE','CANCELLED');
    end if;
  end if;

  v_result:=programacion.fn_engineering_unit_bootstrap_with_contract_repair_v1(
    p_plan_code,p_unit_code
  );

  v_progress:=coalesce(v_result#>>'{state,progress_pct}','0');
  v_next:=coalesce(v_result#>>'{terminal_action}','UNKNOWN');

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,
    reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,
    'PROGRESS',
    'Checkpoint '||p_checkpoint_code||' -> '||p_new_status||
      '; ledger_progress='||v_progress||'%',
    p_detail,
    v_next||coalesce(' / '||(v_result#>>'{current_checkpoint,checkpoint_code}'),''),
    case
      when nullif(p_evidence_ref,'') is null then '[]'::jsonb
      else jsonb_build_array(p_evidence_ref)
    end,
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1'),
    now(),
    coalesce(nullif(p_actor,''),'ENGINEERING_CHECKPOINT_TRANSITION_V1')
  );

  return v_result || jsonb_build_object(
    'transition',jsonb_build_object(
      'status','APPLIED',
      'checkpoint_code',p_checkpoint_code,
      'new_status',p_new_status,
      'ledger_progress_pct',v_progress,
      'next_terminal_action',v_next,
      'auto_contract_repair_evaluated',true
    )
  );
end;
$function$;

DO $m03_close$
DECLARE
 v_exec text;
 v_event_id bigint;
 v_raw text := $m03_raw_json${
  "schema": "PE10_METHOD_RAW_V2",
  "case_ref": "PE10-IG-M107-M109-P0",
  "method_code": "PE10_M03",
  "base_code": "A",
  "algorithm_codes": [
    "M"
  ],
  "source_frozen_at_utc": "2026-10-15T00:00:00Z",
  "source_case": "P0_ORIGINAL.md (original), without post-cutoff method solutions",
  "method_contract": "PE10_METHOD_V1 DRAFT / SRCR_SINGLE / ATMS M only",
  "execution_mode_actual": "ONE_GPT_CONTEXT_READ_ONLY_WITH_EXECUTED_ATMS",
  "scope": "RESEARCH_ONLY_ASOF_HISTORICAL; ADMIN_CURRENTNESS_SEPARATE",
  "comparison_to_other_methods": "NOT_PERFORMED",
  "start_observed": "not clock-attested",
  "end_observed": "2026-10-18T07:23:27.106Z",
  "time_claim": "Only individual SQL client durations are estimates of tool round trips; not LF runtime benchmark",
  "investigation_status": "RESEARCH_RAW_COMPLETE_PENDING_GOVERNED_VALIDATION",
  "checkpoint_status_in_db": "PENDING",
  "sql_evidence": [
    {
      "id": "M03_Q01",
      "sql_literal": "SELECT current_user AS role, current_setting('transaction_read_only') AS read_only, current_setting('request.jwt.claim.role',true) AS jwt_role",
      "rows": [
        {
          "role": "supabase_read_only_user",
          "read_only": "on",
          "jwt_role": null
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:21.931Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 570
    },
    {
      "id": "M03_Q02",
      "sql_literal": "SELECT id,created_at,payload->'source_pack_version' AS source_pack_version,payload->'fetch_spec_version' AS fetch_spec_version,payload->'sql_caller_count' AS declared_sql,payload->'trigger_binding_count' AS declared_triggers,payload->'test_case_count' AS declared_tests,payload->'usage_stats' AS usage_stats,payload->'historical_provenance_only' AS historical_provenance FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "id": 20161,
          "created_at": "2026-10-04 05:14:40.880842+00",
          "source_pack_version": "SOURCE_PACK_V1",
          "fetch_spec_version": "SOURCE_PACK_LOOKUP_V2",
          "declared_sql": 38,
          "declared_triggers": 21,
          "declared_tests": 77,
          "usage_stats": {
            "ig_stat_rows": 0,
            "interpretation": "track_functions none means zero stat rows cannot prove no usage; static governed graph supplies inventory currentness",
            "track_functions": "none"
          },
          "historical_provenance": {
            "router_note": "Router binding snapshot observes readiness revision 5.12 while governed current readiness snapshot is 5.13; retained as provenance/currentness drift only.",
            "contract_note": "Older input contract rows remain recorded; caller usage is not inferred from their existence."
          }
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:22.320Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 385
    },
    {
      "id": "M03_Q03",
      "sql_literal": "SELECT count(*) AS n,count(DISTINCT x->>'dedupe_key') AS unique_callers,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') AS active,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') AS md5_syntax_valid,count(*) FILTER(WHERE x->>'caller_oid' ~ '^[0-9]+$') AS oids_present,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') AS historically_marked_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161",
      "rows": [
        {
          "n": 38,
          "unique_callers": 38,
          "active": 38,
          "md5_syntax_valid": 38,
          "oids_present": 38,
          "historically_marked_live": 38
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:22.792Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 472
    },
    {
      "id": "M03_Q04",
      "sql_literal": "SELECT count(*) total_edges,count(DISTINCT concat(x->>'caller','->',callee.name)) distinct_edges,count(DISTINCT callee.name) distinct_callees,count(*) FILTER(WHERE callee.name LIKE '%cached%') cached_name_edges,count(DISTINCT callee.name) FILTER(WHERE callee.name LIKE '%cached%') cached_name_targets FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(name) WHERE e.id=20161",
      "rows": [
        {
          "total_edges": 76,
          "distinct_edges": 76,
          "distinct_callees": 39,
          "cached_name_edges": 11,
          "cached_name_targets": 9
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:23.249Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 457
    },
    {
      "id": "M03_Q05",
      "sql_literal": "SELECT jsonb_array_length(payload->'edge_current') AS edge_entries,jsonb_array_length(payload->'external_inventory') AS external_entries,jsonb_array_length(payload->'trigger_bindings') AS triggers,jsonb_array_length(payload->'consumer_relation_snapshot_json_rows') AS consumer_snapshots,payload->'pg_depend_direct_rows' AS pg_depend_direct_rows,payload->'unexplained_material_callers' AS unexplained_material_callers FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "edge_entries": 4,
          "external_entries": 6,
          "triggers": 21,
          "consumer_snapshots": 27,
          "pg_depend_direct_rows": 0,
          "unexplained_material_callers": 0
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:23.777Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 528
    },
    {
      "id": "M03_Q06",
      "sql_literal": "SELECT x->>'operational_class' AS operational_class,x->>'governance_lifecycle' AS governance_lifecycle,count(*) AS n FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'external_inventory') x WHERE e.id=20161 GROUP BY 1,2 ORDER BY 1,2",
      "rows": [
        {
          "operational_class": "ACTIVE",
          "governance_lifecycle": "CANDIDATE_READ_ONLY",
          "n": 2
        },
        {
          "operational_class": "ACTIVE",
          "governance_lifecycle": "RUNTIME_SANDBOX_CANARY",
          "n": 1
        },
        {
          "operational_class": "CANDIDATE",
          "governance_lifecycle": "CANDIDATE_READ_ONLY",
          "n": 1
        },
        {
          "operational_class": "CANDIDATE",
          "governance_lifecycle": "NO_HABILITADO",
          "n": 1
        },
        {
          "operational_class": "CANDIDATE_TEST",
          "governance_lifecycle": "CANDIDATE_READ_ONLY",
          "n": 1
        }
      ],
      "rows_returned": 5,
      "time_observed_utc": "2026-10-18T07:23:24.234Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 457
    },
    {
      "id": "M03_Q07",
      "sql_literal": "SELECT id,created_at,receipt_kind,subject_ref,verification_ref,receipt_sha256,payload->'pass' AS historical_pass,payload->'verification_status' AS status,payload->'screens_total' AS screens,payload->'families_total' AS families,payload->'screens_below_2' AS insufficient_screens,payload->'families_below_2' AS insufficient_families,payload->'known_false_pass_signals' AS false_pass,payload->'unresolved_d4' AS d4 FROM programacion.provenance_receipts WHERE id=38",
      "rows": [
        {
          "id": 38,
          "created_at": "2026-10-07 16:01:00.760627+00",
          "receipt_kind": "EVIDENCE_VERIFICATION",
          "subject_ref": "plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2",
          "verification_ref": "supabase://programacion.input_readiness_runs/SOAK_OBSERVATION_HISTORY_V2/20261007",
          "receipt_sha256": "17e949addd09caa82add52c0d792e91d0460435d1b6f77ef7910ff76c431c972",
          "historical_pass": true,
          "status": "VERIFIED",
          "screens": 13,
          "families": 47,
          "insufficient_screens": 0,
          "insufficient_families": 0,
          "false_pass": 0,
          "d4": 0
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:24.667Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 433
    },
    {
      "id": "M03_Q08",
      "sql_literal": "SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez < TIMESTAMPTZ '2026-10-15 00:00:00+00' ORDER BY codigo",
      "rows": [
        {
          "codigo": "IG-M107-CP2-READ-ROLE-CURRENTNESS-001",
          "primera_vez": "2026-10-14 23:44:24.874586+00",
          "causa_raiz": "Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados.",
          "prevencion": "Leer EKB y action_spec. No elevar EXECUTE ni crear motor. Reusar recibo verificado SOAK_OBSERVATION_HISTORY_V2 y revisar la cohorte mediante tablas con SELECT autorizado. Considerar recuentos brutos como evidencia complementaria, nunca sustituto de as-of. Rectificar únicamente queries CP2.",
          "validacion": "2026-10-14: Q1 receipt 38 PASS, Q2 cohort PASS_OBSERVED 13/13 screens, 47 families, 199 completed runs. SQL 42501 reproducido. Migración revierte primer ensayo y lee CP2 DONE, otros tres pendientes sin autorizar producción."
        },
        {
          "codigo": "IG-M107-SOAK-CRITERION-DRIFT-001",
          "primera_vez": "2026-10-14 23:39:14.146551+00",
          "causa_raiz": "Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11.",
          "prevencion": "Antes de CP1 leer M9.11 DONE y el recibo VERIFIED; heredar >=2 as-of, 0 falsos PASS y 0 D4. Reusar historia. No convertir 13/47 en obligación de nuevas corridas ni confundir latest CURRENT con validez histórica. Confirmar los checkpoints posteriores por su naturaleza.",
          "validacion": "Read-only 2026-10-14: receipt 38 13/13 screens,47/47 families, zero below-2, false_pass=0,D4=0; tres negativos sintéticos rechazados. Migración prueba rollback y comprueba CP1 DONE/CP2 PENDING, sin activar producción."
        }
      ],
      "rows_returned": 2,
      "time_observed_utc": "2026-10-18T07:23:25.117Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 450
    },
    {
      "id": "M03_Q09",
      "sql_literal": "SELECT count(*) AS rows, array_agg(DISTINCT (x::jsonb #>> '{adapter_metadata,input_governance_observed_revision}')) AS observed_revisions FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements_text(e.payload->'router_binding_snapshot_json_rows') x WHERE e.id=20161",
      "rows": [
        {
          "rows": 4,
          "observed_revisions": [
            "5.12"
          ]
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:25.456Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 339
    },
    {
      "id": "M03_Q10",
      "sql_literal": "SELECT payload->'excluded_name_candidate' AS excluded,payload->'ambiguous_name_candidates_checked' AS ambiguous_checked,payload->'ambiguous_name_candidates_excluded' AS ambiguous_excluded FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "excluded": {
            "object": "lf-profile-creator-governance-caller-v1",
            "reason": "Current caller.ts invokes configured LF_PROFILE_CREATOR_RUNTIME_SLUG/default run-creacion-perfil-lf and contains no IG call; name/existence is not usage evidence.",
            "sha256": "27594e559e752587c5644463efc67fb9be245319b856766d85435431325cf6ee",
            "version": 16,
            "edge_marker": "ACTIVE",
            "classification": "NOT_IG_CALLER",
            "verified_target": "run-creacion-perfil-lf"
          },
          "ambiguous_checked": 1,
          "ambiguous_excluded": 1
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:25.859Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 403
    },
    {
      "id": "M03_Q11",
      "sql_literal": "SELECT (payload ? 'end_to_end_duration_ms') AS has_e2e_duration_field,(payload ? 'latency_distribution') AS has_latency_distribution,payload->'usage_stats'->>'track_functions' AS track_functions,payload->'usage_stats'->>'ig_stat_rows' AS ig_stat_rows FROM public.lf_eventos WHERE id=20161",
      "rows": [
        {
          "has_e2e_duration_field": false,
          "has_latency_distribution": false,
          "track_functions": "none",
          "ig_stat_rows": "0"
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:26.231Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 372
    },
    {
      "id": "M03_Q12",
      "sql_literal": "SELECT x->>'caller' AS caller, x->'callees' AS callees FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161 AND x->>'caller' IN ('programacion.fn_input_governance_curator_materialize_v1','programacion.fn_input_governance_validator_validate_v1','programacion.fn_input_governance_execute') ORDER BY 1",
      "rows": [
        {
          "caller": "programacion.fn_input_governance_curator_materialize_v1",
          "callees": [
            "fn_input_governance_bootstrap_materialize_v2",
            "fn_input_governance_curator_rebind_v1",
            "fn_input_governance_recurate_source_stale_v1",
            "fn_input_governance_recurate_v2",
            "fn_input_readiness_run_is_current_cached_v1"
          ]
        },
        {
          "caller": "programacion.fn_input_governance_execute",
          "callees": [
            "fn_input_governance_ekb_checkpoint",
            "fn_input_governance_worker_spec_known_current_v1",
            "fn_input_governance_worker_spec_known_no_current_v1",
            "fn_input_readiness_run_is_current_cached_v1"
          ]
        },
        {
          "caller": "programacion.fn_input_governance_validator_validate_v1",
          "callees": [
            "fn_input_governance_bootstrap_validate_v1",
            "fn_input_governance_validate_v2",
            "fn_input_governance_validator_rebind_v1"
          ]
        }
      ],
      "rows_returned": 3,
      "time_observed_utc": "2026-10-18T07:23:26.666Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ASOF_HISTORICAL_QUERY_RUN_20261018",
      "elapsed_client_ms": 435
    },
    {
      "id": "M03_Q13",
      "sql_literal": "SELECT c.id,c.checkpoint_code,c.status,c.evidence_ref,c.assertion_receipt,c.completed_at FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=1133 AND c.checkpoint_code='PE10_M03'",
      "rows": [
        {
          "id": 1627,
          "checkpoint_code": "PE10_M03",
          "status": "PENDING",
          "evidence_ref": "chatgpt-file://file_000000004e48820e8414025654581746/methods/PE10_M03.json#sha256=35c677ff8ba29da910a88b4c2f28fa1905a2723bd9608f60d8405f5eb6d7adea",
          "assertion_receipt": null,
          "completed_at": null
        }
      ],
      "rows_returned": 1,
      "time_observed_utc": "2026-10-18T07:23:27.090Z",
      "source": "Supabase read_only execute_sql",
      "scope": "ADMIN_LIVE_20261018",
      "elapsed_client_ms": 424
    }
  ],
  "algorithms_executed": [
    "ATMS_M: minimal support environments, two alternative risk justifications, invalidation propagation and nogoods"
  ],
  "algorithm_non_executed_reasons": [],
  "ATMS": {
    "type": "EXECUTED_ASSUMPTION_BASED_TMS",
    "engine": "deterministic JS in one chat; no external oracles",
    "evidence_facts": {
      "E20161": "public.lf_eventos/20161 as-of 2026-10-04",
      "E38": "programacion.provenance_receipts/38 as-of 2026-10-07",
      "EKB_SOAK": "EKB drift as-of 2026-10-14",
      "EKB_CP2": "EKB privilege mismatch as-of 2026-10-14"
    },
    "rules": {
      "HISTORICAL_SNAPSHOT": [
        [
          "E20161",
          "ASOF_SCOPE"
        ]
      ],
      "HISTORICAL_CALLER_INVENTORY": [
        [
          "HISTORICAL_SNAPSHOT",
          "DEDUPE_SCOPE"
        ]
      ],
      "HISTORICAL_SOAK_RECEIPT": [
        [
          "E38",
          "SOAK_ASOF_ONLY"
        ]
      ],
      "SAFE_REUSE_HISTORICAL_SOAK": [
        [
          "HISTORICAL_SOAK_RECEIPT",
          "EKB_SOAK",
          "ASOF_SCOPE"
        ]
      ],
      "HISTORICAL_PERMISSION_ISSUE": [
        [
          "EKB_CP2"
        ]
      ],
      "STATIC_GRAPH_NOT_EXECUTION": [
        [
          "E20161",
          "STATIC_NOT_RUNTIME"
        ]
      ],
      "NO_VALID_TIMING_COHORT": [
        [
          "E20161",
          "NO_TELEMETRY"
        ]
      ],
      "RISK_OF_FALSE_CLOSURE": [
        [
          "HISTORICAL_SNAPSHOT",
          "EKB_SOAK"
        ],
        [
          "HISTORICAL_SNAPSHOT",
          "EKB_CP2"
        ]
      ],
      "INVALID_PROMOTION_TO_CURRENT": [
        [
          "HISTORICAL_SNAPSHOT",
          "CLAIM_CURRENT_FROM_ASOF"
        ]
      ],
      "INVALID_INFER_NO_USAGE": [
        [
          "NO_VALID_TIMING_COHORT",
          "CLAIM_NO_USAGE_FROM_NO_STATS"
        ]
      ]
    },
    "nogoods": [
      [
        "ASOF_SCOPE",
        "CLAIM_CURRENT_FROM_ASOF"
      ],
      [
        "STATIC_NOT_RUNTIME",
        "CLAIM_NO_USAGE_FROM_NO_STATS"
      ],
      [
        "NO_TELEMETRY",
        "CLAIM_NO_USAGE_FROM_NO_STATS"
      ]
    ],
    "assumptions": [
      "ASOF_SCOPE",
      "DEDUPE_SCOPE",
      "SOAK_ASOF_ONLY",
      "STATIC_NOT_RUNTIME",
      "NO_TELEMETRY",
      "CLAIM_CURRENT_FROM_ASOF",
      "CLAIM_NO_USAGE_FROM_NO_STATS"
    ],
    "labels": {
      "HISTORICAL_SNAPSHOT": [
        [
          "ASOF_SCOPE",
          "E20161"
        ]
      ],
      "HISTORICAL_CALLER_INVENTORY": [
        [
          "ASOF_SCOPE",
          "DEDUPE_SCOPE",
          "E20161"
        ]
      ],
      "HISTORICAL_SOAK_RECEIPT": [
        [
          "E38",
          "SOAK_ASOF_ONLY"
        ]
      ],
      "SAFE_REUSE_HISTORICAL_SOAK": [
        [
          "ASOF_SCOPE",
          "E38",
          "EKB_SOAK",
          "SOAK_ASOF_ONLY"
        ]
      ],
      "HISTORICAL_PERMISSION_ISSUE": [
        [
          "EKB_CP2"
        ]
      ],
      "STATIC_GRAPH_NOT_EXECUTION": [
        [
          "E20161",
          "STATIC_NOT_RUNTIME"
        ]
      ],
      "NO_VALID_TIMING_COHORT": [
        [
          "E20161",
          "NO_TELEMETRY"
        ]
      ],
      "RISK_OF_FALSE_CLOSURE": [
        [
          "ASOF_SCOPE",
          "E20161",
          "EKB_CP2"
        ],
        [
          "ASOF_SCOPE",
          "E20161",
          "EKB_SOAK"
        ]
      ],
      "INVALID_PROMOTION_TO_CURRENT": [],
      "INVALID_INFER_NO_USAGE": []
    },
    "counterfactual_runs": [
      {
        "scenario": "REMOVE_E38",
        "removed": [
          "E38"
        ],
        "claim": "HISTORICAL_SOAK_RECEIPT",
        "supported": false,
        "expected_supported": false
      },
      {
        "scenario": "REMOVE_E20161",
        "removed": [
          "E20161"
        ],
        "claim": "HISTORICAL_SNAPSHOT",
        "supported": false,
        "expected_supported": false
      },
      {
        "scenario": "REMOVE_EKB_SOAK",
        "removed": [
          "EKB_SOAK"
        ],
        "claim": "RISK_OF_FALSE_CLOSURE",
        "supported": true,
        "expected_supported": true
      },
      {
        "scenario": "FORBID_CURRENT_FROM_ASOF",
        "claim": "INVALID_PROMOTION_TO_CURRENT",
        "supported": false,
        "expected_supported": false
      },
      {
        "scenario": "FORBID_USAGE_FROM_NO_STATS",
        "claim": "INVALID_INFER_NO_USAGE",
        "supported": false,
        "expected_supported": false
      }
    ],
    "negative_checks_passed": true
  },
  "findings": [
    {
      "id": "M03_F01",
      "claim": "Evento histórico 20161 registra 38 callers SQL, 38 identidades deduplicadas, 76 aristas literales (76 pares distintos) y 39 labels de destino; son referencias de snapshot, no llamadas medidas.",
      "evidence_refs": [
        "M03_Q02",
        "M03_Q03",
        "M03_Q04"
      ],
      "confidence": "MEASURED_HISTORICAL_ONLY",
      "impact": "Distinguir inventario léxico vs runtime",
      "new_vs_input": "Reconcilia aristas duplicadas y número de destinos sin asumir ejecución"
    },
    {
      "id": "M03_F02",
      "claim": "38/38 hashes cumplen formato MD5; NO se ha demostrado canonicalización/hash de código ni vigencia actual.",
      "evidence_refs": [
        "M03_Q03"
      ],
      "confidence": "MEASURED_FORMAT_ONLY",
      "impact": "Los hashes formales no certifican integridad histórica del método hash",
      "new_vs_input": "Separación explícita de validez sintáctica y autoría/verificación"
    },
    {
      "id": "M03_F03",
      "claim": "Inventario etiquetado LIVE_PG_PROC al 2026-10-04: 38/38; recibo SOAK VERIFIED al 2026-10-07 pero sujeto a M9.11, no a rendimiento ni a CHECKPOINT M03.",
      "evidence_refs": [
        "M03_Q03",
        "M03_Q07"
      ],
      "confidence": "MEASURED_SCOPED",
      "impact": "Evita transferir currentness de otra fecha o contrato",
      "new_vs_input": "ATMS separa justificación histórica y vigencia operacional"
    },
    {
      "id": "M03_F04",
      "claim": "En evento 20161: 21 trigger bindings, 4 Edge snapshots, 6 externos y 27 relaciones de consumo en snapshot; estos conjuntos no son sumables por posible solape/identidades diferentes.",
      "evidence_refs": [
        "M03_Q05",
        "M03_Q06"
      ],
      "confidence": "MEASURED_HISTORICAL_WITH_SCOPE_LIMIT",
      "impact": "Cobertura total no puede deducirse por suma de poblaciones",
      "new_vs_input": "Medición de clases y relación de solapamiento no demostrada"
    },
    {
      "id": "M03_F05",
      "claim": "track_functions=none; ig_stat_rows=0. Ninguna métrica E2E/latency_distribution en este evento; ausencia no prueba rendimiento ni inactividad.",
      "evidence_refs": [
        "M03_Q02",
        "M03_Q11"
      ],
      "confidence": "MEASURED_ABSENCE_IN_EVENT_ONLY",
      "impact": "Mejoras de tiempo no inferibles del snapshot",
      "new_vs_input": "Negativo lógico ATMS contra inferencia de cero uso"
    },
    {
      "id": "M03_F06",
      "claim": "El snapshot Router contiene observación antigua de readiness 5.12 (en 4 filas) frente a nota interna de 5.13; no equivale a drift actual confirmado ni permite cambiar contratos.",
      "evidence_refs": [
        "M03_Q02",
        "M03_Q09"
      ],
      "confidence": "MEASURED_DOCUMENTED_HISTORICAL_NOTE",
      "impact": "El mantenimiento de evidencia as-of exige anclar versión",
      "new_vs_input": "Invalidador de promoción de snapshot a CURRENT"
    },
    {
      "id": "M03_F07",
      "claim": "El recibo 38 valida criterios soak históricos 13 pantallas, 47 familias, 0 observaciones insuficientes, 0 false PASS signals y 0 D4, pero no tasa o tiempo de flujo completo.",
      "evidence_refs": [
        "M03_Q07"
      ],
      "confidence": "MEASURED_RECEIPT_CONTENT",
      "impact": "Prueba independiente para SOAK, no para performance/consumers",
      "new_vs_input": "ATMS propaga retirada del recibo a justificación"
    },
    {
      "id": "M03_F08",
      "claim": "EKB históricos distinguen falta de permiso de CP2 de una conclusión sobre la política vigente y prohíben elevar EXECUTE como ensayo; invocación no ejecutada.",
      "evidence_refs": [
        "M03_Q08"
      ],
      "confidence": "MEASURED_HISTORICAL_EKB",
      "impact": "Evita falsos READY y escalar permisos innecesariamente",
      "new_vs_input": "Soportes ATMS alternativos para riesgo de cierre prematuro"
    },
    {
      "id": "M03_F09",
      "claim": "La búsqueda nominal de otro caller Edge fue excluida con clasificación NOT_IG_CALLER por objetivo de invocación distinto; el nombre no aporta evidencia de uso.",
      "evidence_refs": [
        "M03_Q10"
      ],
      "confidence": "MEASURED_HISTORICAL_DECLARATION",
      "impact": "Contraprueba contra falso positivo de cobertura",
      "new_vs_input": "Negativo explícito de candidato excluido"
    }
  ],
  "causal_model": {
    "causality_proven": false,
    "hypotheses": [
      {
        "id": "H1",
        "claim": "Confundir vigencia histórica con CURRENT puede inflar cobertura y producir cierres prematuros",
        "support": [
          "M03_F03",
          "M03_F06",
          "M03_F08"
        ],
        "falsifier": "Readback versionado y temporal del grafo ejecutor dentro de un mismo corte y mecanismo"
      },
      {
        "id": "H2",
        "claim": "Inventario léxico de funciones no certifica uso ni impacto temporal",
        "support": [
          "M03_F01",
          "M03_F05"
        ],
        "falsifier": "Trazas runtime instrumentadas con fuente/callee/timestamp y cohortes comparables"
      },
      {
        "id": "H3",
        "claim": "La falta de permiso de CP2 podría explicarse por capacidad de lectura mal descrita y no por ausencia de historial SOAK",
        "support": [
          "M03_F07",
          "M03_F08"
        ],
        "falsifier": "Permisos y recibos vigentes de rol ejecutor autorizado a la fecha objetivo"
      }
    ],
    "atms_dependency_supports": [
      [
        "ASOF_SCOPE",
        "E20161",
        "EKB_CP2"
      ],
      [
        "ASOF_SCOPE",
        "E20161",
        "EKB_SOAK"
      ]
    ]
  },
  "candidate_repairs": [
    {
      "id": "R1",
      "action": "Comparar as-of vs current mediante export o readback versionado con identidades deduplicadas, sin activar funciones",
      "pros": "Distingue drift real de dato antiguo",
      "risk": "Ninguno sobre producción al ser SELECT",
      "prerequisites": "Autorización sólo lectura y semántica canónica de hash/URI"
    },
    {
      "id": "R2",
      "action": "Obtener cohortes de duración E2E por etapa y causa de espera de observaciones existentes",
      "pros": "Permite medir tiempo integral",
      "risk": "Datos históricos pueden no ser representativos",
      "prerequisites": "Timestamps de fuente equiparable y cohortes representativas"
    },
    {
      "id": "R3",
      "action": "Reutilizar recibo SOAK 38 sólo para historial M9.11, sin deducir CP2 currentness",
      "pros": "Evita readbacks duplicados y falso bloqueo",
      "risk": "No prueba currentness actual",
      "prerequisites": "Contrato de CP2 admite heredado"
    }
  ],
  "chosen_repair": {
    "id": "R1",
    "reason": "La primera decisión segura es separar identidad/version as-of del estado actual; no hay evidencia para modificar runtime ni hacer de SOAK una prueba de mejora"
  },
  "rejected_alternatives": [
    "Elevar EXECUTE para poder obtener un PASS de CP2",
    "Eliminar variantes cached por coincidencia de nombre",
    "Usar 0 filas pg_stat como 0 uso o tiempo menor",
    "Añadir 38+21+4+6 como total de consumidores únicos",
    "Comparar main 2026-10-18 como si fuera fuente 2026-10-15"
  ],
  "omissions_searched": [
    "integridad de identidades SQL y formato hash",
    "grafo nominal de llamadas, deduplicación y candidate_exclusion",
    "Edge/triggers/inventario externo y solapes",
    "router snapshot revision vs 5.13 de nota",
    "recibo SOAK, origen histórico, EKB CP2 y permisos",
    "estadísticas y evidencia temporal ausente",
    "ATMS nogoods, justificaciones y contrafactuales"
  ],
  "negative_falsifiers": [
    "Retirar evidencia 38 invalida justificación de SOAK",
    "Retirar evento 20161 invalida inventario de origen",
    "Retirar un EKB mantiene soporte alternativo para riesgo hipotético",
    "No permitir promocionar as-of a CURRENT sin observación independiente",
    "No inferir falta de uso de cero estadísticas"
  ],
  "constraints_preserved": [
    "P0 2026-10-15 UTC",
    "historia sólo con fuentes anteriores al corte",
    "no writes en investigador",
    "algoritmo M únicamente",
    "no comparativa de métodos ni uso de M01/M02",
    "sin benchmark inventado",
    "sin uso de datos posteriores al corte como hallazgos del caso"
  ],
  "unresolved": [
    "Duración E2E comparable no presente en fuente",
    "Hash canónico del método de captura no atestado",
    "No se probaron rutas runtime dinámicas; aristas son menciones",
    "Readback CURRENT no forma parte de P0 y requeriría replay declarado",
    "Cobertura completa del universo trans-modular no demostrada",
    "Recibo gobernado del checkpoint administrativo M03 no existe"
  ],
  "next_safe_step": "Congelar RAW V2 y validar con su contrato; registrar fuente por Train. Para prueba de CURRENT ejecutar lote separado REPLAY_ASOF_NOT_ATTESTED, no convertirlo en hallazgo P0.",
  "research_conclusion": "DIAGNOSTIC_COMPLETE_WITH_MATERIAL_UNKNOWNS; NO_PRODUCT_CHANGE",
  "admin_receipt_state": "PENDING_BY_SEQUENCING_AND_MISSING_OPERATION"
}
$m03_raw_json$;
 v_doc jsonb;
 v_blob_sha text;
 v_sql_count int;
 v_atms_count int;
 v_graph_callers int;
 v_graph_edges int;
 v_receipt_status text;
 v_ekb_count int;
 v_spec jsonb;
 v_contract jsonb;
 v_observed jsonb;
 v_result jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_ref text := 'https://github.com/cristhianlujan/claude-persona-lf-patch/blob/18b4d42cb952c1d0b9f38424040198945c01c710/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M03_RAW_V2.json#git_blob_sha=c6cb821d7e6917a66c0bd657bac1e2ad1b24dab8';
 v_n integer;
BEGIN
 -- Owner-approved work scope, not production execution. The real Train execution
 -- must exist before this transaction; no synthetic execution identity accepted.
 SELECT execution_id INTO v_exec
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
   AND target_code LIKE '%lf_pe10_m03_governed_close_v1'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'M03_CLOSE_TRAIN_AUTHORITY_ABSENT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_work_items
  WHERE id=1133 AND work_code='PEVO-PE10-METHODS32-P0'
  AND status='BACKLOG' AND assignee_ref='PE10_ONE_RUN_COORDINATOR')
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=1133 AND status='PENDING' AND completed_at IS NULL)<>32
 OR NOT EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE id=1627 AND work_item_id=1133 AND checkpoint_code='PE10_M03'
    AND assertion_receipt_sha256 IS NULL AND evidence_ref=v_ref)
 OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units WHERE work_item_id=1133)
 OR (SELECT count(*) FROM programacion.pe10_method_variants
     WHERE method_code='PE10_M03' AND case_ref='PE10-IG-M107-M109-P0'
       AND base_code='A' AND algorithm_codes=ARRAY['M']::text[])<>1
 THEN RAISE EXCEPTION 'M03_CLOSE_PRESTATE_DRIFT'; END IF;

 -- Recompute Git blob identity from complete embedded source bytes,
 -- not a bare string supplied as a PASS by an agent.
 v_blob_sha:=encode(extensions.digest(
   convert_to('blob '||octet_length(convert_to(v_raw,'UTF8'))::text,'UTF8')
   ||decode('00','hex')||convert_to(v_raw,'UTF8'),'sha1'),'hex');
 IF v_blob_sha <> 'c6cb821d7e6917a66c0bd657bac1e2ad1b24dab8' THEN
   RAISE EXCEPTION 'M03_CLOSE_GIT_SOURCE_IDENTITY_MISMATCH:%',v_blob_sha;
 END IF;
 v_doc:=v_raw::jsonb;
 IF v_doc->>'schema'<>'PE10_METHOD_RAW_V2'
 OR v_doc->>'case_ref'<>'PE10-IG-M107-M109-P0'
 OR v_doc->>'method_code'<>'PE10_M03'
 OR v_doc->>'base_code'<>'A'
 OR v_doc->'algorithm_codes'<>'["M"]'::jsonb
 OR v_doc->>'source_frozen_at_utc'<>'2026-10-15T00:00:00Z'
 OR v_doc->>'comparison_to_other_methods'<>'NOT_PERFORMED'
 OR v_doc->>'research_conclusion'<>'DIAGNOSTIC_COMPLETE_WITH_MATERIAL_UNKNOWNS; NO_PRODUCT_CHANGE'
 THEN RAISE EXCEPTION 'M03_CLOSE_RAW_IDENTITY_OR_SCOPE_INVALID'; END IF;

 SELECT count(*) INTO v_sql_count FROM jsonb_array_elements(v_doc->'sql_evidence') q
 WHERE q->>'sql_literal' ~* '^[[:space:]]*SELECT[[:space:]]'
 AND q->>'id' LIKE 'M03_Q%'
 AND q->>'source'='Supabase read_only execute_sql'
 AND jsonb_typeof(q->'rows')='array'
 AND jsonb_array_length(q->'rows')>0
 AND (q->>'rows_returned')::int=jsonb_array_length(q->'rows')
 AND NOT (q ? 'error');
 IF v_sql_count<>13 OR jsonb_array_length(v_doc->'sql_evidence')<>13
 OR (SELECT count(DISTINCT q->>'id') FROM jsonb_array_elements(v_doc->'sql_evidence') q)<>13
 THEN RAISE EXCEPTION 'M03_CLOSE_SQL_EVIDENCE_INCOMPLETE:%',v_sql_count; END IF;
 SELECT count(*) INTO v_atms_count FROM jsonb_array_elements(
   v_doc#>'{ATMS,counterfactual_runs}') t
 WHERE t->'supported'=t->'expected_supported';
 IF jsonb_array_length(v_doc#>'{ATMS,counterfactual_runs}')<>5
 OR v_atms_count<>5
 OR coalesce((v_doc#>>'{ATMS,negative_checks_passed}')::boolean,false) IS NOT TRUE
 OR jsonb_array_length(v_doc#>'{ATMS,labels,INVALID_PROMOTION_TO_CURRENT}')<>0
 OR jsonb_array_length(v_doc#>'{ATMS,labels,INVALID_INFER_NO_USAGE}')<>0
 THEN RAISE EXCEPTION 'M03_CLOSE_ATMS_INVALIDATION_NOT_PROVEN'; END IF;

 -- Source-side as-of readback: measured source assertions, not diagnosis grades.
 SELECT jsonb_array_length(payload->'sql_callers'),
        (SELECT count(*) FROM jsonb_array_elements(payload->'sql_callers') x
         CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') z)
 INTO v_graph_callers,v_graph_edges FROM public.lf_eventos
 WHERE id=20161 AND created_at<TIMESTAMPTZ '2026-10-15 00:00:00+00';
 SELECT payload->>'verification_status' INTO v_receipt_status
 FROM programacion.provenance_receipts WHERE id=38
 AND created_at<TIMESTAMPTZ '2026-10-15 00:00:00+00'
 AND receipt_kind='EVIDENCE_VERIFICATION'
 AND payload->>'subject_ref'='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2'
 AND payload->>'pass'='true';
 SELECT count(*) INTO v_ekb_count FROM transversal.error_knowledge
 WHERE codigo IN ('IG-M107-SOAK-CRITERION-DRIFT-001',
                  'IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 AND primera_vez<TIMESTAMPTZ '2026-10-15 00:00:00+00';
 IF v_graph_callers<>38 OR v_graph_edges<>76
 OR v_receipt_status<>'VERIFIED' OR v_ekb_count<>2
 OR v_doc#>>'{sql_evidence,2,rows,0,n}'<>'38'
 OR v_doc#>>'{sql_evidence,3,rows,0,total_edges}'<>'76'
 OR v_doc#>>'{sql_evidence,6,rows,0,status}'<>'VERIFIED'
 OR v_doc#>>'{sql_evidence,10,rows,0,track_functions}'<>'none'
 OR v_doc#>>'{sql_evidence,10,rows,0,has_e2e_duration_field}'<>'false'
 THEN RAISE EXCEPTION 'M03_CLOSE_HISTORICAL_READBACK_MISMATCH'; END IF;

 -- Canonical Engineering parent identity and explicit scoped material contract.
 INSERT INTO public.lf_eventos
 (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
  payload,origen,created_by_execution_id)
 VALUES
 ('ENGINEERING_PLAN_BINDING','PROGRAM_PLAN',
  'PEVO-PE10-METHODS32-P0/METHODS32',
  'Canonical plan-unit binding for independent method checkpoint results, not a runtime release.',
  'INFO',jsonb_build_object('work_item_id',1133,'method_case','PE10-IG-M107-M109-P0',
    'source_event_id',20161,'checkpoint_ordering','INDEPENDENT_METHOD_VARIANTS',
    'external_evaluator_status','NOT_PERFORMED','runtime_activation',false,
    'train_execution_id',v_exec,'method_output_status','RESEARCH_RESULT_ONLY'),
  'LF_MIGRATION_MERGE_TRAIN',v_exec)
 RETURNING id INTO v_event_id;
 INSERT INTO programacion.engineering_plan_units
 (id,plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,exit_criterion,
  plan_event_id,source_event_id,work_item_id,created_by_execution_id,disposition,unit_metadata)
 VALUES
 (nextval('programacion.engineering_plan_units_id_seq'),
 'PEVO-PE10-METHODS32-P0','METHODS32','METHOD_EVIDENCE',
 'PE10_METHODS32_P0',1,32,'PE10 32 separately researched methods',
 'Each method checkpoint closes only on actual executed method and a governed material assertion receipt; independent variants need not wait for unassessed earlier variants.',
 v_event_id,20161,1133,v_exec,'ASSIGNED',
 jsonb_build_object('schema','PE10_METHOD_VARIANTS_ENGINEERING_UNIT_V1',
   'method_execution_contract','PE10_METHOD_V1',
   'checkpoint_ordering','INDEPENDENT_METHOD_VARIANTS',
   'runtime_activation',false,
   'method_outputs_are_evaluation_inputs_only',true,
   'prior_variants_may_remain_pending',true,
   'source_cutoff_utc','2026-10-15T00:00:00Z',
   'action_specs_v1',jsonb_build_object('PE10_M03',$m03_spec${"status":"READY","action_kind":"VERIFY_QUERY_ONCE","recipe_mode":"READBACK_EXACT","requires_material_execution":true,"contract_family":"PE10_METHOD_EXECUTION_EVIDENCE","precision":"PE10_METHOD_V1_MATERIAL_EVIDENCE","assertion_contract":{"mode":"EXPLICIT_PASS_WHEN_SUBSET","pass_when":{"checkpoint_identity":"PE10_M03","method_algorithm":"M","literal_sql_count":13,"atms_counterfactuals_passed":5,"historical_source_event_id":20161,"ekb_source_count":2,"git_source_blob_verified":true,"scope_is_historical":true,"runtime_modified":false}},"evidence_ref":"https://github.com/cristhianlujan/claude-persona-lf-patch/blob/18b4d42cb952c1d0b9f38424040198945c01c710/docs/profile_updater/experiments/pe10_methods32_p0/PE10_M03_RAW_V2.json#git_blob_sha=c6cb821d7e6917a66c0bd657bac1e2ad1b24dab8","verification_queries":["SELECT id,created_at,payload->'source_pack_version' AS source_pack_version,payload->'fetch_spec_version' AS fetch_spec_version,payload->'sql_caller_count' AS declared_sql,payload->'trigger_binding_count' AS declared_triggers,payload->'test_case_count' AS declared_tests,payload->'usage_stats' AS usage_stats,payload->'historical_provenance_only' AS historical_provenance FROM public.lf_eventos WHERE id=20161","SELECT count(*) AS n,count(DISTINCT x->>'dedupe_key') AS unique_callers,count(*) FILTER(WHERE x->>'operational_class'='ACTIVE') AS active,count(*) FILTER(WHERE x->>'definition_md5' ~ '^[a-f0-9]{32}$') AS md5_syntax_valid,count(*) FILTER(WHERE x->>'caller_oid' ~ '^[0-9]+$') AS oids_present,count(*) FILTER(WHERE x->>'currentness_source'='LIVE_PG_PROC') AS historically_marked_live FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x WHERE e.id=20161","SELECT count(*) total_edges,count(DISTINCT concat(x->>'caller','->',callee.name)) distinct_edges,count(DISTINCT callee.name) distinct_callees,count(*) FILTER(WHERE callee.name LIKE '%cached%') cached_name_edges,count(DISTINCT callee.name) FILTER(WHERE callee.name LIKE '%cached%') cached_name_targets FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'sql_callers') x CROSS JOIN LATERAL jsonb_array_elements_text(x->'callees') callee(name) WHERE e.id=20161","SELECT id,created_at,receipt_kind,subject_ref,verification_ref,receipt_sha256,payload->'pass' AS historical_pass,payload->'verification_status' AS status,payload->'screens_total' AS screens,payload->'families_total' AS families,payload->'screens_below_2' AS insufficient_screens,payload->'families_below_2' AS insufficient_families,payload->'known_false_pass_signals' AS false_pass,payload->'unresolved_d4' AS d4 FROM programacion.provenance_receipts WHERE id=38","SELECT codigo,primera_vez,causa_raiz,prevencion,validacion FROM transversal.error_knowledge WHERE codigo IN ('IG-M107-SOAK-CRITERION-DRIFT-001','IG-M107-CP2-READ-ROLE-CURRENTNESS-001') AND primera_vez < TIMESTAMPTZ '2026-10-15 00:00:00+00' ORDER BY codigo","SELECT (payload ? 'end_to_end_duration_ms') AS has_e2e_duration_field,(payload ? 'latency_distribution') AS has_latency_distribution,payload->'usage_stats'->>'track_functions' AS track_functions,payload->'usage_stats'->>'ig_stat_rows' AS ig_stat_rows FROM public.lf_eventos WHERE id=20161"],"expected":"Executed SRCR individual M/ATMS investigation with 13 literal SQL readbacks, source-bound historical evidence, invalidation tests and declared material unknowns; not an implementation claim","forbidden":["PRETEND_OUTPUT_CORRECTNESS_INDEPENDENTLY_JUDGED","USE_PAST_CUTOFF_AS_P0","MUTATE_RUNTIME","MARK_M01_M02_DONE_WITHOUT_EVIDENCE","SKIP_ASSERTION_RECEIPT"],"target":{"checkpoint":"PE10_M03","declared_objects":["programacion.engineering_work_checkpoints","programacion.engineering_plan_units","public.lf_eventos","programacion.provenance_receipts"],"declared_artifacts":[],"declared_events":[20161],"evidence_artifacts":[{"path":"cristhianlujan/claude-persona-lf-patch:docs/profile_updater/experiments/pe10_methods32_p0/PE10_M03_RAW_V2.json","role":"EVIDENCE","purpose":"IMMUTABLE_EXECUTION_RAW_V2","target_kind":"EXACT_EXISTING_FILE"}]}}$m03_spec$::jsonb)));
 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M03');
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M03',v_spec);
 IF v_contract->>'status'<>'READY'
 OR v_contract->>'mode'<>'EXPLICIT_PASS_WHEN_SUBSET'
 OR coalesce((v_spec->>'requires_material_execution')::boolean,false) IS NOT TRUE
 THEN RAISE EXCEPTION 'M03_CLOSE_GOVERNED_ASSERTION_CONTRACT_NOT_READY:%',coalesce(v_contract::text,'NULL'); END IF;

 -- The receipt is generated by the existing canonical assertion recorder
 -- from source-side validations, not a synthetic client-provided PASS.
 v_observed:=jsonb_build_object(
 'checkpoint_identity','PE10_M03',
 'method_algorithm','M',
 'literal_sql_count',v_sql_count,
 'atms_counterfactuals_passed',v_atms_count,
 'historical_source_event_id',20161,
 'ekb_source_count',v_ekb_count,
 'git_source_blob_verified',true,
 'scope_is_historical',true,
 'runtime_modified',false);
 v_result:=jsonb_build_object('status','PASS','observed',v_observed,
                              'evidence_ref',v_ref,
                              'validation_kind','SOURCE_AND_MATERIAL_COMPLETENESS_ONLY',
                              'external_method_quality_judgment','NOT_PERFORMED');
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
   'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M03',v_result,v_exec);
 IF v_assertion->>'passed'<>'true'
 OR coalesce(v_assertion->>'assertion_receipt_sha256','') !~ '^[a-f0-9]{64}$'
 THEN RAISE EXCEPTION 'M03_CLOSE_CANONICAL_ASSERTION_INVALID'; END IF;
 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
   'PEVO-PE10-METHODS32-P0','METHODS32','PE10_M03','DONE',v_ref,
   v_exec,'Source-bound PE10 M03 method execution evidence; NO independent method-correctness judgment');
 IF v_transition#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M03_CLOSE_CANONICAL_TRANSITION_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=1133 AND checkpoint_code='PE10_M03' AND status='DONE'
      AND completed_at IS NOT NULL AND evidence_ref=v_ref
      AND assertion_receipt->>'passed'='true'
      AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt))<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND checkpoint_code IN('PE10_M01','PE10_M02','PE10_M04')
     AND status='PENDING' AND assertion_receipt IS NULL)<>3
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1133 AND status='DONE')<>1
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=1133)<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'M03_CLOSE_POSTSTATE_INCONSISTENT'; END IF;
END $m03_close$;
