-- Canonical P0 Human Review V4.2 single-renderer contract.
-- Structural presentation is frozen to the Python renderer at:
-- sandbox/story_creator_p0_visual/v1.1/scripts/p0_human_review_shell_v4.py
-- canonical renderer blob: 91144c0f3c01f22b84f5c8a79c43a4e378cb9d18
-- Human-language v2 remains presentation-only and may be layered over that exact shell.

CREATE OR REPLACE FUNCTION private.fn_lf_p0_assert_canonical_browser_review_v42_v1(
  p_html text,
  p_renderer_blob_sha text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_selected_crop_count integer;
  v_required text[] := ARRAY[
    'P0 VISUAL HUMAN REVIEW V4',
    'data-review-shell-version="4.2"',
    'id="review-tabs"',
    'id="source-stage"',
    'id="source-canvas"',
    'id="source-image"',
    'id="overlay"',
    'id="element-list"',
    'id="detail-panel"',
    'id="decision-bar"',
    'id="selected-crop"',
    'IMAGEN ORIGINAL CON ANOTACIONES',
    'LISTA DE ELEMENTOS DETECTADOS',
    'M.counts.total',
    'pageOrder=[''summary'',''screen'',''elements'',''detail'',''decision'']',
    'ResizeObserver',
    'touch-action:pan-y',
    'function buildOverlay()',
    'function drawCrop(e)',
    'challenge_id=${M.challenge_id} action=${action}',
    'data-action="CONFIRM_OBSERVATION"',
    'data-action="CORRECT_WITH_ADJUDICATION"',
    'data-action="REQUEST_NEW_CAPTURE"',
    'data-action="REQUEST_ADDITIONAL_CONTEXT"',
    'data-action="REJECT_AND_BLOCK"',
    'ESCALATE_SECURITY',
    'ESCALATE_PRIVACY',
    'id="p0-human-language-v2"',
    'p0-human-review-human-language/v2'
  ];
  v_marker text;
BEGIN
  IF p_html IS NULL OR btrim(p_html) = '' THEN
    RAISE EXCEPTION 'CANONICAL_V42_HTML_REQUIRED';
  END IF;

  IF p_renderer_blob_sha IS NOT NULL
     AND p_renderer_blob_sha <> '91144c0f3c01f22b84f5c8a79c43a4e378cb9d18' THEN
    RAISE EXCEPTION 'CANONICAL_V42_RENDERER_BLOB_MISMATCH expected=% observed=%',
      '91144c0f3c01f22b84f5c8a79c43a4e378cb9d18', p_renderer_blob_sha;
  END IF;

  FOREACH v_marker IN ARRAY v_required LOOP
    IF position(v_marker in p_html) = 0 THEN
      RAISE EXCEPTION 'CANONICAL_V42_MARKER_MISSING:%', v_marker;
    END IF;
  END LOOP;

  v_selected_crop_count :=
    (length(p_html) - length(replace(p_html, 'id="selected-crop"', '')))
      / length('id="selected-crop"');
  IF v_selected_crop_count <> 1 THEN
    RAISE EXCEPTION 'CANONICAL_V42_SELECTED_CROP_COUNT_INVALID:%', v_selected_crop_count;
  END IF;

  IF position('<div id="source-stage"><div id="source-canvas">' in p_html) = 0 THEN
    RAISE EXCEPTION 'CANONICAL_V42_SOURCE_CANVAS_COMPOSITION_INVALID';
  END IF;
  IF position('crop-gallery' in lower(p_html)) > 0
     OR position('crops-grid' in lower(p_html)) > 0
     OR position('all-crops' in lower(p_html)) > 0 THEN
    RAISE EXCEPTION 'CANONICAL_V42_PARALLEL_CROP_COMPOSITION_FORBIDDEN';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION private.fn_lf_p0_enforce_canonical_browser_review_v42_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_html text;
  v_renderer_blob_sha text;
BEGIN
  IF NEW.object_role <> 'BROWSER_REVIEW' THEN
    RETURN NEW;
  END IF;
  IF NEW.mime_type <> 'text/html' THEN
    RAISE EXCEPTION 'BROWSER_REVIEW_MIME_INVALID';
  END IF;

  v_html := convert_from(NEW.content, 'UTF8');
  v_renderer_blob_sha := coalesce(NEW.metadata->>'renderer_blob_sha', '');
  PERFORM private.fn_lf_p0_assert_canonical_browser_review_v42_v1(
    v_html,
    nullif(v_renderer_blob_sha, '')
  );

  NEW.metadata := coalesce(NEW.metadata, '{}'::jsonb) || jsonb_build_object(
    'shell_version','4.2',
    'renderer_contract','p0-human-review-shell-v4.2-canonical-single-renderer/v1',
    'renderer_blob_sha','91144c0f3c01f22b84f5c8a79c43a4e378cb9d18',
    'source_canvas_mode','SINGLE_BACKGROUND_WITH_CANONICAL_OVERLAY',
    'selected_crop_policy','SELECTED_ELEMENT_ONLY',
    'ordered_observation_count_source','M.counts.total',
    'human_language_contract','p0-human-review-human-language/v2',
    'human_language_presentation_only',true,
    'structural_redesign_forbidden',true
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zz_trg_lf_p0_canonical_browser_review_v42_v1
  ON private.lf_p0_review_evidence_objects_v1;
CREATE TRIGGER zz_trg_lf_p0_canonical_browser_review_v42_v1
BEFORE INSERT ON private.lf_p0_review_evidence_objects_v1
FOR EACH ROW
WHEN (NEW.object_role = 'BROWSER_REVIEW')
EXECUTE FUNCTION private.fn_lf_p0_enforce_canonical_browser_review_v42_v1();

CREATE OR REPLACE FUNCTION public.fn_lf_p0_publish_canonical_review_v42_v1(
  p_source_challenge_id text,
  p_review_id text,
  p_execution_id text,
  p_challenge_id text,
  p_issued_at timestamptz,
  p_expires_at timestamptz,
  p_html text,
  p_renderer_blob_sha text,
  p_renderer_ref text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_old private.lf_p0_human_review_challenges_v1%ROWTYPE;
  v_old_manifest private.lf_p0_review_evidence_objects_v1%ROWTYPE;
  v_manifest jsonb;
  v_manifest_bytes bytea;
  v_manifest_sha text;
  v_manifest_id uuid := gen_random_uuid();
  v_html_bytes bytea;
  v_html_sha text;
  v_html_id uuid := gen_random_uuid();
BEGIN
  IF p_source_challenge_id IS NULL OR p_challenge_id IS NULL OR p_review_id IS NULL OR p_execution_id IS NULL THEN
    RAISE EXCEPTION 'CANONICAL_V42_BINDING_IDS_REQUIRED';
  END IF;
  IF p_challenge_id = p_source_challenge_id THEN
    RAISE EXCEPTION 'CANONICAL_V42_NEW_CHALLENGE_REQUIRED';
  END IF;
  IF p_expires_at <= p_issued_at THEN
    RAISE EXCEPTION 'CANONICAL_V42_EXPIRY_INVALID';
  END IF;

  SELECT * INTO STRICT v_old FROM private.lf_p0_human_review_challenges_v1 WHERE challenge_id = p_source_challenge_id;
  IF v_old.review_lane <> 'P0-4' THEN RAISE EXCEPTION 'P0_4_CHALLENGE_REQUIRED'; END IF;
  IF EXISTS (SELECT 1 FROM private.lf_p0_human_review_decisions_v1 d WHERE d.challenge_id = v_old.challenge_id) THEN
    RAISE EXCEPTION 'CHALLENGE_ALREADY_DECIDED';
  END IF;
  IF EXISTS (SELECT 1 FROM private.lf_p0_human_review_challenges_v1 c WHERE c.challenge_id = p_challenge_id OR c.review_id = p_review_id) THEN
    RAISE EXCEPTION 'CANONICAL_V42_BINDING_ALREADY_EXISTS';
  END IF;

  PERFORM private.fn_lf_p0_assert_canonical_browser_review_v42_v1(p_html,p_renderer_blob_sha);
  IF position(p_challenge_id in p_html) = 0 OR position(p_review_id in p_html) = 0 THEN
    RAISE EXCEPTION 'CANONICAL_V42_HTML_BINDING_MISMATCH';
  END IF;

  SELECT * INTO STRICT v_old_manifest FROM private.lf_p0_review_evidence_objects_v1
  WHERE evidence_object_id = v_old.packet_manifest_object_id AND object_role = 'PACKET_MANIFEST';
  v_manifest := convert_from(v_old_manifest.content, 'UTF8')::jsonb;
  v_manifest := jsonb_set(v_manifest, '{binding,review_id}', to_jsonb(p_review_id), true);
  v_manifest := jsonb_set(v_manifest, '{binding,challenge_id}', to_jsonb(p_challenge_id), true);
  v_manifest := jsonb_set(v_manifest, '{binding,generated_at}', to_jsonb(p_issued_at::text), true);
  v_manifest_bytes := convert_to(v_manifest::text, 'UTF8');
  v_manifest_sha := encode(extensions.digest(v_manifest_bytes, 'sha256'), 'hex');

  INSERT INTO private.lf_p0_review_evidence_objects_v1(evidence_object_id,review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_manifest_id,p_review_id,p_execution_id,'PACKET_MANIFEST','review-manifest-canonical-v42-'||substr(v_old.source_head_sha,1,12)||'.json','application/json',octet_length(v_manifest_bytes),v_manifest_sha,v_manifest_bytes,v_old.data_classification,v_old.source_head_sha,jsonb_build_object('canonical_v42_refresh',true,'refreshed_from_challenge_id',v_old.challenge_id,'renderer_blob_sha',p_renderer_blob_sha,'renderer_ref',p_renderer_ref));

  v_html_bytes := convert_to(p_html, 'UTF8');
  v_html_sha := encode(extensions.digest(v_html_bytes, 'sha256'), 'hex');
  INSERT INTO private.lf_p0_review_evidence_objects_v1(evidence_object_id,review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_html_id,p_review_id,p_execution_id,'BROWSER_REVIEW','human-review-canonical-v42-'||substr(v_old.source_head_sha,1,12)||'.html','text/html',octet_length(v_html_bytes),v_html_sha,v_html_bytes,v_old.data_classification,v_old.source_head_sha,jsonb_build_object('shell_version','4.2','canonical_v42_refresh',true,'refreshed_from_challenge_id',v_old.challenge_id,'renderer_contract','p0-human-review-shell-v4.2-canonical-single-renderer/v1','renderer_blob_sha',p_renderer_blob_sha,'renderer_ref',p_renderer_ref,'human_language_contract','p0-human-review-human-language/v2','human_language_presentation_only',true,'source_canvas_mode','SINGLE_BACKGROUND_WITH_CANONICAL_OVERLAY','selected_crop_policy','SELECTED_ELEMENT_ONLY')) RETURNING content_sha256 INTO v_html_sha;

  INSERT INTO private.lf_p0_human_review_challenges_v1(challenge_id,review_id,execution_id,source_head_sha,visual_output_sha256,packet_manifest_sha256,required_reviewer_role,reviewer_actions,evidence_store_ref,issued_at,expires_at,data_classification,dual_review_required,review_lane,review_subject,source_evidence_object_id,source_sha256,visual_output_object_id,packet_manifest_object_id,browser_review_object_id,browser_review_sha256,semantic_fingerprint,element_count,uncertain_count,inferred_count,changed_count,pending_human_count,delta,review_mode,carry_forward_safe,supersedes_challenge_id,convergence_justification)
  VALUES(p_challenge_id,p_review_id,p_execution_id,v_old.source_head_sha,v_old.visual_output_sha256,v_manifest_sha,v_old.required_reviewer_role,v_old.reviewer_actions,v_old.evidence_store_ref,p_issued_at,p_expires_at,v_old.data_classification,v_old.dual_review_required,v_old.review_lane,v_old.review_subject,v_old.source_evidence_object_id,v_old.source_sha256,v_old.visual_output_object_id,v_manifest_id,v_html_id,v_html_sha,v_old.semantic_fingerprint,v_old.element_count,v_old.uncertain_count,v_old.inferred_count,v_old.changed_count,v_old.pending_human_count,v_old.delta,v_old.review_mode,v_old.carry_forward_safe,v_old.challenge_id,'CANONICAL_V42_SINGLE_RENDERER_REFRESH_NO_HUMAN_DEBT_CHANGE');

  RETURN jsonb_build_object('outcome','CANONICAL_V42_REVIEW_READY','challenge_id',p_challenge_id,'review_id',p_review_id,'browser_review_object_id',v_html_id,'browser_review_sha256',v_html_sha,'packet_manifest_object_id',v_manifest_id,'packet_manifest_sha256',v_manifest_sha,'renderer_blob_sha',p_renderer_blob_sha,'renderer_ref',p_renderer_ref,'source_head_sha',v_old.source_head_sha,'source_sha256',v_old.source_sha256,'semantic_fingerprint',v_old.semantic_fingerprint,'element_count',v_old.element_count,'changed_count',v_old.changed_count,'pending_human_count',v_old.pending_human_count,'supersedes_challenge_id',v_old.challenge_id,'production_authorized',false,'p0_5_authorized',false);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_lf_p0_publish_canonical_review_v42_v1(text,text,text,text,timestamptz,timestamptz,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lf_p0_publish_canonical_review_v42_v1(text,text,text,text,timestamptz,timestamptz,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_lf_p0_refresh_actionable_review_v1(p_challenge_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, private, extensions AS $$
BEGIN
  RAISE EXCEPTION 'CANONICAL_V42_MATERIALIZER_REQUIRED' USING HINT = 'Generate with canonical p0_human_review_shell_v4.py and publish through fn_lf_p0_publish_canonical_review_v42_v1; copying an existing BROWSER_REVIEW is forbidden.';
END;
$$;
COMMENT ON FUNCTION public.fn_lf_p0_refresh_actionable_review_v1(text) IS 'Retired copy-based refresh. Canonical V4.2 must be regenerated from the frozen Python renderer and then persisted via fn_lf_p0_publish_canonical_review_v42_v1.';
COMMENT ON FUNCTION private.fn_lf_p0_assert_canonical_browser_review_v42_v1(text,text) IS 'Fail-closed structural gate for frozen P0 Human Review V4.2. Enforces counts/list/source background+overlay/single selected crop/page order/actions and Human Language v2.';