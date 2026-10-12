-- T-REMED screen status: the end-to-end answer per screen and family, derived on read.
--   GUARANTEED        : coverage COMPLETE (own links + derived global rules); no human work
--   RECOMMENDED       : not complete, but the system proposes catalog codes from same-channel screens (fn_t_remed_recommend_v1); a human confirms
--   HUMAN_DATA_NEEDED : not complete and nothing can be proposed; a human supplies the screen data
--   NOT_APPLICABLE    : the classifier says the family does not apply
-- Family universe and contract version are read from the existing sources (STORY-READINESS rule, version compatibility), nothing hardcoded.
-- Rolled-back run on 3 screens (one per channel): 36/29/31 GUARANTEED of 47, 2.6 s per screen.
create or replace function programacion.fn_t_remed_screen_status_v1(p_pantalla_id integer)
 returns table(family_code text, coverage_status text, disposition text, recommended_codes integer)
 language plpgsql stable security definer set search_path to 'pg_catalog','programacion','lf_ops'
as $fn$
declare v_version bigint; v_graph jsonb; v_fams text[]; v_recs jsonb; f text; cov text; rc int;
begin
  if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id) then return; end if;
  v_version := public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  select array(select jsonb_array_elements_text(valor_config->'families')) into v_fams from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001';
  v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id, v_version);
  select coalesce(jsonb_object_agg(r.family_code, r.c),'{}'::jsonb) into v_recs
    from (select x.family_code, count(*) c from programacion.fn_t_remed_recommend_v1(p_pantalla_id,0.3,false) x group by 1) r;
  foreach f in array v_fams loop
    cov := programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id, f, v_version, v_graph)->>'coverage_status';
    rc := coalesce((v_recs->>f)::int,0);
    family_code := f; coverage_status := cov; recommended_codes := rc;
    disposition := case when cov='COMPLETE' then 'GUARANTEED'
                        when cov='NOT_APPLICABLE' then 'NOT_APPLICABLE'
                        when rc>0 then 'RECOMMENDED'
                        else 'HUMAN_DATA_NEEDED' end;
    return next;
  end loop;
end
$fn$;
comment on function programacion.fn_t_remed_screen_status_v1(integer) is
  'T-REMED end-to-end status of a screen per family: GUARANTEED / RECOMMENDED / HUMAN_DATA_NEEDED / NOT_APPLICABLE. Read-only, derived.';
revoke all on function programacion.fn_t_remed_screen_status_v1(integer) from public, anon, authenticated;
