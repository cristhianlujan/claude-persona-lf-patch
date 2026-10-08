-- Canonical IG materialization is the owner of the pre-Validator verified
-- handoff. Issuance uses the existing Evidence Verifier authority with real
-- snapshot/assessments/identity; no synthetic receipt and no runtime activation.
-- Preserves all previously installed Curator materialization code verbatim
-- except for one additive, fail-closed handoff step on writer strategies.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id integer, p_consumer text, p_curator_identity text, p_force_selftest boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
  v_plan jsonb;
  v_strategy text;
  v_completed bigint;
  v_version bigint;
  v_source_snapshot_sha256 text;
  v_source_manifest jsonb:='[]'::jsonb;
  v_contract_registry jsonb:='[]'::jsonb;
  v_graph jsonb;
  v_context jsonb;
  v_result jsonb;
  v_graph_build_count integer;
  v_core_contract jsonb;
  v_core_run_id bigint;
  v_core_assessment record;
  v_core_result jsonb;
  v_core_invocation_count integer:=0;
  v_semantic_registry jsonb;
  v_semantic_registry_sha text;
  v_semantic_policy jsonb;
  v_semantic_resolver text;
  v_m54_semantic_resolver_oid oid;
  v_semantic_probe jsonb;
  v_semantic_eligibility text;
  v_semantic_execution_state text;
  v_semantic_plan_count integer:=0;
  v_selector_version text;
  v_selector_manifest_sha text;
  v_freshness_count integer;
  v_handoff_receipt jsonb;
begin
  perform set_config('lf.input_request_freshness_delta_cached_v1','',true);
  perform set_config('lf.input_request_graph_build_count_v1','0',true);
  perform set_config('lf.input_request_freshness_count_v1','0',true);
  select c.version_id into v_version
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc,c.id desc limit 1;
  if v_version is null then
    raise exception 'INPUT_REQUEST_CONTEXT_VERSION_UNRESOLVED:%',p_pantalla_id;
  end if;
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);
  v_context:=jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
    'pantalla_id',p_pantalla_id,
    'version_id',v_version,
    'consumer',p_consumer,
    'request_identity',p_curator_identity,
    'strategy',null,
    'completed_run_id',null,
    'graph',v_graph,
    'graph_sha256',programacion.fn_v09_sha256_jsonb(v_graph),
    'contract_registry','[]'::jsonb,
    'source_snapshot_sha256',null,
    'source_manifest','[]'::jsonb
  );
  perform set_config('lf.input_request_context_v1',v_context::text,true);
  v_plan:=programacion.fn_input_governance_curator_plan_v1(
    p_pantalla_id,p_force_selftest,null
  );
  v_strategy:=v_plan->>'strategy';
  v_completed:=nullif(v_plan->>'completed_run_id','')::bigint;

  if v_completed is not null then
    select r.source_snapshot_sha256,coalesce(r.source_manifest,'[]'::jsonb)
      into v_source_snapshot_sha256,v_source_manifest
    from programacion.input_readiness_runs r
    where r.id=v_completed and r.pantalla_id=p_pantalla_id and r.version_id=v_version;
    if not found then
      raise exception 'INPUT_REQUEST_CONTEXT_RUN_IDENTITY_MISMATCH:%:%',p_pantalla_id,v_completed;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id',c.id,
      'contract_code',c.contrato_codigo,
      'status',c.estado,
      'fail_closed',c.fail_closed
    ) order by c.contrato_codigo,c.id),'[]'::jsonb)
    into v_contract_registry
  from programacion.contratos c
  where c.version_id=v_version
    and c.contrato_codigo in (
      'INPUT_READINESS_CONTRACT',
      'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
      'INPUT_CONTEXT_MANIFEST_CONTRACT',
      'INPUT_FRESHNESS_DELTA_CONTRACT',
      'INPUT_RETRIEVAL_HANDLE_CONTRACT',
      'INPUT_FAMILY_POLICY_REGISTRY'
    );

  v_context:=v_context || jsonb_build_object(
    'strategy',v_strategy,
    'completed_run_id',v_completed,
    'contract_registry',v_contract_registry,
    'source_snapshot_sha256',v_source_snapshot_sha256,
    'source_manifest',v_source_manifest
  );
  perform set_config('lf.input_request_context_v1',v_context::text,true);

  case v_strategy
    when 'BOOTSTRAP' then
      v_result:=programacion.fn_input_governance_bootstrap_materialize_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    when 'REBIND' then
      v_result:=programacion.fn_input_governance_curator_rebind_v1(
        p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest
      );
    when 'SOURCE_STALE_RECURATE' then
      v_result:=programacion.fn_input_governance_recurate_source_stale_v1(
        p_pantalla_id,p_consumer,p_curator_identity,v_completed
      );
    when 'FULL_RECURATE' then
      v_result:=programacion.fn_input_governance_recurate_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    when 'NOOP' then
      v_result:=jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_CURATOR_EXECUTION_V1',
        'status','NOOP_CURRENT_RUN',
        'strategy','NOOP',
        'run_id',v_completed,
        'pantalla_id',p_pantalla_id,
        'consumer',p_consumer,
        'write_performed',false,
        'strategy_plan',v_plan,
        'promotion_authorized',false,
        'production_authorized',false
      );
    when 'BLOCK' then
      v_result:=jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_CURATOR_EXECUTION_V1',
        'status','BLOCKED',
        'strategy','BLOCK',
        'blocker','CURATOR_STRATEGY_PLAN_BLOCKED',
        'pantalla_id',p_pantalla_id,
        'consumer',p_consumer,
        'write_performed',false,
        'strategy_plan',v_plan,
        'promotion_authorized',false,
        'production_authorized',false
      );
    else
      raise exception 'INPUT_GOVERNANCE_CURATOR_STRATEGY_UNSUPPORTED:%',coalesce(v_strategy,'<NULL>');
  end case;
  v_core_run_id:=nullif(v_result->>'run_id','')::bigint;
  if v_strategy in ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') then
    if v_core_run_id is null then
      raise exception 'M5_6_PERSISTENCE_PIPELINE_RUN_ID_MISSING:%',v_strategy;
    end if;
    if not exists (select 1 from programacion.input_readiness_runs r where r.id=v_core_run_id and r.pantalla_id=p_pantalla_id) then
      raise exception 'M5_6_PERSISTENCE_PIPELINE_RUN_READBACK_MISSING:%:%',v_strategy,v_core_run_id;
    end if;
    if (select count(*) from programacion.input_family_assessments a where a.run_id=v_core_run_id)=0 then
      raise exception 'M5_6_PERSISTENCE_PIPELINE_ASSESSMENTS_MISSING:%:%',v_strategy,v_core_run_id;
    end if;
    v_result:=v_result || jsonb_build_object(
      'persistence_pipeline_receipt',jsonb_build_object(
        'schema_version','INPUT_GOVERNANCE_PERSISTENCE_PIPELINE_RECEIPT_V1',
        'entrypoint','programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)',
        'strategy',v_strategy,
        'strategy_writer',case v_strategy
          when 'BOOTSTRAP' then 'programacion.fn_input_governance_bootstrap_materialize_v2(integer,text,text)'
          when 'REBIND' then 'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'
          when 'SOURCE_STALE_RECURATE' then 'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'
          when 'FULL_RECURATE' then 'programacion.fn_input_governance_recurate_v2(integer,text,text)' end,
        'run_id',v_core_run_id,
        'run_count',(select count(*) from programacion.input_readiness_runs r where r.id=v_core_run_id),
        'assessment_count',(select count(*) from programacion.input_family_assessments a where a.run_id=v_core_run_id),
        'gap_proposal_count',(select count(*) from programacion.input_gap_proposals g where g.run_id=v_core_run_id),
        'receipt_mode','RETURN_ENVELOPE_READBACK',
        'strategy_functions_fused',false,
        'promotion_authorized',false,
        'production_authorized',false
      )
    );
  end if;
  -- M7.10/EKB: the actual Core and semantic plan are now composed and SHA-bound
  -- in BEFORE INSERT. Contract 5.13 forbids post-INSERT Curator-owned mutations.
  -- NOOP reuses the previously completed run without a write.
  if v_strategy in ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') then
    select count(*),
           count(*) filter (where a.curator_evidence->'core_invocation'->>'contract'='M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'),
           count(*) filter (where a.curator_evidence->'semantic_plan'->>'contract'='M5_4_SEMANTIC_PLAN_V1')
      into v_core_invocation_count, v_semantic_plan_count, v_graph_build_count
    from programacion.input_family_assessments a
    where a.run_id=v_core_run_id;
    if v_core_invocation_count=0 or v_semantic_plan_count<>v_core_invocation_count
       or v_graph_build_count<>v_core_invocation_count then
      raise exception 'IG_PREINSERT_CORE_SEMANTIC_COMPOSITION_MISSING:run=% total=% core=% semantic=%',
        v_core_run_id,v_core_invocation_count,v_semantic_plan_count,v_graph_build_count;
    end if;
    v_result:=v_result || jsonb_build_object(
      'core_invocation',jsonb_build_object(
        'contract','M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1',
        'semantic_plan_contract','M5_4_SEMANTIC_PLAN_V1',
        'facade','programacion.fn_input_deterministic_assess',
        'assessment_count',v_core_invocation_count,
        'semantic_plan_count',v_graph_build_count,
        'composition_timing','BEFORE_IMMUTABLE_INSERT',
        'legacy_seed_removal_checkpoint','NEGATIVE_NO_CLASSIFY'
      )
    );
  end if;
  v_graph_build_count:=coalesce(nullif(current_setting('lf.input_request_graph_build_count_v1',true),'')::integer,0);
  v_freshness_count:=coalesce(nullif(current_setting('lf.input_request_freshness_count_v1',true),'')::integer,0);
  if v_graph_build_count<>1 then
    raise exception 'INPUT_REQUEST_GRAPH_BUILD_COUNT_INVALID:%:%',p_pantalla_id,v_graph_build_count;
  end if;
  if v_freshness_count>1 then
    raise exception 'INPUT_REQUEST_FRESHNESS_COUNT_INVALID:%:%',p_pantalla_id,v_freshness_count;
  end if;
  perform set_config('lf.input_request_freshness_delta_cached_v1','',true);
  perform set_config('lf.input_request_context_v1','',true);
  perform set_config('lf.input_request_graph_build_count_v1','',true);
  perform set_config('lf.input_request_freshness_count_v1','',true);
  -- Governed Curator -> Evidence Verifier -> Validator handoff (M8.8).
  -- A new/materialized run must mint and validate its exact pre-Validator
  -- receipt in the same transaction. NOOP/BLOCK must never mint one.
  if v_strategy in ('BOOTSTRAP','REBIND','SOURCE_STALE_RECURATE','FULL_RECURATE') then
    v_handoff_receipt:=programacion.fn_input_governance_curator_handoff_receipt_v1(
      v_core_run_id,p_curator_identity
    );
    if v_handoff_receipt->>'status' is distinct from 'PERSISTED'
       or nullif(v_handoff_receipt->>'receipt_id','') is null then
      raise exception 'IG_CURATOR_HANDOFF_RECEIPT_NOT_VERIFIED:%:%',
        v_core_run_id,v_strategy;
    end if;
    -- Consumer readback uses the real Evidence Verifier receipt authority;
    -- never assume that writing a receipt is the same as verifying it.
    if programacion.fn_input_governance_validator_handoff_assert_v1(
      v_core_run_id,(v_handoff_receipt->>'receipt_id')::bigint
    )->>'status' is distinct from 'VERIFIED' then
      raise exception 'IG_CURATOR_HANDOFF_VERIFIER_NOT_VERIFIED:%',v_core_run_id;
    end if;
    v_result:=v_result || jsonb_build_object(
      'curator_handoff_receipt',v_handoff_receipt
    );
  end if;
  return v_result || jsonb_build_object(
    'request_context_summary',jsonb_build_object(
      'schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
      'graph_build_count',v_graph_build_count,
      'freshness_delta_count',v_freshness_count,
      'graph_build_exactly_once',v_graph_build_count=1,
      'freshness_at_most_once',v_freshness_count<=1,
      'pantalla_id',p_pantalla_id,
      'version_id',v_version,
      'graph_sha256',v_context->>'graph_sha256',
      'context_sha256',programacion.fn_v09_sha256_jsonb(v_context)
    )
  );
exception when others then
  perform set_config('lf.input_request_freshness_delta_cached_v1','',true);
  perform set_config('lf.input_request_context_v1','',true);
  perform set_config('lf.input_request_graph_build_count_v1','',true);
  perform set_config('lf.input_request_freshness_count_v1','',true);
  raise;
end;
$function$;

do $guard$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_governance_curator_materialize_v1';
  if v_def not like '%fn_input_governance_curator_handoff_receipt_v1%'
     or v_def not like '%fn_input_governance_validator_handoff_assert_v1%'
     or v_def not like '%NOOP/BLOCK must never mint one%'
  then raise exception 'M88_CURATOR_HANDOFF_PRODUCER_NOT_BOUND'; end if;
end;
$guard$;
