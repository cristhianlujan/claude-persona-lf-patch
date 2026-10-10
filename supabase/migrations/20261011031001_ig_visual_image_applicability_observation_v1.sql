-- Scope-based visual-image evidence observation. Never changes existing readiness, oracle comparison or release authority.
CREATE OR REPLACE FUNCTION programacion.fn_ig_visual_image_requirement_readback_v1(
 p_screen_id integer,p_purpose text DEFAULT 'UNSPECIFIED')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $body$
DECLARE v_code text; v_state text; v_rule jsonb; v_decisions int; v_image_total int; v_image_current int; v_requirement text; v_reason text; v_scope_state text;
BEGIN
 SELECT codigo,estado INTO v_code,v_state FROM lf_ops.pantallas WHERE id=p_screen_id;
 IF v_code IS NULL THEN RETURN jsonb_build_object('status','BLOCKED','reason','SCREEN_NOT_FOUND','image_admission_authorized',false); END IF;
 IF p_purpose IS NULL OR p_purpose NOT IN ('FORMAT_RULE_REVIEW','NEW_UI_LAYOUT_DRAFT','VISUAL_FINAL_APPROVAL','UNSPECIFIED')
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','UNRECOGNIZED_EVALUATION_PURPOSE','image_admission_authorized',false); END IF;
 SELECT valor_config INTO v_rule FROM lf_ops.reglas WHERE codigo='NEG-GOBERNANZA-VISUAL-CONFIRM-01' AND estado='VIGENTE' ORDER BY id DESC LIMIT 1;
 IF v_rule IS NULL THEN RETURN jsonb_build_object('status','BLOCKED','reason','VISUAL_SCOPE_AUTHORITY_NOT_CURRENT','image_admission_authorized',false); END IF;
 SELECT count(*) INTO v_decisions FROM lf_design.visual_decisions WHERE decision_status='VIGENTE' AND impact_scope ? v_code;
 SELECT count(*), count(*) FILTER (WHERE status='VIGENTE' AND is_current AND mime_type LIKE 'image/%' AND checksum_sha256 ~ '^[a-f0-9]{64}$')
 INTO v_image_total,v_image_current FROM lf_ops.pantalla_artefactos WHERE pantalla_id=p_screen_id AND mime_type LIKE 'image/%';
 v_scope_state:=CASE WHEN p_purpose='UNSPECIFIED' THEN 'UNRESOLVED' ELSE 'CALLER_DECLARED_NOT_INDEPENDENTLY_VERIFIED' END;
 v_requirement:=CASE p_purpose
  WHEN 'FORMAT_RULE_REVIEW' THEN 'NOT_REQUIRED_FOR_FORMAT_RULE_REVIEW'
  WHEN 'NEW_UI_LAYOUT_DRAFT' THEN 'CONDITIONAL_REQUIRED_AT_VISUAL_APPROVAL'
  WHEN 'VISUAL_FINAL_APPROVAL' THEN 'REQUIRED_FOR_VISUAL_APPROVAL'
  ELSE 'PENDING_PURPOSE_AUTHORITY' END;
 v_reason:=CASE
  WHEN p_purpose='VISUAL_FINAL_APPROVAL' AND v_image_current=0 THEN 'REQUIRED_IMAGE_MISSING'
  WHEN p_purpose='VISUAL_FINAL_APPROVAL' THEN 'CURRENT_IMAGE_PRESENT_FINAL_REVIEW_STILL_REQUIRED'
  WHEN p_purpose='FORMAT_RULE_REVIEW' THEN 'RULE_SCOPE_EXCLUDES_FORMAT_ONLY_NON_VISUAL_CHANGE'
  WHEN p_purpose='NEW_UI_LAYOUT_DRAFT' THEN 'DRAFT_MAY_EXIST_WITHOUT_IMAGE_NOT_FINAL_APPROVAL'
  ELSE 'PURPOSE_UNSPECIFIED_NO_NA_INFERENCE' END;
 RETURN jsonb_build_object('schema_version','IG_VISUAL_IMAGE_OBSERVATION_V1','screen_code',v_code,
 'screen_id',p_screen_id,'screen_state',v_state,'evaluation_purpose',p_purpose,'purpose_authority',v_scope_state,
 'governing_visual_rule','NEG-GOBERNANZA-VISUAL-CONFIRM-01','governing_rule_scope',v_rule->>'aplica_a',
 'visual_decision_count',v_decisions,'registered_image_count',v_image_total,'current_verified_image_count',v_image_current,
 'image_presence',CASE WHEN v_image_current>0 THEN 'CURRENT_IMAGE_REGISTERED' WHEN v_image_total>0 THEN 'NO_CURRENT_IMAGE_REGISTERED' ELSE 'NO_IMAGE_REGISTERED' END,
 'image_requirement',v_requirement,'status',CASE
  WHEN p_purpose='VISUAL_FINAL_APPROVAL' AND v_image_current=0 THEN 'BLOCKED_REQUIRED_IMAGE_MISSING'
  WHEN p_purpose='VISUAL_FINAL_APPROVAL' THEN 'IMAGE_PRESENT_REVIEW_NOT_DONE'
  WHEN p_purpose='FORMAT_RULE_REVIEW' THEN 'IMAGE_NOT_REQUIRED_FOR_DECLARED_PURPOSE'
  WHEN p_purpose='NEW_UI_LAYOUT_DRAFT' THEN 'DRAFT_NO_IMAGE_HOLD'
  ELSE 'PENDING_SCOPE' END,
 'reason',v_reason,'whole_visual_family_not_applicable',false,'image_admission_authorized',false,'production_authorized',false);
END $body$;
COMMENT ON FUNCTION programacion.fn_ig_visual_image_requirement_readback_v1(integer,text)
 IS 'Read-only applicability observation for IMAGE artifact only, from governed screen+visual rule. No image is informational unless exact purpose requires it. Caller intent not independently verified; no readiness/promotion grant.';
REVOKE ALL ON FUNCTION programacion.fn_ig_visual_image_requirement_readback_v1(integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_visual_image_requirement_readback_v1(integer,text) TO service_role;

-- Append-only semantic scope clarification; no rewrite of preexisting decisions.
INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
VALUES ('DEC-IG-VISUAL-IMAGE-APPLICABILITY-20261010',
 'Evidencia visual: ausencia de imagen versus imagen exigida por el alcance',
 'La presencia de una imagen NO es requisito universal para las 47 familias ni todas las pantallas. Para revisión de formatos y reglas sin nueva aprobación visual, informar NO_IMAGE_REGISTERED si no existe, sin interpretar ausencia como error obligatorio. Para nueva especificación UI/layout o aprobación visual aplicar NEG-GOBERNANZA-VISUAL-CONFIRM-01 según la fase: borrador puede carecer de imagen; aprobación final requiere evidencia visual vigente. El alcance incierto permanece PENDING_SCOPE. El helper es solo observacional, no cambia el resultado de la familia VISUAL_EVIDENCE ni autoriza cutover.',
 'Corrección de sobreaplicabilidad: el oráculo shadow REC_001 trataba una imagen ausente como déficit aunque hay decisiones visuales vigentes. El alcance exacto es dinámico, no basado en pantallas fijas.',
 'No altera ninguna decisión histórica, oráculo en uso, familia, readiness, estado M9.8 ni autorización de producción; requiere prueba de contexto antes de integrar al gate.',
 'VIGENTE')
ON CONFLICT DO NOTHING;
UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(unit_metadata,
 '{m9_8_visual_image_applicability_v1}',
 jsonb_build_object('status','OBSERVATION_ONLY_NOT_CUTOVER',
 'function','programacion.fn_ig_visual_image_requirement_readback_v1',
 'governance','DEC-IG-VISUAL-IMAGE-APPLICABILITY-20261010',
 'visual_image_universal_requirement',false,
 'unknown_context','PENDING_SCOPE',
 'require_exact_purpose_and_positive_authority',true,
 'image_absence_alone_is_failure',false,
 'whole_visual_family_not_applicable',false,
 'shadow_gate_unchanged',true,'production_authorized',false),true)
WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';

DO $tests$ DECLARE x jsonb; BEGIN
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(58,'FORMAT_RULE_REVIEW');
 IF x->>'image_presence'<>'NO_IMAGE_REGISTERED' OR x->>'status'<>'IMAGE_NOT_REQUIRED_FOR_DECLARED_PURPOSE'
 OR x->>'image_admission_authorized'<>'false' OR (x->>'visual_decision_count')::int<1
 THEN RAISE EXCEPTION 'FORMAT_REVIEW_FALSE_REQUIRED:%',x; END IF;
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(58,'VISUAL_FINAL_APPROVAL');
 IF x->>'status'<>'BLOCKED_REQUIRED_IMAGE_MISSING' THEN RAISE EXCEPTION 'REQUIRED_VISUAL_FALSE_NA:%',x; END IF;
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(1,'VISUAL_FINAL_APPROVAL');
 IF x->>'status'<>'IMAGE_PRESENT_REVIEW_NOT_DONE' OR (x->>'current_verified_image_count')::int<1
 THEN RAISE EXCEPTION 'EXISTING_IMAGE_INCORRECT:%',x; END IF;
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(43,'FORMAT_RULE_REVIEW');
 IF x->>'status'<>'IMAGE_NOT_REQUIRED_FOR_DECLARED_PURPOSE' THEN RAISE EXCEPTION 'OTHER_SCREEN_MISCLASSIFIED:%',x; END IF;
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(58,'UNSPECIFIED');
 IF x->>'status'<>'PENDING_SCOPE' THEN RAISE EXCEPTION 'UNKNOWN_SCOPE_FALSE_PASS:%',x; END IF;
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(58,'INVALID');
 IF x->>'status'<>'BLOCKED' THEN RAISE EXCEPTION 'INVALID_SCOPE_FALSE_PASS:%',x; END IF;
 x:=programacion.fn_ig_visual_image_requirement_readback_v1(-9901,'FORMAT_RULE_REVIEW');
 IF x->>'status'<>'BLOCKED' THEN RAISE EXCEPTION 'UNKNOWN_SCREEN_FALSE_PASS:%',x; END IF;
 IF NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-VISUAL-IMAGE-APPLICABILITY-20261010' AND estado='VIGENTE')
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units WHERE id=280 AND unit_metadata#>>'{m9_8_visual_image_applicability_v1,status}'='OBSERVATION_ONLY_NOT_CUTOVER')
 THEN RAISE EXCEPTION 'GOVERNANCE_CONTRACT_PARITY_FAILED'; END IF;
 IF programacion.fn_ig_m96_adjudication_live_gate_v1('0a091836-f8db-4063-965d-a02fa2fbd6d5'::uuid)->>'status'<>'BLOCKED'
 THEN RAISE EXCEPTION 'FALSE_M98_PASS'; END IF;
END $tests$;