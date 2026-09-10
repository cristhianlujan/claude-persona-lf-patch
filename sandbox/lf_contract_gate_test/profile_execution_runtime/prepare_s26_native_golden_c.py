#!/usr/bin/env python3
"""Pre-bind S26 Native Golden C with same-run Card/Adapter receipts and native metrics policy."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from profile_execution_contract import build_execution_contract, canonical_json_sha256
from semantic_obligation_manifest import validate_obligation_manifest
from validate_profile_execution import sha256_text

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_003"
DEFAULT_TEMPLATE = EVIDENCE / "obligation_template.json"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def resolve_profile_sources(refs: list[str]) -> tuple[list[dict[str, str]], str]:
    resolved: list[dict[str, str]] = []
    for ref in refs:
        path = ROOT / ref
        if not path.is_file():
            raise SystemExit(f"BLOCK_PROFILE_SOURCE_MISSING:{ref}")
        resolved.append({"ref": ref, "content_sha256": sha256_text(path.read_text(encoding="utf-8"))})
    resolved.sort(key=lambda item: item["ref"])
    return resolved, canonical_json_sha256(resolved)


def extract_markdown_sections(content: str, section_names: list[str]) -> str:
    wanted = set(section_names)
    chunks: list[str] = []
    current_name: str | None = None
    current_lines: list[str] = []

    def flush() -> None:
        nonlocal current_name, current_lines
        if current_name in wanted:
            chunks.append("\n".join(current_lines).strip())
        current_name = None
        current_lines = []

    for line in content.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            flush()
            current_name = match.group(1)
            current_lines = [line]
        elif current_name is not None:
            current_lines.append(line)
    flush()

    found = {re.sub(r"^##\s+", "", chunk.splitlines()[0]).strip() for chunk in chunks if chunk}
    missing = sorted(wanted - found)
    if missing:
        raise SystemExit("BLOCK_CARD_JIT_SECTION_MISSING:" + ",".join(missing))
    ordered: list[str] = []
    for name in section_names:
        for chunk in chunks:
            heading = re.sub(r"^##\s+", "", chunk.splitlines()[0]).strip()
            if heading == name:
                ordered.append(chunk)
                break
    return "\n\n".join(ordered).strip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    template = load_json(args.template)
    if template.get("schema") != "S26_NATIVE_GOLDEN_C_TEMPLATE_V1":
        raise SystemExit("BLOCK_TEMPLATE_SCHEMA_INVALID")
    if template.get("executor_mode") != "GPT_NATIVE":
        raise SystemExit("BLOCK_EXECUTOR_MODE_NOT_GPT_NATIVE")

    execution_id = template["execution_id"]
    input_path = ROOT / template["input_path"]
    visual_path = ROOT / template["visual_artifact_ref_path"]
    input_governance_path = ROOT / template["input_governance_snapshot_path"]
    binding_path = ROOT / template["router_adapter_binding_snapshot_path"]
    metrics_path = ROOT / template["metrics_plan_path"]
    card_path = ROOT / template["card_ref"]
    adapter_path = ROOT / template["adapter_ref"]
    for path, code in (
        (input_path, "INPUT"), (visual_path, "VISUAL_REF"),
        (input_governance_path, "INPUT_GOVERNANCE_SNAPSHOT"), (binding_path, "ADAPTER_BINDING_SNAPSHOT"),
        (metrics_path, "METRICS_PLAN"), (card_path, "CARD"), (adapter_path, "ADAPTER"),
    ):
        if not path.is_file():
            raise SystemExit(f"BLOCK_{code}_MISSING:{rel(path)}")

    input_literal = input_path.read_text(encoding="utf-8")
    input_sha = sha256_text(input_literal)
    visual_ref = load_json(visual_path)
    if visual_ref.get("sha256") != "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287":
        raise SystemExit("BLOCK_VISUAL_SHA_UNEXPECTED")
    if visual_ref.get("drive_byte_parity") is not True:
        raise SystemExit("BLOCK_VISUAL_BYTE_PARITY_NOT_PROVEN")

    input_governance = load_json(input_governance_path)
    if input_governance.get("source_ref") != template["input_governance_ref"]:
        raise SystemExit("BLOCK_INPUT_GOVERNANCE_REF_MISMATCH")
    if input_governance.get("status") != "PASS":
        raise SystemExit("BLOCK_INPUT_GOVERNANCE_NOT_PASS")
    if input_governance.get("scope") != "B2B-CARGA-001":
        raise SystemExit("BLOCK_INPUT_GOVERNANCE_SCOPE_MISMATCH")
    if input_governance.get("invalidated_at") is not None:
        raise SystemExit("BLOCK_INPUT_GOVERNANCE_INVALIDATED")
    input_governance_sha = canonical_json_sha256(input_governance)

    binding = load_json(binding_path)
    required_binding = {
        "adapter_code": template["adapter_code"],
        "adapter_version": template["adapter_version"],
        "assurance_revision": template["adapter_assurance_revision"],
        "target_asset_code": template["adapter_target_ref"],
        "activation": "ROUTER_BOUND_ONLY",
        "runtime_enabled": True,
        "production_enabled": False,
        "single_model_call": True,
        "adapter_llm_call_policy": "NO_SECOND_LLM_CALL",
    }
    for key, expected in required_binding.items():
        if binding.get(key) != expected:
            raise SystemExit(f"BLOCK_ADAPTER_BINDING_{key.upper()}_MISMATCH")
    binding_sha = canonical_json_sha256(binding)

    metrics = load_json(metrics_path)
    if metrics.get("execution_id") != execution_id:
        raise SystemExit("BLOCK_METRICS_EXECUTION_ID_MISMATCH")
    if metrics.get("token_usage", {}).get("default_for_chatgpt_native_without_exact_telemetry") != "NOT_OBSERVED":
        raise SystemExit("BLOCK_TOKEN_POLICY_INVALID")
    metrics_sha = canonical_json_sha256(metrics)

    profile_manifest, profile_sha = resolve_profile_sources(template["profile_sources"])

    card_content = card_path.read_text(encoding="utf-8")
    if "Card ID: CARD_MARKETPLACE_LF_DECISIONES_PRODUCTO_EXPERIENCIA_v0.1_CANDIDATO" not in card_content:
        raise SystemExit("BLOCK_CARD_ID_VERSION_MISMATCH")
    card_sha = sha256_text(card_content)
    jit_card = extract_markdown_sections(card_content, template["card_selected_sections"])
    if len(jit_card) > int(template["card_budget_chars"]):
        raise SystemExit("BLOCK_CARD_JIT_BUDGET_EXCEEDED")

    adapter_content = adapter_path.read_text(encoding="utf-8")
    adapter_sha = sha256_text(adapter_content)
    max_adapter_chars = int(binding.get("runtime_capsule_max_chars", 0))
    if max_adapter_chars <= 0 or len(adapter_content) > max_adapter_chars:
        raise SystemExit("BLOCK_ADAPTER_CAPSULE_BUDGET_EXCEEDED")

    card_receipt = {
        "card_ref": template["card_ref"],
        "card_version": template["card_version"],
        "source_ref": template["card_ref"],
        "content_sha256": card_sha,
        "selected_sections": template["card_selected_sections"],
        "budget_chars": template["card_budget_chars"],
        "request_id": execution_id,
    }
    adapter_receipt = {
        "adapter_code": template["adapter_code"],
        "adapter_version": template["adapter_version"],
        "target_ref": template["adapter_target_ref"],
        "binding_ref": template["router_adapter_binding_snapshot_path"],
        "assurance_revision": template["adapter_assurance_revision"],
        "request_id": execution_id,
    }
    structural_pack = {
        "visual_artifact_sha256": visual_ref["sha256"],
        "input_governance_snapshot_sha256": input_governance_sha,
        "profile_source_sha256": profile_sha,
        "input_sha256": input_sha,
    }
    structural_pack_sha = canonical_json_sha256(structural_pack)
    governed_context_receipt = {
        "schema": "lf-governed-context-receipt/v1",
        "request_id": execution_id,
        "profile_code": template["profile_code"],
        "card_receipts": [card_receipt],
        "adapter_receipts": [adapter_receipt],
    }
    governed_context_receipt["context_fingerprint"] = canonical_json_sha256({
        "request_id": execution_id,
        "cards": [card_receipt],
        "adapters": [adapter_receipt],
        "structural_pack_sha256": structural_pack_sha,
    })
    governed_context_receipt_sha = canonical_json_sha256(governed_context_receipt)

    profile_obligation_ids = [item["obligation_id"] for item in template["obligations"] if item["authority"] == "PROFILE_CONTRACT"]
    input_obligation_ids = [item["obligation_id"] for item in template["obligations"] if item["authority"] == "EXECUTION_INPUT"]
    obligations: list[dict[str, Any]] = []
    for item in template["obligations"]:
        authority_id = "PROFILE-CONTRACT" if item["authority"] == "PROFILE_CONTRACT" else "EXECUTION-INPUT"
        normalized: dict[str, Any] = {
            "obligation_id": item["obligation_id"], "rule": item["rule"],
            "check_type": item["check_type"], "evidence_pointer": item["evidence_pointer"],
            "authority_ids": [authority_id],
        }
        for key in ("expected", "forbidden", "expected_value", "question"):
            if key in item:
                normalized[key] = item[key]
        obligations.append(normalized)

    obligation_manifest = validate_obligation_manifest({
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": execution_id,
        "profile_code": template["profile_code"],
        "profile_source_sha256": profile_sha,
        "input_sha256": input_sha,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT", "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profile-source-manifest:" + canonical_json_sha256(profile_manifest),
                "source_sha256": profile_sha, "required_obligation_ids": profile_obligation_ids,
            },
            {
                "authority_id": "EXECUTION-INPUT", "authority_type": "EXECUTION_INPUT",
                "source_ref": template["input_path"], "source_sha256": input_sha,
                "required_obligation_ids": input_obligation_ids,
            },
        ],
        "obligations": obligations,
    })
    manifest_sha = canonical_json_sha256(obligation_manifest)

    context_bindings = {
        "router_ref": template["router_ref"],
        "input_governance_snapshot_sha256": input_governance_sha,
        "visual_artifact_sha256": visual_ref["sha256"],
        "profile_source_sha256": profile_sha,
        "card_source_sha256": card_sha,
        "adapter_source_sha256": adapter_sha,
        "adapter_binding_snapshot_sha256": binding_sha,
        "governed_context_receipt_sha256": governed_context_receipt_sha,
        "metrics_plan_sha256": metrics_sha,
        "input_sha256": input_sha,
        "obligation_manifest_sha256": manifest_sha,
    }
    context_fingerprint = canonical_json_sha256(context_bindings)

    contract = build_execution_contract(
        run_id=execution_id,
        profile_code=template["profile_code"],
        profile_version="resolved:" + profile_sha[:16],
        objective="Execute a fresh Golden-eligibility UI Architect run with same-run governed Card/Adapter context and native metrics.",
        authorized_scope=[
            "screen:B2B-CARGA-001", "artifact_sha256:" + visual_ref["sha256"],
            "evidence:s26_native_golden_003",
        ],
        current_gate="S26-N08C-GPT_NATIVE_GOLDEN_ELIGIBILITY",
        allowed_actions=["READ_INPUT", "CONSUME_GOVERNED_CONTEXT", "EVALUATE_UI", "EMIT_FINDINGS", "MATERIALIZE_EVIDENCE"],
        forbidden_actions=["MODIFY_PRODUCTION", "MERGE_MAIN", "ACQUIRE_MODEL_WEIGHTS", "MODIFY_SHELL", "SELF_AUTHORIZE_GOLDEN", "SECOND_ADAPTER_LLM_CALL"],
        required_checks=[
            "ROUTER", "INPUT_GOVERNANCE", "PROFILE_CONTRACT", "CARD_RECEIPT_SAME_RUN",
            "ADAPTER_RECEIPT_SAME_RUN", "UI_ARCHITECT_VALIDATOR", "DEPTH_GATE",
            "SEMANTIC_OBLIGATION_COVERAGE", "INDEPENDENT_QUALITY", "LATENCY_OBSERVABLE",
            "TOKEN_USAGE_STATUS", "TRACEABILITY", "NO_MODEL_WEIGHT_ACQUISITION",
        ],
        required_evidence=[
            "router", "input_governance", "visual_artifact", "governed_context_receipt",
            "card_receipt", "adapter_receipt", "profile_execution", "ui_validator", "depth_gate",
            "semantic_manifest", "independent_quality", "native_metrics", "traceability",
        ],
        closure_conditions=[
            "STRUCTURAL_PASS", "GOVERNED_CONTEXT_PASS", "DEPTH_PASS", "SEMANTIC_OBLIGATIONS_PASS",
            "INDEPENDENT_QUALITY_STRICT_PASS", "LATENCY_OBSERVABLE_PASS", "TOKEN_USAGE_STATUS_PASS",
            "TRACEABILITY_PASS", "NO_MODEL_WEIGHT_ACQUISITION", "NO_P0_OPEN", "READBACK_PASS",
        ],
        input_governance_ref=template["input_governance_ref"],
        card_refs_and_hashes=[{"ref": template["card_ref"], "sha256": card_sha}],
        adapter_ref=f"{template['adapter_ref']}@sha256:{adapter_sha};binding_sha256:{binding_sha}",
        context_fingerprint=context_fingerprint,
        tool_permissions=["READ_GITHUB", "READ_SUPABASE", "READ_GOOGLE_DRIVE"],
        executor_mode="GPT_NATIVE",
    )

    result = {
        "schema": "S26_NATIVE_GOLDEN_C_PREFLIGHT_RESOLVED_V1",
        "verdict": "PASS",
        "execution_id": execution_id,
        "template_sha256": canonical_json_sha256(template),
        "input_sha256": input_sha,
        "visual_artifact_sha256": visual_ref["sha256"],
        "input_governance_snapshot_sha256": input_governance_sha,
        "adapter_binding_snapshot_sha256": binding_sha,
        "metrics_plan_sha256": metrics_sha,
        "profile_source_manifest": profile_manifest,
        "profile_source_sha256": profile_sha,
        "card_source_sha256": card_sha,
        "card_jit_selected_sections": template["card_selected_sections"],
        "card_jit_chars": len(jit_card),
        "card_jit_sha256": sha256_text(jit_card),
        "adapter_source_sha256": adapter_sha,
        "adapter_capsule_chars": len(adapter_content),
        "structural_pack_sha256": structural_pack_sha,
        "governed_context_receipt": governed_context_receipt,
        "governed_context_receipt_sha256": governed_context_receipt_sha,
        "context_fingerprint": context_fingerprint,
        "obligation_manifest": obligation_manifest,
        "obligation_manifest_sha256": manifest_sha,
        "execution_contract": contract,
        "execution_contract_sha256": contract["contract_sha256"],
        "native_metrics_prebound": {
            "depth_minimum_score": metrics["depth"]["minimum_score"],
            "latency_metric": metrics["latency_observable"]["metric"],
            "token_usage_default": metrics["token_usage"]["default_for_chatgpt_native_without_exact_telemetry"],
            "execution_started_at": metrics["execution_started_at"],
        },
        "checks": [
            "INPUT_PRESENT", "VISUAL_SHA_BOUND", "INPUT_GOVERNANCE_PASS_CURRENT",
            "PROFILE_SOURCES_RESOLVED", "CARD_JIT_RECEIPT_SAME_RUN", "ADAPTER_RECEIPT_SAME_RUN",
            "ADAPTER_SINGLE_CALL_POLICY_BOUND", "NATIVE_METRICS_PREBOUND", "OBLIGATIONS_PREBOUND",
            "EXECUTION_CONTRACT_VALID",
        ],
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
