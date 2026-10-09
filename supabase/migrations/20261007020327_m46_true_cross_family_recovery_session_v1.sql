-- M4.6 true cross-family contradiction V1.
-- Extends the existing semantic-coherence guard; no parallel validator/evaluator.
-- Pair: MFA_OTP_SSO <-> SESSION on RECOVERY_OTP_VERIFY.
-- Canonical policy: recovery_otp_operational_session_creation = DENY.

do $pre$
declare
  v_def text;
  v_policy text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure
  );
  if position('V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE' in v_def)=0 then
    raise exception 'M46_XF_SEMANTIC_GUARD_EXPECTED_ANCHOR_MISSING';
  end if;
  if position('V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION' in v_def)>0 then
    raise exception 'M46_XF_RULE_ALREADY_PRESENT';
  end if;

  select especificacion#>>'{semantic_depth_contract,recovery_otp_operational_session_creation}'
    into v_policy
  from programacion.contratos
  where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_policy is distinct from 'DENY' then
    raise exception 'M46_XF_RECOVERY_SESSION_POLICY_NOT_DENY:%',coalesce(v_policy,'<NULL>');
  end if;

  if exists (
    select 1
    from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and (
        test_code in (
          'M46_XF_POS_RECOVERY_OTP_SESSION_DENY',
          'M46_XF_NEG_RECOVERY_OTP_SESSION_APPLICABLE'
        )
        or test_order in (460011,460012)
      )
  ) then
    raise exception 'M46_XF_TEST_CASE_ID_OR_ORDER_ALREADY_USED';
  end if;
end;
$pre$;

create or replace function programacion.fn_guard_input_validator_semantic_coherence_v512()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_logical_validator_evidence jsonb;
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_assertion jsonb;
  v_eval jsonb;
  v_positive_requirement boolean := false;
  v_na_authority jsonb;
  v_blocker jsonb;
  v_false_missing boolean := false;
  v_graph jsonb;
  v_rules jsonb;
  v_otp_present boolean := false;
  v_a11y_core_complete boolean := false;
  v_capability_profile text;
  v_recovery_session_policy text;
  v_session_applicability text;
  v_session_na_authority jsonb;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;

  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);

  select contract_revision,version_id,pantalla_id
    into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs
  where id=old.run_id;

  if (v_revision is null or v_revision not in ('5.12','5.13','5.13.1')) then
    return new;
  end if;

  -- M4.6 true cross-family rule.
  -- Recovery OTP verification may use the MFA/OTP policy family, but it must not
  -- create an operational SESSION. The SESSION family must remain positively N/A.
  if new.validator_outcome='PASS'
     and v_revision='5.13.1'
     and old.family_code in ('MFA_OTP_SSO','SESSION') then

    v_capability_profile:=programacion.fn_input_security_capability_profile(v_pantalla_id)->>'profile';

    if v_capability_profile='RECOVERY_OTP_VERIFY' then
      select c.especificacion#>>'{semantic_depth_contract,recovery_otp_operational_session_creation}'
        into v_recovery_session_policy
      from programacion.contratos c
      where c.version_id=v_version_id
        and c.contrato_codigo='INPUT_READINESS_CONTRACT';

      if v_recovery_session_policy is distinct from 'DENY' then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_POLICY_UNRESOLVED:%:policy=%',
          v_pantalla_id,coalesce(v_recovery_session_policy,'<NULL>');
      end if;

      v_session_na_authority:=
        programacion.fn_input_na_positive_authority_v512(
          'SESSION',v_pantalla_id,v_version_id
        );

      if coalesce((v_session_na_authority->>'qualified')::boolean,false) is not true then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_EXCLUSION_AUTHORITY_MISSING:%',
          v_pantalla_id;
      end if;

      select a.applicability
        into v_session_applicability
      from programacion.input_family_assessments a
      where a.run_id=old.run_id
        and a.family_code='SESSION';

      if v_session_applicability is null then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_ASSESSMENT_MISSING:%:run=%',
          v_pantalla_id,old.run_id;
      end if;

      if v_session_applicability<>'NOT_APPLICABLE' then
        raise exception
          'V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION:%:left=MFA_OTP_SSO:right=SESSION:session_applicability=%',
          v_pantalla_id,v_session_applicability;
      end if;
    end if;
  end if;

  if jsonb_typeof(v_logical_validator_evidence->'assertions')='array' then
    for v_assertion in
      select value from jsonb_array_elements(v_logical_validator_evidence->'assertions')
    loop
      if coalesce(v_assertion->>'operator','')='CONTAINS'
         and jsonb_typeof(v_assertion->'expected')='array'
         and jsonb_array_length(v_assertion->'expected')>0
         and coalesce(v_assertion->'source_ref'->>'kind','')
             in ('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET') then
        v_eval:=programacion.fn_input_evaluate_assertion(
          old.run_id,old.family_code,v_assertion
        );
        if coalesce((v_eval->>'passed')::boolean,false) is true then
          v_positive_requirement:=true;
        end if;
      end if;
    end loop;
  end if;

  if new.validator_outcome='PASS' and old.applicability='NOT_APPLICABLE' then
    v_na_authority:=programacion.fn_input_na_positive_authority_v512(
      old.family_code,v_pantalla_id,v_version_id
    );
    if coalesce((v_na_authority->>'qualified')::boolean,false) is not true then
      raise exception 'V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION:%:%',
        v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement then
    if old.family_code in ('REDUCED_MOTION','FORCED_COLORS_CONTRAST') then
      if old.applicability<>'APPLICABLE'
         or old.coverage_status<>'COMPLETE'
         or old.well_defined_status<>'COMPLETE' then
        raise exception
          'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH:%:% expected=APPLICABLE/COMPLETE/COMPLETE actual=%/%/%',
          v_pantalla_id,old.family_code,old.applicability,
          old.coverage_status,old.well_defined_status;
      end if;
    elsif old.family_code='THEME_LIGHT_DARK_SYSTEM' then
      if old.applicability<>'APPLICABLE'
         or old.coverage_status not in ('PARTIAL','COMPLETE')
         or old.well_defined_status not in ('PARTIAL','COMPLETE') then
        raise exception
          'V512_VALIDATOR_THEME_SEMANTICS_MISMATCH:% actual=%/%/%',
          v_pantalla_id,old.applicability,old.coverage_status,
          old.well_defined_status;
      end if;
    end if;

    for v_blocker in
      select value from jsonb_array_elements(coalesce(old.blockers,'[]'::jsonb))
    loop
      if (old.family_code='REDUCED_MOTION'
          and v_blocker->>'code'='REDUCED_MOTION_REQUIREMENT_MISSING')
         or (old.family_code='FORCED_COLORS_CONTRAST'
             and v_blocker->>'code'='FORCED_COLORS_REQUIREMENT_MISSING')
         or (old.family_code='THEME_LIGHT_DARK_SYSTEM'
             and v_blocker->>'code'='THEME_REQUIREMENTS_NOT_LINKED') then
        v_false_missing:=true;
      end if;
    end loop;

    if v_false_missing then
      raise exception
        'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%:%',
        v_pantalla_id,old.family_code;
    end if;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(
    v_pantalla_id,v_version_id
  );
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  if new.validator_outcome='PASS' and old.family_code='ACCESSIBILITY' then
    select count(distinct r->>'rule_code')=4
      into v_a11y_core_complete
    from jsonb_array_elements(v_rules) r
    where r->>'rule_code' in (
      'B2B-RULE-A11Y-001','B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003','B2B-RULE-A11Y-004'
    );

    if v_a11y_core_complete
       and (old.coverage_status<>'COMPLETE'
            or old.well_defined_status<>'COMPLETE') then
      raise exception
        'V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE:%',
        v_pantalla_id;
    end if;
  end if;

  if new.validator_outcome='PASS' and old.family_code='MFA_OTP_SSO' then
    select exists(
      select 1
      from jsonb_array_elements(v_rules) r
      where (r->'config' ? 'otp_operation_id')
         or (r->'config' ? 'otp_policy_id')
         or (r->'config' ? 'email_otp_policy_code')
    ) into v_otp_present;

    if v_otp_present and old.applicability='NOT_APPLICABLE' then
      raise exception
        'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE:%',
        v_pantalla_id;
    end if;
  end if;

  return new;
end;
$function$;

insert into public.lf_assurance_defeater_catalog(
  defeater_code,version,claim_code,claim_version,obligation_code,
  defeater_class,description,required_counterevidence,
  zero_effect_required,status,source_ref,created_by_execution_id
)
values (
  'IG-D-RECOVERY-OTP-OPERATIONAL-SESSION-CROSS-FAMILY-V1',
  1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',
  1,
  'IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
  'SILENT_MATERIAL_GAP',
  'RECOVERY_OTP_VERIFY must not create an operational SESSION: MFA_OTP_SSO may apply to OTP policy while SESSION must remain positively NOT_APPLICABLE.',
  jsonb_build_object(
    'dimension','CROSS_FAMILY_COHERENCE',
    'pair',jsonb_build_array('MFA_OTP_SSO','SESSION'),
    'profile','RECOVERY_OTP_VERIFY',
    'authority_rule','B2B-RULE-AUTH-037',
    'contract_path','semantic_depth_contract.recovery_otp_operational_session_creation',
    'contract_expected','DENY',
    'expected_pair_state',jsonb_build_object(
      'MFA_OTP_SSO','APPLICABLE',
      'SESSION','NOT_APPLICABLE'
    ),
    'typed_finding','V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION'
  ),
  true,
  'CANDIDATO',
  'supabase://programacion.contratos/37#semantic_depth_contract.recovery_otp_operational_session_creation',
  'CHATGPT-IG-M46-XF-RECOVERY-SESSION-20261007'
)
on conflict (defeater_code,version) do update set
  description=excluded.description,
  required_counterevidence=excluded.required_counterevidence,
  zero_effect_required=excluded.zero_effect_required,
  source_ref=excluded.source_ref;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
values
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_XF_POS_RECOVERY_OTP_SESSION_DENY',
  460011,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 cross-family positive — recovery OTP does not create operational session',
  'POSITIVE','AUTOMATED','HIGH',
  jsonb_build_array(
    'pantalla_id=56 resolves RECOVERY_OTP_VERIFY through B2B-RULE-AUTH-037',
    'contract 5.13.1 policy recovery_otp_operational_session_creation=DENY',
    'MFA_OTP_SSO=APPLICABLE and SESSION=NOT_APPLICABLE'
  ),
  jsonb_build_object(
    'schema_version','M46_TRUE_CROSS_FAMILY_PAIR_V1',
    'pair',jsonb_build_array('MFA_OTP_SSO','SESSION'),
    'polarity','POSITIVE',
    'pantalla_id',56,
    'profile','RECOVERY_OTP_VERIFY',
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','PAIR_ACCEPTED',
    'typed_finding',null
  ),
  jsonb_build_object(
    'false_reject',true,
    'persistent_fixture_mutation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','NEG_CONTRADICTION',
    'q_class','Q4',
    'dimension','CROSS_FAMILY_COHERENCE',
    'defeater_code','IG-D-RECOVERY-OTP-OPERATIONAL-SESSION-CROSS-FAMILY-V1',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_recovery_otp_session_pair_v1.sql'
  ),
  'CHATGPT-IG-M46-XF-RECOVERY-SESSION-20261007',
  'CHATGPT-IG-M46-XF-RECOVERY-SESSION-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_XF_NEG_RECOVERY_OTP_SESSION_APPLICABLE',
  460012,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 cross-family negative — recovery OTP incorrectly creates operational session',
  'NEGATIVE','AUTOMATED','HIGH',
  jsonb_build_array(
    'pantalla_id=56 resolves RECOVERY_OTP_VERIFY through B2B-RULE-AUTH-037',
    'contract 5.13.1 policy recovery_otp_operational_session_creation=DENY',
    'mutate only SESSION sibling to APPLICABLE/PARTIAL inside rollback'
  ),
  jsonb_build_object(
    'schema_version','M46_TRUE_CROSS_FAMILY_PAIR_V1',
    'pair',jsonb_build_array('MFA_OTP_SSO','SESSION'),
    'polarity','NEGATIVE',
    'pantalla_id',56,
    'profile','RECOVERY_OTP_VERIFY',
    'mutation','SESSION_NOT_APPLICABLE_TO_APPLICABLE',
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','REJECT_MUTATION_FAIL_CLOSED',
    'typed_finding','V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION'
  ),
  jsonb_build_object(
    'false_pass',true,
    'untyped_failure',true,
    'persistent_fixture_mutation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','NEG_CONTRADICTION',
    'q_class','Q4',
    'dimension','CROSS_FAMILY_COHERENCE',
    'm7_3_reference_test','M7_3_NEG_064_RECOVERY_OTP_CREATES_OPERATIONAL_SESSION',
    'defeater_code','IG-D-RECOVERY-OTP-OPERATIONAL-SESSION-CROSS-FAMILY-V1',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_recovery_otp_session_pair_v1.sql'
  ),
  'CHATGPT-IG-M46-XF-RECOVERY-SESSION-20261007',
  'CHATGPT-IG-M46-XF-RECOVERY-SESSION-20261007'
);

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'NEG_CONTRADICTION',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','NEG_CONTRADICTION',
      'checkpoint_title','Negativo: par de familias contradictorio produce FAIL con finding tipado',
      'action_kind','DECLARED_TEST_EXECUTION',
      'recipe_mode','RUN_EXACT_TEST_SET',
      'precision','EXPLICIT_M46_TRUE_CROSS_FAMILY_PAIR_V1',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',true,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Execute the exact MFA_OTP_SSO <-> SESSION recovery-OTP pair. Canonical pair must be accepted; contradictory SESSION=APPLICABLE must be rejected with typed finding V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'programacion.fn_guard_input_validator_semantic_coherence_v512',
          'public.lf_assurance_defeater_catalog',
          'public.lf_test_suite_cases'
        ),
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_cross_family/m46_recovery_otp_session_pair_v1.sql',
            'role','TEST_HARNESS_EVIDENCE'
          )
        ),
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'test_case_codes',jsonb_build_array(
        'M46_XF_POS_RECOVERY_OTP_SESSION_DENY',
        'M46_XF_NEG_RECOVERY_OTP_SESSION_APPLICABLE'
      ),
      'test_case_set_sha256',programacion.fn_v09_sha256_jsonb(
        jsonb_build_array(
          'M46_XF_POS_RECOVERY_OTP_SESSION_DENY',
          'M46_XF_NEG_RECOVERY_OTP_SESSION_APPLICABLE'
        )
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'tests_total',2,
          'tests_passed',2,
          'tests_failed',0,
          'tests_blocked',0,
          'tests_review_required',0,
          'receipt_bundle_status','VERIFIED',
          'negative_typed_finding','V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION'
        )
      ),
      'verification_queries',jsonb_build_array(
$q$
select
  count(*)=2 as case_count_exact,
  count(*) filter(where test_type='POSITIVE')=1 as positive_count_exact,
  count(*) filter(where test_type='NEGATIVE')=1 as negative_count_exact,
  bool_and(metadata->>'q_class'='Q4') as q4_exact,
  bool_and(metadata->>'dimension'='CROSS_FAMILY_COHERENCE') as cross_family_exact
from public.lf_test_suite_cases
where suite_code='INPUT_GOVERNANCE_REGRESSION'
  and metadata->>'unit_code'='M4.6'
  and metadata->>'checkpoint_code'='NEG_CONTRADICTION'
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'CREATE_PARALLEL_VALIDATOR',
        'CREATE_PARALLEL_ASSURANCE_ENGINE',
        'ACTIVATE_ASSURANCE_EVALUATOR',
        'EXECUTE_FOREIGN_UNIT_TEST_CASES',
        'PERSIST_FIXTURE_MUTATIONS',
        'UNTYPED_NEGATIVE_FAILURE',
        'SYNTHETIC_PASS'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.6'
  and disposition='ASSIGNED';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-M46-TRUE-CROSS-FAMILY-RECOVERY-SESSION-001',
  'INPUT_GOVERNANCE',
  'M4.6 requires true family-to-family contradiction coverage, not only family-to-source coherence',
  'The first M4.6 semantic-coherence cases exercised family-vs-source candidate contradictions. The canonical plan, M7.3 Q4 catalog and contract 5.13.1 additionally require true cross-family coherence. The first governed pair is MFA_OTP_SSO <-> SESSION for RECOVERY_OTP_VERIFY: operational SESSION creation is DENY and SESSION must remain positively NOT_APPLICABLE.',
  'M4.6 checkpoint wording was broader than the initial detector cases and the source pack did not enumerate the concrete pair. The existing contract and M7.3 Q4 catalog contained the missing authority.',
  'CROSS_FAMILY_CHECKPOINT_SATISFIED_BY_INTRA_FAMILY_SOURCE_CONTRADICTION',
  'For M4.6, resolve cross-family rules from the canonical contract plus owned Q4 catalog before closing. Extend the existing semantic-coherence guard instead of creating a second validator. Each governed pair must have a CANDIDATO defeater plus owned positive/negative cases with typed finding.',
  'PASS when RECOVERY_OTP_VERIFY with canonical MFA_OTP_SSO=APPLICABLE and SESSION=NOT_APPLICABLE is accepted, SESSION=APPLICABLE is rejected with V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION, both cases are owned by M4.6/NEG_CONTRADICTION, suite receipt is VERIFIED, and no domain fixture survives rollback.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.contratos/37#semantic_depth_contract.recovery_otp_operational_session_creation; supabase://public.lf_test_suite_cases/M7_3_NEG_064_RECOVERY_OTP_CREATES_OPERATIONAL_SESSION',
  'EXECUTION',
  array['INPUT_VALIDATOR','ASSURANCE_EVALUATOR']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.6 NEG_CONTRADICTION',
  'supabase://programacion.fn_guard_input_validator_semantic_coherence_v512'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

do $post$
declare
  v_def text;
begin
  v_def:=pg_get_functiondef(
    'programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure
  );
  if position('V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION' in v_def)=0 then
    raise exception 'M46_XF_RULE_POSTCHECK_MISSING';
  end if;

  if not exists (
    select 1
    from public.lf_assurance_defeater_catalog
    where defeater_code='IG-D-RECOVERY-OTP-OPERATIONAL-SESSION-CROSS-FAMILY-V1'
      and version=1
      and status='CANDIDATO'
      and obligation_code='IG-C5_13-SEMANTIC_COHERENCE_CONTRACT'
  ) then
    raise exception 'M46_XF_DEFEATER_POSTCHECK_MISSING';
  end if;
end;
$post$;
