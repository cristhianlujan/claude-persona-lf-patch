#!/usr/bin/env python3
"""S26 Cloudflare Workers AI bounded capability benchmark.

Uses the exact pinned S26 focused UI task/schema/gates. Sandbox evidence only:
no Worker deployment, routing, promotion, production mutation, retry or paid fallback.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

MODEL = "@cf/mistralai/mistral-small-3.1-24b-instruct"
MAX_OUTPUT_TOKENS = 256
REQUEST_TIMEOUT_SECONDS = 120
EXPECTED_AUTHORITY_REF = "fcc2b0d57e36a31c26f38acc2510b193aac988c8"


def load_authority_module(authority_root: Path):
    path = authority_root / "sandbox" / "lf_contract_gate_test" / "profile_execution_runtime" / "run_s26_zero_cost_primary_candidate.py"
    if not path.is_file():
        raise RuntimeError(f"S26_AUTHORITY_MODULE_MISSING:{path}")
    spec = importlib.util.spec_from_file_location("s26_authority_benchmark", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("S26_AUTHORITY_MODULE_IMPORT_SPEC_FAILED")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def diagnostic_shape(value: Any) -> Any:
    if isinstance(value, dict):
        return {"keys": sorted(value.keys())}
    if isinstance(value, list):
        return {"type": "list", "length": len(value)}
    if isinstance(value, str):
        return {"type": "str", "length": len(value), "nonempty": bool(value)}
    return {"type": type(value).__name__, "nonempty": bool(value)}


def extract_content(envelope: dict[str, Any]) -> tuple[str, str, dict[str, Any]]:
    root: Any = envelope.get("result") if isinstance(envelope.get("result"), dict) else envelope
    if not isinstance(root, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID")
    response = root.get("response")
    if isinstance(response, dict) and response:
        raw = json.dumps(response, ensure_ascii=False, sort_keys=True)
    elif isinstance(response, str) and response.strip():
        raw = response.strip()
    else:
        raise RuntimeError("CLOUDFLARE_RESPONSE_EMPTY:" + json.dumps({"envelope": diagnostic_shape(envelope), "result": diagnostic_shape(root)}, sort_keys=True))
    usage = root.get("usage")
    return raw, str(root.get("finish_reason") or "stop"), usage if isinstance(usage, dict) else {}


def write_failure_evidence(out_path: Path, *, reason: str, elapsed_s: float, envelope: Any) -> None:
    payload = {
        "scope": "S26_CLOUDFLARE_SANDBOX_CAPABILITY_ONLY_NOT_PROMOTION",
        "provider": "cloudflare_workers_ai_native_rest_guided_json",
        "model": MODEL,
        "inference_requests": 1,
        "retries": 0,
        "elapsed_s": elapsed_s,
        "status": "BLOCK",
        "reason": reason,
        "response_shape": diagnostic_shape(envelope),
        "production_mutation": False,
        "worker_deployed": False,
        "routing_changed": False,
        "promotion_authorized": False,
        "paid_fallback_used": False,
    }
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    account_id = os.getenv("CLOUDFLARE_ACCOUNT_ID", "").strip()
    api_token = os.getenv("CLOUDFLARE_AI_CANARY_TOKEN", "").strip()
    authority_root_raw = os.getenv("S26_AUTHORITY_ROOT", "").strip()
    authority_ref = os.getenv("S26_AUTHORITY_REF", "").strip()
    out_path = Path(os.getenv("S26_CLOUDFLARE_RESULT_PATH", "s26-cloudflare-benchmark-result.json"))

    if not account_id or not api_token:
        print("BLOCK S26_CLOUDFLARE_REQUIRED_SECRET_MISSING")
        return 2
    if not authority_root_raw:
        print("BLOCK S26_AUTHORITY_ROOT_MISSING")
        return 2
    if authority_ref != EXPECTED_AUTHORITY_REF:
        print(f"BLOCK S26_AUTHORITY_REF_MISMATCH expected={EXPECTED_AUTHORITY_REF} observed={authority_ref}")
        return 2

    authority = load_authority_module(Path(authority_root_raw).resolve())
    repository = authority.RepositoryBindings(authority.REPO_ROOT, max_prompt_chars=120_000)
    gates = authority.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = authority.governed_generation_schema(
        schema_binding.payload, profile_slug="ui_architect", schema_mode="UI_FOCUSED_DECISION"
    )

    payload = {
        "messages": [
            {"role": "system", "content": authority.build_system_prompt()},
            {"role": "user", "content": authority.TASK},
        ],
        "guided_json": generation_schema,
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_OUTPUT_TOKENS,
    }
    url = "https://api.cloudflare.com/client/v4/accounts/" + account_id + "/ai/run/" + MODEL
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_token}", "Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )

    started = time.monotonic()
    envelope: Any = None
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            envelope = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        elapsed_s = round(time.monotonic() - started, 3)
        detail = exc.read().decode("utf-8", errors="replace")[-1600:]
        reason = f"S26_CLOUDFLARE_HTTP_ERROR status={exc.code} detail={detail.replace(chr(10), ' ')}"
        write_failure_evidence(out_path, reason=reason, elapsed_s=elapsed_s, envelope={"http_status": exc.code})
        print("BLOCK " + reason)
        return 3
    except Exception as exc:
        elapsed_s = round(time.monotonic() - started, 3)
        reason = f"S26_CLOUDFLARE_TRANSPORT type={type(exc).__name__}"
        write_failure_evidence(out_path, reason=reason, elapsed_s=elapsed_s, envelope={})
        print("BLOCK " + reason)
        return 3

    elapsed_s = round(time.monotonic() - started, 3)
    try:
        raw, finish_reason, usage = extract_content(envelope)
    except RuntimeError as exc:
        reason = "S26_" + str(exc)
        write_failure_evidence(out_path, reason=reason, elapsed_s=elapsed_s, envelope=envelope)
        print("BLOCK " + reason)
        return 4

    contract_gate, parsed = gates.contract(profile_slug="ui_architect", raw_output=raw, schema=schema_binding)
    semantic_gate = gates.semantic_utility(profile_slug="ui_architect", payload=parsed, contract_gate=contract_gate)
    result = {
        "scope": "S26_CLOUDFLARE_SANDBOX_CAPABILITY_ONLY_NOT_PROMOTION",
        "provider": "cloudflare_workers_ai_native_rest_guided_json",
        "model": MODEL,
        "authority_ref": authority_ref,
        "authority_source_hashes": authority.source_hashes(),
        "prompt_policy": "S26_PINNED_FOCUSED_UI_SINGLE_SHOT_CF_MISTRAL_GUIDED_JSON_V1",
        "generation_schema_policy": generation_policy,
        "max_output_tokens": MAX_OUTPUT_TOKENS,
        "request_timeout_seconds": REQUEST_TIMEOUT_SECONDS,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "inference_requests": 1,
        "retries": 0,
        "elapsed_s": elapsed_s,
        "finish_reason": finish_reason,
        "usage": usage,
        "raw_output_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
        "raw_output": raw,
        "output": parsed if isinstance(parsed, dict) else None,
        "contract_gate": contract_gate,
        "semantic_gate": semantic_gate,
        "production_mutation": False,
        "worker_deployed": False,
        "routing_changed": False,
        "promotion_authorized": False,
        "paid_fallback_used": False,
    }
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("S26_CLOUDFLARE_BENCHMARK=" + json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
    if contract_gate.get("status") == "PASS" and semantic_gate.get("status") == "PASS":
        print("S26_CLOUDFLARE_CAPABILITY_PASS_NO_PROMOTION", flush=True)
    else:
        print("S26_CLOUDFLARE_CAPABILITY_FAIL_CLOSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
