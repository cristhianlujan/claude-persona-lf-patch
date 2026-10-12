-- T-REMED: generic screen contract. The graph no longer calls the B2B login contract function.
-- lf_ops.fn_screen_contract_v1 is derived from the live definition of lf_ops.fn_b2b_backoffice_login_contract with the B2B data removed:
--   no B2B defaults, contract_code LF-SCREEN-CONTRACT-V1, product_scope = app shell code, usage text generic,
--   analytics no longer limited to AUTH / B2B_LOGIN_ / B2B_PASSWORD_ events. The B2B login function and its view stay unchanged for B2B login consumers.
-- programacion.fn_input_screen_canonical_graph now calls the generic function.
-- Guarded: raises if the source function or the expected fragments are missing, or if any 'B2B' text remains in the generic definition.
do $m$
declare d text; d2 text; g text; g2 text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='lf_ops' and p.proname='fn_b2b_backoffice_login_contract';
  if d is null then raise exception 'SOURCE_CONTRACT_FN_NOT_FOUND'; end if;
  d2:=replace(d,'lf_ops.fn_b2b_backoffice_login_contract(','lf_ops.fn_screen_contract_v1(');
  d2:=regexp_replace(d2,' DEFAULT ''[^'']*''::text','','g');
  d2:=replace(d2,'''LF-B2B-BACKOFFICE-LOGIN-CONTRACT-V1''','''LF-SCREEN-CONTRACT-V1''');
  d2:=replace(d2,'''product_scope'', ''BACKOFFICE_EMPRESA''','''product_scope'', c.app_shell_code');
  d2:=replace(d2,E'        ''default_view'', ''select * from lf_ops.v_b2b_backoffice_login_contract;'',\n','');
  d2:=replace(d2,'select * from lf_ops.fn_screen_contract_v1(''''B2B_APP_SHELL'''',''''B2B_AUTENTICACION'''',''''B2B-AUTH-001'''');','select * from lf_ops.fn_screen_contract_v1(<app_shell_code>,<module_code>,<screen_code>);');
  d2:=replace(d2,E'\n        and (ae.event_category = ''AUTH'' or ae.event_code like ''B2B_LOGIN_%'' or ae.event_code like ''B2B_PASSWORD_%'')','');
  if position('B2B' in d2)>0 then raise exception 'B2B_RESIDUE_IN_GENERIC_CONTRACT:%',substr(d2,position('B2B' in d2)-60,160); end if;
  execute d2;
  comment on function lf_ops.fn_screen_contract_v1(text,text,text) is 'LF_METADATA_V1 | PURPOSE: contrato de lectura de una pantalla (generico, cualquier app shell). INPUTS: p_app_shell_code, p_module_code, p_screen_code (sin valores por defecto). OUTPUT: contexto, campos, validaciones, reglas (propias y heredadas del nivel global), errores, politicas, perfiles, analytics y design system. JOIN POLICY: usar *_id numericos. La funcion lf_ops.fn_b2b_backoffice_login_contract queda solo para el contrato de login B2B.';
  select pg_get_functiondef(p.oid) into g from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_input_screen_canonical_graph';
  if g is null then raise exception 'GRAPH_FN_NOT_FOUND'; end if;
  g2:=replace(g,'lf_ops.fn_b2b_backoffice_login_contract(','lf_ops.fn_screen_contract_v1(');
  if g2=g then raise exception 'GRAPH_CALL_NOT_FOUND'; end if;
  execute g2;
end $m$;
