-- M4.6 DEFEATER_RULES_IG
-- Register the five existing Input Governance semantic-coherence contradictions
-- as inert CANDIDATO defeaters under the canonical assurance claim/obligation.
-- No ACTIVE binding, no evaluator activation, no production effect.

do $pre$
begin
  if not exists (
    select 1
    from public.lf_assurance_claim_catalog
    where claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      and version=1
      and status='CANDIDATO'
  ) then
    raise exception 'M46_ASSURANCE_CLAIM_MISSING_OR_NOT_CANDIDATE';
  end if;

  if not exists (
    select 1
    from public.lf_assurance_obligation_catalog
    where obligation_code='IG-C5_13-SEMANTIC_COHERENCE_CONTRACT'
      and version=1
      and claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      and claim_version=1
      and status='CANDIDATO'
  ) then
    raise exception 'M46_SEMANTIC_COHERENCE_OBLIGATION_MISSING_OR_NOT_CANDIDATE';
  end if;

  if to_regprocedure('programacion.fn_guard_input_validator_semantic_coherence_v512()') is null then
    raise exception 'M46_EXISTING_SEMANTIC_GUARD_MISSING';
  end if;
end;
$pre$;

insert into public.lf_assurance_defeater_catalog
(
  defeater_code,version,claim_code,claim_version,obligation_code,
  defeater_class,description,required_counterevidence,
  zero_effect_required,status,source_ref,created_by_execution_id
)
values
(
  'IG-D-REDUCED-MOTION-SOURCE-CANDIDATE-MISMATCH-V1',1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',1,
  'IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
  'SILENT_MATERIAL_GAP',
  'REDUCED_MOTION cannot PASS when canonical positive requirement evidence exists but applicability/coverage/well-defined semantics or missing-blocker state contradict that evidence.',
  jsonb_build_object(
    'family_code','REDUCED_MOTION',
    'positive_requirement_sources',jsonb_build_array('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET'),
    'when_positive_requirement_true',jsonb_build_object(
      'applicability','APPLICABLE',
      'coverage_status','COMPLETE',
      'well_defined_status','COMPLETE',
      'forbidden_blocker_code','REDUCED_MOTION_REQUIREMENT_MISSING'
    ),
    'guard_error_codes',jsonb_build_array(
      'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH',
      'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE'
    )
  ),
  true,'CANDIDATO',
  'supabase://programacion.fn_guard_input_validator_semantic_coherence_v512#REDUCED_MOTION',
  'CHATGPT-IG-M46-DEFEATERS-20261007'
),
(
  'IG-D-FORCED-COLORS-SOURCE-CANDIDATE-MISMATCH-V1',1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',1,
  'IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
  'SILENT_MATERIAL_GAP',
  'FORCED_COLORS_CONTRAST cannot PASS when canonical positive requirement evidence exists but applicability/coverage/well-defined semantics or missing-blocker state contradict that evidence.',
  jsonb_build_object(
    'family_code','FORCED_COLORS_CONTRAST',
    'positive_requirement_sources',jsonb_build_array('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET'),
    'when_positive_requirement_true',jsonb_build_object(
      'applicability','APPLICABLE',
      'coverage_status','COMPLETE',
      'well_defined_status','COMPLETE',
      'forbidden_blocker_code','FORCED_COLORS_REQUIREMENT_MISSING'
    ),
    'guard_error_codes',jsonb_build_array(
      'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH',
      'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE'
    )
  ),
  true,'CANDIDATO',
  'supabase://programacion.fn_guard_input_validator_semantic_coherence_v512#FORCED_COLORS_CONTRAST',
  'CHATGPT-IG-M46-DEFEATERS-20261007'
),
(
  'IG-D-THEME-SOURCE-CANDIDATE-MISMATCH-V1',1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',1,
  'IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
  'SILENT_MATERIAL_GAP',
  'THEME_LIGHT_DARK_SYSTEM cannot PASS when canonical positive requirement evidence exists but applicability/coverage/well-defined semantics or missing-blocker state contradict that evidence.',
  jsonb_build_object(
    'family_code','THEME_LIGHT_DARK_SYSTEM',
    'positive_requirement_sources',jsonb_build_array('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET'),
    'when_positive_requirement_true',jsonb_build_object(
      'applicability','APPLICABLE',
      'coverage_status_allowed',jsonb_build_array('PARTIAL','COMPLETE'),
      'well_defined_status_allowed',jsonb_build_array('PARTIAL','COMPLETE'),
      'forbidden_blocker_code','THEME_REQUIREMENTS_NOT_LINKED'
    ),
    'guard_error_codes',jsonb_build_array(
      'V512_VALIDATOR_THEME_SEMANTICS_MISMATCH',
      'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE'
    )
  ),
  true,'CANDIDATO',
  'supabase://programacion.fn_guard_input_validator_semantic_coherence_v512#THEME_LIGHT_DARK_SYSTEM',
  'CHATGPT-IG-M46-DEFEATERS-20261007'
),
(
  'IG-D-ACCESSIBILITY-CORE-INCOMPLETE-V1',1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',1,
  'IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
  'SILENT_MATERIAL_GAP',
  'ACCESSIBILITY cannot PASS as incomplete when all four canonical accessibility core rules are present.',
  jsonb_build_object(
    'family_code','ACCESSIBILITY',
    'required_rule_codes',jsonb_build_array(
      'B2B-RULE-A11Y-001','B2B-RULE-A11Y-002','B2B-RULE-A11Y-003','B2B-RULE-A11Y-004'
    ),
    'when_all_rules_present',jsonb_build_object(
      'coverage_status','COMPLETE',
      'well_defined_status','COMPLETE'
    ),
    'guard_error_codes',jsonb_build_array(
      'V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE'
    )
  ),
  true,'CANDIDATO',
  'supabase://programacion.fn_guard_input_validator_semantic_coherence_v512#ACCESSIBILITY',
  'CHATGPT-IG-M46-DEFEATERS-20261007'
),
(
  'IG-D-MFA-OTP-PRESENT-NOT-APPLICABLE-V1',1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',1,
  'IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
  'SILENT_MATERIAL_GAP',
  'MFA_OTP_SSO cannot PASS as NOT_APPLICABLE when canonical rules expose OTP operation/policy configuration.',
  jsonb_build_object(
    'family_code','MFA_OTP_SSO',
    'otp_signal_keys',jsonb_build_array(
      'otp_operation_id','otp_policy_id','email_otp_policy_code'
    ),
    'when_otp_signal_present',jsonb_build_object(
      'forbidden_applicability','NOT_APPLICABLE'
    ),
    'guard_error_codes',jsonb_build_array(
      'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE'
    )
  ),
  true,'CANDIDATO',
  'supabase://programacion.fn_guard_input_validator_semantic_coherence_v512#MFA_OTP_SSO',
  'CHATGPT-IG-M46-DEFEATERS-20261007'
)
on conflict (defeater_code,version) do nothing;

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'DEFEATER_RULES_IG',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','DEFEATER_RULES_IG',
      'checkpoint_title','Reglas cross-family de IG registradas como defeaters (formato Super Admin), sin motor propio',
      'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
      'recipe_mode','GIT_FIRST_OR_VERSIONED_CONTRACT',
      'precision','EXPLICIT_M46_CROSS_FAMILY_DEFEATERS_V1',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',true,
      'mutation_policy','ONLY_DECLARED_TARGETS',
      'expected','Exactly five Input Governance semantic-coherence defeaters are registered as CANDIDATO under the existing INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1 claim and IG-C5_13-SEMANTIC_COHERENCE_CONTRACT obligation. No ACTIVE binding or new evaluator is created.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_assurance_defeater_catalog',
          'programacion.fn_guard_input_validator_semantic_coherence_v512'
        ),
        'declared_artifacts','[]'::jsonb,
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'mutation_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007011500_m46_cross_family_defeaters_v1.sql',
            'role','GIT_FIRST_MIGRATION'
          )
        )
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'defeater_count_exact',true,
          'all_candidate',true,
          'claim_binding_exact',true,
          'obligation_binding_exact',true,
          'all_zero_effect_required',true,
          'no_active_ig_defeater',true
        )
      ),
      'verification_queries',jsonb_build_array(
$q$
select
  count(*)=5 as defeater_count_exact,
  bool_and(status='CANDIDATO') as all_candidate,
  bool_and(claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1' and claim_version=1) as claim_binding_exact,
  bool_and(obligation_code='IG-C5_13-SEMANTIC_COHERENCE_CONTRACT') as obligation_binding_exact,
  bool_and(zero_effect_required) as all_zero_effect_required,
  count(*) filter(where status='ACTIVE')=0 as no_active_ig_defeater
from public.lf_assurance_defeater_catalog
where version=1
  and defeater_code in (
    'IG-D-REDUCED-MOTION-SOURCE-CANDIDATE-MISMATCH-V1',
    'IG-D-FORCED-COLORS-SOURCE-CANDIDATE-MISMATCH-V1',
    'IG-D-THEME-SOURCE-CANDIDATE-MISMATCH-V1',
    'IG-D-ACCESSIBILITY-CORE-INCOMPLETE-V1',
    'IG-D-MFA-OTP-PRESENT-NOT-APPLICABLE-V1'
  )
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'CREATE_PARALLEL_ASSURANCE_ENGINE',
        'ACTIVATE_ASSURANCE_BINDING',
        'PROMOTE_DEFEATER_TO_ACTIVE',
        'CHANGE_EXISTING_VALIDATOR_GUARD_BEHAVIOR',
        'INFER_NEW_CONTRADICTION_RULE_FROM_TITLE'
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
  'IG-M46-CROSS-FAMILY-DEFEATER-CATALOG-001',
  'INPUT_GOVERNANCE',
  'Cross-family contradiction rules must reuse ASSURANCE_EVALUATOR defeater semantics',
  'M4.6 previously had contradiction logic embedded only in fn_guard_input_validator_semantic_coherence_v512. Five existing family-specific contradiction conditions are now represented as CANDIDATO defeaters under the existing Input Governance 5.13 assurance claim and semantic-coherence obligation, without creating a second evaluator or activating assurance.',
  'Existing runtime guard logic was not represented in the canonical assurance defeater catalog.',
  'VALIDATOR_CONTRADICTION_RULE_EXISTS_OUTSIDE_ASSURANCE_CATALOG',
  'Represent each existing contradiction condition as a versioned defeater bound to the canonical claim/obligation. Keep entries CANDIDATO until governance separately authorizes assurance activation; the Validator guard remains unchanged.',
  'PASS when exactly five M4.6 defeaters exist at version 1, all are CANDIDATO, all bind INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1 / IG-C5_13-SEMANTIC_COHERENCE_CONTRACT, all require zero effect, and none is ACTIVE.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://public.lf_assurance_defeater_catalog; supabase://programacion.fn_guard_input_validator_semantic_coherence_v512',
  'EXECUTION',
  array['INPUT_VALIDATOR','ASSURANCE_EVALUATOR']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.6 DEFEATER_RULES_IG',
  'supabase://public.lf_assurance_defeater_catalog'
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
