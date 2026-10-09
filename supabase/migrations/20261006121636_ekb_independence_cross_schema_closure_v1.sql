insert into public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,detectability,
    source_context,source_ref
  )
  select
    extensions.gen_random_uuid(),
    'INDEPENDENCE-CROSS-SCHEMA-CLOSURE-001',
    'GOVERNANCE',
    'T-INDEP v1 same-schema closure cannot prove independence across schema boundaries',
    'lf_independent_assurance_measure_v1 resolves both roots and dependencies only inside one dependency schema. A wrapper in another schema can therefore hide the material producer graph.',
    'T-INDEP v1 uses one dependency_schema and FUNCTION_NAME_MATCH_WITHIN_DECLARED_SCHEMA. N-6 pairs a producer in programacion with a reviewer in public.',
    'CROSS_SCHEMA_PRODUCER_REVIEWER -> V1_CLOSURE_INCOMPLETE; WRAPPER_BRIDGE -> NOT_FULL_PROOF',
    'Fail closed for cross-schema producer/reviewer pairs. Do not treat wrappers as full closure. Evolve the existing INDEPENDENT_ASSURANCE capability to traverse qualified cross-schema dependencies and requalify it before consumer PASS.',
    'PASS only when the exact qualified producer and reviewer closures are traversed across schemas and overall plus DEPENDENCIES/DATA/AUTHOR are INDEPENDENT. N-6 remains blocked until then.',
    'HIGH',1,now(),now(),'CROSS_PLAN_TRANSVERSAL','ACTIVO',
    '2026-10-06 probe public.fn_input_governance_safe_autofix_v1 vs public.lf_independent_strategy_review_record_judge_v1 returned UNPROVEN; dependency_dimension said INDEPENDENT with producer_dependency_count=0 because the public wrapper delegates to programacion and v1 does not traverse that boundary.',
    now(),now(),'PRE_EXECUTION',
    array['SUPER_ADMIN','IG','PROGRAMMING_AGENT'],
    'R2_NO_VE','LOUD_EARLY',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2:N-6/INDEPENDENT_JUDGE',
    'supabase://public.lf_independent_assurance_measure_v1+public.fn_input_governance_safe_autofix_v1+programacion.fn_input_governance_safe_autofix_v1+public.lf_independent_strategy_review_record_judge_v1'
  where not exists (
    select 1 from public.lf_error_knowledge where codigo='INDEPENDENCE-CROSS-SCHEMA-CLOSURE-001'
  );