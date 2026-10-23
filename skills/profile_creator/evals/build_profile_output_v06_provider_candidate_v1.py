#!/usr/bin/env python3
"""Build the current SRCR V0.6 provider candidate for Profile Updater output validation.

This is a source-authored current candidate, not a canonical example and not a
quality/cutover receipt. It intentionally remains NEEDS_MORE_EVIDENCE until the
provider-bound positive/negative receipts exist as VERIFIED ledger evidence.
"""
from __future__ import annotations

import copy
import hashlib
import json
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROFILE = ROOT / "profiles/systemic_root_cause_repair_lf"
V06 = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
LEDGER_LOCATOR = (
    "supabase://private/lf_evidence_ledger_v1/"
    "profile_output_validation/systemic_root_cause_repair_lf"
)
OBSERVED_AT = "2026-10-23T15:02:05.054404Z"

# Read-only authority/readback snapshot captured before candidate authoring.
SNAPSHOT = {
    "operation_row_sha256": "8150f1fb924561074b450ddede68d568ede03acb8287a4d0e6eebcc926cd3595",
    "pack_harness_row_sha256": "4012252c8e0ac30ca7148e5d1f5466db348866e512ec7171f3a0ff0d13a40309",
    "pack_harness_manifest_sha256": "fd8e28de7adb5cfad888bdaa5ab08b914ee935a7d039c360dbd4bb4efbdf88f4",
    "executor_event_sha256": "1c87dccbb4894ef145581113be38e48d26b416b2fef5a37b480e03fe930ae020",
    "full_route_rollback_event_sha256": "2f5035704acfd33b34b2b8f43632977655710cab5c2ca8ea832aa4c21674ccad",
    "output_receipt_snapshot_sha256": "ce0fee1b5ec220d630d34dca5654ea94a56980f867564f1f32a5580e280d1f79",
    "verified_output_receipt_count": 0,
}


def _sha_file(rel: str) -> str:
    return hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()


def _load_scaffold() -> dict:
    # Reuse only the already-tested V0.6 structural scaffolding. The current
    # authority/evidence and the blocking diagnosis are replaced below.
    return runpy.run_path(
        str(PROFILE / "evals/v06_edge_closure_cases.py"),
        run_name="profile_output_v06_provider_candidate_scaffold",
    )


def _unresolved(statement: str) -> dict:
    return {
        "status": "UNRESOLVED",
        "statement": statement,
        "evidence_refs": [LEDGER_LOCATOR],
        "missing_evidence": [
            "provider-bound positive and negative output validation receipts with verification_state=VERIFIED"
        ],
    }


def build(source_head_sha: str) -> tuple[dict, dict]:
    if not isinstance(source_head_sha, str) or len(source_head_sha) != 40:
        raise ValueError("SOURCE_HEAD_SHA_REQUIRED")

    fixture = _load_scaffold()
    candidate, evidence = fixture["v06_pair"]()
    closure_proof = fixture["closure_proof"]
    to_nonready = fixture["v05"]["to_nonready"]

    attempt = {
        "surface": "SUPABASE_TABLE_OR_VIEW",
        "locator": LEDGER_LOCATOR,
        "result": "ABSENT",
        "observation": (
            "Current readback contains two ANCHORED canonical-example receipts and "
            "zero VERIFIED output-validation receipts for systemic_root_cause_repair_lf."
        ),
        "evidence_id": "EV-PROVIDER-ATTEMPT",
    }
    candidate = to_nonready(candidate, [attempt])
    candidate["profile_pack_id"] = V06
    candidate["case_mode"] = "ARCHITECTURE_AUDIT"
    candidate["symptom"] = {
        "status": "OBSERVED",
        "statement": (
            "The existing output-validation producer is provider-bound to GitHub, but "
            "its durable ledger evidence is still limited to canonical examples; no "
            "VERIFIED receipt exists for a current evolved V0.6 candidate."
        ),
        "evidence_refs": [
            "supabase://public/lf_eventos/21493",
            LEDGER_LOCATOR,
            "github://cristhianlujan/claude-persona-lf-patch/skills/profile_creator/evals/"
            "produce_pe10_c6_source_bound_output_evidence_v1.py",
        ],
        "missing_evidence": [],
    }
    candidate["immediate_cause"] = _unresolved(
        "The exact-head provider has not yet consumed a committed current V0.6 candidate "
        "plus its external evidence manifest and returned both positive and derived-negative results."
    )
    candidate["systemic_root_cause"] = _unresolved(
        "The source-bound output path previously terminated at V0.2 canonical examples, "
        "so the V0.6 evidence-manifest transport and real-candidate receipt path had no complete proof."
    )
    candidate["first_bad_control"] = _unresolved(
        "The first unresolved control is provider validation of a non-example V0.6 candidate "
        "bound to the same exact GitHub HEAD and external evidence manifest."
    )
    candidate["escape_control"] = _unresolved(
        "Checkpoint closure correctly stays blocked because example_fixture_only ANCHORED receipts "
        "cannot satisfy the VERIFIED output-receipt reader."
    )
    if isinstance(candidate.get("causal_chain"), list):
        for row in candidate["causal_chain"]:
            if isinstance(row, dict):
                row.update(_unresolved(
                    "Provider-bound V0.6 output evidence is still incomplete at the current ledger boundary."
                ))
    candidate["recurrence_evidence"] = []
    candidate["repair_level"] = "UNDETERMINED"
    candidate["blocking_codes"] = ["PROFILE_OUTPUT_PROVIDER_VERIFIED_RECEIPTS_MISSING"]
    candidate["selected_alternative"] = None
    candidate["residual_risks"] = []
    candidate["current_uncertainties"] = [{
        "uncertainty_id": "U-PROVIDER-E2E",
        "uncertainty": (
            "A true current V0.6 candidate has not yet produced both VERIFIED output-validation receipts."
        ),
        "impact": "DESIGN_BLOCKING",
        "evidence_needed": [
            "exact-head positive validation result",
            "derived-negative validation result",
            "two EVIDENCE_LEDGER receipts resolved as VERIFIED",
        ],
        "design_consequence": (
            "Without those receipts the provider path cannot be used to close the engineering checkpoint "
            "or activate Profile Updater v0.2."
        ),
        "containment_ref": None,
        "attempted_sources": [attempt],
    }]

    disposition = candidate.get("repair_disposition")
    if isinstance(disposition, dict):
        disposition["decision"] = "UNDETERMINED"
        disposition["rationale"] = (
            "The transport repair is now source-tested, but the current candidate remains blocked until "
            "provider-bound VERIFIED receipts exist; no cutover decision is permitted from source tests alone."
        )

    candidate["live_authority_packet"] = {
        "status": "COMPLETE",
        "observed_at": OBSERVED_AT,
        "applicable_surfaces": [
            "PACK_VALIDATION_HARNESS",
            "ACTUALIZACION_PERFIL_LF",
            "EVIDENCE_LEDGER_OUTPUT_RECEIPTS",
            "ENGINEERING_TEST_EXECUTOR",
            "POSTGRES_ROLLBACK_PROBE",
        ],
        "inspected_surfaces": [
            "PACK_VALIDATION_HARNESS",
            "ACTUALIZACION_PERFIL_LF",
            "EVIDENCE_LEDGER_OUTPUT_RECEIPTS",
            "ENGINEERING_TEST_EXECUTOR",
            "POSTGRES_ROLLBACK_PROBE",
        ],
        "evidence_refs": [
            "supabase://public/lf_capability_current/PACK_VALIDATION_HARNESS@1.0.0",
            "supabase://public/lf_operation_registry/ACTUALIZACION_PERFIL_LF@v0.1",
            LEDGER_LOCATOR,
            "supabase://public/lf_eventos/21504",
            "supabase://public/lf_eventos/21513",
        ],
        "unavailable_sources": [],
        "unavailable_source_assessments": [],
        "material_effects_observed": False,
    }
    candidate["execution_effect_reconciliation"] = []

    graph = candidate["material_process_graph"]
    nodes = graph["nodes"]
    nodes[0]["node_id"] = "NODE-OUTPUT-CANDIDATE"
    nodes[0]["phase"] = "CURRENT_V06_CANDIDATE"
    nodes[0]["disposition"] = "REUSE_AS_IS"
    nodes[0].pop("blocking_uncertainty_id", None)
    nodes[1]["node_id"] = "NODE-VERIFIED-OUTPUT-RECEIPT"
    nodes[1]["phase"] = "PROVIDER_VERIFICATION_AND_LEDGER"
    nodes[1]["disposition"] = "DESIGN_BLOCKING"
    nodes[1]["blocking_uncertainty_id"] = "U-PROVIDER-E2E"
    graph["edges"] = [{
        "edge_id": "EDGE-OUTPUT-PROVIDER-VERIFICATION",
        "from_node": "NODE-OUTPUT-CANDIDATE",
        "to_node": "NODE-VERIFIED-OUTPUT-RECEIPT",
        "edge_kind": "CONTROL_FLOW",
        "observation_status": "OBSERVED_OPEN",
        "disposition": "DESIGN_BLOCKING",
        "producer_evidence_refs": ["EV-E-PRODUCER"],
        "transport_evidence_refs": ["EV-E-TRANSPORT"],
        "consumer_evidence_refs": [],
        "enforcement_evidence_refs": ["EV-E-ENFORCEMENT"],
        "effect_readback_evidence_refs": ["EV-PROVIDER-ATTEMPT"],
        "gap_evidence_refs": ["EV-PROVIDER-ATTEMPT"],
        "next_gate": None,
        "next_gate_consumer_evidence_refs": [],
        "canonical_route_consistency": {
            "applicability": "REQUIRED", "status": "UNRESOLVED", "evidence_refs": []
        },
        "post_transition_currentness": {
            "applicability": "REQUIRED", "status": "UNRESOLVED", "evidence_refs": []
        },
        "terminality": {
            "applicability": "REQUIRED", "status": "UNRESOLVED", "evidence_refs": []
        },
        "identity_consistency": {
            "applicability": "REQUIRED", "status": "UNRESOLVED", "evidence_refs": []
        },
        "rollback_executability": {
            "applicability": "REQUIRED", "status": "UNRESOLVED", "evidence_refs": []
        },
        "proposed_change_ref": None,
        "blocking_uncertainty_id": "U-PROVIDER-E2E",
    }]

    # Keep the closure scaffold mechanically consistent with a non-ready candidate,
    # but replace the open-requirement text with the actual unresolved provider proof.
    proof = candidate.get("closure_proof", {})
    for row in proof.get("proof_obligations", []):
        if row.get("status") == "OPEN":
            row["missing_requirements"] = [
                "provider-bound VERIFIED positive and negative output-validation receipts"
            ]
            row["closure_basis"] = None

    # Replace every scaffold locator/digest with an exact current authority or
    # exact-head source. Evidence IDs remain stable because the closure/edge
    # contracts reference those IDs.
    mapping = {
        "EV-ASSET": (
            "supabase://public/lf_capability_current/PACK_VALIDATION_HARNESS@1.0.0",
            SNAPSHOT["pack_harness_manifest_sha256"], "1.0.0"
        ),
        "EV-OP": (
            "supabase://public/lf_operation_registry/ACTUALIZACION_PERFIL_LF@v0.1",
            SNAPSHOT["operation_row_sha256"], "v0.1"
        ),
        "EV-OWNER": (
            "supabase://public/lf_capability_registry/PACK_VALIDATION_HARNESS",
            SNAPSHOT["pack_harness_row_sha256"], OBSERVED_AT
        ),
        "EV-CLOSURE": (
            "supabase://public/lf_eventos/21504",
            SNAPSHOT["executor_event_sha256"], OBSERVED_AT
        ),
        "EV-E-PRODUCER": (
            "git-sha256:skills/profile_creator/evals/build_profile_output_v06_provider_candidate_v1.py@"
            + _sha_file("skills/profile_creator/evals/build_profile_output_v06_provider_candidate_v1.py"),
            _sha_file("skills/profile_creator/evals/build_profile_output_v06_provider_candidate_v1.py"),
            _sha_file("skills/profile_creator/evals/build_profile_output_v06_provider_candidate_v1.py")
        ),
        "EV-E-TRANSPORT": (
            "git-sha256:skills/profile_creator/validators/run_bound_profile_output_validator_v1.py@"
            + _sha_file("skills/profile_creator/validators/run_bound_profile_output_validator_v1.py"),
            _sha_file("skills/profile_creator/validators/run_bound_profile_output_validator_v1.py"),
            _sha_file("skills/profile_creator/validators/run_bound_profile_output_validator_v1.py")
        ),
        "EV-E-CONSUMER": (
            "git-sha256:skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql@"
            + _sha_file("skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql"),
            _sha_file("skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql"),
            _sha_file("skills/profile_creator/contracts/profile_update_verified_receipt_reader_candidate_v1.sql")
        ),
        "EV-E-ENFORCEMENT": (
            "git-sha256:profiles/systemic_root_cause_repair_lf/contracts/runtime_binding.json@"
            + _sha_file("profiles/systemic_root_cause_repair_lf/contracts/runtime_binding.json"),
            _sha_file("profiles/systemic_root_cause_repair_lf/contracts/runtime_binding.json"),
            _sha_file("profiles/systemic_root_cause_repair_lf/contracts/runtime_binding.json")
        ),
        "EV-E-READBACK": (
            LEDGER_LOCATOR, SNAPSHOT["output_receipt_snapshot_sha256"], OBSERVED_AT
        ),
        "EV-E-NEXT": (
            "supabase://public/lf_eventos/21513",
            SNAPSHOT["full_route_rollback_event_sha256"], OBSERVED_AT
        ),
        "EV-E-ROUTE": (
            "supabase://public/lf_eventos/21513",
            SNAPSHOT["full_route_rollback_event_sha256"], OBSERVED_AT
        ),
        "EV-E-CURRENTNESS": (
            LEDGER_LOCATOR, SNAPSHOT["output_receipt_snapshot_sha256"], OBSERVED_AT
        ),
        "EV-E-TERMINALITY": (
            "supabase://public/lf_eventos/21504",
            SNAPSHOT["executor_event_sha256"], OBSERVED_AT
        ),
        "EV-E-IDENTITY": (
            "git-sha256:profiles/systemic_root_cause_repair_lf/manifest.json@"
            + _sha_file("profiles/systemic_root_cause_repair_lf/manifest.json"),
            _sha_file("profiles/systemic_root_cause_repair_lf/manifest.json"),
            _sha_file("profiles/systemic_root_cause_repair_lf/manifest.json")
        ),
        "EV-E-ROLLBACK": (
            "supabase://public/lf_eventos/21513",
            SNAPSHOT["full_route_rollback_event_sha256"], OBSERVED_AT
        ),
    }
    for row in evidence["evidence"]:
        eid = row.get("evidence_id")
        if eid in mapping:
            locator, digest, revision = mapping[eid]
            row["source_locator"] = locator
            row["digest"] = "sha256:" + digest
            row["revision_or_observed_at"] = revision
            row["state"] = "CURRENT"

    evidence["evidence"].append({
        "evidence_id": "EV-PROVIDER-ATTEMPT",
        "subject": "PROFILE-OUTPUT-VERIFIED-RECEIPT-GAP",
        "evidence_class": "OBSERVED_LIVE",
        "source_locator": LEDGER_LOCATOR,
        "revision_or_observed_at": OBSERVED_AT,
        "digest": "sha256:" + SNAPSHOT["output_receipt_snapshot_sha256"],
        "state": "CURRENT",
    })
    evidence["observed_at"] = OBSERVED_AT
    evidence["producer"] = {
        "kind": "GPT_NATIVE_CURRENT_CHAT_SOURCE_AUTHORED",
        "resolver_ref": "github-actions://Profile-GPT-Native-Capture-Regression/exact-pr-head",
    }
    evidence["bundle_digest"] = closure_proof.canonical_evidence_bundle_digest(evidence)
    return candidate, evidence


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: build_profile_output_v06_provider_candidate_v1.py <40-char-source-head>")
    candidate, evidence = build(sys.argv[1])
    print("PROFILE_OUTPUT_V06_CANDIDATE=" + json.dumps(
        candidate, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ))
    print("PROFILE_OUTPUT_V06_EVIDENCE_MANIFEST=" + json.dumps(
        evidence, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
