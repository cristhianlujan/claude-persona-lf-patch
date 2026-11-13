-- LF L39 / B08 -- SELECT-ONLY, NO WRITER INVOCATIONS.
-- Run only AFTER B09 E2E (PR #3823 installs SHA receiver, it does NOT create E2E RUN).
-- Scope AUTH-033 on screen B2B-AUTH-004. Shape is taken from live
-- public.lf_ig_rule_owner_decide_v2. Do not fake independent Step70.
-- IMPORTANT: computed_source_sha below mirrors the deployed function
-- lf_asset_snapshot_sha_v1('REGLA',code); role SELECT cannot invoke that
-- function (42501). Re-verify official source SHA through authorized writer
-- before use. RUN must remain IN_PROGRESS and date be within window.
WITH owner_present AS (
 SELECT count(*) AS n FROM public.lf_ig_project_owner_v2
 WHERE project_code='LF' AND owner_name='Cristhian Luján'
   AND identity_mode='UNVERIFIED_CHAT_DECLARATION'
   AND status='TEMP_DOCUMENTARY_ACTIVE'
),
candidate_runs AS MATERIALIZED (
 SELECT e.execution_id,e.started_at,e.status,e.target_code,
   e.manifest->'screen_selection_result'->>'selected_screen_code' screen_code,
   s50.evidence_payload->'profile_output' AS profile_output,
   s70.evidence_payload->'semantic_judge_result' AS judge_receipt,
   (s50.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}') AS patch
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
 WHERE e.operation_code='EJECUCION_PERFIL_LF' AND e.status='IN_PROGRESS'
  AND e.target_type='PERFIL' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  AND e.manifest->>'read_only'='true'
  AND e.manifest->>'no_write'='true'
  AND e.manifest->>'no_promotion'='true'
  AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true'
  AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-AUTH-004'
)
SELECT c.execution_id,c.started_at,c.screen_code,
 c.patch->>'rule_code' rule_code,c.patch->>'change_kind' change_kind,
 encode(extensions.digest(convert_to(c.patch::text,'UTF8'),'sha256'),'hex') AS propuesta_sha256_raw,
 encode(extensions.digest(convert_to((to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex') AS source_sha256_sql_equivalent,
 r.estado AS rule_state,c.profile_output#>>'{deliverable_created,product_decision,proposed_by}' AS proposed_by,
 c.profile_output#>>'{deliverable_created,product_decision,decision_id}' AS profile_decision_id,
 c.judge_receipt->>'verdict' AS judge_verdict,
 'identity_verified=false' AS identity_assertion,
 'RECHAZAR_FIRST_NO_RULE_PROMOTION; NOT_AN_AUTHORIZATION_TO_INVOKE' AS proposed_test_lane
FROM candidate_runs c
JOIN lf_ops.reglas r ON r.codigo=c.patch->>'rule_code' AND r.estado='CANDIDATO'
JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id AND p.codigo=c.screen_code
CROSS JOIN owner_present o
WHERE o.n=1
 AND c.patch->>'rule_code'='B2B-RULE-AUTH-033'
 AND c.patch->>'change_kind'='DOCUMENTARY_ONLY'
 AND c.profile_output->>'worker'='product_director_lf'
 AND c.profile_output->>'output_type'='PRODUCT_DIRECTION_SPEC'
 AND c.profile_output->>'self_verdict'='PASS'
 AND nullif(btrim(c.profile_output#>>'{deliverable_created,product_decision,proposed_by}'),'') IS NOT NULL
 AND c.profile_output#>>'{deliverable_created,product_decision,proposed_by}' <> 'Cristhian Luján'
 AND nullif(c.profile_output#>>'{deliverable_created,product_decision,decision_id}','') IS NOT NULL
 AND jsonb_typeof(c.patch->'changes')='object'
 AND (SELECT count(*) FROM jsonb_object_keys(c.patch->'changes'))>0
 AND NOT EXISTS (
  SELECT 1 FROM public.lf_ig_owner_decision_v2 d
  WHERE d.parent_execution_id=c.execution_id AND d.rule_code=r.codigo
    AND d.kind='UPDATE_CANDIDATE'
 )
ORDER BY c.started_at DESC;
