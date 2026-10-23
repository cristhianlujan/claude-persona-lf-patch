-- LF IG / M10.5 / independent CURRENT-SOURCE quality observation capture.
-- This DOES NOT assert the vNext post-cutover CP2, alter any underlying rule,
-- make QA claims about uninspected frontend code, or promote production.
DO $m105_independent_qa$
DECLARE
  v_plan CONSTANT text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit CONSTANT text := 'M10.5';
  v_meta jsonb; v_snapshot jsonb; v_counts jsonb;
BEGIN
  IF (SELECT (programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit))->>'terminal_action')
     IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
     OR (SELECT (programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit))#>>'{current_checkpoint,checkpoint_code}')
     IS DISTINCT FROM 'NEW_RUNS_VNEXT'
  THEN RAISE EXCEPTION 'M105_AUDIT_WRONG_CHECKPOINT'; END IF;

  SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=477 FOR UPDATE;
  IF v_meta ? 'm105_independent_family_observations_v1'
    THEN RAISE EXCEPTION 'M105_AUDIT_ALREADY_RECORDED_NO_OVERWRITE'; END IF;
  IF v_meta#>>'{m105_scope_v1,schema_version}' <> 'M105_SCOPE_SNAPSHOT_V1'
    THEN RAISE EXCEPTION 'M105_AUDIT_SCOPE_DRIFT'; END IF;

  WITH cohort AS (
    SELECT x.value::integer AS screen_id FROM jsonb_array_elements_text(
      v_meta#>'{m105_scope_v1,screen_ids}') x(value)
  ), live_contract AS (
    SELECT p.id,p.codigo,p.nombre,p.module_code,s.app_shell_code,
       coalesce(jsonb_array_length(c.contract#>'{visual,colors}'),0) AS colors_count,
       coalesce(jsonb_array_length(c.contract#>'{visual,variants}'),0) AS variants_count,
       coalesce(jsonb_array_length(c.contract#>'{visual,components}'),0) AS components_count,
       coalesce(jsonb_array_length(c.contract#>'{visual,typography}'),0) AS typography_count,
       (SELECT count(*) FROM programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') l
        JOIN lf_ops.reglas r ON r.id=l.regla_id
        WHERE r.codigo='B2B-RULE-A11Y-003'
          AND r.valor_config->>'implementation_status'='PENDING_IMPLEMENTATION_QA') AS reduced_qa,
       (SELECT count(*) FROM programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') l
        JOIN lf_ops.reglas r ON r.id=l.regla_id
        WHERE r.codigo='B2B-RULE-A11Y-004'
          AND r.valor_config->>'implementation_status'='PENDING_IMPLEMENTATION_QA') AS forced_qa,
       (SELECT count(*) FROM programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') l
        JOIN lf_ops.reglas r ON r.id=l.regla_id
        WHERE r.codigo='B2B-RULE-THEME-003' AND r.valor_config->>'scope'
              IS DISTINCT FROM s.app_shell_code) AS theme_scope_mismatch
    FROM cohort k JOIN lf_ops.pantallas p ON p.id=k.screen_id
    JOIN lf_ops.modulos m ON m.module_id=p.module_id
    JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id
    JOIN LATERAL lf_ops.fn_screen_contract_v1(s.app_shell_code,m.module_code,p.codigo) c ON true
  ), summary AS (
    SELECT jsonb_build_object(
     'screen_count',count(*),
     'reduced_motion_qa_pending',count(*) FILTER(WHERE reduced_qa=1),
     'forced_colors_qa_pending',count(*) FILTER(WHERE forced_qa=1),
     'b2b_theme_scope_mismatches',count(*) FILTER(WHERE theme_scope_mismatch=1),
     'no_contract_visual_variants',count(*) FILTER(WHERE variants_count=0)
    ) j FROM live_contract
  ), per_screen AS (
    SELECT jsonb_agg(jsonb_build_object(
      'screen_id',id,'screen_code',codigo,'screen_name',nombre,
      'module_code',module_code,'app_shell_code',app_shell_code,
      'current_source','lf_ops.fn_screen_contract_v1+programacion.fn_input_effective_rule_links_v1',
      'visual_contract_inventory',jsonb_build_object(
        'color_token_count',colors_count,
        'typography_token_count',typography_count,
        'component_binding_count',components_count,
        'variant_count',variants_count,
        'source_code_hardcoding_verdict','NOT_EVALUATED_NO_FRONTEND_SOURCE_BINDING'),
      'observations',
      (CASE WHEN reduced_qa=1 THEN jsonb_build_array(jsonb_build_object(
        'family','REDUCED_MOTION','status','OPEN_QA_VERIFICATION',
        'finding','Current governed rule declares PENDING_IMPLEMENTATION_QA; this does not prove a UI defect',
        'evidence_ref','lf_ops.reglas/B2B-RULE-A11Y-003 + effective screen link',
        'required_work','Check actual prefers-reduced-motion behavior of live frontend; nonessential animations reduced and no functional state conveyed only by motion',
        'closing_test','Positive default behavior + negative simulated reduced-motion preference with equal functional result'))
        ELSE '[]'::jsonb END)
      || (CASE WHEN forced_qa=1 THEN jsonb_build_array(jsonb_build_object(
        'family','FORCED_COLORS_CONTRAST','status','OPEN_QA_VERIFICATION',
        'finding','Current governed rule declares PENDING_IMPLEMENTATION_QA; this does not prove a UI defect',
        'evidence_ref','lf_ops.reglas/B2B-RULE-A11Y-004 + effective screen link',
        'required_work','Check forced-colors rendering, focus, distinguishable control states and readable errors under high contrast',
        'closing_test','Positive normal palette + negative forced-colors simulation; no global forced-color-adjust:none'))
        ELSE '[]'::jsonb END)
      || (CASE WHEN theme_scope_mismatch=1 THEN jsonb_build_array(jsonb_build_object(
        'family','THEME_LIGHT_DARK_SYSTEM','status','OPEN_CONFIRMED_RULE_SCOPE_MISMATCH',
        'finding','B2B_APP_SHELL-specific theme rule is effective globally in CLIENT_APP_SHELL',
        'evidence_ref','lf_ops.reglas/B2B-RULE-THEME-003 + derived global binding; actual shell from lf_ops',
        'required_work','Align rule applicability with shell via existing selector/governance or generalize rule semantics as a properly scoped transversal rule; preserve valid CLIENT theme',
        'closing_test','Client shell does not consume B2B-specific theme rule; B2B continues to consume its authorized rule'))
        ELSE '[]'::jsonb END)
      || (CASE WHEN variants_count=0 THEN jsonb_build_array(jsonb_build_object(
        'family','DESIGN_SYSTEM','status','OPEN_APPLICABILITY_AND_SOURCE_REVIEW',
        'finding','No visual variants in current screen contract. Not proof the screen requires visual variants or images',
        'evidence_ref','lf_ops.fn_screen_contract_v1 visual.variants for exact screen code',
        'required_work','Inspect screen nature and declared provider assets; link existing variants if required; authorize N/A otherwise',
        'closing_test','Independent design/provider readback or explicit nature-bound N/A'))
        ELSE '[]'::jsonb END)
    ) ORDER BY id) j FROM live_contract
  )
  SELECT jsonb_build_object(
     'schema_version','M105_INDEPENDENT_CURRENT_SOURCE_FAMILY_OBSERVATIONS_V1',
     'method','INDEPENDENT_READONLY_CURRENT_CONTRACT_AND_RULE_BINDING',
     'not_from_historical_assessment',true,
     'inspection_phases_completed',jsonb_build_array('CURRENT_CONTRACT','EFFECTIVE_RULE_BINDINGS','DESIGN_TOKEN_DECLARATIONS'),
     'inspection_phases_pending',jsonb_build_array('IMPLEMENTATION_SOURCE','ACTUAL_FORCED_COLORS_RENDER','ACTUAL_REDUCED_MOTION_RENDER','HARDCODE_SCAN','VNEXT_EDGE_RUNTIME'),
     'checkpoint_assertion','NOT_ASSERTED',
     'screen_count',s.j->'screen_count','counts',s.j,'screens',ps.j,
     'interpretation','Observations remain open per family; missing QA proof is not a failed checkpoint. Only observed scope mismatch is confirmed; no uninspected frontend bug is claimed',
     'visual_sample',jsonb_build_object('screen_code','ONB_001','source','Google_Drive','file_id','1QJXIKQIrFpfuXfZbN5QVLl6OWBj360Je','sample_type','STATIC_NORMAL_WEB','cannot_prove','CSS hardcodes, reduced motion or forced-colors interaction')
  ) INTO v_snapshot
  FROM summary s CROSS JOIN per_screen ps;

  v_counts:=v_snapshot->'counts';
  IF v_counts->>'screen_count' <> '13'
   OR v_counts->>'reduced_motion_qa_pending'<>'13'
   OR v_counts->>'forced_colors_qa_pending'<>'13'
   OR v_counts->>'b2b_theme_scope_mismatches'<>'6'
   OR v_counts->>'no_contract_visual_variants'<>'2'
  THEN RAISE EXCEPTION 'M105_AUDIT_CONTRACT_READBACK_DRIFT:%',v_counts; END IF;
  IF jsonb_array_length(v_snapshot->'screens') <> 13
  THEN RAISE EXCEPTION 'M105_AUDIT_INCOMPLETE_COHORT'; END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(unit_metadata,
    '{m105_independent_family_observations_v1}',v_snapshot,true)
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=477;
  IF (SELECT unit_metadata->'m105_independent_family_observations_v1'
       FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code=v_unit)
      IS DISTINCT FROM v_snapshot THEN
      RAISE EXCEPTION 'M105_AUDIT_POSTWRITE_NOT_EQUAL'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=477 AND checkpoint_code='NEW_RUNS_VNEXT' AND status='PENDING')<>1
  THEN RAISE EXCEPTION 'M105_AUDIT_MUST_NOT_CLOSE_CP2'; END IF;
END $m105_independent_qa$;

INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,
source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT
'IG-M105-FAMILY-OBSERVATION-NOT-RUNTIME-FAIL-004','INPUT_GOVERNANCE',
'Observation of implementation/QA is not CP2 runtime failure',
'An inherited access rule with PENDING_IMPLEMENTATION_QA and a missing visual contract entry are review observations, not proof of broken code; B2B-scoped theme rule currently derives globally to six CLIENT screens.',
'Mixing canonical configuration presence, runtime behavioral verification, QA evidence and product/shell scope as a single PASS/FAIL loses observations or creates false failures.',
'Independently inspect current source and artifacts screen by screen; store actionable family observations separately from engineering checkpoint lifecycle; require behavioral positive/negative tests for accessible modes; never claim hardcoding from a static design PNG. Gate actual vNext Edge only at post-cutover CP2.',
'Current Supabase readback: 13/13 pending QA for reduced motion and forced colors, 6/13 cross-shell theme mismatches, 2/13 no variants; CP2 remains PENDING.',
'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5#m105_independent_family_observations_v1',
'programacion.engineering_plan_units/M10.5/CP2','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
'ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='IG-M105-FAMILY-OBSERVATION-NOT-RUNTIME-FAIL-004');
