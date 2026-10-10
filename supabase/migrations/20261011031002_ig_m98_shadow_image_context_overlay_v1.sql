-- IG M9.8: read-only context overlay for shadow field comparison.
-- The production gate, source comparison, and original oracle remain unchanged.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m96_shadow_field_context_overlay_v1(
 p_screen_id integer,p_version_id bigint,p_request_context jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $body$
DECLARE purpose text; scope_ref text; intent text; raw jsonb; obs jsonb; dif jsonb;
 annotated jsonb:='[]'::jsonb; outj jsonb; c int:=0;
BEGIN
 IF jsonb_typeof(p_request_context) IS DISTINCT FROM 'object'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','REQUEST_CONTEXT_INVALID','production_authorized',false); END IF;
 purpose:=nullif(btrim(coalesce(p_request_context->>'evaluation_purpose','')),'');
 scope_ref:=nullif(btrim(coalesce(p_request_context->>'request_scope_ref','')),'');
 intent:=nullif(btrim(coalesce(p_request_context->>'request_intent','')),'');
 IF purpose IS NULL OR scope_ref IS NULL OR intent IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','REQUEST_CONTEXT_SCOPE_REQUIRED','production_authorized',false); END IF;
 IF purpose NOT IN ('FORMAT_RULE_REVIEW','NEW_UI_LAYOUT_DRAFT','VISUAL_FINAL_APPROVAL','UNSPECIFIED')
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','UNKNOWN_EVIDENCE_PURPOSE','production_authorized',false); END IF;
 raw:=programacion.fn_ig_m96_shadow_field_probe_v1(p_screen_id,p_version_id);
 IF raw->>'schema_version' IS DISTINCT FROM 'IG_M96_SHADOW_FIELD_OBSERVATION_V1'
 OR raw->>'status' IS DISTINCT FROM 'BLOCKED_PENDING_FIELD_POLICY_AND_ADJUDICATION'
 OR jsonb_typeof(raw->'field_diffs') IS DISTINCT FROM 'array'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CANONICAL_COMPARATOR_NOT_READY','production_authorized',false); END IF;
 obs:=programacion.fn_ig_visual_image_requirement_readback_v1(p_screen_id,purpose);
 IF obs->>'schema_version' IS DISTINCT FROM 'IG_VISUAL_IMAGE_OBSERVATION_V1'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','IMAGE_REQUIREMENT_OBSERVER_NOT_READY','production_authorized',false); END IF;
 FOR dif IN SELECT value FROM jsonb_array_elements(raw->'field_diffs') LOOP
  IF dif->>'family_code'='VISUAL_EVIDENCE' THEN
   c:=c+1;
   annotated:=annotated||jsonb_build_array(dif||jsonb_build_object(
    'image_scope_annotation',jsonb_build_object(
    'image_presence',obs->>'image_presence','image_requirement',obs->>'image_requirement',
    'image_observation_status',obs->>'status','purpose_authority',obs->>'purpose_authority',
    'image_missing_alone_is_coverage_divergence',false,
    'field_divergence_still_requires_adjudication',true)));
  ELSE annotated:=annotated||jsonb_build_array(dif);
  END IF;
 END LOOP;
 outj:=jsonb_build_object(
  'schema_version','IG_M96_SHADOW_CONTEXT_OVERLAY_V1',
  'status','BLOCKED_UNVERIFIED_PER_FIELD_ADJUDICATION',
  'request_scope_ref',scope_ref,'request_intent',intent,'evaluation_purpose',purpose,
  'scope_authentication','CALLER_DECLARATION_NOT_VERIFIED',
  'canonical_shadow_sha256',raw->>'canonical_shadow_sha256',
  'raw_field_diff_count',raw->'field_diff_count',
  'raw_oracles_implemented',raw->'oracles_implemented',
  'raw_oracles_missing',raw->'oracles_missing',
  'raw_field_diffs_unchanged',raw->'field_diffs',
  'annotated_field_diffs',annotated,'visual_diff_annotation_count',c,
  'visual_image_observation',obs,
  'whole_visual_family_not_applicable',false,'shadow_comparison_unmodified',true,
  'typed_receipt_emitted',false,'human_decisions_emitted',false,
  'release_authorized',false,'production_authorized',false);
 RETURN outj||jsonb_build_object('context_overlay_sha256',programacion.fn_v09_sha256_jsonb(outj));
END $body$;
COMMENT ON FUNCTION programacion.fn_ig_m96_shadow_field_context_overlay_v1(integer,bigint,jsonb)
 IS 'Read-only shadow annotation. Reuses canonical 47-family comparison; caller purpose does not prove scope/authority. No admission, receipt or release.';
REVOKE ALL ON FUNCTION programacion.fn_ig_m96_shadow_field_context_overlay_v1(integer,bigint,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m96_shadow_field_context_overlay_v1(integer,bigint,jsonb) TO service_role;

INSERT INTO transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
SELECT 'DEC-IG-M98-SHADOW-IMAGE-CONTEXT-20261010',
'M9.8 shadow: separar presencia de imagen y su obligatoriedad',
'El comparador contextual reutiliza el probe M9.6 y la regla visual vigente. Ausencia de imagen se informa y solo bloquea si es obligatoria para el proposito demostrado. Contexto declarado por consumidor no constituye prueba independiente. Se preserva el universo 47, el digest, diferencias, recibos y tres HOLD historicos; el comparador oficial no se altera.',
'No toda revision de formato o regla requiere imagen. El oracle anterior mezcla ausencia de imagen con cobertura semantica.',
'Observacion shadow no decisional; no activa consumidores ni modifica el gate terminal.',
'VIGENTE'
WHERE NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-SHADOW-IMAGE-CONTEXT-20261010');
UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{m9_8_shadow_image_context_overlay_v1}',
 jsonb_build_object('status','OBSERVATIONAL_SHADOW_ONLY',
 'function','programacion.fn_ig_m96_shadow_field_context_overlay_v1',
 'origin','programacion.fn_ig_m96_shadow_field_probe_v1',
 'context','request_scope_ref+request_intent+evaluation_purpose',
 'authority','DEC-IG-M98-SHADOW-IMAGE-CONTEXT-20261010',
 'canonical_shadow_unchanged',true,'visual_family_not_skipped',true,
 'human_decisions_required',true,'source_receipts_required',true,
 'release_authorized',false,'production_authorized',false),true)
 WHERE id=280 AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.8';

DO $tests$
DECLARE a jsonb;b jsonb;c jsonb;d jsonb;e jsonb;
BEGIN
 a:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(58,19,
 jsonb_build_object('evaluation_purpose','FORMAT_RULE_REVIEW','request_scope_ref','fixture://rec-format','request_intent','INSPECT_EXISTING_FORMAT'));
 IF a->>'status'<>'BLOCKED_UNVERIFIED_PER_FIELD_ADJUDICATION'
 OR a#>>'{visual_image_observation,status}'<>'IMAGE_NOT_REQUIRED_FOR_DECLARED_PURPOSE'
 OR a#>>'{visual_image_observation,image_presence}'<>'NO_IMAGE_REGISTERED'
 OR a->>'whole_visual_family_not_applicable'<>'false'
 OR a->>'release_authorized'<>'false' OR (a->>'visual_diff_annotation_count')::int<1
 THEN RAISE EXCEPTION 'FORMAT_REVIEW_FALSE_IMAGE_REQUIREMENT'; END IF;
 b:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(58,19,
 jsonb_build_object('evaluation_purpose','VISUAL_FINAL_APPROVAL','request_scope_ref','fixture://rec-approval','request_intent','PROMOTE_NEW_VISUAL'));
 IF b#>>'{visual_image_observation,status}'<>'BLOCKED_REQUIRED_IMAGE_MISSING'
 OR b->>'canonical_shadow_sha256' IS DISTINCT FROM a->>'canonical_shadow_sha256'
 OR b->'raw_field_diffs_unchanged' IS DISTINCT FROM a->'raw_field_diffs_unchanged'
 THEN RAISE EXCEPTION 'FALSE_NA_OR_CANONICAL_DRIFT'; END IF;
 c:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(58,19,jsonb_build_object(
 'evaluation_purpose','UNSPECIFIED','request_scope_ref','fixture://rec-unknown','request_intent','UNRESOLVED'));
 IF c#>>'{visual_image_observation,status}'<>'PENDING_SCOPE' THEN RAISE EXCEPTION 'UNKNOWN_PURPOSE_FALSE_PASS'; END IF;
 d:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(58,19,'{}'::jsonb);
 IF d->>'reason'<>'REQUEST_CONTEXT_SCOPE_REQUIRED' THEN RAISE EXCEPTION 'EMPTY_CONTEXT_ACCEPTED'; END IF;
 d:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(58,19,jsonb_build_object(
 'evaluation_purpose','SKIP_ALL_VISUAL','request_scope_ref','fixture://rec-invalid','request_intent','SKIP'));
 IF d->>'reason'<>'UNKNOWN_EVIDENCE_PURPOSE' THEN RAISE EXCEPTION 'UNKNOWN_PURPOSE_ACCEPTED'; END IF;
 d:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(1,19,jsonb_build_object(
 'evaluation_purpose','VISUAL_FINAL_APPROVAL','request_scope_ref','fixture://onb','request_intent','PROMOTE'));
 IF d#>>'{visual_image_observation,status}'<>'IMAGE_PRESENT_REVIEW_NOT_DONE'
 OR d->>'status'<>'BLOCKED_UNVERIFIED_PER_FIELD_ADJUDICATION' THEN RAISE EXCEPTION 'SECOND_SCREEN_IMAGE_MISCLASSIFIED'; END IF;
 e:=programacion.fn_ig_m96_shadow_field_context_overlay_v1(43,19,jsonb_build_object(
 'evaluation_purpose','FORMAT_RULE_REVIEW','request_scope_ref','fixture://b2b','request_intent','REVIEW'));
 IF e->>'status'<>'BLOCKED_UNVERIFIED_PER_FIELD_ADJUDICATION'
 OR e#>>'{visual_image_observation,status}'<>'IMAGE_NOT_REQUIRED_FOR_DECLARED_PURPOSE'
 OR e->>'release_authorized'<>'false' THEN RAISE EXCEPTION 'THIRD_SCREEN_FORMAT_MISCLASSIFIED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM transversal.decision_log WHERE adr='DEC-IG-M98-SHADOW-IMAGE-CONTEXT-20261010' AND estado='VIGENTE')
 OR NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units WHERE id=280
 AND unit_metadata#>>'{m9_8_shadow_image_context_overlay_v1,status}'='OBSERVATIONAL_SHADOW_ONLY')
 THEN RAISE EXCEPTION 'GOVERNANCE_CONTRACT_NOT_BOUND'; END IF;
END $tests$;
