BEGIN;
DO $guard$
BEGIN
 IF md5(pg_get_functiondef('saly.creative_template_review_v1(bigint)'::regprocedure)) <> '301817c34074093298e78d04ca4c0234' THEN
  RAISE EXCEPTION 'COMPILER_BASE_CHANGED';
 END IF;
END $guard$;

CREATE OR REPLACE FUNCTION saly.creative_template_review_v1(p_item bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'saly', 'visual', 'extensions'
AS $function$
DECLARE u record; t jsonb; c jsonb; b record; tok record; target text; seen text[];
 rec text; trace jsonb:='[]'; lines text[]; ctx jsonb; brief text; style_bindings jsonb; rendered text;
BEGIN
 SELECT o.id oid,o.context_set_id,o.scope_json->'strategy' plan,i.code,
  v.manifest_json tpl,v.id vid,v.version,v.manifest_sha256,s.standard_code INTO STRICT u
 FROM saly.creative_order_items i JOIN saly.creative_orders o ON o.id=i.order_id
 JOIN saly.proyecto p ON p.id=o.project_id JOIN visual.standard_versions v ON v.id=(i.context_json->>'template_version_id')::bigint
 JOIN visual.standards s ON s.id=v.standard_id
 WHERE i.id=p_item AND p.codigo='SALY-001' AND v.brand_code='SALY' AND v.state='CANDIDATE'
 AND o.design_mode='EXPLORE' AND v.manifest_sha256=i.context_json->>'template_sha256'
 AND v.manifest_json->>'type'='MOBILE_TEMPLATE_REVIEW_V1';
 ctx:=saly.creative_item_context_l2a(p_item); t:=u.tpl;
 lines:=ARRAY[u.plan->>'objective',u.plan->>'body',t->>'native_layout'];
 style_bindings:=coalesce(t->'style_bindings','{}'::jsonb);
 IF jsonb_typeof(style_bindings) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'BAD_TEMPLATE_STYLE_BINDINGS'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_each(style_bindings) d
   WHERE jsonb_typeof(d.value) IS DISTINCT FROM 'object'
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(u.plan->'components') x WHERE x->>'code'=d.key))
 THEN RAISE EXCEPTION 'BAD_TEMPLATE_STYLE_COMPONENT'; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(u.plan->'components') LOOP
   rec:=coalesce(t->'owners'->>(c->>'code'),'native');
   IF rec NOT IN ('native','composition') THEN RAISE EXCEPTION 'BAD_COMPONENT_OWNER'; END IF;
   IF rec='native' THEN lines:=array_append(lines,c->>'instruction'); END IF;
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(style_bindings->(c->>'code'),'{}'::jsonb)) k
      WHERE c->'bindings' ? k) THEN RAISE EXCEPTION 'TEMPLATE_STYLE_BINDING_COLLISION'; END IF;
   FOR b IN SELECT key,value FROM jsonb_each_text(c->'bindings'||coalesce(style_bindings->(c->>'code'),'{}'::jsonb)) ORDER BY key COLLATE "C" LOOP
     target:=b.value; seen:=ARRAY[]::text[];
     LOOP
       IF target=ANY(seen) THEN RAISE EXCEPTION 'ALIAS_CYCLE'; END IF;
       seen:=array_append(seen,target);
       SELECT v.id,v.value_json->'value' val,v.metadata->>'alias_target_code' alias,v.approval_status,e.family
       INTO STRICT tok FROM saly.creative_context_tokens ct JOIN saly.identity_versions v ON v.id=ct.identity_version_id
       JOIN saly.identity_elements e ON e.id=v.element_id WHERE ct.context_set_id=u.context_set_id AND e.code=target
       AND EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'tokens') x WHERE x->>'code'=target)
       AND ct.value_sha256=encode(extensions.digest(v.value_json::text,'sha256'),'hex');
       EXIT WHEN tok.alias IS NULL; target:=tok.alias;
     END LOOP;
     IF tok.val IS NULL OR jsonb_typeof(tok.val)='null' THEN RAISE EXCEPTION 'EMPTY_OR_UNRESOLVED_TOKEN'; END IF;
     IF jsonb_typeof(tok.val)='object' THEN
       IF tok.family IS DISTINCT FROM 'TYPOGRAPHY'
          OR NOT (tok.val ?& ARRAY['size_px','weight','line_height_px'])
          OR (tok.val - ARRAY['size_px','weight','line_height_px']) <> '{}'::jsonb
          OR jsonb_typeof(tok.val->'size_px') IS DISTINCT FROM 'number'
          OR jsonb_typeof(tok.val->'weight') IS DISTINCT FROM 'number'
          OR jsonb_typeof(tok.val->'line_height_px') IS DISTINCT FROM 'number'
       THEN RAISE EXCEPTION 'UNSUPPORTED_STRUCTURED_TOKEN'; END IF;
       IF (tok.val->>'size_px')::numeric<=0
          OR (tok.val->>'line_height_px')::numeric<=0
          OR (tok.val->>'weight')::numeric NOT BETWEEN 1 AND 1000
       THEN RAISE EXCEPTION 'INVALID_TYPOGRAPHY_TOKEN'; END IF;
       rendered:=format('%s px, peso %s, interlineado %s px',tok.val->>'size_px',tok.val->>'weight',tok.val->>'line_height_px');
     ELSIF jsonb_typeof(tok.val) IN ('number','string','boolean') THEN
       rendered:=tok.val#>>'{}';
       IF nullif(btrim(rendered),'') IS NULL THEN RAISE EXCEPTION 'EMPTY_OR_UNRESOLVED_TOKEN'; END IF;
     ELSE RAISE EXCEPTION 'UNSUPPORTED_STRUCTURED_TOKEN';
     END IF;
     trace:=trace||jsonb_build_array(jsonb_build_object('component',c->>'code','property',b.key,'consumer',rec,
      'chain',seen,'value',tok.val,'version_id',tok.id,'status',tok.approval_status));
     IF rec='native' THEN lines:=array_append(lines,format('%s · %s: %s.',c->>'code',b.key,rendered)); END IF;
   END LOOP;
 END LOOP;
 brief:=array_to_string(lines,chr(10));
 RETURN jsonb_build_object('order_id',u.oid,'item_id',p_item,'template',u.standard_code,'template_version_id',u.vid,
 'template_version',u.version,'template_sha256',u.manifest_sha256,'native_prompt',brief,'trace',trace,
 'prompt_sha256',encode(extensions.digest(convert_to(brief,'UTF8'),'sha256'),'hex'),'attachments','[]'::jsonb,
 'composition',t->'composition','navigation_active',u.plan->'navigation_active','cta_copy',(SELECT x->>'instruction' FROM jsonb_array_elements(u.plan->'components') x WHERE x->>'code'='cta'),'logo',t->'logo','mode','REVIEW_ONLY','transmitted',false);
END $function$;

DO $review$
DECLARE
 prev visual.standard_versions%ROWTYPE;
 item saly.creative_order_items%ROWTYPE;
 a_before jsonb;
 b_compiled jsonb;
 v_id bigint;
 v_sha text;
 bad_id bigint;
 bad_sha text;
 bad_spec jsonb;
 spec jsonb;
 n integer;
BEGIN
 SELECT i.* INTO STRICT item FROM saly.creative_order_items i
 JOIN saly.creative_orders o ON o.id=i.order_id
 WHERE i.id=9 AND i.code='HOME_B' AND i.status='PENDIENTE' AND o.id=5
 AND o.scope_json->'render_authorized'='false'::jsonb
 AND i.context_json->'handoff_review'->'transmitted'='false'::jsonb
 AND i.context_json->>'template_version_id'='4' FOR UPDATE OF i;
 SELECT * INTO STRICT prev FROM visual.standard_versions
 WHERE id=4 AND brand_code='SALY' AND version='0.2' AND state='CANDIDATE'
 AND manifest_sha256=item.context_json->>'template_sha256'
 AND manifest_sha256='22a0698d002a7e6a537e98084521729e3cbf768cbf3a30449f9ca37ccf58b416';
 SELECT context_json->'handoff_review' INTO STRICT a_before FROM saly.creative_order_items WHERE id=8 AND code='HOME_A';
 IF a_before IS DISTINCT FROM saly.creative_template_review_v1(8) THEN RAISE EXCEPTION 'HOME_A_RECOMPILE_REGRESSION'; END IF;
 IF item.context_json->'handoff_review' IS DISTINCT FROM saly.creative_template_review_v1(9) THEN RAISE EXCEPTION 'HOME_B_BASE_RECOMPILE_REGRESSION'; END IF;
 spec:=prev.manifest_json||jsonb_build_object('style_bindings',$json${"identidad":{"fuente base":"candidate.saly_ds_v1.typography.font.family.base"},"disponible":{"tipografía monto principal":"candidate.saly_ds_v1.typography.font.amount.hero","radio tarjeta principal (px)":"candidate.saly_ds_v1.radius.radius.card.hero"},"servicios":{"radio tarjetas secundarias (px)":"candidate.saly_ds_v1.radius.radius.card.secondary"},"cta":{"fuente base":"candidate.saly_ds_v1.typography.font.family.base","tipografía botón":"candidate.saly_ds_v1.typography.font.button.primary","radio botón (px)":"candidate.saly_ds_v1.radius.radius.button.primary"}}$json$::jsonb);
 INSERT INTO visual.standard_versions(standard_id,brand_code,kind,version,parent_version_id,manifest_json,state)
 VALUES(prev.standard_id,prev.brand_code,prev.kind,'0.3',prev.id,spec,'CANDIDATE')
 RETURNING id,manifest_sha256 INTO v_id,v_sha;
 UPDATE saly.creative_order_items SET context_json=context_json||jsonb_build_object(
 'template_version_id',v_id,'template_sha256',v_sha,
 'token_codes',(SELECT jsonb_agg(DISTINCT code ORDER BY code) FROM (
 SELECT jsonb_array_elements_text(item.context_json->'token_codes') AS code
 UNION ALL
 SELECT b.value FROM jsonb_each(spec->'style_bindings') c CROSS JOIN LATERAL jsonb_each_text(c.value) b
 ) selected)) WHERE id=item.id;
 b_compiled:=saly.creative_template_review_v1(item.id);
 WITH expected(component,property,version_id,consumer) AS (VALUES
('identidad','fuente base',34,'native'),
('disponible','tipografía monto principal',35,'native'),
('disponible','radio tarjeta principal (px)',49,'native'),
('servicios','radio tarjetas secundarias (px)',50,'native'),
('cta','fuente base',34,'composition'),
('cta','tipografía botón',41,'composition'),
('cta','radio botón (px)',51,'composition')
 )
 SELECT count(*) INTO n FROM expected e
 JOIN LATERAL jsonb_array_elements(b_compiled->'trace') x ON x->>'component'=e.component AND x->>'property'=e.property
 AND (x->>'version_id')::bigint=e.version_id AND x->>'consumer'=e.consumer AND x->>'status'='CANDIDATE'
 JOIN saly.identity_versions iv ON iv.id=e.version_id AND x->'value'=iv.value_json->'value';
 IF n<>7 OR jsonb_array_length(b_compiled->'trace')<>12
 OR position('48 px, peso 700, interlineado 56 px' IN b_compiled->>'native_prompt')=0
 OR position('Inter, system-ui, sans-serif' IN b_compiled->>'native_prompt')=0
 OR position('radio tarjeta principal (px): 24' IN b_compiled->>'native_prompt')=0
 OR position('radio tarjetas secundarias (px): 16' IN b_compiled->>'native_prompt')=0
 OR position('radio botón' IN b_compiled->>'native_prompt')<>0
 OR position('tipografía botón' IN b_compiled->>'native_prompt')<>0
 OR b_compiled->'composition' IS DISTINCT FROM prev.manifest_json->'composition'
 OR b_compiled->'logo' IS DISTINCT FROM prev.manifest_json->'logo'
 OR b_compiled->>'mode' IS DISTINCT FROM 'REVIEW_ONLY'
 OR b_compiled->'transmitted' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'HOME_B_TYPED_HANDOFF_MISMATCH'; END IF;
 -- Exercise an unsupported structured token through the real compiler.
 -- A nested exception rolls back the temporary version and item pointer.
 BEGIN
  bad_spec:=jsonb_set(spec,'{style_bindings,disponible,tipografía monto principal}',
   to_jsonb('candidate.saly_home_v3.elevation.card.hero'::text));
  INSERT INTO visual.standard_versions(standard_id,brand_code,kind,version,parent_version_id,manifest_json,state)
  VALUES(prev.standard_id,prev.brand_code,prev.kind,'0.3-negative-test',v_id,bad_spec,'CANDIDATE')
  RETURNING id,manifest_sha256 INTO bad_id,bad_sha;
  UPDATE saly.creative_order_items SET context_json=context_json||jsonb_build_object(
 'template_version_id',bad_id,'template_sha256',bad_sha,
 'token_codes',(context_json->'token_codes')||jsonb_build_array('candidate.saly_home_v3.elevation.card.hero')) WHERE id=item.id;
  PERFORM saly.creative_template_review_v1(item.id);
  RAISE EXCEPTION 'NEGATIVE_TEST_UNEXPECTED_PASS';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM IS DISTINCT FROM 'UNSUPPORTED_STRUCTURED_TOKEN' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM visual.standard_versions WHERE standard_id=prev.standard_id AND version='0.3-negative-test')
 OR b_compiled IS DISTINCT FROM saly.creative_template_review_v1(item.id)
 THEN RAISE EXCEPTION 'NEGATIVE_TEST_ROLLBACK_FAILED'; END IF;
 UPDATE saly.creative_order_items SET context_json=jsonb_set(context_json,'{handoff_review}',b_compiled) WHERE id=item.id;
 IF (SELECT context_json->'handoff_review' FROM saly.creative_order_items WHERE id=8) IS DISTINCT FROM a_before
 OR a_before IS DISTINCT FROM saly.creative_template_review_v1(8)
 THEN RAISE EXCEPTION 'HOME_A_CHANGED'; END IF;
END $review$;
COMMIT;
