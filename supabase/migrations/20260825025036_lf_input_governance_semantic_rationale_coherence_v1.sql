-- INPUT_GOVERNANCE_AGENT: specialized semantic probes must update rationale together
-- with coverage/readiness/blockers. No screen functional data is modified.
do $migration$
declare
  v_def text;
  v_old text := $old$v:=jsonb_set(v,'{bootstrap_level}',to_jsonb(v_level),true);$old$;
  v_new text := $new$v:=jsonb_set(v,'{bootstrap_level}',to_jsonb(v_level),true);
      v:=jsonb_set(v,'{rationale}',to_jsonb('Governed semantic resolution '||coalesce(v_sem->'probe'->>'resolution_contract','SEMANTIC_PROBE_V1')||': '||p_family_code||'='||v_level||' from direct canonical source readback; absence never implies N/A.'),true);$new$;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_governance_bootstrap_classify_v2'
    and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text, p_version_id bigint';

  if v_def is null then
    raise exception 'INPUT_BOOTSTRAP_CLASSIFIER_V2_NOT_FOUND';
  end if;
  if length(v_def)-length(replace(v_def,v_old,'')) <> length(v_old) then
    raise exception 'INPUT_BOOTSTRAP_CLASSIFIER_RATIONALE_PREDECESSOR_NOT_EXACTLY_ONCE';
  end if;

  execute replace(v_def,v_old,v_new);
end;
$migration$;
