-- T-SELECT / PAULO-184 — CAPABILITY_SELECTOR v1.0.0
-- R16 Git-first. Registry/current pointer only; no runtime or production activation.
-- Generic source anchor: 4a9442cde62fec0ac54dcf67defac73b817b756e

DO $t_select$
DECLARE
  v_execution_id constant text := 'CHATGPT-IG-T-SELECT-20261004';
  v_manifest jsonb := $manifest$
  {
    "schema_version":"LF_CAPABILITY_MANIFEST_V1",
    "capability_code":"CAPABILITY_SELECTOR",
    "version":"1.0.0",
    "owner":"SUPER_ADMIN",
    "contract":{
      "input":["signals","catalog","policy"],
      "output":["selected_capabilities","reasons","fallback_state"],
      "states":["CLEAR","MULTI","NO_SIGNAL","CONTRADICTORY","CAPABILITY_FAILURE"],
      "multi_label":true,
      "selection_basis":"TYPED_SIGNAL_TYPE",
      "admission_authority":false,
      "execution_permission":false
    },
    "delivery":{
      "mode":"REPOSITORY_BOUND_PURE_PYTHON",
      "source_path":"sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_v1.py",
      "source_git_blob_sha1":"6b984ce7442814aeb6b3f5c1651c15b7ef1e9936",
      "contract_path":"sandbox/lf_contract_gate_test/transversal_assets/capability_selector/capability_selector_contract_v1.json",
      "contract_git_blob_sha1":"dadc5e6874588e5cf324154088a81cbfae0bade7",
      "source_bundle_sha256":"e4b993b812ad99bfdd8d9626712b93d81b814d939ad6ff8f5f648a5600b1a887"
    },
    "installation":{"required":false,"reinstall_required":false,"runtime_deploy_required":false},
    "dependencies":{
      "capabilities":[
        {"capability_code":"TYPED_EVIDENCE_REGISTRY","version":"3.0.0","role":"UPSTREAM_SIGNAL_TYPING"},
        {"capability_code":"CURRENTNESS_AUTHORITY","version":"1.0.0","role":"UPSTREAM_CATALOG_CURRENTNESS"}
      ],
      "consumer_policy_required":true
    },
    "compatibility":{
      "domain_specific_branches":false,
      "screen_or_family_literals":false,
      "model_or_method_router":false,
      "safe_change_admission_duplicated":false,
      "ranking_or_confidence_authorizes_execution":false
    },
    "migration":{"mode":"CAPABILITY_REGISTRY_AND_CURRENT_POINTER_ONLY","subject_runtime_cutover":false},
    "rollback":{"supported":true,"mode":"REMOVE_T_SELECT_CURRENT_VERSION_REGISTRY_ROWS","runtime_state_untouched":true},
    "usage":{
      "entrypoint":"capability_selector_v1.select_capabilities",
      "fallback_configured_by_consumer":true,
      "non_ig_fixture":"non_ig_consumer_fixture_v1.json",
      "ig_binding":"ig_m5_4_selector_binding_v1.json"
    },
    "currentness":{
      "dependency_authority":"CURRENTNESS_AUTHORITY@1.0.0",
      "typed_signal_authority":"TYPED_EVIDENCE_REGISTRY@3.0.0",
      "test_git_blob_sha1":"a602339d741f06b2cc5dfe67c07a456b86935ae2",
      "non_ig_fixture_git_blob_sha1":"dc5f488a7efed4a5d2358fda6bfd7ad54ff2a190",
      "ig_binding_git_blob_sha1":"611c81a2c809019a5a953a376e7c74d08fece2cf",
      "test_observation":"PASS_T_SELECT_CAPABILITY_SELECTOR_V1 checks=9"
    }
  }
  $manifest$::jsonb;
  v_manifest_sha text;
  v_promote jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='TYPED_EVIDENCE_REGISTRY' AND version='3.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_TYPED_EVIDENCE_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CURRENTNESS_AUTHORITY' AND version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  END IF;

  IF EXISTS (SELECT 1 FROM public.lf_capability_registry WHERE capability_code='CAPABILITY_SELECTOR')
     OR EXISTS (SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='CAPABILITY_SELECTOR')
     OR EXISTS (SELECT 1 FROM public.lf_capability_current WHERE capability_code='CAPABILITY_SELECTOR') THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_CAPABILITY_SELECTOR_ALREADY_REGISTERED';
  END IF;

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  INSERT INTO public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) VALUES (
    'CAPABILITY_SELECTOR','Capability Selector','TRANSVERSAL','SUPER_ADMIN','ACTIVE',
    'Domain-agnostic multi-label capability selector from typed signals; selection never grants execution permission or admission.',
    v_execution_id,v_execution_id,false,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  INSERT INTO public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,
    manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) VALUES (
    'CAPABILITY_SELECTOR','1.0.0',1,0,0,'RELEASED',NULL,
    v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@4a9442cde62fec0ac54dcf67defac73b817b756e/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/CAPABILITY_SELECTOR_v1.manifest.json',
    'github://cristhianlujan/claude-persona-lf-patch@4a9442cde62fec0ac54dcf67defac73b817b756e/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@4a9442cde62fec0ac54dcf67defac73b817b756e/sandbox/lf_contract_gate_test/transversal_assets/capability_selector/test_capability_selector_v1.py',
    v_execution_id
  );

  v_promote := public.fn_lf_capability_promote_v1(
    'CAPABILITY_SELECTOR','1.0.0',NULL,v_execution_id,
    'T-SELECT generic selector proven with non-IG fixture and IG consumer binding; repository-bound, no runtime activation.'
  );
  IF coalesce((v_promote->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_PROMOTION:%',v_promote::text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='CAPABILITY_SELECTOR'
      AND capability_kind='TRANSVERSAL'
      AND owner_scope='SUPER_ADMIN'
      AND status='ACTIVE'
      AND entry_guard_required=false
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_REGISTRY_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code AND v.version=c.version
    WHERE c.capability_code='CAPABILITY_SELECTOR'
      AND c.version='1.0.0'
      AND c.manifest_sha256=v.manifest_sha256
      AND v.manifest->'contract'->>'admission_authority'='false'
      AND v.manifest->'contract'->>'execution_permission'='false'
      AND v.manifest->'compatibility'->>'domain_specific_branches'='false'
      AND v.manifest->'compatibility'->>'model_or_method_router'='false'
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_SELECT_CURRENT_READBACK';
  END IF;
END
$t_select$;
