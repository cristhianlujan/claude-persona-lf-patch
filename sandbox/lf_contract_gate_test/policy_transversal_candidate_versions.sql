-- SOURCE-ONLY SANDBOX MATERIALIZATION OF POLICY CANDIDATES.
-- This file makes Git authoritative for the exact candidate payloads before any promotion.
-- It intentionally rolls back when run as-is.

begin;

do $policy_candidates$
declare
  r record;
  v_computed text;
  v_existing_sha text;
begin
  for r in
    select * from (values
      (
        'POL-LF-POLICY-CONSUMPTION'::text,
        'v1.1-transversal-candidate'::text,
        $json${
          "rules":["RESOLVE_TRANSVERSAL_AND_OPERATION_POLICIES_ONCE","DISTRIBUTE_MINIMUM_REQUIRED_FIELDS","DO_NOT_LOAD_FULL_POLICY_DOCUMENTS_WHEN_SNAPSHOT_SUFFICES","POLICY_SHA_REQUIRED_FOR_READBACK","EXPLICIT_OPERATION_POLICY_EXTENDS_NOT_DUPLICATES_TRANSVERSAL"],
          "scope":"TRANSVERSAL_LF_GOVERNANCE",
          "version":"v1.1-transversal-candidate",
          "delivery":"COMPACT_RUNTIME_CAPSULE",
          "authority":"SUPABASE",
          "policy_kind":"POLICY_CONSUMPTION_POLICY",
          "snapshot_view":"public.v_lf_operation_policy_snapshot",
          "inheritance_model":"TRANSVERSAL_PLUS_OPERATION_SPECIFIC_ONCE",
          "resolution_source":"public.v_lf_operation_policy_snapshot",
          "adapter_second_llm_call":false,
          "required_runtime_fields":["operation_code","policy_code","policy_version","policy_sha","policy_payload"],
          "max_policy_payload_chars":1800,
          "single_resolution_per_operation":true
        }$json$::jsonb,
        'e5eb786e14a4b735e271a81b702a0a775e0bf39ba174d333531a82a0858b5553'::text
      ),
      (
        'POL-LF-SOURCE-RESOLUTION'::text,
        'v1.2-transversal-candidate'::text,
        $json${
          "rules":["CANONICAL_ID_BEFORE_FREE_SEARCH","REGISTERED_ALIAS_ONLY","SOURCE_OF_TRUTH_BEFORE_REPOSITORY_CONTENT","NO_SIMILARITY_BASED_AUTHORITY_INFERENCE","CLASSIFY_SOURCE_FAMILY_BEFORE_HYDRATION","CONTROLLED_FALLBACK_REQUIRES_EVIDENCE"],
          "scope":"TRANSVERSAL_LF_GOVERNANCE",
          "version":"v1.2-transversal-candidate",
          "authority":"SUPABASE",
          "policy_kind":"SOURCE_RESOLUTION_POLICY",
          "resolution_order":["ACT-0001","public.v_lf_fuente_operativa","CANONICAL_ID","REGISTERED_ALIAS","CANONICAL_BINDING","SOURCE_ARTIFACT","CONTROLLED_FALLBACK"],
          "family_strategies":{
            "MIGRATION":{
              "flow":["SUPABASE_LEDGER_VERSION_NAME_STATE","EXACT_GITHUB_MIGRATION_PATH_PR_HEAD","CANONICAL_PARITY_VALIDATOR","BROADER_SEARCH_IF_UNRESOLVED","ZIP_LAST_RESORT_ONLY"],
              "rules":["SUPABASE_FIRST_MIGRATIONS","NO_ZIP_MIGRATIONS"],
              "zip_exception_required_fields":["zip_reason","files_needed","direct_routes_attempted","why_direct_failed"]
            },
            "EXISTING_ARTIFACT":{
              "modes":["EVALUATE_EXISTING","REMEDIATE_EXISTING"],
              "required":["source_artifact_ref","source_image_sha256","source_dimensions"],
              "on_missing":"FAIL_CLOSED",
              "downstream_authorized":false,
              "remediate_additional_required":["authorized_delta","target_component_id","visual_evidence","acceptance_criteria"]
            }
          }
        }$json$::jsonb,
        '459d9ec975d5955d63619876e13abf2f0975a978e38cfff0aa5eed2d68295ae0'::text
      ),
      (
        'POL-LF-STATE-MODEL'::text,
        'v1.1-transversal-candidate'::text,
        $json${
          "rules":["NEVER_INFER_PERMISSION_FROM_SINGLE_STATE_DIMENSION","NORMALIZE_ALIAS_BEFORE_LLM_CONSUMPTION","UNKNOWN_OR_EMPTY_STATE_BLOCKS_ACTION","RUNTIME_PERMISSION_REQUIRES_COMBINED_STATE_EVALUATION"],
          "scope":"TRANSVERSAL_LF_GOVERNANCE",
          "version":"v1.1-transversal-candidate",
          "authority":"SUPABASE",
          "dimensions":{
            "runtime_estado":["NO_APLICA","NO_HABILITADO","CANDIDATE_READ_ONLY","SANDBOX_READ_ONLY","PRODUCCION_CONTROLADA_READ_ONLY","APROBADO_PRODUCCION_CONTROLADA_READ_ONLY","APROBADO_PRODUCCION_CONTROLADA","RUNTIME_OPERATIVO"],
            "estado_operativo":["ACTIVO","READ_ONLY","APROBADO","BLOQUEADO","ELIMINADO"],
            "estado_documental":["CANDIDATO","EN_REVISION","VIGENTE","APROBADO","NO_VALIDADO","LEGACY","ELIMINADO"],
            "impacto_automatico":["BLOQUEADO","REQUIERE_APROBACION","CONTROLADO","PERMITIDO_CONTROLADO"]
          },
          "application":"ALL_ROUTER_GOVERNED_ASSET_AND_OPERATION_STATE_DECISIONS",
          "policy_kind":"STATE_MODEL_POLICY",
          "source_view":"public.v_lf_fuente_operativa",
          "alias_source":"public.cat_estado_normalizacion_lf",
          "inheritance_model":"TRANSVERSAL_ONCE"
        }$json$::jsonb,
        'f451bb4d2b17cdac48c4dddb250108b2874a9d036edcfb9d2f7fa540416332aa'::text
      )
    ) as x(policy_code,policy_version,policy_payload,expected_sha)
  loop
    v_computed := encode(digest(r.policy_payload::text,'sha256'),'hex');
    if v_computed <> r.expected_sha then
      raise exception 'POLICY_CANDIDATE_SOURCE_SHA_MISMATCH code=% version=% expected=% computed=%',
        r.policy_code,r.policy_version,r.expected_sha,v_computed;
    end if;

    select policy_sha into v_existing_sha
    from public.lf_policy_versions
    where policy_code=r.policy_code and policy_version=r.policy_version;

    if found then
      if v_existing_sha <> r.expected_sha then
        raise exception 'POLICY_CANDIDATE_EXISTING_SHA_MISMATCH code=% version=% expected=% existing=%',
          r.policy_code,r.policy_version,r.expected_sha,v_existing_sha;
      end if;
    else
      insert into public.lf_policy_versions(
        policy_code,policy_version,policy_payload,policy_sha,status,effective_at,
        source_ref,created_by_execution_id
      ) values (
        r.policy_code,r.policy_version,r.policy_payload,r.expected_sha,'CANDIDATE',now(),
        'GOV-TRANSVERSAL-POLICY-ROOTFIX-20260905_SOURCE_FIRST',
        'GPT-GOV-POLICY-TRANSVERSAL-ROOTFIX-20260905-001'
      );
    end if;
  end loop;
end;
$policy_candidates$;

rollback;
