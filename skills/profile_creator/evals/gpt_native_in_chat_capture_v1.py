#!/usr/bin/env python3
"""GPT-native in-chat RAW capture: source binding, never model dispatch or attestation.

An authoring conversation may supply real model-authored RAW. The captured object
is deliberately NOT PROFILE_RUNTIME_RESPONSE_V1 or PROFILE_EXECUTION_RECEIPT_V1.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA = "LF_GPT_NATIVE_IN_CHAT_CAPTURE_V1"


def _sha(value: Any) -> str:
    data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _text_sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def _at_pointer(raw: Any, pointer: str) -> Any:
    _require(pointer.startswith("/"), "OBLIGATION_POINTER_INVALID")
    value = raw
    for token in pointer[1:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        if isinstance(value, dict) and token in value:
            value = value[token]
        elif isinstance(value, list) and token.isdigit() and int(token) < len(value):
            value = value[int(token)]
        else:
            raise ValueError("EXACT_OBLIGATION_POINTER_MISSING")
    return value


def capture(frozen: dict, raw_output: dict, *, root: Path, profile_slug: str) -> dict:
    """Freeze current ChatGPT-chat RAW without pretending to invoke a model."""
    _require(frozen.get("run_id") and isinstance(raw_output, dict) and bool(raw_output), "CAPTURE_INPUT_INVALID")
    contract = frozen["execution_contract"]
    _require(contract.get("executor_mode") == "GPT_NATIVE", "NON_GPT_NATIVE_EXECUTOR_FORBIDDEN")
    _require(contract.get("run_id") == frozen["run_id"], "EXECUTION_ID_MISMATCH")
    _require(contract.get("profile_code") and profile_slug, "PROFILE_IDENTITY_MISSING")
    _require(_sha({k: v for k, v in contract.items() if k != "contract_sha256"})
             == contract.get("contract_sha256"), "EXECUTION_CONTRACT_SHA_MISMATCH")
    _require(_text_sha(frozen["input_literal"]) == frozen.get("input_sha256"), "INPUT_SHA_MISMATCH")
    source_manifest = frozen["profile_source_manifest"]
    sources = []
    root = root.resolve()
    for item in source_manifest:
        path = (root / item["ref"]).resolve()
        _require(path.is_relative_to(root) and path.is_file(), "PROFILE_SOURCE_UNAVAILABLE")
        content = path.read_text(encoding="utf-8")
        _require(_text_sha(content) == item["content_sha256"], "PROFILE_SOURCE_DRIFT")
        sources.append({"ref": item["ref"], "content": content})
    _require(_sha(source_manifest) == frozen["profile_source_sha256"], "PROFILE_SOURCE_MANIFEST_SHA_MISMATCH")
    obligations = frozen["scoped_semantic_obligation_manifest"]
    _require(obligations.get("execution_id") == frozen["run_id"], "OBLIGATION_RUN_MISMATCH")
    _require(obligations.get("input_sha256") == frozen["input_sha256"], "OBLIGATION_INPUT_MISMATCH")
    _require(obligations.get("profile_source_sha256") == frozen["profile_source_sha256"], "OBLIGATION_SOURCE_MISMATCH")
    _require(_sha(obligations) == frozen["scoped_semantic_obligation_manifest_sha256"],
             "OBLIGATION_MANIFEST_SHA_MISMATCH")
    for obligation in obligations.get("obligations", []):
        if obligation.get("check_type") == "EXACT_VALUE":
            _require(_at_pointer(raw_output, obligation["evidence_pointer"]) ==
                     obligation["expected_value"], "DETERMINISTIC_OBLIGATION_FAILED:" + obligation["obligation_id"])
    _require(not any(k in raw_output for k in
            ("runtime_attestation", "provider_signature", "independent_semantic_review_receipt")),
            "RAW_FORGED_ATTESTATION_FIELD")
    request = {
        "request_type": "PROFILE_RUNTIME_REQUEST_V1", "operation_code": "EJECUCION_PERFIL_LF",
        "execution_id": frozen["run_id"], "profile_code": contract["profile_code"],
        "profile_slug": profile_slug, "profile_sources": sources,
        "profile_source_refs": [s["ref"] for s in sources],
        "profile_source_sha256": frozen["profile_source_sha256"],
        "input_literal": frozen["input_literal"], "input_sha256": frozen["input_sha256"],
        "obligation_manifest_sha256": frozen["scoped_semantic_obligation_manifest_sha256"],
        "executor_mode": "GPT_NATIVE", "execution_contract_sha256": contract["contract_sha256"],
        "execution_contract": contract,
    }
    request_sha = _sha(request)
    captured = {
        "schema": SCHEMA, "producer_mode": "GPT_NATIVE",
        "producer_transport": "CHAT_SESSION_AUTHORING",
        "capture_status": "GPT_CHAT_SOURCE_READBACK_BOUND_UNATTESTED",
        "run_id": frozen["run_id"], "profile_code": contract["profile_code"],
        "profile_source_sha256": frozen["profile_source_sha256"],
        "input_sha256": frozen["input_sha256"],
        "execution_contract_sha256": contract["contract_sha256"],
        "request_sha256": request_sha,
        "raw_output": raw_output, "raw_output_sha256": _sha(raw_output),
        "model_author_claim": "GPT_NATIVE_CURRENT_CHAT_UNVERIFIED_BY_PROVIDER",
        "runtime_provider_attested": False, "independent_semantic_review": "NOT_EXECUTED",
        "runtime_execution_receipt": None,
        "downstream_authorized": False, "benchmark_admitted": False,
        "production_activation": False, "cutover_eligible": False,
    }
    captured["capture_sha256"] = _sha(captured)
    return captured


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", type=Path, required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--raw", type=Path, required=True)
    p.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--profile-slug", required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    runs = json.loads(args.bundle.read_text(encoding="utf-8"))["runs"]
    exact = [r for r in runs if r["run_id"] == args.run_id]
    _require(len(exact) == 1, "FROZEN_RUN_NOT_UNIQUE")
    raw = json.loads(args.raw.read_text(encoding="utf-8"))
    output = capture(exact[0], raw, root=args.root, profile_slug=args.profile_slug)
    args.output.write_text(json.dumps(output, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": output["capture_status"], "request_sha256": output["request_sha256"],
                      "capture_sha256": output["capture_sha256"], "runtime_provider_attested": False,
                      "downstream_authorized": False}, sort_keys=True))


if __name__ == "__main__":
    main()
