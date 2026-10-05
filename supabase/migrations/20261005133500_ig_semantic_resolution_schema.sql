begin;

do $registry$
declare
  v_required text[] := array['evidence_schema_version','final_normalized','trace'];
  v_desc text := 'SemanticResolution normalized final evidence; trace separated; readiness forbidden';
  v_sha text;
begin
  v_sha := encode(extensions.digest(convert_to(jsonb_build_object('schema_version','semantic-resolution/v1','validator_version','v3.2','required_keys',to_jsonb(v_required),'description',v_desc,'active',true)::text,'UTF8'),'sha256'),'hex');
  insert into private.lf_typed_evidence_schema_registry_v3(schema_version,validator_version,required_keys,description,active,registry_sha256,registered_by_execution_id)
  values ('semantic-resolution/v1','v3.2',v_required,v_desc,true,v_sha,'IG_CURATOR_VALIDATOR_REFACTOR_V2:M3.7:SCHEMA_DEFINE_REGISTER')
  on conflict (schema_version) do nothing;
  if not exists (select 1 from private.lf_typed_evidence_schema_registry_v3 where schema_version='semantic-resolution/v1' and validator_version='v3.2' and required_keys=v_required and active and registry_sha256=v_sha) then
    raise exception 'BLOCK_M3_7_SEMANTIC_RESOLUTION_REGISTRY_DRIFT';
  end if;
end
$registry$;

do $validator$
declare
  v_def text;
  v_case text := $case$
    when 'semantic-resolution/v1' then
      return p_payload->>'evidence_schema_version'='semantic-resolution/v1'
        and jsonb_typeof(p_payload->'final_normalized')='object'
        and jsonb_typeof(p_payload->'trace')='object'
        and not (p_payload ? 'readiness')
        and not (p_payload->'final_normalized' ? 'readiness')
        and not (p_payload->'trace' ? 'readiness')
        and nullif(btrim(coalesce(p_payload#>>'{final_normalized,subject_ref}','')),'') is not null
        and nullif(btrim(coalesce(p_payload#>>'{final_normalized,property_path}','')),'') is not null
        and nullif(btrim(coalesce(p_payload#>>'{final_normalized,operation}','')),'') is not null
        and (p_payload->'final_normalized' ? 'final_value_or_ref')
        and p_payload#>'{final_normalized,final_value_or_ref}' is not null
        and p_payload#>'{final_normalized,final_value_or_ref}' <> 'null'::jsonb
        and nullif(btrim(coalesce(p_payload#>>'{final_normalized,resolution_type}','')),'') is not null
        and jsonb_typeof(p_payload#>'{final_normalized,authority_refs}')='array'
        and jsonb_typeof(p_payload#>'{final_normalized,evidence_refs}')='array'
        and nullif(btrim(coalesce(p_payload#>>'{final_normalized,verification_status}','')),'') is not null
        and jsonb_typeof(p_payload#>'{final_normalized,human_required}')='boolean'
        and (p_payload->'final_normalized' ? 'canonical_effect')
        and jsonb_typeof(p_payload#>'{trace,research}')='array'
        and jsonb_typeof(p_payload#>'{trace,alternatives}')='array'
        and jsonb_typeof(p_payload#>'{trace,contradictions}')='array'
        and lower((p_payload->'final_normalized')::text) !~ '(buscar|revisar|investigar|recomendar|considerar)';
$case$;
begin
  select pg_get_functiondef('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)'::regprocedure) into v_def;
  if position('semantic-resolution/v1' in v_def)=0 then
    if position('    else return false;' in v_def)=0 then raise exception 'BLOCK_M3_7_VALIDATOR_ANCHOR_MISSING'; end if;
    execute replace(v_def,'    else return false;',v_case||E'\n    else return false;');
  end if;
end
$validator$;

do $verify$
declare
  v_ok jsonb := '{"evidence_schema_version":"semantic-resolution/v1","final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"}},"trace":{"research":[],"alternatives":[],"contradictions":[]}}'::jsonb;
begin
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',v_ok) is not true then raise exception 'BLOCK_M3_7_POSITIVE_REJECTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',v_ok||'{"readiness":true}'::jsonb) is true then raise exception 'BLOCK_M3_7_READINESS_ACCEPTED'; end if;
end
$verify$;

commit;
