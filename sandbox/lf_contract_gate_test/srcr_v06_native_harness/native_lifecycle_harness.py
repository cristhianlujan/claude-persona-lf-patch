#!/usr/bin/env python3
"""SRCR V0.6 native evaluation harness (sandbox only).

This harness is evaluation-only. It does not route production traffic, activate
runtime, call a model, write Supabase, or issue canonical quality. It prepares a
GPT_NATIVE execution contract, validates a resolver-bound investigation trace,
and runs the existing SRCR deterministic/semantic pre-quality floors over a
frozen candidate plus an externally assembled evidence manifest.

It reuses the generic PROFILE_EXECUTION_CONTRACT_V1 and the existing LF
evidence-resolver identities instead of creating a second runtime or resolver.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parents[3]
PROFILE_ROOT = ROOT / "profiles" / "systemic_root_cause_repair_lf"

EXECUTION_CONTRACT_PATH = (
    ROOT
    / "sandbox"
    / "lf_contract_gate_test"
    / "profile_execution_runtime"
    / "profile_execution_contract.py"
)
RUNTIME_VALIDATE_PATH = PROFILE_ROOT / "validators" / "runtime_validate.py"
SEMANTIC_UTILITY_PATH = PROFILE_ROOT / "validators" / "runtime_semantic_utility.py"
OUTPUT_SCHEMA_PATH = PROFILE_ROOT / "schemas" / "output.schema.json"
RESEARCH_TRACE_PATH = PROFILE_ROOT / "validators" / "research_trace.py"

PROFILE_CODE = "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"
PROFILE_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6"
EXECUTOR_MODE = "GPT_NATIVE"
REQUIRED_TOOL_PERMISSIONS = ("READ_GITHUB", "READ_SUPABASE")
FORBIDDEN_WRITE_PREFIXES = ("WRITE_", "MUTATE_", "DELETE_", "MERGE_", "PUBLISH_", "DEPLOY_")

EVIDENCE_RESOLVERS = {
    "GITHUB": {
        "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
        "provider": "GITHUB",
    },
    "SUPABASE": {
        "resolver_id": "LF_SUPABASE_READBACK_V1",
        "provider": "SUPABASE",
    },
}

TRACE_REQUIRED_FIELDS = {
    "sequence",
    "tool_permission",
    "resolver_id",
    "provider",
    "query_locator",
    "request_digest",
    "result_digest",
    "observed_at",
    "evidence_id",
    "consumer",
}


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"MODULE_LOAD_FAILED:{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


execution_contract = _load("srcr_v06_execution_contract", EXECUTION_CONTRACT_PATH)
runtime_validate = _load("srcr_v06_runtime_validate", RUNTIME_VALIDATE_PATH)
runtime_semantic_utility = _load("srcr_v06_runtime_semantic_utility", SEMANTIC_UTILITY_PATH)
research_trace = _load("srcr_v06_research_trace", RESEARCH_TRACE_PATH)
output_schema = json.loads(OUTPUT_SCHEMA_PATH.read_text(encoding="utf-8"))
schema_validator = Draft7Validator(output_schema)


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _sha_ok(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    raw = value.removeprefix("sha256:")
    return len(raw) == 64 and all(ch in "0123456789abcdef" for ch in raw)


def build_native_execution_contract(
    *,
    run_id: str,
    objective: str,
    context_fingerprint: str,
    profile_version: str,
) -> dict[str, Any]:
    contract = execution_contract.build_execution_contract(
        run_id=run_id,
        profile_code=PROFILE_CODE,
        profile_version=profile_version,
        objective=objective,
        authorized_scope=["READ_ONLY_DEEP_SYSTEMIC_AUDIT"],
        current_gate="SRCR_V06_NATIVE_EVALUATION",
        allowed_actions=[
            "READ_INPUT",
            "READ_GITHUB",
            "READ_SUPABASE",
            "EVALUATE_SYSTEMIC_CAUSALITY",
            "EMIT_FROZEN_CANDIDATE",
            "EMIT_INVESTIGATION_TRACE",
        ],
        forbidden_actions=[
            "MODIFY_PRODUCTION",
            "WRITE_SUPABASE",
            "WRITE_GITHUB",
            "MERGE_MAIN",
            "ACTIVATE_RUNTIME",
            "PUBLISH_PROFILE",
            "SELF_AUTHORIZE_QUALITY",
        ],
        required_checks=[
            "PROFILE_SOURCE_EXACT",
            "READ_ONLY_AUTHORITY_TRAVERSAL",
            "QUERY_TRACE_COMPLETE",
            "EXTERNAL_EVIDENCE_MANIFEST",
            "OUTPUT_SCHEMA",
            "CANONICAL_RUNTIME_VALIDATE",
            "CANONICAL_SEMANTIC_UTILITY",
            "INDEPENDENT_QUALITY_PENDING",
        ],
        required_evidence=[
            "case_packet",
            "profile_source",
            "investigation_trace",
            "evidence_manifest",
            "frozen_candidate",
        ],
        closure_conditions=[
            "CANDIDATE_FROZEN",
            "SCHEMA_PASS",
            "RUNTIME_VALIDATE_PASS",
            "SEMANTIC_UTILITY_PASS",
            "INDEPENDENT_QUALITY_NOT_SELF_ISSUED",
        ],
        input_governance_ref="supabase://public/lf_eventos/CASE_PACKET",
        card_refs_and_hashes=[],
        adapter_ref="chatgpt-native-current-context-v1",
        card_resolution={
            "mode": "GENERIC_SAFE",
            "critical_authority_missing": False,
            "unresolved_capabilities": [],
            "core_policy_ref": "profiles/systemic_root_cause_repair_lf/contracts/main_contract.md",
            "core_policy_sha256": hashlib.sha256(
                (PROFILE_ROOT / "contracts" / "main_contract.md").read_bytes()
            ).hexdigest(),
            "fallback_reason": "SRCR evaluation has no Card dependency; use the profile contract as the bounded generic-safe authority.",
        },
        context_fingerprint=context_fingerprint,
        tool_permissions=list(REQUIRED_TOOL_PERMISSIONS),
        executor_mode=EXECUTOR_MODE,
    )
    errors = execution_contract.validate_execution_contract(
        contract,
        expected_profile_code=PROFILE_CODE,
        expected_executor_mode=EXECUTOR_MODE,
    )
    if errors:
        raise RuntimeError("NATIVE_EXECUTION_CONTRACT_INVALID:" + ",".join(errors))
    return contract


def validate_query_trace(trace: Any) -> list[str]:
    return research_trace.validate_query_trace(trace)


def validate_manifest_trace_binding(manifest: Any, trace: Any) -> list[str]:
    return research_trace.validate_manifest_trace_binding(manifest, trace)


def post_producer_validation(
    *,
    candidate: Any,
    evidence_manifest: Any,
    query_trace: Any,
) -> dict[str, Any]:
    trace_errors = validate_query_trace(query_trace)
    binding_errors = validate_manifest_trace_binding(evidence_manifest, query_trace)

    schema_errors = sorted(
        {
            f"{'.'.join(str(x) for x in err.absolute_path)}:{err.message}"
            for err in schema_validator.iter_errors(candidate)
        }
    )
    if schema_errors:
        return {
            "status": "FAIL",
            "first_failed_stage": "OUTPUT_SCHEMA",
            "trace_errors": trace_errors,
            "manifest_trace_binding_errors": binding_errors,
            "schema_errors": schema_errors,
            "runtime_validate": "NOT_REACHED",
            "semantic_utility": "NOT_REACHED",
            "independent_quality": "NOT_EXECUTED",
        }

    deterministic = runtime_validate.validate(candidate, evidence_manifest)
    if deterministic.get("valid") is not True:
        return {
            "status": "FAIL",
            "first_failed_stage": "RUNTIME_VALIDATE",
            "trace_errors": trace_errors,
            "manifest_trace_binding_errors": binding_errors,
            "schema_errors": [],
            "runtime_validate": deterministic,
            "semantic_utility": "NOT_REACHED",
            "independent_quality": "NOT_EXECUTED",
        }

    semantic = runtime_semantic_utility.evaluate(
        candidate,
        deterministic,
        evidence_manifest,
    )
    semantic_status = semantic.get("status")
    floors_clean = (
        not trace_errors
        and not binding_errors
        and deterministic.get("valid") is True
        and semantic_status == "PASS"
    )
    return {
        "status": "PASS_PRE_QUALITY" if floors_clean else "FAIL",
        "first_failed_stage": None if floors_clean else "SEMANTIC_UTILITY_OR_TRACE",
        "trace_errors": trace_errors,
        "manifest_trace_binding_errors": binding_errors,
        "schema_errors": [],
        "runtime_validate": deterministic,
        "semantic_utility": semantic,
        "independent_quality": "PENDING_INDEPENDENT_REVIEW" if floors_clean else "NOT_EXECUTED",
        "canonical_quality_accepted": False,
    }



def materialize_prequality_freeze(
    *,
    candidate: Any,
    evidence_manifest: Any,
    query_trace: Any,
) -> dict[str, Any]:
    validation = post_producer_validation(
        candidate=candidate,
        evidence_manifest=evidence_manifest,
        query_trace=query_trace,
    )
    if validation.get("status") != "PASS_PRE_QUALITY":
        raise RuntimeError(
            "PREFREEZE_VALIDATION_NOT_CLEAN:"
            + str(validation.get("first_failed_stage") or "UNKNOWN")
        )
    if validation.get("schema_errors"):
        raise RuntimeError("PREFREEZE_SCHEMA_INVALID")
    deterministic = validation.get("runtime_validate")
    semantic = validation.get("semantic_utility")
    if not isinstance(deterministic, dict) or deterministic.get("status") != "PASS":
        raise RuntimeError("PREFREEZE_DETERMINISTIC_NOT_PASS")
    if not isinstance(semantic, dict) or semantic.get("status") != "PASS":
        raise RuntimeError("PREFREEZE_UTILITY_NOT_PASS")
    raw = json.dumps(
        candidate, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    manifest_digest = (
        evidence_manifest.get("bundle_digest")
        if isinstance(evidence_manifest, dict)
        else None
    )
    return {
        "schema": "SRCR_PREQUALITY_FREEZE_V1",
        "receipt_kind": "NON_ACCEPTANCE_PRE_QUALITY_FREEZE",
        "candidate_sha256": hashlib.sha256(raw).hexdigest(),
        "candidate_bytes": len(raw),
        "manifest_bundle_digest": manifest_digest,
        "trace_count": len(query_trace) if isinstance(query_trace, list) else 0,
        "pre_quality_status": validation["status"],
        "schema_error_count": 0,
        "deterministic_status": deterministic["status"],
        "semantic_utility_status": semantic["status"],
        "independent_quality": validation.get("independent_quality"),
        "canonical_quality_accepted": False,
    }

def build_native_handoff(
    *,
    run_id: str,
    case_packet: Any,
    profile_source_sha256: str,
) -> dict[str, Any]:
    if not isinstance(case_packet, dict):
        raise RuntimeError("CASE_PACKET_NOT_OBJECT")
    if not _sha_ok(profile_source_sha256):
        raise RuntimeError("PROFILE_SOURCE_SHA256_INVALID")

    context = {
        "case_packet": case_packet,
        "profile_code": PROFILE_CODE,
        "profile_pack_id": PROFILE_PACK_ID,
        "profile_source_sha256": profile_source_sha256,
        "evidence_resolvers": EVIDENCE_RESOLVERS,
    }
    context_fingerprint = canonical_sha256(context)
    contract = build_native_execution_contract(
        run_id=run_id,
        objective=str(case_packet.get("user_request") or "SRCR V0.6 native evaluation"),
        context_fingerprint=context_fingerprint,
        profile_version=profile_source_sha256,
    )
    return {
        "schema": "SRCR_V06_NATIVE_EVALUATION_HANDOFF_V1",
        "run_id": run_id,
        "profile_code": PROFILE_CODE,
        "profile_pack_id": PROFILE_PACK_ID,
        "executor_mode": EXECUTOR_MODE,
        "tool_permissions": list(REQUIRED_TOOL_PERMISSIONS),
        "evidence_resolvers": EVIDENCE_RESOLVERS,
        "case_packet": case_packet,
        "profile_source_sha256": profile_source_sha256,
        "context_fingerprint": context_fingerprint,
        "execution_contract": contract,
        "producer_requirements": {
            "oracle_access_before_freeze": False,
            "production_mutation": False,
            "runtime_activation": False,
            "query_trace_required": True,
            "external_evidence_manifest_required": True,
            "candidate_self_issued_quality_receipt_forbidden": True,
        },
        "post_producer_pipeline": [
            "OUTPUT_SCHEMA",
            "RUNTIME_VALIDATE_WITH_EXTERNAL_MANIFEST",
            "RUNTIME_SEMANTIC_UTILITY_WITH_EXTERNAL_MANIFEST",
            "INDEPENDENT_SEMANTIC_JUDGE",
            "QUALITY_RECEIPT_VALIDATION",
        ],
    }


def _read_json(path: str) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    p_pre = sub.add_parser("preflight")
    p_pre.add_argument("--run-id", required=True)
    p_pre.add_argument("--case-packet", required=True)
    p_pre.add_argument("--profile-source-sha256", required=True)

    p_post = sub.add_parser("post")
    p_post.add_argument("--candidate", required=True)
    p_post.add_argument("--manifest", required=True)
    p_post.add_argument("--trace", required=True)

    p_freeze = sub.add_parser("freeze")
    p_freeze.add_argument("--candidate", required=True)
    p_freeze.add_argument("--manifest", required=True)
    p_freeze.add_argument("--trace", required=True)

    args = parser.parse_args()
    if args.command == "preflight":
        payload = build_native_handoff(
            run_id=args.run_id,
            case_packet=_read_json(args.case_packet),
            profile_source_sha256=args.profile_source_sha256,
        )
    elif args.command == "post":
        payload = post_producer_validation(
            candidate=_read_json(args.candidate),
            evidence_manifest=_read_json(args.manifest),
            query_trace=_read_json(args.trace),
        )
    else:
        payload = materialize_prequality_freeze(
            candidate=_read_json(args.candidate),
            evidence_manifest=_read_json(args.manifest),
            query_trace=_read_json(args.trace),
        )

    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if payload.get("status") not in {"FAIL"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
