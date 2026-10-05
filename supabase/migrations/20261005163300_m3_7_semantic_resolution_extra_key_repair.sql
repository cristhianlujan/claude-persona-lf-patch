begin;

grant lf_governance_owner_v3 to postgres with admin false, inherit false, set true granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

do $repair$
declare
  v_def text;
  v_old text := $old$return p_payload->>'evidence_schema_version'='semantic-resolution/v1'
        and jsonb_typeof(p_payload->'final_normalized')='object'$old$;
  v_new text := $new$return p_payload->>'evidence_schema_version'='semantic-resolution/v1'
        and (p_payload - array['evidence_schema_version','final_normalized','trace']) = '{}'::jsonb
        and jsonb_typeof(p_payload->'final_normalized')='object'$new$;
begin
  select pg_get_functiondef('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)'::regprocedure) into v_def;
  if position('(p_payload - array[' in v_def) = 0 then
    if position(v_old in v_def) = 0 then raise exception 'BLOCK_M3_7_REPAIR_ANCHOR_MISSING'; end if;
    execute replace(v_def,v_old,v_new);
  end if;
end
$repair$;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

commit;
