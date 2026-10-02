-- N-5 N-9 rollback-only prelude.
-- Reconstructs the exact N-4 preimage from the already-applied N-5 postimage.
-- Executed only inside the N-9 judge transaction; caller owns ROLLBACK.

do $n5_preimage$
declare
  v_spec jsonb;
  v_def text;
  v_new text;
begin
  select especificacion into strict v_spec
  from programacion.contratos
  where id=46
    and version_id=19
    and contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and fail_closed
  for update;

  if md5(v_spec::text) <> '07858e213bf984c078efdab01dad7139' then
    raise exception 'N5_PRELUDE_POSTIMAGE_CONTRACT_DRIFT:%',md5(v_spec::text);
  end if;

  v_def:=pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure);
  if md5(v_def) <> 'c269dc106970a078a498ec3881592282' then
    raise exception 'N5_PRELUDE_POSTIMAGE_V3_DRIFT:%',md5(v_def);
  end if;

  v_new:=replace(v_def,
    '  v_implementation_pending boolean:=false;'||chr(10)||'  v_family_complete jsonb;'||chr(10)||'begin',
    '  v_implementation_pending boolean:=false;'||chr(10)||'begin'
  );
  v_new:=replace(v_new,
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);'||chr(10)||
    '  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,null);'||chr(10)||
    '  if coalesce((v_family_complete->>''handled'')::boolean,false) then return v_family_complete; end if;',
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);'
  );
  if v_new=v_def then raise exception 'N5_PRELUDE_V3_INVERSE_NOOP'; end if;
  execute v_new;

  v_def:=pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure);
  if md5(v_def) <> '4759a64974a2359ecf15f859cb654039' then
    raise exception 'N5_PRELUDE_POSTIMAGE_V3_CACHED_DRIFT:%',md5(v_def);
  end if;

  v_new:=replace(v_def,
    '  v_implementation_pending boolean:=false;'||chr(10)||'  v_family_complete jsonb;'||chr(10)||'begin',
    '  v_implementation_pending boolean:=false;'||chr(10)||'begin'
  );
  v_new:=replace(v_new,
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);'||chr(10)||
    '  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);'||chr(10)||
    '  if coalesce((v_family_complete->>''handled'')::boolean,false) then return v_family_complete; end if;',
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);'
  );
  if v_new=v_def then raise exception 'N5_PRELUDE_V3_CACHED_INVERSE_NOOP'; end if;
  execute v_new;

  v_spec:=v_spec #- '{families,ASSETS_ICONS,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,BROWSER_PLATFORM,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,DESIGN_SYSTEM,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,FEATURE_FLAGS,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,I18N_FORMATS,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,IDEMPOTENCY_CONCURRENCY,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,LOADING_EMPTY_ERROR_STATES,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,OBSERVABILITY,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,PERFORMANCE,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,PRIVACY_PII,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,TESTING_OBLIGATIONS,complete_criteria_v1}';
  v_spec:=v_spec #- '{families,VISUAL_EVIDENCE,complete_criteria_v1}';
  v_spec:=v_spec - 'complete_criteria_contract_version' - 'complete_criteria_family_count';

  update programacion.contratos
  set especificacion=v_spec
  where id=46
    and version_id=19
    and contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and fail_closed;

  if md5(pg_get_functiondef('programacion.fn_input_governance_family_complete_probe_v1(integer,text,bigint,jsonb)'::regprocedure))
       <> '8b811c9cf20ff4903ced50b7b4b70ba3' then
    raise exception 'N5_PRELUDE_POSTIMAGE_FAMILY_PROBE_DRIFT';
  end if;
  execute 'drop function programacion.fn_input_governance_family_complete_probe_v1(integer,text,bigint,jsonb)';

  if md5(v_spec::text) <> '60f17665df3453a5b0bd9a72bdc8c2cf' then
    raise exception 'N5_PRELUDE_PREIMAGE_CONTRACT_MISMATCH:%',md5(v_spec::text);
  end if;
  if md5(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure))
       <> 'aa4e57b3fe9f1a3cd0041d8c86d96b1e' then
    raise exception 'N5_PRELUDE_PREIMAGE_V3_MISMATCH';
  end if;
  if md5(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure))
       <> '9d472c47da26eb6367a8de57b97aa1d6' then
    raise exception 'N5_PRELUDE_PREIMAGE_V3_CACHED_MISMATCH';
  end if;
end
$n5_preimage$;
