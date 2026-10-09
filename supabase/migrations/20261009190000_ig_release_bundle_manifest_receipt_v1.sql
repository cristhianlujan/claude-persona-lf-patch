-- IG M9.0 / release bundle owned by Input Governance (does NOT consume post-pase FINAL_EVIDENCE, which is not finished).
-- 1) programacion.fn_input_governance_release_bundle_manifest_v1(git_head, edge_index_sha256): read-only, deterministic manifest + bundle_sha256
--    over the material identities: Git head, contracts, capability registry, Core (PROGRAMACION_FN_INPUT_GOVERNANCE_* assets),
--    semantics / Curator / Validator code identities (sha256 of live function definitions) and Edge (assets + deployed index.ts sha256).
--    Fail-closed on malformed input or an empty component.
-- 2) programacion.fn_input_governance_release_bundle_receipt_v1(git_head, edge_index_sha256): persists the bundle as a VERIFIED
--    EVIDENCE_VERIFICATION receipt in programacion.provenance_receipts (same channel pattern as the Curator handoff receipt), idempotent per bundle sha,
--    and reads it back through fn_assert_provenance_receipt.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_release_bundle_manifest_v1(p_git_head text, p_edge_index_sha256 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $fn$
declare
  c_edge_codes constant text[] := array['EDGE_FN_INPUT_GOVERNANCE_AGENT_V1','EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1','EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1'];
  v_contracts jsonb; v_registry jsonb; v_core jsonb; v_edge jsonb;
  v_semantics jsonb; v_curator jsonb; v_validator jsonb;
  v_ident jsonb; v_k text;
begin
  if p_git_head is null or p_git_head !~ '^[0-9a-f]{40}$' then
    raise exception 'RELEASE_BUNDLE_GIT_HEAD_INVALID';
  end if;
  if jsonb_typeof(p_edge_index_sha256) is distinct from 'object'
     or (select count(*) from jsonb_object_keys(p_edge_index_sha256)) <> 3 then
    raise exception 'RELEASE_BUNDLE_EDGE_SHA_SET_INVALID';
  end if;
  foreach v_k in array c_edge_codes loop
    if coalesce(p_edge_index_sha256->>v_k,'') !~ '^[0-9a-f]{64}$' then
      raise exception 'RELEASE_BUNDLE_EDGE_SHA_INVALID:%', v_k;
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'contrato_codigo',c.contrato_codigo,'estado',c.estado,'version_id',c.version_id) order by c.id),'[]'::jsonb)
    into v_contracts from programacion.contratos c
   where c.contrato_codigo ~* '(INPUT_READINESS|INPUT_FRESHNESS|INPUT_GOVERNANCE)';
  select coalesce(jsonb_agg(jsonb_build_object('capability_code',r.capability_code,'version',r.version,'manifest_sha256',r.manifest_sha256) order by r.capability_code),'[]'::jsonb)
    into v_registry from public.lf_capability_current r;
  select coalesce(jsonb_agg(jsonb_build_object('codigo_activo',a.codigo_activo,'runtime_estado',a.runtime_estado,'estado_operativo',a.estado_operativo) order by a.codigo_activo),'[]'::jsonb)
    into v_core from public.lf_activos a where a.codigo_activo like 'PROGRAMACION_FN_INPUT_GOVERNANCE_%';
  select coalesce(jsonb_agg(jsonb_build_object('codigo_activo',a.codigo_activo,'runtime_estado',a.runtime_estado,'version',a.version,'index_ts_sha256',p_edge_index_sha256->>a.codigo_activo) order by a.codigo_activo),'[]'::jsonb)
    into v_edge from public.lf_activos a where a.codigo_activo = any (c_edge_codes);

  select coalesce(jsonb_agg(jsonb_build_object('proc',x.sig,'def_sha256',x.h) order by x.sig),'[]'::jsonb) into v_semantics from (
    select p.oid::regprocedure::text sig, encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') h
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion' and p.proname in ('fn_input_governance_semantic_probe_v3','fn_input_governance_bootstrap_classify_v2','fn_input_governance_shadow_priority_oracle_v2')) x;
  select coalesce(jsonb_agg(jsonb_build_object('proc',x.sig,'def_sha256',x.h) order by x.sig),'[]'::jsonb) into v_curator from (
    select p.oid::regprocedure::text sig, encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') h
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion' and p.proname in ('fn_input_governance_curator_materialize_v1','fn_input_governance_curator_handoff_receipt_v1')) x;
  select coalesce(jsonb_agg(jsonb_build_object('proc',x.sig,'def_sha256',x.h) order by x.sig),'[]'::jsonb) into v_validator from (
    select p.oid::regprocedure::text sig, encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') h
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='programacion' and p.proname in ('fn_input_governance_validator_validate_handoff_v1','fn_input_governance_validator_handoff_assert_v1')) x;

  if jsonb_array_length(v_contracts)=0 or jsonb_array_length(v_registry)=0 or jsonb_array_length(v_core)=0
     or jsonb_array_length(v_edge)<>3 or jsonb_array_length(v_semantics)=0
     or jsonb_array_length(v_curator)=0 or jsonb_array_length(v_validator)=0 then
    raise exception 'RELEASE_BUNDLE_COMPONENT_EMPTY';
  end if;

  v_ident := jsonb_build_object(
    'schema_version','IG_RELEASE_BUNDLE_MANIFEST_V1',
    'git_head',p_git_head,
    'contracts_sha256',programacion.fn_v09_sha256_jsonb(v_contracts),
    'registry_sha256',programacion.fn_v09_sha256_jsonb(v_registry),
    'core_sha256',programacion.fn_v09_sha256_jsonb(v_core),
    'semantics_sha256',programacion.fn_v09_sha256_jsonb(v_semantics),
    'curator_sha256',programacion.fn_v09_sha256_jsonb(v_curator),
    'validator_sha256',programacion.fn_v09_sha256_jsonb(v_validator),
    'edge_sha256',programacion.fn_v09_sha256_jsonb(v_edge));

  return jsonb_build_object(
    'schema_version','IG_RELEASE_BUNDLE_MANIFEST_V1',
    'identities',v_ident,
    'bundle_sha256',programacion.fn_v09_sha256_jsonb(v_ident),
    'components',jsonb_build_object('contracts',v_contracts,'registry',v_registry,'core',v_core,'semantics',v_semantics,'curator',v_curator,'validator',v_validator,'edge',v_edge),
    'post_pase_dependency',false,'promotion_authorized',false,'production_authorized',false);
end;
$fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_release_bundle_receipt_v1(p_git_head text, p_edge_index_sha256 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $fn$
declare
  v_manifest jsonb; v_sha text; v_ref constant text := 'input-governance-release-bundle';
  v_issuer constant text := 'SUPABASE:INPUT_GOVERNANCE_RELEASE_BUNDLE_V1';
  v_token text; v_id bigint; v_rsha text; v_payload jsonb;
begin
  v_manifest := programacion.fn_input_governance_release_bundle_manifest_v1(p_git_head, p_edge_index_sha256);
  v_sha := v_manifest->>'bundle_sha256';

  select r.id, r.receipt_sha256 into v_id, v_rsha
  from programacion.provenance_receipts r
  where r.receipt_kind='EVIDENCE_VERIFICATION' and r.issuer_channel='EVIDENCE_VERIFIER_V1'
    and r.head_sha=p_git_head and r.subject_type='input_governance_release_bundle'
    and r.subject_ref=v_ref and r.subject_sha256=v_sha
  order by r.id desc limit 1;

  if v_id is null then
    select decrypted_secret into v_token from vault.decrypted_secrets
     where name='EVIDENCE_VERIFIER_V1_TOKEN' order by created_at desc limit 1;
    if length(coalesce(v_token,''))<32 then raise exception 'RELEASE_BUNDLE_EVIDENCE_VERIFIER_TOKEN_MISSING'; end if;
    v_payload := jsonb_build_object('head_sha',p_git_head,'subject_type','input_governance_release_bundle','subject_ref',v_ref,
      'subject_sha256',v_sha,'verification_status','VERIFIED','verifier_identity',v_issuer,
      'verification_method','SUPABASE_RELEASE_BUNDLE_MANIFEST_DIGEST_V1','manifest',v_manifest);
    select r.id, r.receipt_sha256 into v_id, v_rsha
    from programacion.issue_provenance_receipt('EVIDENCE_VERIFIER_V1', v_token, 'EVIDENCE_VERIFICATION', null, p_git_head,
      'input_governance_release_bundle', v_ref, v_sha, v_issuer,
      'supabase://programacion.fn_input_governance_release_bundle_manifest_v1#'||v_sha, v_payload) r;
  end if;

  perform programacion.fn_assert_provenance_receipt(v_id,'EVIDENCE_VERIFICATION',null,p_git_head,'input_governance_release_bundle',v_ref,v_sha);

  return jsonb_build_object('status','PERSISTED','schema_version','IG_RELEASE_BUNDLE_RECEIPT_V1',
    'receipt_id',v_id,'receipt_sha256',v_rsha,'bundle_sha256',v_sha,'head_sha',p_git_head,'subject_ref',v_ref);
end;
$fn$;
