begin;
-- M9.7/TYPED_SCHEMA: reuse the canonical typed evidence registry and validator.
-- Restore the exact governance role membership before commit (pattern M3.7).
grant lf_governance_owner_v3 to postgres with admin false, inherit false, set true granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

do $registry$
declare
  v_required text[] := array['evidence_schema_version','current_release_ref','candidate_release_ref','current_release_sha256','candidate_release_sha256','source_snapshot_sha256','comparison','duration_ms','recorded_at'];
  v_desc text := 'IG shadow comparison receipt: immutable CURRENT/CANDIDATE release, source SHA, typed comparison, elapsed duration';
  v_sha text;
begin
  v_sha := encode(extensions.digest(convert_to(jsonb_build_object('schema_version','ig-shadow-receipt/v1','validator_version','v3.2','required_keys',to_jsonb(v_required),'description',v_desc,'active',true)::text,'UTF8'),'sha256'),'hex');
  insert into private.lf_typed_evidence_schema_registry_v3(schema_version,validator_version,required_keys,description,active,registry_sha256,registered_by_execution_id)
  values('ig-shadow-receipt/v1','v3.2',v_required,v_desc,true,v_sha,'IG_CURATOR_VALIDATOR_REFACTOR_V2:M9.7:TYPED_SCHEMA')
  on conflict(schema_version) do nothing;
  if not exists (
    select 1 from private.lf_typed_evidence_schema_registry_v3
    where schema_version='ig-shadow-receipt/v1' and validator_version='v3.2'
      and required_keys=v_required and description=v_desc and active and registry_sha256=v_sha
  ) then raise exception 'BLOCK_M9_7_SHADOW_SCHEMA_DRIFT'; end if;
end $registry$;

do $validator$
declare
  v_def text;
  v_case text := $case$
    when 'ig-shadow-receipt/v1' then
      return p_payload->>'evidence_schema_version'='ig-shadow-receipt/v1'
        and (p_payload - array['evidence_schema_version','current_release_ref','candidate_release_ref','current_release_sha256','candidate_release_sha256','source_snapshot_sha256','comparison','duration_ms','recorded_at'])='{}'::jsonb
        and nullif(btrim(coalesce(p_payload->>'current_release_ref','')),'') is not null
        and nullif(btrim(coalesce(p_payload->>'candidate_release_ref','')),'') is not null
        and coalesce(p_payload->>'current_release_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'candidate_release_sha256','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload->>'source_snapshot_sha256','') ~ '^[0-9a-f]{64}$'
        and jsonb_typeof(p_payload->'comparison')='object'
        and ((p_payload->'comparison') - array['result','method_version','current_output_sha256','candidate_output_sha256','difference_count'])='{}'::jsonb
        and p_payload#>>'{comparison,result}' in ('MATCH','MISMATCH','INCONCLUSIVE')
        and nullif(btrim(coalesce(p_payload#>>'{comparison,method_version}','')),'') is not null
        and coalesce(p_payload#>>'{comparison,current_output_sha256}','') ~ '^[0-9a-f]{64}$'
        and coalesce(p_payload#>>'{comparison,candidate_output_sha256}','') ~ '^[0-9a-f]{64}$'
        and jsonb_typeof(p_payload#>'{comparison,difference_count}')='number'
        and (p_payload#>>'{comparison,difference_count}')::numeric >= 0
        and (p_payload#>>'{comparison,difference_count}')::numeric = trunc((p_payload#>>'{comparison,difference_count}')::numeric)
        and (p_payload#>>'{comparison,result}' <> 'MATCH'
             or ((p_payload#>>'{comparison,current_output_sha256}')=(p_payload#>>'{comparison,candidate_output_sha256}')
                 and (p_payload#>>'{comparison,difference_count}')::numeric=0))
        and (p_payload#>>'{comparison,result}' <> 'MISMATCH'
             or ((p_payload#>>'{comparison,current_output_sha256}')<>(p_payload#>>'{comparison,candidate_output_sha256}')
                 and (p_payload#>>'{comparison,difference_count}')::numeric>0))
        and jsonb_typeof(p_payload->'duration_ms')='number'
        and (p_payload->>'duration_ms')::numeric >= 0
        and private.fn_lf_try_timestamptz(p_payload->>'recorded_at') is not null;
$case$;
begin
  select pg_get_functiondef('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)'::regprocedure) into v_def;
  if position('when ''ig-shadow-receipt/v1'' then' in v_def)=0 then
    if position('    else return false;' in v_def)=0 then raise exception 'BLOCK_M9_7_VALIDATOR_ANCHOR_MISSING'; end if;
    execute replace(v_def,'    else return false;',v_case||E'\n    else return false;');
  end if;
end $validator$;

do $verify$
declare
  v_hex_a text := repeat('a',64);
  v_hex_b text := repeat('b',64);
  v_positive jsonb;
  v_old jsonb;
begin
  v_positive := jsonb_build_object(
    'evidence_schema_version','ig-shadow-receipt/v1',
    'current_release_ref','sha:CURRENT',
    'candidate_release_ref','sha:CANDIDATE',
    'current_release_sha256',v_hex_a,
    'candidate_release_sha256',v_hex_b,
    'source_snapshot_sha256',v_hex_a,
    'comparison',jsonb_build_object('result','MATCH','method_version','hash-compare/v1','current_output_sha256',v_hex_a,'candidate_output_sha256',v_hex_a,'difference_count',0),
    'duration_ms',42.5,'recorded_at','2026-10-09T18:30:00Z'
  );
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',v_positive) is not true then raise exception 'BLOCK_M9_7_POSITIVE_REJECTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',v_positive - 'source_snapshot_sha256') is not false then raise exception 'BLOCK_M9_7_MISSING_SHA_ACCEPTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',jsonb_set(v_positive,'{current_release_sha256}','"not-a-sha"'::jsonb)) is not false then raise exception 'BLOCK_M9_7_INVALID_SHA_ACCEPTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',jsonb_set(v_positive,'{comparison,result}','"MISMATCH"'::jsonb)) is not false then raise exception 'BLOCK_M9_7_INCONSISTENT_COMPARISON_ACCEPTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',jsonb_set(v_positive,'{duration_ms}','-1'::jsonb)) is not false then raise exception 'BLOCK_M9_7_NEGATIVE_DURATION_ACCEPTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',v_positive||'{"readiness":true}'::jsonb) is not false then raise exception 'BLOCK_M9_7_UNDECLARED_FIELD_ACCEPTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('ig-shadow-receipt/v1',jsonb_set(v_positive,'{comparison,result}','"UNKNOWN"'::jsonb)) is not false then raise exception 'BLOCK_M9_7_INVALID_STATUS_ACCEPTED'; end if;
  v_old := jsonb_build_object('evidence_schema_version','semantic-resolution/v1','final_normalized',jsonb_build_object('subject_ref','lf://screen/52/field/status','property_path','status','operation','SET','final_value_or_ref','ACTIVE','resolution_type','AUTHORITY_RESOLUTION','authority_refs',jsonb_build_array('supabase://authority/ref'),'evidence_refs',jsonb_build_array('supabase://evidence/ref'),'verification_status','VERIFIED','human_required',false,'canonical_effect',jsonb_build_object('state','ACTIVE')),'trace',jsonb_build_object('research',jsonb_build_array(),'alternatives',jsonb_build_array(),'contradictions',jsonb_build_array()));
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',v_old) is not true then raise exception 'BLOCK_M9_7_PRIOR_SCHEMA_REGRESSION'; end if;
end $verify$;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

do $security_restore$
declare v_ok boolean;
begin
  select count(*)=1 and bool_and(pg_get_userbyid(am.grantor)='supabase_admin' and am.admin_option and not am.inherit_option and not am.set_option)
    into v_ok from pg_auth_members am join pg_roles granted on granted.oid=am.roleid
    join pg_roles member on member.oid=am.member
    where granted.rolname='lf_governance_owner_v3' and member.rolname='postgres';
  if not coalesce(v_ok,false) then raise exception 'BLOCK_M9_7_GOVERNANCE_MEMBERSHIP_NOT_RESTORED'; end if;
  if has_schema_privilege('lf_governance_owner_v3','private','CREATE') then raise exception 'BLOCK_M9_7_GOVERNANCE_CREATE_NOT_RESTORED'; end if;
end $security_restore$;
commit;
