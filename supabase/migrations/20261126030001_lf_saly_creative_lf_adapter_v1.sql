BEGIN;
CREATE OR REPLACE FUNCTION saly.creative_lf_identity_packet_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,lf_design AS $fn$
 SELECT jsonb_build_object('business_code','LF','design_system',to_jsonb(ds),
 'tokens',jsonb_build_object(
 'colors',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.color_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'typography',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.typography_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'spacing',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.token_name),'[]'::jsonb) FROM lf_design.spacing_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'components',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.component_token_code),'[]'::jsonb) FROM lf_design.component_tokens t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE'),
 'themes',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.theme_binding_code),'[]'::jsonb) FROM lf_design.theme_bindings t WHERE t.design_system_id=ds.design_system_id AND t.status='VIGENTE')),
 'assets',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.asset_code),'[]'::jsonb) FROM lf_design.brand_assets a WHERE a.is_current AND a.status='VIGENTE'))
 FROM lf_design.design_systems ds WHERE ds.project_code='LF' AND ds.design_system_code='LF_DS_V1';
$fn$;
REVOKE ALL ON FUNCTION saly.creative_lf_identity_packet_v1() FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
