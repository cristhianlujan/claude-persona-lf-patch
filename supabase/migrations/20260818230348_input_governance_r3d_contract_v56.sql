update programacion.contratos c
set especificacion = c.especificacion || jsonb_build_object(
  'contract_revision','5.6',
  'remediation_revision','AUDIT_20260818_R3_SEMANTIC_FAIL_CLOSED',
  'story_ready_rule','NO_STORY_STAGE_OPEN',
  'source_ref_contract','STRUCTURED_ALLOWLIST_V3_EXPLICIT_SCREEN_ID',
  'semantic_fail_closed',jsonb_build_object(
    'severity_must_be_resolved',true,
    'story_open_requires_p0',true,
    'implementation_ready_requires_complete_coverage_and_definition',true,
    'screen_scoped_refs_require_explicit_pantalla_id',true,
    'contract_revision_pinned_per_run',true,
    'terminal_successor_invalidation_is_monotonic',true,
    'declared_supabase_visual_must_physically_exist_for_qa',true,
    'module_health_requires_semantic_story_gate',true
  )
)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{readiness_stage_hierarchy,coverage_and_well_defined_not_forced_monotonic}','false'::jsonb,true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{applicability_source_grounding,na_by_absence}','"DENY_AS_SOLE_AUTHORITY"'::jsonb,true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{audit_remediation}',coalesce(c.especificacion->'audit_remediation','[]'::jsonb) || jsonb_build_array(
  'AUD-IGA-016_SEVERITY_FAIL_CLOSED',
  'AUD-IGA-017_COVERAGE_IMPLEMENTATION_MONOTONICITY',
  'AUD-IGA-018_CONTRACT_PIN_CURRENTNESS_LATCH',
  'AUD-IGA-019_SOURCE_REF_EXPLICIT_IDENTITY',
  'AUD-IGA-020_VISUAL_STORAGE_QA_GATE',
  'AUD-IGA-021_MODULE_HEALTH_SEMANTIC_GATE'
),true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

update programacion.contratos c
set especificacion=jsonb_set(c.especificacion,'{negative_tests}',coalesce(c.especificacion->'negative_tests','[]'::jsonb) || jsonb_build_array(
  'UNRESOLVED_SEVERITY',
  'STORY_OPEN_WITH_NON_P0',
  'IMPLEMENTATION_READY_WITH_INCOMPLETE_COVERAGE',
  'NOT_APPLICABLE_BY_ABSENCE_ONLY',
  'SCREEN_SCOPED_REF_WITHOUT_ID',
  'CONTRACT_REVISION_DRIFT',
  'REVERSIBLE_CURRENTNESS',
  'DECLARED_STORAGE_VISUAL_MISSING',
  'HEALTH_PASS_WITH_STORY_OPEN'
),true)
where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';

update lf_ops.reglas
set valor_config=jsonb_set(valor_config,'{story_ready_rule}','"NO_STORY_STAGE_OPEN"'::jsonb,true)
where codigo='B2B-RULE-STORY-READINESS-001';