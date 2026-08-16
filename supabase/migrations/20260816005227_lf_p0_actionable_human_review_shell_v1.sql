-- P0 actionable human-review shell v1.
CREATE OR REPLACE FUNCTION private.fn_lf_p0_make_browser_review_actionable_v1(
  p_html text,
  p_issue_number integer DEFAULT 125
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_script text;
BEGIN
  IF p_html IS NULL OR btrim(p_html) = '' THEN RAISE EXCEPTION 'BROWSER_REVIEW_HTML_REQUIRED'; END IF;
  IF position('challenge_id=${M.challenge_id} action=${action}' in p_html) > 0 OR position('id="p0-governed-decision-actionable-v1"' in p_html) > 0 THEN RETURN p_html; END IF;
  IF position('id="p0-review-binding-v1"' in p_html) = 0 THEN RAISE EXCEPTION 'BROWSER_REVIEW_BINDING_MISSING'; END IF;
  IF position('class="decision-btn"' in p_html) = 0 THEN RAISE EXCEPTION 'BROWSER_REVIEW_DECISION_BUTTONS_MISSING'; END IF;
  IF position('</body>' in p_html) = 0 THEN RAISE EXCEPTION 'BROWSER_REVIEW_BODY_END_MISSING'; END IF;
  v_script := format($actionable$
<script id="p0-governed-decision-actionable-v1">
(()=>{
  const bindingNode=document.getElementById("p0-review-binding-v1");
  const bar=document.getElementById("decision-bar");
  if(!bindingNode||!bar)return;
  let binding={};
  try{binding=JSON.parse(bindingNode.textContent||"{}")}catch(_){return}
  const challenge=String(binding.challenge_id||"");
  if(!challenge)return;
  let panel=document.getElementById("p0-governed-decision-output");
  if(!panel){
    panel=document.createElement("div"); panel.id="p0-governed-decision-output"; panel.hidden=true;
    panel.style.cssText="margin:12px;padding:12px;border:1px solid #b8c4cf;border-radius:8px;background:#f8fafc";
    const label=document.createElement("div"); label.textContent="Decisión gobernada preparada"; label.style.fontWeight="800";
    const out=document.createElement("code"); out.id="p0-governed-decision-text"; out.style.cssText="display:block;margin:8px 0;white-space:pre-wrap;word-break:break-all";
    const copy=document.createElement("button"); copy.id="p0-copy-governed-decision"; copy.type="button"; copy.textContent="Copiar decisión"; copy.style.marginRight="8px";
    const issue=document.createElement("a"); issue.id="p0-open-authenticated-review-provider"; issue.href="https://github.com/cristhianlujan/claude-persona-lf-patch/issues/%s"; issue.target="_blank"; issue.rel="noopener noreferrer"; issue.textContent="Abrir canal autenticado";
    const note=document.createElement("div"); note.textContent="La pantalla prepara la decisión; no la publica ni la autentica. El proveedor autenticado y su readback siguen siendo obligatorios."; note.style.cssText="margin-top:8px;font-size:12px;opacity:.78";
    panel.append(label,out,copy,issue,note); bar.appendChild(panel);
    copy.addEventListener("click",async()=>{const text=out.textContent||"";if(!text)return;try{await navigator.clipboard.writeText(text)}catch(_){const ta=document.createElement("textarea");ta.value=text;ta.setAttribute("readonly","");ta.style.position="fixed";ta.style.opacity="0";document.body.appendChild(ta);ta.select();document.execCommand("copy");ta.remove();}});
  }
  const out=document.getElementById("p0-governed-decision-text");
  document.querySelectorAll(".decision-btn[data-action]").forEach(btn=>{btn.addEventListener("click",()=>{const action=String(btn.dataset.action||"");if(!action)return;out.textContent=`challenge_id=${challenge} action=${action}`;panel.hidden=false;});});
})();
</script>
$actionable$, p_issue_number);
  RETURN replace(p_html, '</body>', v_script || '</body>');
END;
$$;

CREATE OR REPLACE FUNCTION private.fn_lf_p0_enforce_actionable_browser_review_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, private, extensions AS $$
DECLARE v_html text; v_upgraded text;
BEGIN
  IF NEW.object_role <> 'BROWSER_REVIEW' THEN RETURN NEW; END IF;
  IF NEW.mime_type <> 'text/html' THEN RAISE EXCEPTION 'BROWSER_REVIEW_MIME_INVALID'; END IF;
  v_html := convert_from(NEW.content, 'UTF8');
  v_upgraded := private.fn_lf_p0_make_browser_review_actionable_v1(v_html, 125);
  IF v_upgraded <> v_html THEN
    NEW.content := convert_to(v_upgraded, 'UTF8'); NEW.content_bytes := octet_length(NEW.content); NEW.content_sha256 := encode(extensions.digest(NEW.content, 'sha256'), 'hex');
    NEW.metadata := coalesce(NEW.metadata, '{}'::jsonb) || jsonb_build_object('actionable_decision_contract','p0-governed-decision-actionable/v1','decision_transport','AUTHENTICATED_PROVIDER_READBACK_REQUIRED','direct_machine_acceptance',false);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_lf_p0_actionable_browser_review_v1 ON private.lf_p0_review_evidence_objects_v1;
CREATE TRIGGER trg_lf_p0_actionable_browser_review_v1 BEFORE INSERT ON private.lf_p0_review_evidence_objects_v1 FOR EACH ROW WHEN (NEW.object_role = 'BROWSER_REVIEW') EXECUTE FUNCTION private.fn_lf_p0_enforce_actionable_browser_review_v1();

CREATE OR REPLACE FUNCTION public.fn_lf_p0_refresh_actionable_review_v1(p_challenge_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, private, extensions AS $$
DECLARE
  v_old private.lf_p0_human_review_challenges_v1%ROWTYPE; v_old_manifest private.lf_p0_review_evidence_objects_v1%ROWTYPE; v_old_browser private.lf_p0_review_evidence_objects_v1%ROWTYPE;
  v_now timestamptz := clock_timestamp(); v_review_id text; v_execution_id text; v_challenge_id text; v_manifest jsonb; v_manifest_bytes bytea; v_manifest_sha text; v_manifest_id uuid; v_html text; v_html_bytes bytea; v_html_sha text; v_html_id uuid;
BEGIN
  SELECT * INTO STRICT v_old FROM private.lf_p0_human_review_challenges_v1 WHERE challenge_id=p_challenge_id;
  IF v_old.review_lane <> 'P0-4' THEN RAISE EXCEPTION 'P0_4_CHALLENGE_REQUIRED'; END IF;
  IF EXISTS (SELECT 1 FROM private.lf_p0_human_review_decisions_v1 d WHERE d.challenge_id=v_old.challenge_id) THEN RAISE EXCEPTION 'CHALLENGE_ALREADY_DECIDED'; END IF;
  SELECT * INTO STRICT v_old_manifest FROM private.lf_p0_review_evidence_objects_v1 WHERE evidence_object_id=v_old.packet_manifest_object_id AND object_role='PACKET_MANIFEST';
  SELECT * INTO STRICT v_old_browser FROM private.lf_p0_review_evidence_objects_v1 WHERE evidence_object_id=v_old.browser_review_object_id AND object_role='BROWSER_REVIEW';
  v_review_id := 'P0-HUMAN-REVIEW-'||upper(substr(v_old.source_head_sha,1,12))||'-ACTIONABLE-'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDDHH24MISS');
  v_execution_id := 'EXEC-P0-HUMAN-ACTIONABLE-'||substr(v_old.source_head_sha,1,12)||'-'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDDHH24MISS');
  v_challenge_id := 'CH-P0-HUMAN-'||upper(substr(v_old.source_head_sha,1,12))||'-ACTIONABLE-'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDDHH24MISS');
  v_manifest := convert_from(v_old_manifest.content,'UTF8')::jsonb;
  v_manifest := jsonb_set(v_manifest,'{binding,review_id}',to_jsonb(v_review_id),true); v_manifest := jsonb_set(v_manifest,'{binding,challenge_id}',to_jsonb(v_challenge_id),true);
  v_manifest_bytes := convert_to(v_manifest::text,'UTF8'); v_manifest_sha := encode(extensions.digest(v_manifest_bytes,'sha256'),'hex');
  INSERT INTO private.lf_p0_review_evidence_objects_v1(review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_review_id,v_execution_id,'PACKET_MANIFEST','review-manifest-actionable-'||substr(v_old.source_head_sha,1,12)||'.json','application/json',octet_length(v_manifest_bytes),v_manifest_sha,v_manifest_bytes,v_old.data_classification,v_old.source_head_sha,jsonb_build_object('refreshed_from_challenge_id',v_old.challenge_id,'actionable_shell_refresh',true)) RETURNING evidence_object_id INTO v_manifest_id;
  v_html := convert_from(v_old_browser.content,'UTF8'); v_html := replace(v_html,v_old.review_id,v_review_id); v_html := replace(v_html,v_old.challenge_id,v_challenge_id); v_html := replace(v_html,v_old.packet_manifest_object_id::text,v_manifest_id::text); v_html := replace(v_html,v_old.packet_manifest_sha256,v_manifest_sha); v_html_bytes := convert_to(v_html,'UTF8'); v_html_sha := encode(extensions.digest(v_html_bytes,'sha256'),'hex');
  INSERT INTO private.lf_p0_review_evidence_objects_v1(review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_review_id,v_execution_id,'BROWSER_REVIEW','human-review-actionable-'||substr(v_old.source_head_sha,1,12)||'.html','text/html',octet_length(v_html_bytes),v_html_sha,v_html_bytes,v_old.data_classification,v_old.source_head_sha,coalesce(v_old_browser.metadata,'{}'::jsonb)||jsonb_build_object('refreshed_from_challenge_id',v_old.challenge_id,'actionable_shell_refresh',true)) RETURNING evidence_object_id,content_sha256 INTO v_html_id,v_html_sha;
  INSERT INTO private.lf_p0_human_review_challenges_v1(challenge_id,review_id,execution_id,source_head_sha,visual_output_sha256,packet_manifest_sha256,required_reviewer_role,reviewer_actions,evidence_store_ref,issued_at,expires_at,data_classification,dual_review_required,review_lane,review_subject,source_evidence_object_id,source_sha256,visual_output_object_id,packet_manifest_object_id,browser_review_object_id,browser_review_sha256,semantic_fingerprint,element_count,uncertain_count,inferred_count,changed_count,pending_human_count,delta,review_mode,carry_forward_safe,supersedes_challenge_id,convergence_justification)
  VALUES(v_challenge_id,v_review_id,v_execution_id,v_old.source_head_sha,v_old.visual_output_sha256,v_manifest_sha,v_old.required_reviewer_role,v_old.reviewer_actions,v_old.evidence_store_ref,v_now,v_now+interval '24 hours',v_old.data_classification,v_old.dual_review_required,v_old.review_lane,v_old.review_subject,v_old.source_evidence_object_id,v_old.source_sha256,v_old.visual_output_object_id,v_manifest_id,v_html_id,v_html_sha,v_old.semantic_fingerprint,v_old.element_count,v_old.uncertain_count,v_old.inferred_count,v_old.changed_count,v_old.pending_human_count,v_old.delta,v_old.review_mode,v_old.carry_forward_safe,v_old.challenge_id,'ACTIONABLE_REVIEW_SHELL_REFRESH_NO_HUMAN_DEBT_CHANGE');
  RETURN jsonb_build_object('outcome','ACTIONABLE_REVIEW_READY','challenge_id',v_challenge_id,'review_id',v_review_id,'source_head_sha',v_old.source_head_sha,'semantic_fingerprint',v_old.semantic_fingerprint,'changed_count',v_old.changed_count,'pending_human_count',v_old.pending_human_count,'packet_manifest_object_id',v_manifest_id,'packet_manifest_sha256',v_manifest_sha,'browser_review_object_id',v_html_id,'browser_review_sha256',v_html_sha,'supersedes_challenge_id',v_old.challenge_id,'production_authorized',false,'p0_5_authorized',false);
END;
$$;
REVOKE ALL ON FUNCTION public.fn_lf_p0_refresh_actionable_review_v1(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_lf_p0_refresh_actionable_review_v1(text) TO service_role;
COMMENT ON FUNCTION public.fn_lf_p0_refresh_actionable_review_v1(text) IS 'Fail-closed P0-4 review refresh: preserves visual evidence/human debt and reissues only the browser/manifest binding with an actionable challenge-bound decision command.';