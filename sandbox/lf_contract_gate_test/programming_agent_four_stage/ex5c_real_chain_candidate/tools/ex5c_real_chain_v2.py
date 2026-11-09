"""EX5C N -> N+1 source-only N:M chain, on original V1 up to PG10 and V2 thereafter.

The V2 modules are independent from V1. No production, Analysis, Testing,
Supabase or hidden oracle access. A local ACCEPT means shape only.
Only the fixed source bundles are read; missing authority stays False.
"""
from __future__ import annotations

import base64
import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import ex5c_real_world_v1 as w
w.setup_paths()
import test_pg10_decision_chain_v1 as t10

from pg11_c1_diff_hygiene_candidate_v2 import prepare_pg11_c1
from pg11_c2_terminology_catalog_candidate_v2 import prepare_pg11_c2
from pg11_c3_suppression_waiver_candidate_v2 import prepare_pg11_c3
from pg11_c4_diff_requirement_batch_trace_candidate_v2 import prepare_pg11_c4
from pg11_c5_independent_reviewer_candidate_v2 import prepare_pg11_c5
from pg11_pg10_handoff_bridge_candidate_v2 import bridge_pg10_c5_to_pg11_c1
from pg12_c1_candidate_identity_v2 import prepare_pg12_c1
from pg12_c2_execution_inputs_usage_candidate_v2 import prepare_pg12_c2
from pg12_c3_check_results_link_candidate_v2 import prepare_pg12_c3
from pg12_c4_persistence_readback_request_candidate_v2 import prepare_pg12_c4
from pg12_git_identity_and_pg11_bridge_v2 import (
    bridge_pg11_to_pg12_identity, verify_git_object,
)
from pg13_c1_freeze_intent_candidate_v2 import prepare_pg13_c1
from pg13_c2_rebuild_comparison_candidate_v2 import prepare_pg13_c2
from pg13_c3_mutation_block_candidate_v2 import prepare_pg13_c3, SCENARIOS
from pg13_pg12_exact_freeze_bridge_v2 import bridge_pg12_c4_to_pg13_c1
from pg13_ex5c_reconstructed_freeze_attack_v2 import local_freeze_and_attacks
from pg14_c1_testing_execution_contract_candidate_v2 import prepare_pg14_c1
from pg14_c2_testing_payload_candidate_v2 import prepare_pg14_c2
from pg14_c2_completeness_guard_v2 import validate_pg14_c2_completeness
from pg14_c3_testing_admission_readback_request_candidate_v2 import prepare_pg14_c3
from pg14_pg13_freeze_bridge_v2 import bridge_pg13_to_pg14
from pg14_local_testing_receiver_v2 import simulate_testing_receiver


def authorize_from_real_hunks():
    """N:M per path; repeated hunks of one triple are one authorization.

    Sources are fixed evidence bundles, not an authenticated approval registry.
    """
    hunks = w.real_hunks()
    files = sorted(set(w.SOL1_FILES) | set(w.SOL2_FILES))
    diff = [{"path": path, "change_type": "MODIFIED", "old_path": None}
            for path in files]
    authorization = []
    traces = []
    for record in diff:
        path = record["path"]
        links = {}
        for hunk in hunks:
            if hunk["path"] != path:
                continue
            for req in hunk["requirements"]:
                requirement_ref = w.SPEC + "#" + req
                batch_ref = "ex5c://batch/ex5c-" + hunk["solution_id"]
                scope_ref = "ex5c://scope/" + hunk["solution_id"]
                key = (requirement_ref, batch_ref, scope_ref)
                if key not in links:
                    links[key] = {
                        "requirement_ref": requirement_ref,
                        "batch_ref": batch_ref,
                        "scope_ref": scope_ref,
                        "evidence_ref": hunk["header_ref"],
                        "change_reason_ref": (
                            w.RUN_WORKER if hunk["solution_id"] == "SOL-001"
                            else w.RUN_V3),
                    }
        if not links:
            raise AssertionError("EX5C_V2_ORPHAN_REAL_DIFF_FILE:" + path)
        authorization.append({
            **record,
            "authorized_links": [
                {k: row[k] for k in ("requirement_ref", "batch_ref", "scope_ref")}
                for _, row in sorted(links.items())
            ],
        })
        traces.append({
            "path": path, "status_reported": "LINKED",
            "links": [row for _, row in sorted(links.items())],
        })
    return diff, authorization, traces


def make_pg11_v2():
    upstream = t10.build()
    pg08 = upstream["upstream"]["pg08"]
    pg09 = upstream["upstream"]
    diff, authorization, traces = authorize_from_real_hunks()
    files = [row["path"] for row in diff]
    c1 = prepare_pg11_c1(
        expected_base_sha=w.BASE, expected_head_sha=w.N1,
        declared_diff=diff, authorized_scope=authorization,
        residue_observations=[], dependency_observations=[],
        compatibility_observations=[{
            "surface": "MODULE_CONTRACT",
            "contract_ref": w.SPEC + "#lote-c",
            "baseline_ref": "github://" + w.REPO + "/tree/" + w.BASE + "/apps/time-service",
            "evidence_ref": w.RUN_V3 + "#maven_verify",
            "compatible_reported": True,
        }],
    )
    c2 = prepare_pg11_c2(
        pg11_c1=c1, declared_changed_paths=files,
        terminology_observations=[{
            "path": w.J + "/reminder/ReminderRepository.java",
            "symbol_ref": "github://" + w.REPO + "/blob/" + w.N1 + "/" +
                          w.J + "/reminder/ReminderRepository.java#findByTextContaining",
            "kind": "DOMAIN_IDENTIFIER",
            "literal_value": "findByTextContaining",
            "source_ref": w.SPEC + "#REM-C1",
            "term_ids": ["REM-C1"],
            "term_exists_reported": True,
            "term_matches_reported": True,
            "literal_match_reported": True,
            "neighbor_match_reported": True,
        }],
        glossary_snapshot_ref=w.SPEC + "@" + w.N1,
        catalog_snapshot_ref=w.SPEC + "@" + w.N1,
        messages_snapshot_ref=w.SPEC + "@" + w.N1 + "#REM-B2",
        neighbor_baseline_ref="github://" + w.REPO + "/tree/" + w.BASE + "/" + w.J,
    )
    c3 = prepare_pg11_c3(
        pg11_c2=c2, suppression_observations=[], waiver_observations=[],
        std_gen_05_source_ref=w.SPEC + "@" + w.N1 + "#norma-de-formato",
    )
    c4 = prepare_pg11_c4(
        pg11_c1=c1, pg11_c2=c2, pg11_c3=c3,
        declared_diff=diff, authorized_scope=authorization,
        trace_observations=traces,
    )
    # This represents the latest N+1 change per path. The worker's
    # N provenance remains in each N:M C4 link and in the hunk manifest.
    reviews = [{
        "path": path,
        "builder_principal_ref": w.BUILDER["SOL-002"],
        "reviewer_principal_ref": w.REVIEWER,
        "reviewer_role_ref": "ex5c://role/independent-verifier-source-only",
        "builder_provenance_ref": w.RUN_V3,
        "reviewer_provenance_ref": "ex5c://reviewer-provenance/unattested",
        "review_scope_ref": "github://" + w.REPO + "/compare/" + w.N +
                            "..." + w.N1,
        "reviewer_is_builder_reported": False,
        "reviewer_independence_reported": True,
    } for path in files]
    c5 = prepare_pg11_c5(
        pg11_c4=c4, review_observations=reviews,
        review_policy_ref="ex5c://policy/reviewer-distinct-from-builder",
    )
    bridge = bridge_pg10_c5_to_pg11_c1(
        pg10_c5=upstream["c5"], pg10_c4=upstream["c4"],
        pg09_c4=pg09["c4"], pg08_final=pg08["final"],
        pg08_c1=pg08["c1"],
        lineage_solution_ids=["SOL-001", "SOL-002"],
        pg11_c1=c1,
        run_binding={
            "run_ref": upstream["c5"]["run_ref"],
            "target_repo": w.REPO,
            "base_head_sha": w.BASE,
            "expected_head_sha": w.N1,
        },
    )
    return locals()


def make_pg12_v2(pg11=None):
    pg11 = pg11 or make_pg11_v2()
    v1, cost = w.worker_cost()
    v2 = w.load_bundle("lf-evidence-bundle-v2.json", w.V2_SHA)
    v3 = w.load_bundle("lf-evidence-bundle-v3.json", w.V3_SHA)
    prior = next(s for s in v2["snapshots"] if s["label"] == "candidate")
    if prior["commit"] != w.N or v3["git"]["base_commit"] != w.N:
        raise AssertionError("EX5C_V2_INCREMENTAL_LINEAGE_DRIFT")
    old = {f["path"]: f["git_blob_oid"] for f in prior["files"]}
    new = {f["path"]: f["oid"] for f in v3["git"]["files"]}
    changed = [{
        "path": path, "change_type": "MODIFIED", "old_path": None,
        "object_type": "blob", "object_oid": new[path], "old_object_oid": old[path],
    } for path in sorted(set(w.SOL1_FILES) | set(w.SOL2_FILES))]
    builders = [{
        "path": path, "builder_principal_ref": w.BUILDER["SOL-002"],
        "builder_provenance_ref": w.RUN_V3,
    } for path in sorted(set(w.SOL1_FILES) | set(w.SOL2_FILES))]
    c1 = prepare_pg12_c1(
        pg11_c5=pg11["c5"], repo_ref=w.REPO,
        base_commit_sha=w.N, candidate_commit_sha=w.N1,
        candidate_tree_sha=v3["git"]["tree"], diff_sha256=w.DIFF_SOL2,
        changed_objects=changed,
        builder_principal_ref=w.BUILDER["SOL-002"],
        builder_provenance_ref=w.RUN_V3,
        builder_bindings=builders,
    )
    # The v1 source is a real raw N commit, v3 is a raw N+1 commit.
    # They are verified independently; PG12 bridge never fabricates
    # a raw full-root Git tree when only subtree bytes are available.
    raw_n = base64.b64decode(v1["git"]["raw_commit_base64"], validate=True)
    raw_n1 = base64.b64decode(v3["git"]["raw_commit_base64"], validate=True)
    verify_git_object(object_kind="commit", object_bytes=raw_n, declared_oid=w.N)
    verify_git_object(object_kind="commit", object_bytes=raw_n1, declared_oid=w.N1)
    bridge = bridge_pg11_to_pg12_identity(
        pg10_pg11_bridge=pg11["bridge"], pg11_c5=pg11["c5"],
        pg12_c1=c1, repo_ref=w.REPO,
    )
    usage = cost["attempts"][0]
    amount = str(usage["estimated_usd"])
    row = {
        "stage_ref": "PG-07-SOL-001", "input_tokens": usage["input_tokens"],
        "output_tokens": usage["output_tokens"],
        "cached_input_tokens": 0, "cost_reported": amount,
        "wasted_cost_reported": "0",
    }
    c2 = prepare_pg12_c2(
        pg12_c1=c1, context_id=w.RUN_WORKER + "#ex5c",
        catalog_version_ref=w.SPEC + "@" + w.N1,
        skill_versions=[{"name": "programming-worker",
                         "version_ref": "github://cristhianlujan/programming-agent@298307e2f9cac72abfde2b181f3554b0e28bad24"}],
        stack_profile_ref="github://" + w.REPO + "/tree/" + w.N1 + "/apps/time-service",
        provider_ref="anthropic://models",
        model_ref=cost["model"], ekb_snapshot_ref=w.SPEC + "@" + w.N1,
        toolchain_versions=[
            {"name": "maven", "version_ref": w.RUN_V3 + "#maven_verify"},
            {"name": "java", "version_ref": w.RUN_V3 + "#javac"},
            {"name": "google-java-format", "version_ref": v3["formatter_sha256"]},
        ],
        linter_config_sha256=v3["formatter_sha256"],
        optimization_mode="HYBRID",
        usage_totals={**row, "stage_ref": "TOTAL"},
        usage_by_stage=[row],
        extra_queries=[{
            "query_id": "EX5C-N1-NATIVE-BILLING-UNKNOWN",
            "reason_type": "EVIDENCE_GAP",
            "resolver_ref": "ex5c://owner/native-usage",
            "exact_query_ref": w.RUN_V3 + "#no-model-api-billing",
        }],
        identifier_term_map=[{
            "identifier_ref": w.J + "/reminder/ReminderRepository.java#findByTextContaining",
            "term_ids": ["REM-C1"],
            "glossary_source_ref": w.SPEC + "#REM-C1",
        }],
        billing_currency="USD",
    )
    checks = [{
        "checkpoint_code": f"PG-{stage:02d}_C{number}",
        "candidate_identity_sha256": c1["candidate_sha256"],
        "check_contract_ref": "github://cristhianlujan/claude-persona-lf-patch/tree/" +
                              "8bbba93398f873bdf5079fc9db907de2a2504afa/sandbox/lf_contract_gate_test/programming_agent_four_stage",
        "result_ref": None, "result_digest_sha256": None,
        "runner_ref": w.RUN_V3,
        "observed_outcome": "NOT_RUN", "execution_receipt_ref": None,
    } for stage, count in ((8, 8), (11, 5)) for number in range(1, count + 1)]
    c3 = prepare_pg12_c3(
        pg12_c2=c2, candidate_identity_sha256=c1["candidate_sha256"],
        check_observations=checks,
    )
    c4 = prepare_pg12_c4(
        pg12_c3=c3,
        storage_contract_ref="ex5c://pg12/isolated-local-readback-v2",
        authorized_writer_ref="ex5c://disposable-postgres-only",
        readback_contract_ref="ex5c://pg12/readback-contract-v2",
        record_key_ref="ex5c://pg12/N1-" + w.N1,
        expected_store_namespace="pg12_test_ex5c_n1",
    )
    return locals()


def make_pg13_v2(pg12=None):
    pg12 = pg12 or make_pg12_v2()
    v3 = pg12["v3"]
    c1 = prepare_pg13_c1(
        pg12_c4=pg12["c4"],
        candidate_commit_sha=w.N1, candidate_tree_sha=v3["git"]["tree"],
        freeze_policy_ref="ex5c://pg13/freeze/immutable-N1",
        freeze_request_ref="ex5c://pg13/N1-" + w.N1,
    )
    bridge = bridge_pg12_c4_to_pg13_c1(
        pg12_c1=pg12["c1"], pg12_c4=pg12["c4"], pg13_c1=c1,
    )
    before = w.canon_sha(v3["class_equivalence"]["baseline"])
    after = w.canon_sha(v3["class_equivalence"]["candidate"])
    rebuild = [{
        "artifact_ref": w.RUN_V3 + "#javac-g-none-classes",
        "baseline_digest_sha256": before,
        "rebuild_digest_sha256": after,
        "difference_ref": None,
    }]
    c2 = prepare_pg13_c2(
        pg13_c1=c1, rebuild_observations=rebuild,
        build_recipe_ref=w.RUN_V3 + "#maven_verify",
        environment_lock_ref=v3["formatter_sha256"],
    )
    scenarios = [{
        "scenario_code": code,
        "attempt_ref": "ex5c://pg13/isolated-local-mutation/" + code,
        "expected_verdict": "BLOCK",
        "evidence_ref": "ex5c://pg13/pending-execution/" + code,
    } for code in sorted(SCENARIOS)]
    c3 = prepare_pg13_c3(
        pg13_c2=c2, mutation_scenarios=scenarios,
        policy_ref="ex5c://pg13/immutable-ref-policy",
    )
    # Tests invoke local_freeze_and_attacks separately and demand five BLOCKs.
    # No stage flags are promoted based on these source-only declarations.
    return locals()


def make_pg14_v2(pg13=None, local_freeze=None):
    pg13 = pg13 or make_pg13_v2()
    if local_freeze is None:
        local_freeze = local_freeze_and_attacks()
    if local_freeze["source_commit"] != w.N1 or local_freeze["blocked_mutation_count"] != 5:
        raise AssertionError("EX5C_V2_N1_FREEZE_NOT_VERIFIED")
    contract = json.loads((ROOT / "wave1_boundary_contracts" /
                           "testing_admission_contract_v1.json").read_text(encoding="utf-8"))
    analysis = {
        "package_ref": "ex5c://analysis/not-ready",
        "package_sha256": w.canon_sha({
            "status": "NOT_READY", "source": w.SPEC, "version": w.N1}),
        "source_currentness_ref": w.SPEC + "@" + w.N1,
        "ready_verified": False,
    }
    identity = pg13["pg12"]["c1"]
    c1 = prepare_pg14_c1(
        pg13_c3=pg13["c3"], admission_contract=contract,
        analysis_package_ref=analysis["package_ref"],
        analysis_package_sha256=analysis["package_sha256"],
        source_currentness_ref=analysis["source_currentness_ref"],
        frozen_candidate_ref=w.RUN_V3 + "#N1",
        frozen_candidate_sha256=identity["candidate_sha256"],
    )
    bridge = bridge_pg13_to_pg14(
        pg12_c1=identity, pg13_bridge=pg13["bridge"],
        pg13_c1=pg13["c1"], pg13_c2=pg13["c2"], pg13_c3=pg13["c3"],
        pg14_c1=c1,
        freeze_tag_ref="refs/tags/frozen/" + w.N1,
        freeze_tag_oid=local_freeze["local_tag_oid"],
        analysis_package_observation=analysis,
    )
    obligations = [{
        "obligation_ref": "REM-C1",
        "spec_ref": w.SPEC + "@" + w.N1 + "#REM-C1",
        "test_case_ref": w.RUN_V3 + "#maven_verify",
        "expected_oracle_ref": "ex5c://unverified/blind-oracle-not-available",
    }]
    c2 = prepare_pg14_c2(
        pg14_c1=c1, catalog_version_ref=w.SPEC + "@" + w.N1,
        spec_test_obligations=obligations,
        blind_test_contract_ref="fn_submit_blind_test_contract",
        pending_copy_texts=[], required_obligation_ref="REM-C1",
        copy_applicability_ref="ex5c://not-applicable/no-ui-copy-in-time-service@" + w.N1,
    )
    completeness = validate_pg14_c2_completeness(c2)
    c3 = prepare_pg14_c3(
        pg14_c2=c2,
        testing_admission_endpoint_ref="ex5c://testing/isolated-local-receiver-only",
        readback_contract_ref="ex5c://pg14/disposable-readback-v2",
        request_key_ref="ex5c://pg14/N1-" + w.N1,
    )
    verdict = simulate_testing_receiver(
        pg14_bridge=bridge, pg14_c1=c1, pg14_c2=c2, pg14_c3=c3,
        request_payload=c3["admission_request"],
    )
    tampered_request = copy.deepcopy(c3["admission_request"])
    tampered_request["frozen_candidate_sha256_reported"] = "f" * 64
    blocked = simulate_testing_receiver(
        pg14_bridge=bridge, pg14_c1=c1, pg14_c2=c2, pg14_c3=c3,
        request_payload=tampered_request,
    )
    return locals()
