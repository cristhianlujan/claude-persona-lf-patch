-- Human Review Convergence Contract v1: append-only lifecycle, exact-bound browser artifact, semantic delta.
ALTER TABLE private.lf_p0_human_review_challenges_v1
  ADD COLUMN IF NOT EXISTS review_lane text NOT NULL DEFAULT 'P0-4',
  ADD COLUMN IF NOT EXISTS review_subject text NOT NULL DEFAULT 'P0_VISUAL_PRIMARY_SCREEN',
  ADD COLUMN IF NOT EXISTS source_evidence_object_id uuid,
  ADD COLUMN IF NOT EXISTS source_sha256 text,
  ADD COLUMN IF NOT EXISTS visual_output_object_id uuid,
  ADD COLUMN IF NOT EXISTS packet_manifest_object_id uuid,
  ADD COLUMN IF NOT EXISTS browser_review_object_id uuid,
  ADD COLUMN IF NOT EXISTS browser_review_sha256 text,
  ADD COLUMN IF NOT EXISTS semantic_fingerprint text,
  ADD COLUMN IF NOT EXISTS element_count integer,
  ADD COLUMN IF NOT EXISTS uncertain_count integer,
  ADD COLUMN IF NOT EXISTS inferred_count integer,
  ADD COLUMN IF NOT EXISTS changed_count integer,
  ADD COLUMN IF NOT EXISTS pending_human_count integer,
  ADD COLUMN IF NOT EXISTS delta jsonb,
  ADD COLUMN IF NOT EXISTS review_mode text,
  ADD COLUMN IF NOT EXISTS carry_forward_safe boolean,
  ADD COLUMN IF NOT EXISTS supersedes_challenge_id text,
  ADD COLUMN IF NOT EXISTS convergence_justification text;

ALTER TABLE private.lf_p0_human_review_challenges_v1
  DROP CONSTRAINT IF EXISTS lf_p0_human_review_challenges_v1_review_lane_check,
  DROP CONSTRAINT IF EXISTS lf_p0_human_review_challenges_v1_review_mode_check,
  DROP CONSTRAINT IF EXISTS lf_p0_human_review_challenges_v1_source_sha256_check,
  DROP CONSTRAINT IF EXISTS lf_p0_human_review_challenges_v1_browser_review_sha256_check,
  DROP CONSTRAINT IF EXISTS lf_p0_human_review_challenges_v1_semantic_fingerprint_check,
  DROP CONSTRAINT IF EXISTS lf_p0_human_review_challenges_v1_counters_check;

ALTER TABLE private.lf_p0_human_review_challenges_v1
  ADD CONSTRAINT lf_p0_human_review_challenges_v1_review_lane_check CHECK (review_lane IN ('P0-4')),
  ADD CONSTRAINT lf_p0_human_review_challenges_v1_review_mode_check CHECK (review_mode IS NULL OR review_mode IN ('HOLISTIC','DELTA')),
  ADD CONSTRAINT lf_p0_human_review_challenges_v1_source_sha256_check CHECK (source_sha256 IS NULL OR source_sha256 ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT lf_p0_human_review_challenges_v1_browser_review_sha256_check CHECK (browser_review_sha256 IS NULL OR browser_review_sha256 ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT lf_p0_human_review_challenges_v1_semantic_fingerprint_check CHECK (semantic_fingerprint IS NULL OR semantic_fingerprint ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT lf_p0_human_review_challenges_v1_counters_check CHECK (
    (element_count IS NULL OR element_count >= 0) AND
    (uncertain_count IS NULL OR uncertain_count >= 0) AND
    (inferred_count IS NULL OR inferred_count >= 0) AND
    (changed_count IS NULL OR changed_count >= 0) AND
    (pending_human_count IS NULL OR pending_human_count >= 0)
  );

ALTER TABLE private.lf_p0_review_evidence_objects_v1
  DROP CONSTRAINT IF EXISTS lf_p0_review_evidence_objects_v1_object_role_check;
ALTER TABLE private.lf_p0_review_evidence_objects_v1
  ADD CONSTRAINT lf_p0_review_evidence_objects_v1_object_role_check CHECK (
    object_role IN ('SOURCE_IMAGE','VISUAL_OUTPUT','CROPS_ZIP','PACKET_MANIFEST','PACKET_ZIP','BROWSER_REVIEW')
  );

DROP TRIGGER IF EXISTS trg_lf_p0_human_review_challenges_v1_immutable ON private.lf_p0_human_review_challenges_v1;
CREATE TRIGGER trg_lf_p0_human_review_challenges_v1_immutable
BEFORE UPDATE OR DELETE ON private.lf_p0_human_review_challenges_v1
FOR EACH ROW EXECUTE FUNCTION private.fn_lf_p0_forbid_mutation_v1();

CREATE OR REPLACE VIEW private.v_lf_p0_human_review_challenge_state_v1 AS
WITH ranked AS (
  SELECT c.*,
         row_number() OVER (PARTITION BY c.review_lane,c.review_subject ORDER BY c.issued_at DESC,c.created_at DESC,c.challenge_id DESC) AS lifecycle_rank
  FROM private.lf_p0_human_review_challenges_v1 c
), checked AS (
  SELECT r.*,
         src.content_sha256 AS observed_source_sha256,
         vis.content_sha256 AS observed_visual_sha256,
         man.content_sha256 AS observed_manifest_sha256,
         br.content_sha256 AS observed_browser_sha256,
         br.source_head_sha AS browser_head_sha
  FROM ranked r
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 src ON src.evidence_object_id=r.source_evidence_object_id AND src.object_role='SOURCE_IMAGE'
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 vis ON vis.evidence_object_id=r.visual_output_object_id AND vis.object_role='VISUAL_OUTPUT'
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 man ON man.evidence_object_id=r.packet_manifest_object_id AND man.object_role='PACKET_MANIFEST'
  LEFT JOIN private.lf_p0_review_evidence_objects_v1 br ON br.evidence_object_id=r.browser_review_object_id AND br.object_role='BROWSER_REVIEW'
)
SELECT checked.*,
       CASE
         WHEN lifecycle_rank > 1 THEN 'SUPERSEDED'
         WHEN expires_at <= now() THEN 'EXPIRED'
         WHEN review_lane <> 'P0-4' THEN 'NOT_REVIEW_READY'
         WHEN source_evidence_object_id IS NULL OR source_sha256 IS NULL OR source_sha256 <> observed_source_sha256 THEN 'NOT_REVIEW_READY'
         WHEN visual_output_object_id IS NULL OR visual_output_sha256 <> observed_visual_sha256 THEN 'NOT_REVIEW_READY'
         WHEN packet_manifest_object_id IS NULL OR packet_manifest_sha256 <> observed_manifest_sha256 THEN 'NOT_REVIEW_READY'
         WHEN browser_review_object_id IS NULL OR browser_review_sha256 <> observed_browser_sha256 OR source_head_sha <> browser_head_sha THEN 'NOT_REVIEW_READY'
         WHEN semantic_fingerprint IS NULL OR element_count IS NULL OR uncertain_count IS NULL OR inferred_count IS NULL OR changed_count IS NULL OR pending_human_count IS NULL OR delta IS NULL OR review_mode IS NULL THEN 'NOT_REVIEW_READY'
         ELSE 'ACTIVE'
       END AS lifecycle_state
FROM checked;

CREATE OR REPLACE VIEW private.v_lf_p0_human_review_active_queue_v1 AS
SELECT * FROM private.v_lf_p0_human_review_challenge_state_v1 WHERE lifecycle_state='ACTIVE';

CREATE OR REPLACE FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(
  p_receipt_evidence_object_id uuid,
  p_source_evidence_object_id uuid,
  p_review_subject text DEFAULT 'P0_VISUAL_PRIMARY_SCREEN'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_receipt private.lf_p0_review_evidence_objects_v1%ROWTYPE;
  v_source private.lf_p0_review_evidence_objects_v1%ROWTYPE;
  v_receipt_json jsonb;
  v_reader jsonb;
  v_elements jsonb;
  v_uncertainties jsonb;
  v_semantic jsonb;
  v_fingerprint text;
  v_element_count int;
  v_uncertain_count int;
  v_inferred_count int;
  v_prev private.lf_p0_human_review_challenges_v1%ROWTYPE;
  v_prev_json jsonb;
  v_prev_elements jsonb := '[]'::jsonb;
  v_prev_semantic jsonb := '[]'::jsonb;
  v_prev_fingerprint text;
  v_changed int := 0;
  v_added int := 0;
  v_removed int := 0;
  v_unchanged int := 0;
  v_prior_decisions int := 0;
  v_pending int;
  v_review_mode text;
  v_review_id text;
  v_execution_id text;
  v_challenge_id text;
  v_now timestamptz := clock_timestamp();
  v_visual_text text;
  v_visual_bytes bytea;
  v_visual_sha text;
  v_visual_id uuid;
  v_manifest jsonb;
  v_manifest_text text;
  v_manifest_bytes bytea;
  v_manifest_sha text;
  v_manifest_id uuid;
  v_binding jsonb;
  v_html text;
  v_html_bytes bytea;
  v_html_sha text;
  v_html_id uuid;
  v_delta jsonb;
  v_existing private.lf_p0_human_review_challenges_v1%ROWTYPE;
BEGIN
  IF p_review_subject IS NULL OR btrim(p_review_subject)='' THEN RAISE EXCEPTION 'REVIEW_SUBJECT_REQUIRED'; END IF;

  SELECT * INTO STRICT v_receipt FROM private.lf_p0_review_evidence_objects_v1 WHERE evidence_object_id=p_receipt_evidence_object_id;
  SELECT * INTO STRICT v_source FROM private.lf_p0_review_evidence_objects_v1 WHERE evidence_object_id=p_source_evidence_object_id;
  IF v_receipt.object_role <> 'PACKET_MANIFEST' THEN RAISE EXCEPTION 'EXACT_RECEIPT_ROLE_INVALID'; END IF;
  IF v_source.object_role <> 'SOURCE_IMAGE' THEN RAISE EXCEPTION 'SOURCE_ROLE_INVALID'; END IF;
  IF coalesce(v_source.metadata->>'holdout','false')::boolean THEN RAISE EXCEPTION 'SEALED_HOLDOUT_FORBIDDEN'; END IF;
  IF v_source.content_sha256 <> coalesce(v_receipt.metadata->>'source_sha256','') THEN RAISE EXCEPTION 'SOURCE_SHA_BINDING_MISMATCH'; END IF;
  IF v_receipt.source_head_sha !~ '^[0-9a-f]{40}$' THEN RAISE EXCEPTION 'HEAD_SHA_INVALID'; END IF;

  v_receipt_json := convert_from(v_receipt.content,'UTF8')::jsonb;
  IF v_receipt_json->>'terminal_result' <> 'READY_FOR_HUMAN_REVIEW_RECHECK' THEN RAISE EXCEPTION 'TECHNICAL_GATE_NOT_REVIEW_READY'; END IF;
  IF v_receipt_json->>'source_sha256' <> v_source.content_sha256 THEN RAISE EXCEPTION 'RECEIPT_SOURCE_SHA_MISMATCH'; END IF;
  IF v_receipt_json->>'code_head_sha' <> v_receipt.source_head_sha THEN RAISE EXCEPTION 'RECEIPT_HEAD_SHA_MISMATCH'; END IF;
  IF jsonb_array_length(coalesce(v_receipt_json->'reader_outputs','[]'::jsonb)) < 1 THEN RAISE EXCEPTION 'FINAL_READER_MISSING'; END IF;

  v_reader := v_receipt_json->'reader_outputs'->(jsonb_array_length(v_receipt_json->'reader_outputs')-1);
  v_elements := coalesce(v_reader->'elements','[]'::jsonb);
  v_uncertainties := coalesce(v_reader->'reader_uncertainties','[]'::jsonb);
  v_element_count := jsonb_array_length(v_elements);
  v_uncertain_count := jsonb_array_length(v_uncertainties);
  SELECT count(*) INTO v_inferred_count FROM jsonb_array_elements(v_elements) e WHERE e->>'classification'='INFERRED';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'element_id',e->>'element_id','element_type',e->>'element_type','region',e->'region','visible_text',e->>'visible_text',
      'ocr_consensus_text',e->>'ocr_consensus_text','classification',e->>'classification','semantic_role',e->>'semantic_role',
      'subcomponent_role',e->>'subcomponent_role','parent_id',e->>'parent_id','state',e->>'state'
    ) ORDER BY e->>'element_id'),'[]'::jsonb)
  INTO v_semantic FROM jsonb_array_elements(v_elements) e;
  v_fingerprint := encode(extensions.digest(convert_to(v_semantic::text,'UTF8'),'sha256'),'hex');

  SELECT * INTO v_existing FROM private.lf_p0_human_review_challenges_v1
  WHERE review_lane='P0-4' AND review_subject=p_review_subject AND source_head_sha=v_receipt.source_head_sha
    AND semantic_fingerprint=v_fingerprint AND browser_review_object_id IS NOT NULL
  ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('outcome','UNCHANGED_REUSED','challenge_id',v_existing.challenge_id,'review_id',v_existing.review_id,'source_head_sha',v_existing.source_head_sha,'semantic_fingerprint',v_fingerprint,'pending_human_count',v_existing.pending_human_count);
  END IF;

  SELECT * INTO v_prev FROM private.lf_p0_human_review_challenges_v1
  WHERE review_lane='P0-4' AND review_subject=p_review_subject ORDER BY issued_at DESC,created_at DESC LIMIT 1;
  IF FOUND THEN
    SELECT convert_from(content,'UTF8')::jsonb INTO v_prev_json FROM private.lf_p0_review_evidence_objects_v1
      WHERE (evidence_object_id=v_prev.visual_output_object_id OR (v_prev.visual_output_object_id IS NULL AND content_sha256=v_prev.visual_output_sha256))
        AND object_role='VISUAL_OUTPUT' ORDER BY (evidence_object_id=v_prev.visual_output_object_id) DESC,created_at DESC LIMIT 1;
    IF v_prev_json IS NOT NULL THEN
      v_prev_elements := CASE WHEN jsonb_typeof(v_prev_json->'elements')='array' THEN v_prev_json->'elements' ELSE coalesce(v_prev_json#>'{final_reader,elements}','[]'::jsonb) END;
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'element_id',e->>'element_id','element_type',e->>'element_type','region',e->'region','visible_text',e->>'visible_text',
        'ocr_consensus_text',e->>'ocr_consensus_text','classification',e->>'classification','semantic_role',e->>'semantic_role',
        'subcomponent_role',e->>'subcomponent_role','parent_id',e->>'parent_id','state',e->>'state'
      ) ORDER BY e->>'element_id'),'[]'::jsonb) INTO v_prev_semantic FROM jsonb_array_elements(v_prev_elements) e;
      v_prev_fingerprint := encode(extensions.digest(convert_to(v_prev_semantic::text,'UTF8'),'sha256'),'hex');
      WITH cur AS (SELECT e->>'element_id' id,e FROM jsonb_array_elements(v_semantic) e), old AS (SELECT e->>'element_id' id,e FROM jsonb_array_elements(v_prev_semantic) e), d AS (
        SELECT coalesce(cur.id,old.id) id,cur.e ce,old.e oe FROM cur FULL JOIN old USING(id)
      ) SELECT count(*) FILTER (WHERE oe IS NULL),count(*) FILTER (WHERE ce IS NULL),count(*) FILTER (WHERE ce=oe),count(*) FILTER (WHERE ce IS NOT NULL AND oe IS NOT NULL AND ce<>oe)
        INTO v_added,v_removed,v_unchanged,v_changed FROM d;
    ELSE
      v_added := v_element_count;
    END IF;
  ELSE
    v_added := v_element_count;
  END IF;

  SELECT count(*) INTO v_prior_decisions FROM private.lf_p0_human_review_decisions_v1 d JOIN private.lf_p0_human_review_challenges_v1 c ON c.challenge_id=d.challenge_id WHERE c.review_lane='P0-4' AND c.review_subject=p_review_subject;
  v_review_mode := CASE WHEN v_prior_decisions=0 THEN 'HOLISTIC' ELSE 'DELTA' END;
  v_pending := CASE WHEN v_review_mode='HOLISTIC' THEN v_element_count ELSE greatest(0,v_added+v_removed+v_changed) END;
  IF v_prev.challenge_id IS NOT NULL AND v_prev_fingerprint=v_fingerprint AND v_prev.pending_human_count IS NOT NULL AND v_pending > v_prev.pending_human_count THEN RAISE EXCEPTION 'HUMAN_DEBT_CONVERGENCE_FAIL'; END IF;

  v_delta := jsonb_build_object('unchanged',v_unchanged,'changed',v_changed,'added',v_added,'removed',v_removed,'invalidated',CASE WHEN v_prev_fingerprint IS NULL OR v_prev_fingerprint=v_fingerprint THEN 0 ELSE v_changed+v_added+v_removed END);
  v_review_id := 'P0-HUMAN-REVIEW-'||upper(substr(v_receipt.source_head_sha,1,12))||'-'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDDHH24MISS');
  v_execution_id := 'EXEC-P0-HUMAN-'||substr(v_receipt.source_head_sha,1,12)||'-'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDDHH24MISS');
  v_challenge_id := 'CH-P0-HUMAN-'||upper(substr(v_receipt.source_head_sha,1,12))||'-'||to_char(v_now AT TIME ZONE 'UTC','YYYYMMDDHH24MISS');

  v_visual_text := v_reader::text; v_visual_bytes:=convert_to(v_visual_text,'UTF8'); v_visual_sha:=encode(extensions.digest(v_visual_bytes,'sha256'),'hex');
  INSERT INTO private.lf_p0_review_evidence_objects_v1(review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_review_id,v_execution_id,'VISUAL_OUTPUT','visual-output-'||substr(v_receipt.source_head_sha,1,12)||'.json','application/json',octet_length(v_visual_bytes),v_visual_sha,v_visual_bytes,v_source.data_classification,v_receipt.source_head_sha,jsonb_build_object('semantic_fingerprint',v_fingerprint,'exact_receipt_object_id',p_receipt_evidence_object_id)) RETURNING evidence_object_id INTO v_visual_id;

  v_binding := jsonb_build_object('source_head_sha',v_receipt.source_head_sha,'source_object_id',p_source_evidence_object_id,'source_sha256',v_source.content_sha256,'visual_output_object_id',v_visual_id,'visual_output_sha256',v_visual_sha,'review_id',v_review_id,'challenge_id',v_challenge_id,'review_lane','P0-4','review_subject',p_review_subject);
  v_manifest := jsonb_build_object('schema_version','p0-human-review-convergence/v1','binding',v_binding,'semantic_fingerprint',v_fingerprint,'delta',v_delta,'counters',jsonb_build_object('element_count',v_element_count,'uncertain_count',v_uncertain_count,'inferred_count',v_inferred_count,'changed_count',v_changed+v_added+v_removed,'pending_human_count',v_pending),'review_mode',v_review_mode,'carry_forward_safe',v_prev_fingerprint=v_fingerprint,'p0_5_separate',true,'sealed_holdout_used',false,'production_authorized',false);
  v_manifest_text:=v_manifest::text; v_manifest_bytes:=convert_to(v_manifest_text,'UTF8'); v_manifest_sha:=encode(extensions.digest(v_manifest_bytes,'sha256'),'hex');
  INSERT INTO private.lf_p0_review_evidence_objects_v1(review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_review_id,v_execution_id,'PACKET_MANIFEST','review-manifest-'||substr(v_receipt.source_head_sha,1,12)||'.json','application/json',octet_length(v_manifest_bytes),v_manifest_sha,v_manifest_bytes,v_source.data_classification,v_receipt.source_head_sha,jsonb_build_object('exact_receipt_object_id',p_receipt_evidence_object_id)) RETURNING evidence_object_id INTO v_manifest_id;
  v_binding := v_binding || jsonb_build_object('packet_manifest_object_id',v_manifest_id,'packet_manifest_sha256',v_manifest_sha,'generated_at',v_now);

  v_html := '<!doctype html><html lang="es" data-review-shell-version="4.2"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>P0 VISUAL HUMAN REVIEW V4</title><style>body{font-family:system-ui;margin:0;background:#eef2f6;color:#172334}header{position:sticky;top:0;background:#06192b;color:white;padding:12px;z-index:5}.grid{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(320px,.85fr);gap:12px;padding:12px}.card{background:white;border:1px solid #d7e0e8;border-radius:10px;overflow:hidden}#source-stage{position:relative;overflow:auto}#source-image{width:100%;display:block}.overlay{position:absolute;border:2px solid #145edb;background:#145edb11;cursor:pointer}.item{padding:8px;border-bottom:1px solid #eee;cursor:pointer}.item.changed{background:#fff6df}#detail-panel,#decision-bar{padding:12px}.decision-btn{margin:4px;padding:8px}.meta{font-size:12px;opacity:.8}@media (max-width: 767px){.grid{grid-template-columns:1fr}.card{min-height:0}} </style></head><body><header><b>P0 VISUAL HUMAN REVIEW V4</b><div class="meta">HEAD '||v_receipt.source_head_sha||' · challenge '||v_challenge_id||' · modo '||v_review_mode||'</div></header><div class="grid"><section class="card"><div id="source-stage"><img id="source-image" alt="Pantalla fuente" src="data:'||v_source.mime_type||';base64,'||encode(v_source.content,'base64')||'"><div id="overlay"></div></div></section><section class="card"><div id="element-list"></div><div id="detail-panel">Seleccione un elemento.</div><div id="selected-crop" hidden></div><div id="decision-bar"><button class="decision-btn" data-action="CONFIRM_OBSERVATION">Confirmar</button><button class="decision-btn" data-action="CORRECT_WITH_ADJUDICATION">Corregir</button><button class="decision-btn" data-action="REQUEST_NEW_CAPTURE">Nueva captura</button><button class="decision-btn" data-action="REQUEST_ADDITIONAL_CONTEXT">Contexto</button><button class="decision-btn" data-action="REJECT_AND_BLOCK">Bloquear</button><button class="decision-btn" data-action="ESCALATE_SECURITY">Seguridad</button><button class="decision-btn" data-action="ESCALATE_PRIVACY">Privacidad</button></div></section></div><script id="p0-review-binding-v1" type="application/json">'||replace(v_binding::text,'</','<\/')||'</script><script id="p0-review-data-v1" type="application/json">'||replace(v_elements::text,'</','<\/')||'</script><script>const binding=JSON.parse(document.getElementById("p0-review-binding-v1").textContent);const els=JSON.parse(document.getElementById("p0-review-data-v1").textContent);const list=document.getElementById("element-list"),detail=document.getElementById("detail-panel"),overlay=document.getElementById("overlay"),img=document.getElementById("source-image");function select(e){detail.textContent=JSON.stringify({id:e.element_id,text:e.visible_text||e.ocr_consensus_text||"",classification:e.classification,region:e.region},null,2)}els.forEach(e=>{const row=document.createElement("div");row.className="item";row.textContent=(e.element_id||"")+" · "+(e.visible_text||e.ocr_consensus_text||e.semantic_role||e.element_type||"");row.onclick=()=>select(e);list.appendChild(row)});function boxes(){overlay.replaceChildren();const w=img.naturalWidth||1,h=img.naturalHeight||1;els.forEach(e=>{const r=e.region;if(!r)return;const b=document.createElement("button");b.className="overlay";b.style.left=(100*r.x/w)+"%";b.style.top=(100*r.y/h)+"%";b.style.width=(100*r.width/w)+"%";b.style.height=(100*r.height/h)+"%";b.title=e.element_id||"";b.onclick=()=>select(e);overlay.appendChild(b)})}img.addEventListener("load",boxes);new ResizeObserver(boxes).observe(img);</script></body></html>';
  v_html_bytes:=convert_to(v_html,'UTF8'); v_html_sha:=encode(extensions.digest(v_html_bytes,'sha256'),'hex');
  INSERT INTO private.lf_p0_review_evidence_objects_v1(review_id,execution_id,object_role,object_name,mime_type,content_bytes,content_sha256,content,data_classification,source_head_sha,metadata)
  VALUES(v_review_id,v_execution_id,'BROWSER_REVIEW','human-review-'||substr(v_receipt.source_head_sha,1,12)||'.html','text/html',octet_length(v_html_bytes),v_html_sha,v_html_bytes,v_source.data_classification,v_receipt.source_head_sha,jsonb_build_object('binding',v_binding,'shell_version','4.2','navigable',true)) RETURNING evidence_object_id INTO v_html_id;

  INSERT INTO private.lf_p0_human_review_challenges_v1(challenge_id,review_id,execution_id,source_head_sha,visual_output_sha256,packet_manifest_sha256,required_reviewer_role,reviewer_actions,evidence_store_ref,issued_at,expires_at,data_classification,dual_review_required,review_lane,review_subject,source_evidence_object_id,source_sha256,visual_output_object_id,packet_manifest_object_id,browser_review_object_id,browser_review_sha256,semantic_fingerprint,element_count,uncertain_count,inferred_count,changed_count,pending_human_count,delta,review_mode,carry_forward_safe,supersedes_challenge_id,convergence_justification)
  VALUES(v_challenge_id,v_review_id,v_execution_id,v_receipt.source_head_sha,v_visual_sha,v_manifest_sha,'P0_VISUAL_ADJUDICATOR','["CONFIRM_OBSERVATION","CORRECT_WITH_ADJUDICATION","REQUEST_NEW_CAPTURE","REQUEST_ADDITIONAL_CONTEXT","REJECT_AND_BLOCK","ESCALATE_SECURITY","ESCALATE_PRIVACY"]'::jsonb,'private.lf_p0_review_evidence_objects_v1',v_now,v_now+interval '24 hours',v_source.data_classification,v_source.data_classification='SENSITIVE','P0-4',p_review_subject,p_source_evidence_object_id,v_source.content_sha256,v_visual_id,v_manifest_id,v_html_id,v_html_sha,v_fingerprint,v_element_count,v_uncertain_count,v_inferred_count,v_changed+v_added+v_removed,v_pending,v_delta,v_review_mode,v_prev_fingerprint=v_fingerprint,v_prev.challenge_id,CASE WHEN v_prev_fingerprint=v_fingerprint THEN 'SEMANTICALLY_EQUIVALENT_REFRESH_NO_HUMAN_DEBT_INCREASE' ELSE 'MATERIAL_DELTA_REQUIRES_REVIEW' END);

  RETURN jsonb_build_object('outcome','REVIEW_READY','review_id',v_review_id,'challenge_id',v_challenge_id,'source_head_sha',v_receipt.source_head_sha,'source_sha256',v_source.content_sha256,'visual_output_object_id',v_visual_id,'visual_output_sha256',v_visual_sha,'packet_manifest_object_id',v_manifest_id,'packet_manifest_sha256',v_manifest_sha,'browser_review_object_id',v_html_id,'browser_review_sha256',v_html_sha,'semantic_fingerprint',v_fingerprint,'delta',v_delta,'element_count',v_element_count,'uncertain_count',v_uncertain_count,'inferred_count',v_inferred_count,'changed_count',v_changed+v_added+v_removed,'pending_human_count',v_pending,'review_mode',v_review_mode,'supersedes_challenge_id',v_prev.challenge_id,'production_authorized',false,'p0_5_authorized',false);
END; $$;

REVOKE ALL ON FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_lf_p0_materialize_convergent_review_v1(uuid,uuid,text) TO service_role;