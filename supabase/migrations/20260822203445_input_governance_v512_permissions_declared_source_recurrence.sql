update programacion.contratos
set especificacion=jsonb_set(especificacion,'{negative_tests}',case when (especificacion->'negative_tests') ? 'PERMISSIONS_EXCLUSION_RULE_MUST_BE_DECLARED_SOURCE' then especificacion->'negative_tests' else (especificacion->'negative_tests')||'["PERMISSIONS_EXCLUSION_RULE_MUST_BE_DECLARED_SOURCE"]'::jsonb end,true)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 V5.12 recurrence: successor validation rejected the direct PERMISSIONS AUTH-029 assertion with ASSERTION_SOURCE_NOT_DECLARED because the assessment still declared only SCREEN_RULE_SET. Rollback was complete. Fix: the exact RULE used by the validator must also be present in assessment.source_refs.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12: every specialized assertion source must be explicitly declared in the same assessment source_refs. For pre-auth PERMISSIONS exclusion add the direct AUTH RULE ref; do not rely on a broader SCREEN_RULE_SET declaration.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'Negative: direct AUTH RULE assertion absent from assessment.source_refs must fail ASSERTION_SOURCE_NOT_DECLARED. Positive: exact RULE declared + relevant path + matching DENY semantics may validate.'),
    source_context='INPUT_GOVERNANCE_V512_PERMISSIONS_DECLARED_SOURCE_20260822',
    source_ref='programacion.input_family_assessments.source_refs + fn_input_evaluate_assertion'
where codigo='AUD-039';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12: una assertion especializada debe declarar exactamente su RULE en assessment.source_refs; declarar sólo el conjunto amplio no satisface provenance.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22: PERMISSIONS usó AUTH-029 directo en assertion sin declararlo aún en source_refs.')
where regla_codigo='PRV-AUD-039';