do $patch$
declare
  f text;
  old_inspection text := $$if v_req ~ '(^| )(consulta|consultar|version|estado|metadata|existe)( |$)' then$$;
  new_inspection text := $$if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then$$;
  old_tiebreak text := E'),0) desc,\n      b.codigo_activo\n    limit 1;';
  new_tiebreak text := E'),0) desc,\n      case when b.tipo_activo in (''PERFIL'',''SKILL'') then 1 else 0 end desc,\n      b.codigo_activo\n    limit 1;';
begin
  select pg_get_functiondef(p.oid) into f
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='lf_router_resolve_v1';

  if strpos(f, old_inspection)=0 then
    raise exception 'inspection pattern not found';
  end if;
  if strpos(f, old_tiebreak)=0 then
    raise exception 'tie-break pattern not found';
  end if;

  f := replace(f, old_inspection, new_inspection);
  f := replace(f, old_tiebreak, new_tiebreak);
  execute f;
end
$patch$;
