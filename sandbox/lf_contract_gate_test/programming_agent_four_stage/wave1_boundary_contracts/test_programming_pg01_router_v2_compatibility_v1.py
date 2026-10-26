"""Actual canonical Router SQL -> candidate receiver, disposable local PG only.

Characterization includes missing links; never invent fields/admission receipts.
Invoked by run_programming_pg01_receiver_base_v1.py --router-v2-evidence.
"""
from copy import deepcopy
import hashlib
import json
from run_programming_pg01_receiver_base_v1 import canonical_function, literal


def exercise_router_v2(*, context, sql, query, check, repo, persisted, receiver):
    source_paths = {
        "validator": "supabase/migrations/20261024090500_lf_router_stage1_v2_lf_integration_v1.sql",
        "route": "supabase/migrations/20261024133000_lf_router_product_context_resolution_v1.sql",
    }
    sources = {k: (repo / p).read_text() for k, p in source_paths.items()}
    sql(canonical_function(sources["validator"], "public.lf_router_stage1_validate_v2"))
    sql(canonical_function(sources["route"], "public.lf_router_route_v1"))
    # main also patches the function body through guarded DO blocks. Replay
    # those exact patches, without unrelated data writes or postchecks.
    original_definition = query("to_jsonb(pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure))")
    patches = [
        ("20261024170000_lf_router_profile_execution_handoff_v1.sql", "$patch_route$"),
        ("20261024193000_lf_profile_input_governance_task_applicability_v1.sql", "$patch_router_task_binding$"),
        ("20261025000500_lf_router_product_dynamic_profile_selection_v1.sql", "$patch$"),
        ("20261026145500_lf_router_product_context_resolution_v1.sql", "$patch_route$"),
        ("20261026161500_lf_router_thin_derivation_profile_investigation_v1.sql", "$route$"),
        ("20261026213000_lf_router_profile_selection_all_channels_v1.sql", "$patch_route$"),
    ]
    for name, tag in patches:
        path = "supabase/migrations/" + name
        text = (repo / path).read_text()
        start = text.index("DO " + tag)
        end = text.index(tag + ";", start + len("DO " + tag)) + len(tag) + 1
        sql(text[start:end])
        source_paths[name] = path
        sources[name] = text
    final_definition = query("to_jsonb(pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure))")
    check("router_v2_latest_main_dynamic_product_patch_present", "PRODUCTO_PROFILE_SELECTION_REQUIRED" in final_definition, True)
    # 20261026161500 (thin derivation) replaces the context-first Product block:
    # the Router now only derives and the selected profile investigates READ_ONLY.
    check("router_v2_latest_main_context_first_block_replaced", "product_context_read_before_profile_selection" in final_definition, False)
    check("router_v2_latest_main_thin_derivation_patch_present", "'router_work_mode','DERIVATION_ONLY'" in final_definition, True)
    def programming_branch(text):
        start = text.index("IF v_channel='PROGRAMACION' THEN")
        return text[start:text.index("    END IF;", start)]
    branch = programming_branch(final_definition)
    check("router_v2_programming_branch_replaced_by_profile_selection",
          "'paso','PROGRAMACION_PROFILE_SELECTION_REQUIRED'" in branch and branch != programming_branch(original_definition), True)
    for marker in (
        "'code','PROGRAMACION_PRECHECK_DEFINICION'",
        "'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS'",
        "'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO'",
        "'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA'",
        "'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1'",
        "'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1'",
    ):
        check("router_v2_programming_precondition_preserved_" + marker.split("','")[0].strip("'"), marker in branch, True)
    # Test-only stub: the disposable DB has no profile catalog or real selector.
    # Signature and fixed result emulate only the Router dependency.
    sql("""CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_prepare_v1(p_text text)
           RETURNS jsonb LANGUAGE sql AS $stub$
           SELECT jsonb_build_object('schema_version','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
                                     'catalog_profile_count',3)
           $stub$;""")
    stage1 = {
        "schema_version": "LF_ROUTER_STAGE1_V2", "texto_original": "Corregir el backend del login B2B ya definido",
        "es_operacion": True, "respuesta_directa": False, "accion": "corregir", "sujeto": "backend login B2B",
        "correcciones": [], "formas_busqueda": ["backend login B2B"], "ambiguo": False,
        "alternativas": [], "pregunta_usuario": None, "capability_hint": None,
        "downstream_execution_allowed": False, "canal_candidato": "PROGRAMACION", "negocio_codigo": "LF",
        "negocios_afectados": [], "ruta_transversal": None, "razon_seleccion": "Correccion tecnica sobre definicion vigente",
        "alcance": {"target_type": "COMPONENTE", "target_hint": "backend login B2B", "resolution_status": "UNRESOLVED"},
    }
    check("router_v2_stage1_valid", query("public.lf_router_stage1_validate_v2(" + literal(stage1) + ")")["valid"], True)
    route = query("public.lf_router_route_v1(" + literal(stage1) + ")")
    b = repo / "sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts"
    raw = (b / "programming_entry_contract_v1.json").read_bytes()
    entry = json.loads(raw); digest = hashlib.sha256(raw).hexdigest()
    good, handoff = persisted(context, "router_v2_positive_snapshot")
    subject = receiver(good)
    check("router_v2_actual_paso_is_profile_selection", route["paso"], "PROGRAMACION_PROFILE_SELECTION_REQUIRED")
    check("router_v2_derivation_only", route["router_work_mode"], "DERIVATION_ONLY")
    check("router_v2_profile_candidates_stub", route["profile_selection_candidate_count"], 3)
    check("router_v2_channel_precondition_code", route["channel_precondition"]["code"], "PROGRAMACION_PRECHECK_DEFINICION")
    check("router_v2_precondition_before_effect", route["channel_precondition"]["required_before_channel_effect"], True)
    check("router_v2_gate2_no_profile_effects", route["gate2_authorizes_profile_effects"], False)
    check("router_v2_conditional_continuation_only", route["channel_precondition"]["si_definicion_vigente"], "PROGRAMACION_ADMISION_REQUERIDA")
    check("router_v2_contract_schema_matches_receiver", route["channel_precondition"]["contrato_entrada_despues_precheck"], entry["schema_version"])
    check("router_v2_receiver_digest_matches_exact_file", subject.contract_digest, digest)
    check("router_v2_frozen_entry_digest", digest, "d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8")
    check("router_v2_upstream_name", route["channel_precondition"]["upstream_requerido_despues_precheck"], "ANALYSIS_IMPLEMENTATION_PACKAGE_V1")
    check("router_v2_never_execution", route["downstream_execution_allowed"], False)
    check("router_v2_does_not_supply_context_id", "context_id" in route, False)
    check("router_v2_does_not_supply_schema_digest", "snapshot_schema_digest_sha256" in route, False)
    check("router_v2_does_not_certify_definition_current", "currentness" in route, False)
    check("router_v2_no_expected_handoff_blocks", subject.consume(None, "S1")["code"], "EXPECTED_HANDOFF_INVALID_OR_MISSING")
    accepted = subject.consume(handoff, "S1")
    check("router_v2_structural_snapshot_positive", accepted["state"], "ACCEPT")
    check("router_v2_fixture_has_no_package_envelope", "ANALYSIS_IMPLEMENTATION_PACKAGE_V1" in json.dumps(good), False)
    # Characterize a real gap: this boundary validates a snapshot and an expected
    # handoff, but does not authenticate the producer's package admission.
    check("router_v2_gap_missing_package_not_independently_attested", accepted["execution_allowed"], False)
    zero = deepcopy(context)
    zero["extensions"]["programming_context_snapshot"]["scope_readiness"][0]["status"] = "NOT_APPLICABLE"
    zero["extensions"]["programming_context_snapshot"]["package_readiness"] = "NEED_MORE_EVIDENCE"
    zero, zero_handoff = persisted(zero, "router_v2_zero_ready")
    check("router_v2_zero_ready_receiver_BLOCK", receiver(zero).consume(zero_handoff, "S1")["code"], "NO_READY_SCOPE")
    check("router_v2_unknown_scope_BLOCK", subject.consume(handoff, "OTHER")["code"], "REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN")
    stale = receiver(good, change="snapshot_source", classification="BREAKING").consume(handoff, "S1")
    check("router_v2_stale_receiver_BLOCK", stale["code"], "CURRENTNESS_NOT_ADMISSIBLE")
    tampered = deepcopy(accepted["material_projection"]);tampered["snapshot"].pop("requirements")
    check("router_v2_lossy_receiver_BLOCK", subject.consume(handoff,"S1",proposed_projection=tampered)["code"], "MATERIAL_PROJECTION_LOSS_OR_MISMATCH")
    policy = json.loads((repo / "sandbox/lf_contract_gate_test/router_stage1/channel_policy_candidate_v1.json").read_text())
    check("router_v2_three_channels", [x["code"] for x in policy["channels"]], ["PRODUCTO","PROGRAMACION","OPERACIONES"])
    check("router_v2_policy_deployed", policy["state"], "DEPLOYED_LF_V2")
    check("router_v2_policy_analysis_return", policy["decision_policy"]["programming_on_analysis_missing_or_stale"], "RETURN_TO_ANALYSIS_NO_CODE")
    check("router_v2_policy_runtime_return", policy["decision_policy"]["programming_on_unauthorized_runtime"], "BLOCK_NO_CODE")
    return {
        "evidence_tier": "LOCAL_CANONICAL_ROUTER_SQL_AND_RECEIVER_SYNTHETIC_CONTEXT_CURRENTNESS",
        "route_input_fixture": stage1, "actual_route_output": route,
        "canonical_source_sha256": {source_paths[k]: hashlib.sha256(v.encode()).hexdigest() for k,v in sources.items()},
        "receiver_contract_digest": digest, "schema_identity_match": True,
        "profile_selector_stubbed_for_local_replay": True,
        "runtime_authorization_tested": False, "definition_currentness_tested": False,
        "gaps": ["ROUTER_DERIVES_PROFILE_SELECTION_PRECONDITION_NOT_ADMISSION", "NO_ROUTER_SCHEMA_DIGEST_OR_EXPECTED_HANDOFF",
                 "PACKAGE_ENVELOPE_AND_ADMITTED_A9_PROVENANCE_NOT_CHECKED_BY_BOUNDARY",
                 "NO_ONE_TO_ONE_RUNTIME_AUTHORIZATION_BLOCK_IN_RECEIVER"],
        "mapping": {
            "RETURN_TO_ANALYSIS_NO_CODE": ["EXPECTED_HANDOFF_INVALID_OR_MISSING", "NO_READY_SCOPE", "REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN", "CURRENTNESS_NOT_ADMISSIBLE"],
            "BLOCK_NO_CODE": ["MATERIAL_PROJECTION_LOSS_OR_MISMATCH"],
        },
        "mapping_is_proposed_consumer_projection_not_router_dispatch": True,
        "positive_receipt": accepted["receipt"], "execution_allowed": False,
    }
