BEGIN;
DO $review$
DECLARE
  previous visual.standard_versions%ROWTYPE;
  item saly.creative_order_items%ROWTYPE;
  geometry jsonb := '{"units":"logical_px","origin":"top_left","viewport":[400,848],"header":[0,0,400,80],"logo":[24,24,104,32],"primary":[0,80,400,212],"cta":[32,292,336,48],"details":[0,340,400,428],"footer":[0,768,400,80],"footer_columns":4}'::jsonb;
  layout_text text;
  spec jsonb;
  compiled jsonb;
  version_id bigint;
  version_sha text;
BEGIN
  SELECT i.* INTO STRICT item FROM saly.creative_order_items i
  JOIN saly.creative_orders o ON o.id=i.order_id
  WHERE o.code='SALY_HOME_TEMPLATE_AB_001' AND i.code='HOME_B'
    AND i.status='PENDIENTE' AND o.scope_json->'render_authorized'='false'::jsonb
    AND i.context_json->'handoff_review'->'transmitted'='false'::jsonb
  FOR UPDATE OF i;
  SELECT v.* INTO STRICT previous FROM visual.standard_versions v
  JOIN visual.standards s ON s.id=v.standard_id
  WHERE v.id=(item.context_json->>'template_version_id')::bigint
    AND v.manifest_sha256=item.context_json->>'template_sha256'
    AND s.standard_code='SALY_TEMPLATE_PHONE_LOGO_FOOTER' AND v.brand_code='SALY'
    AND v.version='0.1' AND v.state='CANDIDATE';
  layout_text := format('Lienzo interior %s × %s. Origen arriba a la izquierda. Cajas [x,y,ancho,alto] en píxeles lógicos. Deja vacías la cabecera %s, la caja del botón %s y la navegación %s. En %s coloca el saludo, la etiqueta de disponible y el monto como primer foco visual. En %s agrupa el próximo descuento, el total retirado y cómo se calcula el disponible, seguidos por los tres servicios. Puedes variar la disposición de los servicios. Omite marco, logo, botón, navegación y adornos.',
    geometry#>>'{viewport,0}',geometry#>>'{viewport,1}',geometry->'header',geometry->'cta',geometry->'footer',geometry->'primary',geometry->'details');
  spec := previous.manifest_json || jsonb_build_object('native_layout',layout_text,'composition',jsonb_build_object(
    'geometry',geometry,'logo_fit','contain','logo_align','left_center','navigation_labels',jsonb_build_array('Inicio','Historial','Explorar','Perfil'),
    'pending_assets',jsonb_build_array('isolated_frame','navigation_icons'),'render_ready',false));
  INSERT INTO visual.standard_versions(standard_id,brand_code,kind,version,parent_version_id,manifest_json,state)
    VALUES(previous.standard_id,previous.brand_code,previous.kind,'0.2',previous.id,spec,'CANDIDATE')
    RETURNING id,manifest_sha256 INTO version_id,version_sha;
  UPDATE saly.creative_order_items SET context_json=context_json || jsonb_build_object(
    'template_version_id',version_id,'template_sha256',version_sha)
    WHERE id=item.id;
  compiled := saly.creative_template_review_v1(item.id);
  IF compiled->'composition'->'geometry' IS DISTINCT FROM geometry
    OR compiled->'logo' IS DISTINCT FROM previous.manifest_json->'logo'
    OR position(layout_text IN compiled->>'native_prompt')=0
    OR compiled->>'mode' IS DISTINCT FROM 'REVIEW_ONLY'
    OR compiled->'transmitted' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'Home B geometry or review handoff mismatch';
  END IF;
  UPDATE saly.creative_order_items SET context_json=jsonb_set(context_json,'{handoff_review}',compiled) WHERE id=item.id;
END $review$;
COMMIT;
