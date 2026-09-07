#!/usr/bin/env python3
"""S26 Cloudflare Workers AI bounded capability benchmark.

Uses the exact S26 focused UI task/prompt/schema/gates from a pinned authority
checkout. Produces sandbox evidence only; no Worker deployment, routing,
promotion, or production mutation is performed.
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

MODEL = "@cf/qwen/qwen3-30b-a3b-fp8"
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
    """Return structural diagnostics without persisting reasoning text."""
    if isinstance(value, dict):
        result: dict[str, Any] = {"keys": sorted(value.keys())}
        for key in ("content", "parsed", "response", "reasoning", "reasoning_content"):
            if key in value:
                item = value[key]
                result[key] = {
                    "type": type(item).__name__,
                    "length": len(item) if isinstance(item, (str, list, dict)) else None,
                    "nonempty": bool(item),
                }
        return result
    if isinstance(value, list):
        return {"type": "list", "length": len(value), "first": diagnostic_shape(value[0]) if value else None}
    return {"type": type(value).__name__, "nonempty": bool(value)}


def extract_content(envelope: dict[str, Any]) -> tuple[str, str, dict[str, Any], dict[str, Any]]:
    root: Any = envelope.get("result") if isinstance(envelope.get("result"), dict) else envelope
    diagnostics = {"envelope": diagnostic_shape(envelope), "root": diagnostic_shape(root)}
    if not isinstance(root, dict):
        raise RuntimeError("CLOUDFLARE_RESULT_INVALID:" + json.dumps(diagnostics, sort_keys=True))

    direct_response = root.get("response")
    if isinstance(direct_response, dict) and direct_response:
        usage = root.get("usage")
        return json.dumps(direct_response, ensure_ascii=False, sort_keys=True), str(root.get("finish_reason") or "stop"), usage if isinstance(usage, dict) else {}, diagnostics
    if isinstance(direct_response, str) and direct_response.strip():
        usage = root.get("usage")
        return direct_response.strip(), str(root.get("finish_reason") or "stop"), usage if isinstance(usage, dict) else {}, diagnostics

    choices = root.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError("CLOUDFLARE_CHOICES_MISSING:" + json.dumps(diagnostics, sort_keys=True))
    choice = choices[0]
    diagnostics["finish_reason"] = str(choice.get("finish_reason") or "")
    message = choice.get("message")
    if not isinstance(message, dict):
        raise RuntimeError("CLOUDFLARE_MESSAGE_MISSING:" + json.dumps(diagnostics, sort_keys=True))
    diagnostics["message"] = diagnostic_shape(message)

    parsed = message.get("parsed")
    if isinstance(parsed, dict) and parsed:
        raw = json.dumps(parsed, ensure_ascii=False, sort_keys=True)
    else:
        content = message.get("content")
        if isinstance(content, list):
            content = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        raw = content.strip() if isinstance(content, str) else ""
    if not raw:
        raise RuntimeError("CLOUDFLARE_CONTENT_EMPTY:" + json.dumps(diagnostics, sort_keys=True))

    usage = root.get("usage")
    return raw, str(choice.get("finish_reason") or ""), usage if isinstance(usage, dict) else {}, diagnostics


def write_failure_evidence(out_path: Path, *, reason: str, elapsed_s: float, envelope: Any) -> None:
    payload = {
        "scope": "S26_CLOUDFLARE_SANDBOX_CAPABILITY_ONLY_NOT_PROMOTION",
        "provider": "cloudflare_workers_ai_direct_rest",
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

    authority_root = Path(authority_root_raw).resolve()
    authority = load_authority_module(authority_root)
    repository = authority.RepositoryBindings(authority.REPO_ROOT, max_prompt_chars=120_000)
    gates = authority.OutputGates(repository)
    schema_binding = repository.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")
    generation_schema, generation_policy = authority.governed_generation_schema(
        schema_binding.payload, profile_slug="ui_architect", schema_mode="UI_FOCUSED_DECISION"
    )

    # Qwen3's documented soft switch is transport control, not a task change.
    # It prevents the bounded output budget from being consumed by hidden reasoning.
    governed_task = authority.TASK + "\n/no_think"
    payload = {
        "messages": [
            {"role": "system", "content": authority.build_system_prompt()},
            {"role": "user", "content": governed_task},
        ],
        "stream": False,
        "temperature": 0,
        "top_p": 1,
        "seed": 42,
        "max_tokens": MAX_OUTPUT_TOKENS,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {"type": "json_schema", "json_schema": generation_schema},
    }

    url = "https://api.cloudflare.com/client/v4/accounts/" + account_id + "/ai/run/@cf/qwen/qwen3-30b-a3b-fp8"
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
        raw, finish_reason, usage, response_diagnostics = extract_content(envelope)
    except RuntimeError as exc:
        reason = "S26_" + str(exc)
        write_failure_evidence(out_path, reason=reason, elapsed_s=elapsed_s, envelope=envelope)
        print("BLOCK " + reason)
        return 4

    contract_gate, parsed = gates.contract(profile_slug="ui_architect", raw_output=raw, schema=schema_binding)
    semantic_gate = gates.semantic_utility(profile_slug="ui_architect", payload=parsed, contract_gate=contract_gate)

    result = {
        "scope": "S26_CLOUDFLARE_SANDBOX_CAPABILITY_ONLY_NOT_PROMOTION",
        "provider": "cloudflare_workers_ai_direct_rest",
        "model": MODEL,
        "authority_ref": authority_ref,
        "authority_source_hashes": authority.source_hashes(),
        "prompt_policy": "S26_PINNED_FOCUSED_UI_SINGLE_SHOT_CF_V3_NO_THINK",
        "generation_schema_policy": generation_policy,
        "thinking_control": "QWEN3_SOFT_SWITCH_NO_THINK_PLUS_HARD_SWITCH_HINT",
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
        "response_diagnostics": response_diagnostics,
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
