BEGIN;
-- Read-only compiler. Templates own fixed zones; order components own the content.
CREATE FUNCTION saly.creative_template_review_v1(p_item bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,saly,visual,extensions AS $fn$
DECLARE u record; t jsonb; c jsonb; b record; tok record; target text; seen text[];
 rec text; trace jsonb:='[]'; lines text[]; ctx jsonb; brief text;
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
 FOR c IN SELECT value FROM jsonb_array_elements(u.plan->'components') LOOP
   rec:=coalesce(t->'owners'->>(c->>'code'),'native');
   IF rec NOT IN ('native','composition') THEN RAISE EXCEPTION 'BAD_COMPONENT_OWNER'; END IF;
   IF rec='native' THEN lines:=array_append(lines,c->>'instruction'); END IF;
   FOR b IN SELECT key,value FROM jsonb_each_text(c->'bindings') ORDER BY key COLLATE "C" LOOP
     target:=b.value; seen:=ARRAY[]::text[];
     LOOP
       IF target=ANY(seen) THEN RAISE EXCEPTION 'ALIAS_CYCLE'; END IF;
       seen:=array_append(seen,target);
       SELECT v.id,v.value_json->'value' val,v.metadata->>'alias_target_code' alias,v.approval_status
       INTO STRICT tok FROM saly.creative_context_tokens ct JOIN saly.identity_versions v ON v.id=ct.identity_version_id
       JOIN saly.identity_elements e ON e.id=v.element_id WHERE ct.context_set_id=u.context_set_id AND e.code=target
       AND EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'tokens') x WHERE x->>'code'=target)
       AND ct.value_sha256=encode(extensions.digest(v.value_json::text,'sha256'),'hex');
       EXIT WHEN tok.alias IS NULL; target:=tok.alias;
     END LOOP;
     IF tok.val IS NULL OR left(tok.val#>>'{}',1)='{' THEN RAISE EXCEPTION 'EMPTY_OR_UNRESOLVED_TOKEN'; END IF;
     trace:=trace||jsonb_build_array(jsonb_build_object('component',c->>'code','property',b.key,'consumer',rec,
      'chain',seen,'value',tok.val,'version_id',tok.id,'status',tok.approval_status));
     IF rec='native' THEN lines:=array_append(lines,format('%s · %s: %s.',c->>'code',b.key,tok.val#>>'{}')); END IF;
   END LOOP;
 END LOOP;
 brief:=array_to_string(lines,chr(10));
 RETURN jsonb_build_object('order_id',u.oid,'item_id',p_item,'template',u.standard_code,'template_version_id',u.vid,
 'template_version',u.version,'template_sha256',u.manifest_sha256,'native_prompt',brief,'trace',trace,
 'prompt_sha256',encode(extensions.digest(convert_to(brief,'UTF8'),'sha256'),'hex'),'attachments','[]'::jsonb,
 'composition',t->'composition','navigation_active',u.plan->'navigation_active','cta_copy',(SELECT x->>'instruction' FROM jsonb_array_elements(u.plan->'components') x WHERE x->>'code'='cta'),'logo',t->'logo','mode','REVIEW_ONLY','transmitted',false);
END $fn$;
REVOKE ALL ON FUNCTION saly.creative_template_review_v1(bigint) FROM PUBLIC,anon,authenticated;
DO $seed$
DECLARE proj bigint; ctx bigint; ord bigint; sid bigint; vid bigint; iid bigint; first_item bigint;
 lg jsonb; plan jsonb; t record; spec jsonb; tsha text; chosen jsonb; result jsonb;
BEGIN
 SELECT id INTO STRICT proj FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO';
 SELECT id INTO STRICT ctx FROM saly.creative_context_sets WHERE project_id=proj AND code='SALY_HOME_FIRST' AND version_label='0.3' AND state='SEALED';
 SELECT jsonb_build_object('id',id,'code',code,'version',version_number,'sha256',sha256) INTO STRICT lg
 FROM saly.brand_assets WHERE project_id=proj AND code='logo.primary.transparent' AND approval_status='APPROVED' AND version_number=1 AND sha256 IS NOT NULL;
 plan:=$json$
 {"objective":"Diseña una Home móvil SALY para que el empleado vea su disponible y pueda solicitar un adelanto.",
 "body":"Una pantalla vertical. Diseña la composición del cuerpo desde cero. Conserva estas etiquetas y datos de muestra. No añadas cifras, fechas ni funciones.",
 "basis":"Interpretación de la solicitud y contenido funcional del piloto Home anterior. Jerarquía interior abierta.",
 "navigation_active":"Inicio","components":[
 {"code":"identidad","instruction":"Usa el acento de marca en el cuerpo.","bindings":{"acento":"color.brand.primary"}},
 {"code":"disponible","instruction":"Hola, Cristhian. Disponible para adelanto: S/ 575. Próximo descuento: 28 nov. Adelantos retirados: S/ 300. Mi disponible: Cómo se calcula.","bindings":{}},
 {"code":"servicios","instruction":"Incluye Saly Plus, Saly Rewards y Beneficios. Texto de Rewards: Participa en sorteos y gana premios exclusivos.","bindings":{}},
 {"code":"cta","instruction":"Solicitar adelanto","bindings":{"fondo":"color.action.primary.bg","texto":"candidate.saly_ds_v1.color.surface.white"}},
 {"code":"navegacion","instruction":"Navegación: Inicio, Historial, Explorar, Perfil. Inicio activo. Propón su presentación.","bindings":{"activa":"candidate.saly_home_v3.semantic.color.navigation.active","fondo":"candidate.saly_home_v3.semantic.color.navigation.background"}}]}
 $json$::jsonb;
 INSERT INTO saly.creative_orders(project_id,code,request_key,title,request_kind,design_mode,requested_by,scope_json,status,context_set_id)
 VALUES(proj,'SALY_HOME_TEMPLATE_AB_001','SALY_HOME_TEMPLATE_AB_001','Home SALY con plantillas A y B','APP_SCREEN_BATCH','EXPLORE','SALY_DIGITAL_FACTORY',
 jsonb_build_object('literal_request',$request$Así es con a y b hay que hacer el pedido del home. 

Primero quiero ver cuál es la estrategia o el handoff que se utilizar.

Por eso anda corriendo paso a paso y muestras los valores para ver qué llegó$request$,
 'strategy',plan,'review_only',true,'render_authorized',false),'PLANIFICADO',ctx) RETURNING id INTO ord;
 SELECT jsonb_agg(DISTINCT b.value ORDER BY b.value) INTO chosen FROM jsonb_array_elements(plan->'components') c CROSS JOIN LATERAL jsonb_each_text(c->'bindings') b;
 FOR t IN SELECT * FROM (VALUES
 ('HOME_A','SALY_TEMPLATE_IPHONE16PRO',1,'iPhone 16 Pro','Propón espacio para el logo oficial y el botón «Solicitar adelanto». Diseña solo la interfaz dentro del iPhone 16 Pro.',
 'Marco iPhone 16 Pro y área útil. Colocar logo y CTA en las zonas propuestas. Marco aislado pendiente de validar.'),
 ('HOME_B','SALY_TEMPLATE_PHONE_LOGO_FOOTER',2,'Celular con logo y footer','Reserva cabecera para el logo, espacio para «Solicitar adelanto» y footer inferior fijo. Diseña solo el cuerpo.',
 'Marco de celular, logo oficial en cabecera, CTA y footer inferior con iconos y etiquetas Inicio, Historial, Explorar y Perfil. La sección activa la indica el pedido. Medidas, marco aislado y juego de iconos pendientes de verificar.')
 ) AS seed(item_code,template_code,n,title,native_layout,composition) ORDER BY n LOOP
   spec:=jsonb_build_object('type','MOBILE_TEMPLATE_REVIEW_V1','name',t.title,'logo',lg,'native_layout',t.native_layout,
     'composition',t.composition,'owners',CASE WHEN t.n=1 THEN '{"cta":"composition"}'::jsonb ELSE '{"cta":"composition","navegacion":"composition"}'::jsonb END);
   INSERT INTO visual.standards(brand_code,standard_code,kind) VALUES('SALY',t.template_code,'APP_MOCKUP') RETURNING id INTO sid;
   INSERT INTO visual.standard_versions(standard_id,brand_code,kind,version,manifest_json,state)
   VALUES(sid,'SALY','APP_MOCKUP','0.1',spec,'CANDIDATE') RETURNING id,manifest_sha256 INTO vid,tsha;
   INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,variant_of_item_id,title,acceptance_json,context_json)
   VALUES(ord,t.item_code,t.n,CASE WHEN t.n=1 THEN 'SCREEN' ELSE 'VARIANT' END,first_item,t.title,
    '{"qa_required":true,"review_only":true}',jsonb_build_object('template_version_id',vid,'template_sha256',tsha,'token_codes',chosen,
    'screen_spec',jsonb_build_object('screen','HOME','mode','TEMPLATE_REVIEW'))) RETURNING id INTO iid;
   IF t.n=1 THEN first_item:=iid; END IF;
   result:=saly.creative_template_review_v1(iid);
   IF jsonb_array_length(result->'trace')<>5 OR result->'transmitted'<>'false'::jsonb
      OR (t.n=2 AND position('Navegación: Inicio' IN result->>'native_prompt')>0) THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
   UPDATE saly.creative_order_items SET context_json=context_json||jsonb_build_object('handoff_review',result) WHERE id=iid;
 END LOOP;
END $seed$;
COMMIT;
