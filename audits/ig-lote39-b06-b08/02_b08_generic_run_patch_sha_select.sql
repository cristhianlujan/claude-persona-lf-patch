-- B08 / L39: GENERAL E2E RUN ELIGIBILITY WATCHER. SELECT-ONLY.
-- After B09 #3823 creates a real profile RUN and independent judge,
-- compute EXACT SHA256(govened_rule_patch::jsonb::text), never use a
-- prewritten documentary SHA if the RAW does not match.
-- Identity remains UNVERIFIED_CHAT_DECLARATION and identity_verified=false.
WITH owner_current AS (
 SELECT count(*) n FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF' AND owner_name='Cristhian Luján'
 AND status='TEMP_DOCUMENTARY_ACTIVE'
 AND identity_mode='UNVERIFIED_CHAT_DECLARATION'
),
run_context AS (
 SELECT e.execution_id,e.started_at,e.status,e.target_code,
 e.manifest#>>'{screen_selection_result,selected_screen_code}' AS screen_code,
 s50.evidence_payload->'profile_output' AS raw_output,
 s70.evidence_payload->'semantic_judge_result' AS judge,
 s50.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' AS patch
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps s40
  ON s40.execution_id=e.execution_id AND s40.step_id='input_validate'
  AND s40.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps s50
  ON s50.execution_id=e.execution_id AND s50.step_id='execute_profile'
  AND s50.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps s60
  ON s60.execution_id=e.execution_id AND s60.step_id='output_validate'
  AND s60.status='STEP_PASS_WITH_EVIDENCE'
  AND s60.evidence_payload->>'output_contract_result'='PASS'
 JOIN public.lf_operation_execution_steps s70
  ON s70.execution_id=e.execution_id AND s70.step_id='semantic_judge'
  AND s70.status='STEP_PASS_WITH_EVIDENCE'
  AND s70.evidence_payload->'blocking_codes'='[]'::jsonb
  AND s70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
 WHERE e.operation_code='EJECUCION_PERFIL_LF'
 AND e.status='IN_PROGRESS' AND e.target_type='PERFIL'
 AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND e.manifest->>'read_only'='true'
 AND e.manifest->>'no_write'='true'
 AND e.manifest->>'no_promotion'='true'
 AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true'
),
verified AS (
 SELECT rc.*,r.id AS rule_id,r.estado AS rule_state,
 CASE WHEN r.id IS NULL THEN 'CREATE'
      WHEN r.estado='CANDIDATO' THEN 'UPDATE_CANDIDATE'
      WHEN r.estado='VIGENTE' THEN 'CORRECT_VIGENTE'
      ELSE 'NOT_ELIGIBLE'
 END AS decision_kind,
 CASE WHEN r.id IS NULL THEN encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||(rc.patch->>'rule_code'),'UTF8'),'sha256'),'hex')
 ELSE encode(extensions.digest(convert_to((to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 END AS computed_source_sha_equivalent,
 CASE WHEN r.id IS NULL THEN true ELSE EXISTS(
  SELECT 1 FROM lf_ops.reglas_pantallas rp
  JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
  WHERE rp.regla_id=r.id AND p.codigo=rc.screen_code) END AS rule_screen_matches
 FROM run_context rc
 LEFT JOIN lf_ops.reglas r ON r.codigo=rc.patch->>'rule_code'
)
SELECT v.execution_id,v.started_at,v.screen_code,
 v.patch->>'rule_code' AS rule_code,v.patch->>'change_kind' AS change_kind,
 v.decision_kind,v.rule_state,v.rule_screen_matches,
 encode(extensions.digest(convert_to(v.patch::text,'UTF8'),'sha256'),'hex') AS propuesta_sha256_exact_raw,
 v.computed_source_sha_equivalent AS source_sha256_equivalent_SELECT_ONLY,
 v.raw_output#>>'{deliverable_created,product_decision,proposed_by}' AS proposed_by,
 v.raw_output#>>'{deliverable_created,product_decision,decision_id}' AS profile_decision_id,
 v.judge->>'verdict' AS judge_verdict,
 (v.patch->>'rule_code'='B2B-RULE-AUTH-033' AND v.screen_code='B2B-AUTH-004') AS l38_auth033_example_match,
 false AS identity_verified,
 'NOT_YET_AUTHORIZE_V2; date and literal phrase to be supplied by owner' AS next_action
FROM verified v CROSS JOIN owner_current o
WHERE o.n=1 AND v.rule_screen_matches=true
 AND v.decision_kind<>'NOT_ELIGIBLE'
 AND ((v.decision_kind='CREATE' AND v.patch->>'change_kind'='CREATE')
 OR (v.decision_kind='UPDATE_CANDIDATE' AND v.patch->>'change_kind'='DOCUMENTARY_ONLY')
 OR (v.decision_kind='CORRECT_VIGENTE' AND v.patch->>'change_kind' IN ('DOCUMENTARY_ONLY','FUNCTIONAL')))
 AND v.raw_output->>'worker'='product_director_lf'
 AND v.raw_output->>'output_type'='PRODUCT_DIRECTION_SPEC'
 AND v.raw_output->>'self_verdict'='PASS'
 AND nullif(v.screen_code,'') IS NOT NULL
 AND nullif(btrim(v.raw_output#>>'{deliverable_created,product_decision,proposed_by}'),'') IS NOT NULL
 AND v.raw_output#>>'{deliverable_created,product_decision,proposed_by}'<>'Cristhian Luján'
 AND nullif(v.raw_output#>>'{deliverable_created,product_decision,decision_id}','') IS NOT NULL
 AND jsonb_typeof(v.patch->'changes')='object'
 AND (SELECT count(*) FROM jsonb_object_keys(v.patch->'changes'))>0
 AND NOT EXISTS (
  SELECT 1 FROM public.lf_ig_owner_decision_v2 d
  WHERE d.parent_execution_id=v.execution_id AND d.rule_code=v.patch->>'rule_code'
    AND d.kind=v.decision_kind)
ORDER BY v.started_at DESC;
