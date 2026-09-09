#!/usr/bin/env python3
"""Pre-bind fresh S26 Native Golden Run E without producing RAW output."""
from __future__ import annotations
import contextlib
import io
import json
import os
import sys
from pathlib import Path

import prepare_s26_native_golden_c as base
from profile_execution_contract import build_execution_contract, canonical_json_sha256

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_005"
TEMPLATE = EVIDENCE / "obligation_template.json"
OBSERVATION_PACKET = EVIDENCE / "visual_observation_packet.json"
OUT = EVIDENCE / "preflight_binding.json"


def main() -> int:
    template = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    if template.get("run_revision") != "E":
        raise SystemExit("BLOCK_RUN_REVISION_NOT_E")
    raw_exists = (EVIDENCE / "raw_output.json").exists()
    if raw_exists and os.getenv("S26_RUN_E_ALLOW_RAW_REEVAL") != "1":
        raise SystemExit("BLOCK_RUN_E_RAW_EXISTS_BEFORE_PREFLIGHT")
    observation_packet = json.loads(OBSERVATION_PACKET.read_text(encoding="utf-8"))
    if observation_packet.get("schema") != "LF_RESOLVER_BACKED_SCREEN_OBSERVATION_PACKET_V1":
        raise SystemExit("BLOCK_RUN_E_OBSERVATION_PACKET_SCHEMA")
    source_visual = observation_packet.get("source_visual") or {}
    if source_visual.get("sha256") != "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287":
        raise SystemExit("BLOCK_RUN_E_OBSERVATION_PACKET_VISUAL_SHA")
    if source_visual.get("byte_parity_verified") is not True:
        raise SystemExit("BLOCK_RUN_E_OBSERVATION_PACKET_BYTE_PARITY")
    if any("current_page" in json.dumps(item, ensure_ascii=False) for item in observation_packet.get("observable_facts", [])):
        raise SystemExit("BLOCK_RUN_E_CURRENT_PAGE_LEAK_IN_FACTS")
    forbidden = set((observation_packet.get("execution_authority") or {}).get("forbidden") or [])
    if "Treat a producer-derived pagination formula as an upstream/canonical rule." not in forbidden:
        raise SystemExit("BLOCK_RUN_E_PRECISION_AUTHORITY_GUARD_MISSING")
    old = sys.argv[:]
    buf = io.StringIO()
    try:
        sys.argv = [str(Path(base.__file__)), "--template", str(TEMPLATE), "--output", str(EVIDENCE / "base_preflight.json")]
        with contextlib.redirect_stdout(buf):
            rc = base.main()
    finally:
        sys.argv = old
    if rc != 0:
        return rc
    resolved = json.loads(buf.getvalue())
    observation_packet_sha = canonical_json_sha256(observation_packet)
    contract = build_execution_contract(
        run_id=resolved["execution_id"], profile_code=template["profile_code"], profile_version="resolved:" + resolved["profile_source_sha256"][:16], objective=template["objective"],
        authorized_scope=["screen:B2B-CARGA-001", "artifact_sha256:" + resolved["visual_artifact_sha256"], "evidence:s26_native_golden_005", "observation_packet_sha256:" + observation_packet_sha], current_gate=template["current_gate"],
        allowed_actions=["READ_INPUT", "CONSUME_GOVERNED_CONTEXT", "EVALUATE_UI", "EMIT_FINDINGS", "MATERIALIZE_EVIDENCE"],
        forbidden_actions=["MODIFY_PRODUCTION", "MERGE_MAIN", "ACQUIRE_MODEL_WEIGHTS", "MODIFY_SHELL", "SELF_AUTHORIZE_GOLDEN", "SECOND_ADAPTER_LLM_CALL", "INFER_CURRENT_PAGE", "LABEL_DERIVED_RULE_AS_UPSTREAM"],
        required_checks=["ROUTER", "INPUT_GOVERNANCE", "PROFILE_CONTRACT", "RESOLVER_BACKED_OBSERVATION_PACKET", "CARD_RECEIPT_SAME_RUN", "ADAPTER_RECEIPT_SAME_RUN", "UI_ARCHITECT_VALIDATOR", "DEPTH_GATE", "SEMANTIC_OBLIGATION_COVERAGE", "INDEPENDENT_QUALITY", "LATENCY_OBSERVABLE", "TOKEN_USAGE_STATUS", "TRACEABILITY", "NO_MODEL_WEIGHT_ACQUISITION"],
        required_evidence=["router", "input_governance", "resolver_backed_observation_packet", "visual_artifact_provenance", "governed_context_receipt", "card_receipt", "adapter_receipt", "profile_execution", "ui_validator", "depth_gate", "semantic_manifest", "independent_quality", "native_metrics", "traceability"],
        closure_conditions=["STRUCTURAL_PASS", "GOVERNED_CONTEXT_PASS", "RESOLVER_BACKED_UPSTREAM_PASS", "DEPTH_PASS", "SEMANTIC_OBLIGATIONS_PASS", "INDEPENDENT_QUALITY_STRICT_PASS", "LATENCY_OBSERVABLE_PASS", "TOKEN_USAGE_STATUS_PASS", "TRACEABILITY_PASS", "NO_MODEL_WEIGHT_ACQUISITION", "NO_P0_OPEN", "READBACK_PASS"],
        input_governance_ref=template["input_governance_ref"], card_refs_and_hashes=[{"ref": template["card_ref"], "sha256": resolved["card_source_sha256"]}], adapter_ref=f"{template['adapter_ref']}@sha256:{resolved['adapter_source_sha256']};binding_sha256:{resolved['adapter_binding_snapshot_sha256']}", context_fingerprint=resolved["context_fingerprint"], tool_permissions=["READ_GITHUB", "READ_SUPABASE", "READ_GOOGLE_DRIVE"], executor_mode="GPT_NATIVE")
    resolved.update(schema=template["preflight_schema"], run_revision="E", execution_contract=contract, execution_contract_sha256=contract["contract_sha256"], resolver_backed_observation_packet_sha256=observation_packet_sha, resolver_backed_observation_packet_path=OBSERVATION_PACKET.relative_to(ROOT).as_posix(), source_ref_policy="RAW_E_MUST_USE_IMMUTABLE_GITHUB_REFS_TO_PREBOUND_COMMIT", current_page_authority="NOT_SUPPLIED_DO_NOT_INFER", pagination_precision_authority="DERIVED_NON_CANONICAL_ONLY", base_resolver="prepare_s26_native_golden_c.py", base_resolver_contract_rebound=True, raw_output_absent_at_preflight=True, reevaluation_with_existing_raw=raw_exists)
    rendered = json.dumps(resolved, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    OUT.write_text(rendered, encoding="utf-8")
    (EVIDENCE / "governed_context_receipt.json").write_text(json.dumps(resolved["governed_context_receipt"], ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (EVIDENCE / "obligation_manifest.json").write_text(json.dumps(resolved["obligation_manifest"], ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
