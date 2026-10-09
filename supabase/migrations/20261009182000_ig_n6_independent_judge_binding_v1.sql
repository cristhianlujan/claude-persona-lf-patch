-- IG N-6 / INDEPENDENT_JUDGE: bind the independent judge to a dedicated reviewer (authored by a separate agent from the contract only,
-- zero user-defined function calls) instead of the generic strategy-review recorder whose static closure reaches the Router and the
-- Input Governance pipeline. Context carries distinct authors, honest data refs and the evidence-bound data adjudication.
UPDATE programacion.engineering_plan_units
   SET unit_metadata = jsonb_set(
         unit_metadata,
         '{transversal_execution_v1,INDEPENDENT_JUDGE,capabilities,0,execution_input}',
         (unit_metadata #> '{transversal_execution_v1,INDEPENDENT_JUDGE,capabilities,0,execution_input}')
           || jsonb_build_object('reviewer_root','public.lf_input_safe_autofix_independent_review_v1',
                                 'context', '{"producer_author_ref": "CLAUDE_SONNET_5_5:N-6:PR2092", "reviewer_author_ref": "SUBAGENT_a4975e411b7494031:INDEPENDENT_AUTHOR", "producer_data_refs": ["lf_ops.pantalla_elementos", "lf_ops.reglas", "lf_design.component_tokens", "lf_ops.pantallas", "lf_ops.modulos", "lf_ops.app_shells", "lf_design.design_systems", "programacion.input_readiness_runs", "programacion.input_gap_proposals"], "reviewer_data_refs": ["lf_ops.pantalla_elementos", "lf_ops.reglas", "lf_design.component_tokens", "lf_ops.pantallas", "lf_ops.modulos", "lf_ops.app_shells", "lf_design.design_systems", "programacion.input_readiness_runs"], "adjudicated_data_exceptions": ["lf_design.component_tokens", "lf_design.design_systems", "lf_ops.app_shells", "lf_ops.modulos", "lf_ops.pantalla_elementos", "lf_ops.pantallas", "lf_ops.reglas", "programacion.input_readiness_runs"], "adjudicated_data_exceptions_basis": "Canonical single-source-of-truth tables: a reviewer replaying a deterministic transformation must read the same rows the producer wrote/read. Independence is carried by zero shared function closure and a different author; read-only access, recomputation from raw joins without any shared helper."}'::jsonb),
         false)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='N-6' AND disposition='ASSIGNED'
   AND unit_metadata #>> '{transversal_execution_v1,INDEPENDENT_JUDGE,capabilities,0,execution_input,reviewer_root}' = 'public.lf_independent_strategy_review_record_judge_v1';
