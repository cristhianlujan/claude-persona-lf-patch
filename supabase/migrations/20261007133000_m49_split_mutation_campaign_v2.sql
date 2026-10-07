-- M4.9 exact mutation campaign contract + correlated-false-consensus repair.
-- Reuses the already-live per-case rollback harness:
--   programacion.fn_engineering_ig_validator_mutation_case_v2(p_case,p_pantalla_id)
-- The systemic runtime repair is independent of M4.9:
-- successor validation must rebind the parent's frozen assertions instead of setting expected=current actual.

do $patch_validate_v2$
declare
  v_def text;
  v_new text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure
  );

  if position(
    'v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text;'
    in v_def
  )=0 then
    raise exception 'M49_VALIDATE_V2_DECLARATION_ANCHOR_MISSING';
  end if;
  if position(
    'select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision'
    in v_def
  )=0 then
    raise exception 'M49_VALIDATE_V2_RUN_SELECT_ANCHOR_MISSING';
  end if;
  if position(
    'into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision'
    in v_def
  )=0 then
    raise exception 'M49_VALIDATE_V2_RUN_INTO_ANCHOR_MISSING';
  end if;
  if position(
    'v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code);'
    in v_def
  )=0 then
    raise exception 'M49_VALIDATE_V2_ASSERTION_BUILDER_ANCHOR_MISSING';
  end if;

  v_new:=replace(
    v_def,
    'v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text;',
    'v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text; v_parent bigint;'
  );
  v_new:=replace(
    v_new,
    'select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision',
    'select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision,supersedes_run_id'
  );
  v_new:=replace(
    v_new,
    'into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision',
    'into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision,v_parent'
  );
  v_new:=replace(
    v_new,
    'v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code);',
    'v_assertions:=case when v_parent is not null then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code) else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code) end;'
  );

  if v_new=v_def then
    raise exception 'M49_VALIDATE_V2_PATCH_NO_CHANGE';
  end if;

  execute v_new;
end;
$patch_validate_v2$;

-- Tighten the existing per-case harness: T10 may pass only for a semantic
-- frozen-parent/oracle rejection, never for an arbitrary technical exception.
do $patch_case_v2$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)'::regprocedure
  );

  v_old:=
'if v_technical_error is not null then
        v_detected:=true;
        v_detection_surface:=''CANONICAL_VALIDATOR_EXCEPTION'';
      else';

  if position(v_old in v_def)=0 then
    raise exception 'M49_CASE_V2_T10_EXCEPTION_ANCHOR_MISSING';
  end if;

  v_new:=replace(
    v_def,
    v_old,
'if v_technical_error is not null then
        v_detected:=(
          v_technical_error like ''%V58_REBOUND_ASSERTION_FAILED%''
          or v_technical_error like ''%VALIDATOR_ASSERTION_FAILED%''
          or v_technical_error like ''%SOURCE_SNAPSHOT_STALE%''
        );
        v_detection_surface:=case
          when v_detected then ''FROZEN_PARENT_ORACLE_REJECTION''
          else ''UNEXPECTED_TECHNICAL_ERROR''
        end;
      else'
  );

  execute v_new;
end;
$patch_case_v2$;

-- Canonical exact case set for M4.9 / RUN_CAMPAIGN.
insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
select
  'INPUT_GOVERNANCE_REGRESSION',
  'M4_9_T'||lpad(v.ord::text,2,'0')||'_'||v.mutation_code,
  49000+v.ord,
  array[]::text[],
  'M4.9 mutation T'||v.ord::text||' — '||v.mutation_code,
  'NEGATIVE','AUTOMATED','HIGH',
  jsonb_build_array(
    'M4.2 single Validator entrypoint live',
    'fixture rollback required'
  ),
  jsonb_build_object(
    'fixture_kind','VALIDATOR_MUTATION_CASE_V2',
    'mutation_code',v.mutation_code,
    'source_case_code',v.source_case,
    'rollback_only',true
  ),
  jsonb_build_object(
    'decision','DETECTED_FAIL_CLOSED',
    'known_mutation_detected',true,
    'false_pass',false
  ),
  jsonb_build_object(
    'false_pass',true,
    'durable_fixture_residue',true,
    'unexpected_technical_error_as_detection',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'unit_code','M4.9',
    'work_code','PAULO-063',
    'checkpoint_code','RUN_CAMPAIGN',
    'campaign_ordinal',v.ord,
    'canonical_validator_entrypoint','programacion.fn_input_governance_validator_validate_v1',
    'case_entrypoint','programacion.fn_engineering_ig_validator_mutation_case_v2',
    'source_case_code',v.source_case
  ),
  'EXEC-M49-CAMPAIGN-V2-20261007',
  'EXEC-M49-CAMPAIGN-V2-20261007'
from (values
  (1,'MISSING_SOURCE','M7_3_NEG_001_MISSING_SOURCE'),
  (2,'CONTRADICTORY_SOURCE','M7_3_NEG_002_CONTRADICTORY_SOURCE'),
  (3,'BROKEN_ID','M7_3_NEG_003_BROKEN_ID'),
  (4,'INVENTED_URL','M7_3_NEG_004_INVENTED_URL'),
  (5,'TIMEOUT_WITHOUT_SOURCE','M7_3_NEG_005_TIMEOUT_WITHOUT_SOURCE'),
  (6,'UNJUSTIFIED_NOT_APPLICABLE','M7_3_NEG_006_UNJUSTIFIED_NOT_APPLICABLE'),
  (7,'STALE_EVIDENCE','M7_3_NEG_007_STALE_EVIDENCE'),
  (8,'HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE','M7_3_NEG_008_HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE'),
  (9,'SELF_AUTHORITY','M7_3_NEG_009_SELF_AUTHORITY'),
  (10,'CORRELATED_CURATOR_RESOLVER_DEFECT',null)
) v(ord,mutation_code,source_case)
on conflict (suite_code,test_code) do update set
  test_order=excluded.test_order,
  title=excluded.title,
  input_payload=excluded.input_payload,
  expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,
  metadata=excluded.metadata,
  status=excluded.status,
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

-- Compile the exact case set into the current checkpoint contract.
update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  coalesce(pu.unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'RUN_CAMPAIGN',
    coalesce(pu.unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN}','{}'::jsonb)
    || jsonb_build_object(
      'status','READY',
      'precision','EXACT_M4_9_VALIDATOR_MUTATION_CAMPAIGN_V2',
      'handler_requirement',null,
      'test_execution_contract',jsonb_build_object(
        'mode','EXACT_CASE_SET',
        'test_code','ENG_M4_9_RUN_CAMPAIGN',
        'case_entrypoint','programacion.fn_engineering_ig_validator_mutation_case_v2(integer,integer)',
        'canonical_validator_entrypoint','programacion.fn_input_governance_validator_validate_v1(bigint,text)',
        'case_codes',(
          select jsonb_agg(c.test_code order by c.test_order)
          from public.lf_test_suite_cases c
          where c.suite_code='INPUT_GOVERNANCE_REGRESSION'
            and c.metadata->>'unit_code'='M4.9'
            and c.metadata->>'checkpoint_code'='RUN_CAMPAIGN'
        ),
        'expected_outcome','10_OF_10_DETECTED_FAIL_CLOSED',
        'persistence_entrypoint','programacion.fn_engineering_run_test_persist_v1',
        'rollback_only_fixtures',true,
        'synthetic_pass','FORBIDDEN',
        'fallback_case_discovery','FORBIDDEN'
      )
    )
  ),
  true
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code='M4.9'
  and pu.disposition='ASSIGNED';

select programacion.fn_engineering_blocker_resolve_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2',
  'M4.9',
  'M4_9_RUN_CAMPAIGN_EXACT_TEST_CONTRACT_MISSING',
  'supabase://programacion.fn_engineering_ig_validator_mutation_case_v2+public.lf_test_suite_cases/M4.9/RUN_CAMPAIGN',
  'EXEC-M49-CAMPAIGN-V2-20261007'
);

-- Mechanical proof of the defect repair. This case rolls back all of its own
-- runtime/source mutations, but the validator repair remains in the outer migration.
do $t10$
declare
  r jsonb;
begin
  r:=programacion.fn_engineering_ig_validator_mutation_case_v2(10,54);
  if r->>'status'<>'PASS'
     or coalesce((r->>'detected')::boolean,false) is not true
     or coalesce((r->>'false_pass')::boolean,true) is not false
     or coalesce((r->>'rollback_clean')::boolean,false) is not true
     or coalesce(r->>'technical_error','') not like '%V58_REBOUND_ASSERTION_FAILED%' then
    raise exception 'M49_T10_REPAIR_PROOF_FAILED:%',r;
  end if;
end;
$t10$;

do $post$
declare
  v_cases integer;
  v_spec jsonb;
  v_def text;
begin
  select count(*) into v_cases
  from public.lf_test_suite_cases c
  where c.suite_code='INPUT_GOVERNANCE_REGRESSION'
    and c.metadata->>'unit_code'='M4.9'
    and c.metadata->>'checkpoint_code'='RUN_CAMPAIGN';
  if v_cases<>10 then
    raise exception 'M49_EXACT_CASE_COUNT_INVALID:%',v_cases;
  end if;

  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure
  );
  if position(
    'fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)'
    in v_def
  )=0 then
    raise exception 'M49_FROZEN_PARENT_ORACLE_NOT_ACTIVE';
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9','RUN_CAMPAIGN'
  );
  if v_spec->>'status'<>'READY'
     or jsonb_array_length(
          coalesce(v_spec#>'{test_execution_contract,case_codes}','[]'::jsonb)
        )<>10 then
    raise exception 'M49_RUN_CAMPAIGN_SPEC_NOT_EXACT:%',v_spec;
  end if;
end;
$post$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-VALIDATOR-CORRELATED-FALSE-CONSENSUS-001',
  'INPUT_GOVERNANCE',
  'Successor Validator must not derive expected values from the same mutated current resolver as Curator',
  'T10 proved a real false consensus: a canonical-graph defect introduced before Curator was observed identically by Curator and resolver, and validate_v2 returned PASS for the affected family.',
  'Successor validate_v2 used fn_input_governance_bootstrap_assertions_v1, whose common path derives expected from current actual. A shared current-source defect therefore contaminated both candidate and oracle.',
  'SUCCESSOR_RUN -> FROZEN_PARENT_ASSERTIONS -> REBIND_CURRENT_ACTUAL -> FAIL_CLOSED_ON_DIVERGENCE',
  'When supersedes_run_id is present, validate_v2 must use fn_input_v58_build_assertions(new_run,parent_run,family). Bootstrap assertions remain only for runs without a predecessor. Mutation campaigns must use the canonical M4.2 Validator entrypoint.',
  'PASS when M4.9 T10 changes the canonical graph before Curator, Curator and classifier share the defect, the canonical Validator rejects via V58_REBOUND_ASSERTION_FAILED, false_pass=false, and rollback_clean=true.',
  'CRITICAL',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_governance_validate_v2+programacion.fn_engineering_ig_validator_mutation_case_v2/T10',
  'VALIDATION',
  array['INPUT_VALIDATOR','ENGINEERING_EXECUTOR']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.9 T10 correlated Curator/resolver mutation',
  'supabase://programacion.fn_input_governance_validate_v2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
