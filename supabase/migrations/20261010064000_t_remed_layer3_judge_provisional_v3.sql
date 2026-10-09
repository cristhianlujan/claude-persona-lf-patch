-- T-REMED layer 3 (judge): a policy whose own parameter_provenance declares LF_PROVISIONAL / MUST_BE_RATIFIED is not promotable.
-- Layer 3 judge: independent. Recomputes from raw tables; never calls reconcile/complete; returns verdict + failed criteria only. -----
create or replace function public.lf_t_remed_judge_v3(p_pantalla_id integer)
 returns jsonb
 language plpgsql stable security definer set search_path to 'pg_catalog'
as $fn$
declare
  l record; v_row jsonb; v_fail text[]; v_items jsonb:='[]'::jsonb; v_cited int; v_pending int; v_targets int; v_pk text;
begin
  for l in select * from programacion.t_remed_links where subject_kind='PANTALLA' and subject_id=p_pantalla_id order by link_id loop
    v_fail:=array[]::text[];
    select a.attname::text into v_pk from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=i.indkey[0]
      where i.indrelid=to_regclass(l.target_table) and i.indisprimary limit 1;
    execute format('select to_jsonb(x) from %s x where x.%I=$1',l.target_table,v_pk) into v_row using l.target_id;
    if v_row is null then v_fail:=array_append(v_fail,'TARGET_EXISTS');
    else
      if coalesce(v_row->>'source_decision_number',v_row->>'source_decision_id') is null then v_fail:=array_append(v_fail,'SOURCE_DECISION_DECLARED'); end if;
      if v_row->>'status' not in ('CANDIDATO','EN_REVISION','VIGENTE') then v_fail:=array_append(v_fail,'TARGET_ACTIVE'); end if;
      if coalesce(v_row->'parameter_provenance','{}'::jsonb)::text ~ '(LF_PROVISIONAL|MUST_BE_RATIFIED)' then v_fail:=array_append(v_fail,'NO_PROVISIONAL_PARAMETERS'); end if;
    end if;
    select count(distinct r.id), count(distinct r.id) filter (where coalesce(r.pendiente_decision,false))
      into v_cited, v_pending
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado in ('VIGENTE','CANDIDATO') and jsonb_typeof(r.valor_config)='object'
      and jsonb_path_exists(r.valor_config, format('$."%s" ? (@ == %s)',l.reference_role,l.target_id)::jsonpath);
    if v_cited=0 then v_fail:=array_append(v_fail,'CITED_BY_A_RULE'); end if;
    if v_pending>0 then v_fail:=array_append(v_fail,'NO_PENDING_RULE'); end if;
    select count(distinct (r.valor_config->>l.reference_role)) into v_targets
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.estado in ('VIGENTE','CANDIDATO') and jsonb_typeof(r.valor_config)='object' and r.valor_config ? l.reference_role;
    if v_targets>1 and l.reference_role<>v_pk then v_fail:=array_append(v_fail,'NO_CONFLICT'); end if;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('link_id',l.link_id,'verdict',case when cardinality(v_fail)=0 then 'PASS' else 'FAIL' end,'failed',to_jsonb(v_fail)));
  end loop;
  return jsonb_build_object('schema_version','LF_T_REMED_JUDGE_V3','pantalla_id',p_pantalla_id,'checked_count',jsonb_array_length(v_items),
    'failed_count',(select count(*) from jsonb_array_elements(v_items) i where i->>'verdict'='FAIL'),'items',v_items);
end;
$fn$;

revoke all on function public.lf_t_remed_judge_v3(integer) from public, anon, authenticated;
