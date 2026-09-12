#!/usr/bin/env python3
"""Resolve immutable inputs into the pre-execution S26 Native Golden B contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from profile_execution_contract import build_execution_contract, canonical_json_sha256
from semantic_obligation_manifest import validate_obligation_manifest
from validate_profile_execution import sha256_text

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_TEMPLATE = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_002/obligation_template.json"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def resolve_profile_sources(refs: list[str]) -> tuple[list[dict[str, str]], str]:
    resolved = []
    for ref in refs:
        path = ROOT / ref
        if not path.is_file():
            raise SystemExit(f"BLOCK_PROFILE_SOURCE_MISSING:{ref}")
        content = path.read_text(encoding="utf-8")
        resolved.append({"ref": ref, "content_sha256": sha256_text(content)})
    resolved.sort(key=lambda item: item["ref"])
    return resolved, canonical_json_sha256(resolved)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    template = load_json(args.template)
    if template.get("schema") != "S26_NATIVE_GOLDEN_OBLIGATION_TEMPLATE_V1":
        raise SystemExit("BLOCK_TEMPLATE_SCHEMA_INVALID")
    if template.get("executor_mode") != "GPT_NATIVE":
        raise SystemExit("BLOCK_EXECUTOR_MODE_NOT_GPT_NATIVE")

    input_path = ROOT / template["input_path"]
    visual_path = ROOT / template["visual_artifact_ref_path"]
    card_path = ROOT / template["card_ref"]
    adapter_path = ROOT / template["adapter_ref"]
    for path, code in (
        (input_path, "INPUT"), (visual_path, "VISUAL_REF"),
        (card_path, "CARD"), (adapter_path, "ADAPTER"),
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

    profile_manifest, profile_sha = resolve_profile_sources(template["profile_sources"])
    card_sha = sha256_text(card_path.read_text(encoding="utf-8"))
    adapter_sha = sha256_text(adapter_path.read_text(encoding="utf-8"))
    visual_ref_sha = canonical_json_sha256(visual_ref)

    profile_obligation_ids = [
        item["obligation_id"] for item in template["obligations"]
        if item["authority"] == "PROFILE_CONTRACT"
    ]
    input_obligation_ids = [
        item["obligation_id"] for item in template["obligations"]
        if item["authority"] == "EXECUTION_INPUT"
    ]

    obligations = []
    for item in template["obligations"]:
        authority_id = "PROFILE-CONTRACT" if item["authority"] == "PROFILE_CONTRACT" else "EXECUTION-INPUT"
        normalized = {
            "obligation_id": item["obligation_id"],
            "rule": item["rule"],
            "check_type": item["check_type"],
            "evidence_pointer": item["evidence_pointer"],
            "authority_ids": [authority_id],
        }
        for key in ("expected", "forbidden", "expected_value", "question"):
            if key in item:
                normalized[key] = item[key]
        obligations.append(normalized)

    obligation_manifest = validate_obligation_manifest({
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": template["execution_id"],
        "profile_code": template["profile_code"],
        "profile_source_sha256": profile_sha,
        "input_sha256": input_sha,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profile-source-manifest:" + canonical_json_sha256(profile_manifest),
                "source_sha256": profile_sha,
                "required_obligation_ids": profile_obligation_ids,
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": template["input_path"],
                "source_sha256": input_sha,
                "required_obligation_ids": input_obligation_ids,
            },
        ],
        "obligations": obligations,
    })
    manifest_sha = canonical_json_sha256(obligation_manifest)

    authority_context = {
        "router_ref": template["router_ref"],
        "input_governance_ref": template["input_governance_ref"],
        "visual_artifact_ref": visual_ref,
        "visual_artifact_ref_sha256": visual_ref_sha,
        "profile_sources": profile_manifest,
        "profile_source_sha256": profile_sha,
        "card_ref": template["card_ref"],
        "card_sha256": card_sha,
        "adapter_ref": template["adapter_ref"],
        "adapter_sha256": adapter_sha,
        "input_sha256": input_sha,
        "obligation_manifest_sha256": manifest_sha,
    }
    context_fingerprint = canonical_json_sha256(authority_context)

    contract = build_execution_contract(
        run_id=template["execution_id"],
        profile_code=template["profile_code"],
        profile_version="resolved:" + profile_sha[:16],
        objective="Evaluate the frozen B2B-CARGA-001 screen under the native-first governed UI Architect runtime.",
        authorized_scope=[
            "screen:B2B-CARGA-001",
            "artifact_sha256:" + visual_ref["sha256"],
            "evidence:s26_native_golden_002",
        ],
        current_gate="S26-N08-GPT_NATIVE_GOLDEN_B",
        allowed_actions=["READ_INPUT", "EVALUATE_UI", "EMIT_FINDINGS", "MATERIALIZE_EVIDENCE"],
        forbidden_actions=[
            "MODIFY_PRODUCTION", "MERGE_MAIN", "ACQUIRE_MODEL_WEIGHTS",
            "MODIFY_SHELL", "SELF_AUTHORIZE_GOLDEN",
        ],
        required_checks=[
            "ROUTER", "INPUT_GOVERNANCE", "PROFILE_CONTRACT", "UI_ARCHITECT_VALIDATOR",
            "SEMANTIC_OBLIGATION_COVERAGE", "INDEPENDENT_QUALITY", "NO_MODEL_WEIGHT_ACQUISITION",
        ],
        required_evidence=[
            "router", "input_governance", "visual_artifact", "profile_execution",
            "ui_validator", "semantic_manifest", "independent_quality",
        ],
        closure_conditions=[
            "STRUCTURAL_PASS", "SEMANTIC_OBLIGATIONS_PASS", "INDEPENDENT_QUALITY_STRICT_PASS",
            "NO_MODEL_WEIGHT_ACQUISITION", "NO_P0_OPEN", "READBACK_PASS",
        ],
        input_governance_ref=template["input_governance_ref"],
        card_refs_and_hashes=[{"ref": template["card_ref"], "sha256": card_sha}],
        adapter_ref=f"{template['adapter_ref']}@sha256:{adapter_sha}",
        context_fingerprint=context_fingerprint,
        tool_permissions=["READ_GITHUB", "READ_SUPABASE", "READ_GOOGLE_DRIVE"],
        executor_mode="GPT_NATIVE",
    )

    result = {
        "schema": "S26_NATIVE_GOLDEN_PREFLIGHT_RESOLVED_V1",
        "verdict": "PASS",
        "execution_id": template["execution_id"],
        "template_ref": rel(args.template),
        "template_sha256": canonical_json_sha256(template),
        "input_sha256": input_sha,
        "visual_artifact_sha256": visual_ref["sha256"],
        "visual_artifact_ref_sha256": visual_ref_sha,
        "profile_source_manifest": profile_manifest,
        "profile_source_sha256": profile_sha,
        "card_sha256": card_sha,
        "adapter_sha256": adapter_sha,
        "context_fingerprint": context_fingerprint,
        "obligation_manifest": obligation_manifest,
        "obligation_manifest_sha256": manifest_sha,
        "execution_contract": contract,
        "execution_contract_sha256": contract["contract_sha256"],
        "checks": [
            "INPUT_PRESENT", "VISUAL_SHA_BOUND", "VISUAL_BYTE_PARITY_DECLARED",
            "PROFILE_SOURCES_RESOLVED", "CARD_RESOLVED", "ADAPTER_RESOLVED",
            "OBLIGATIONS_PREBOUND", "EXECUTION_CONTRACT_VALID",
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
