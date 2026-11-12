-- L15 PG18 BASELINE / NEVER RUN LIVE.
-- Exact live-source definitions for request,decide,apply,guard are supplied
-- by the existing live_promotion_baseline_fixture.sql (MD5 verified).
-- These three additional functions are deliberately STUBS, not exact live code.
-- They retain exact signatures and demonstrate coexistence/call compatibility.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_batch_v1(p_ids text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $stub$ DECLARE x text; v jsonb; a jsonb:='[]'::jsonb; BEGIN
FOREACH x IN ARRAY coalesce(p_ids,ARRAY[]::text[]) LOOP
 v:=public.lf_rule_promotion_apply_v1(x);
 a:=a||jsonb_build_array(jsonb_build_object('id',x,'status',v->>'status'));
END LOOP;
RETURN jsonb_build_object('simulation','L15_STUB_ONLY','cases',a);
END $stub$;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_batch_v1(
 p_ids text[],p_decision text,p_decided_by text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $stub$ DECLARE x text; v jsonb; a jsonb:='[]'::jsonb; BEGIN
FOREACH x IN ARRAY coalesce(p_ids,ARRAY[]::text[]) LOOP
 v:=public.lf_rule_promotion_decide_v1(x,p_decision,p_decided_by,p_note);
 a:=a||jsonb_build_array(jsonb_build_object('id',x,'status',v->>'status'));
END LOOP;
RETURN jsonb_build_object('simulation','L15_STUB_ONLY','cases',a);
END $stub$;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_report_v1(
 p_page integer DEFAULT 1,p_size integer DEFAULT 8)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $stub$
 SELECT jsonb_build_object('simulation','L15_STUB_ONLY',
  'page',p_page,'size',p_size,'pending',
  (SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE status='PENDING'));
$stub$;
