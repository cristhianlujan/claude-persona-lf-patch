do $$
declare
  v_def text;
  v_new text;
  v_old text := $old$            or exists (
              select 1 from regexp_split_to_table(lower(concat_ws(' ',b.nombre_canonico,b.subtipo_activo)), '[^a-z0-9]+') tok
              where length(tok)>=2
                and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                and position(tok in v_req)>0
            )
          )$old$;
  v_rep text := $rep$            or exists (
              select 1 from regexp_split_to_table(lower(concat_ws(' ',b.nombre_canonico,b.subtipo_activo)), '[^a-z0-9]+') tok
              where length(tok)>=2
                and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                and position(tok in v_req)>0
            )
            or exists (
              select 1
              from jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw,
                   regexp_split_to_table(lower(kw),'[^a-z0-9]+') tok
              where length(tok)>=3
                and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                and position(tok in v_req)>0
            )
          )$rep$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into v_def;
  if position(v_old in v_def)=0 then raise exception 'KEYWORD_VERIFICATION_BASELINE_NOT_FOUND'; end if;
  v_new := replace(v_def,v_old,v_rep);
  execute v_new;
end $$;
