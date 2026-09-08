#!/usr/bin/env python3
"""Fail-closed guard: active S26 workflows may not acquire or run local model weights."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROUTE_REL = Path("sandbox/lf_contract_gate_test/profile_execution_runtime/s26_runtime_route_v1.json")
WORKFLOW_ROOT = Path(".github/workflows")
FORBIDDEN = {
    "HUGGINGFACE_MODEL_DOWNLOAD": re.compile(r"huggingface\.co", re.I),
    "GGUF_WEIGHT_REFERENCE": re.compile(r"\.gguf(?:\b|\?)", re.I),
    "SAFETENSORS_WEIGHT_REFERENCE": re.compile(r"\.safetensors(?:\b|\?)", re.I),
    "HF_HUB_DOWNLOAD": re.compile(r"\b(?:hf_hub_download|snapshot_download)\b", re.I),
    "LOCAL_LLAMA_RUNTIME": re.compile(r"(?:llama\.cpp|GitHubHostedLlamaCpp)", re.I),
    "LOCAL_MODEL_ENV": re.compile(r"\b(?:LF_MODEL_PATH|LF_MMPROJ_PATH|LF_SEMANTIC_MODEL_PATH)\b"),
}
SCRIPT_REF = re.compile(r"(sandbox/lf_contract_gate_test/profile_execution_runtime/[A-Za-z0-9_./-]+\.py)")


def _load_route(root: Path) -> dict:
    path = root / ROUTE_REL
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"S26_MODEL_DOWNLOAD_GUARD_FAIL route_invalid={type(exc).__name__}") from exc
    required = {
        "status": "ACTIVE_SANDBOX_PRIMARY",
        "environment_scope": "NON_PRODUCTION",
        "primary_runtime": "CLOUDFLARE_WORKERS_AI",
        "cloudflare_plan": "WORKERS_FREE_ZERO_COST_ONLY",
        "paid_fallback": "DISABLED",
        "local_gguf_fallback": "DISABLED",
        "model_download": "DISABLED",
        "limit_behavior": "FAIL_CLOSED",
    }
    bad = {key: payload.get(key) for key, expected in required.items() if payload.get(key) != expected}
    if bad:
        raise SystemExit("S26_MODEL_DOWNLOAD_GUARD_FAIL route_state=" + json.dumps(bad, sort_keys=True))
    return payload


def _workflow_in_scope(path: Path, text: str) -> bool:
    name = path.name.lower()
    return name.startswith("s26-") or "run_s26_" in text or "LF_S26_" in text


def _scan_text(label: str, text: str, violations: list[str]) -> None:
    for code, pattern in FORBIDDEN.items():
        if pattern.search(text):
            violations.append(f"{code}:{label}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.repo_root.resolve()
    route = _load_route(root)

    workflow_dir = root / WORKFLOW_ROOT
    if not workflow_dir.is_dir():
        raise SystemExit("S26_MODEL_DOWNLOAD_GUARD_FAIL workflow_root_missing")

    in_scope: list[Path] = []
    referenced_scripts: set[Path] = set()
    violations: list[str] = []
    cloudflare_route_seen = False

    for path in sorted(list(workflow_dir.glob("*.yml")) + list(workflow_dir.glob("*.yaml"))):
        text = path.read_text(encoding="utf-8")
        if not _workflow_in_scope(path, text):
            continue
        in_scope.append(path)
        if "CLOUDFLARE" in text.upper() or "run_s26_cloudflare" in text:
            cloudflare_route_seen = True
        _scan_text(str(path.relative_to(root)), text, violations)
        for match in SCRIPT_REF.findall(text):
            referenced_scripts.add(Path(match))

    if not in_scope:
        raise SystemExit("S26_MODEL_DOWNLOAD_GUARD_FAIL no_active_s26_workflow")
    if not cloudflare_route_seen:
        violations.append("CLOUDFLARE_ROUTE_MISSING:active_s26_workflows")

    guard_rel = Path(__file__).resolve().relative_to(root)
    for relative in sorted(referenced_scripts):
        if relative == guard_rel:
            continue
        path = (root / relative).resolve()
        try:
            path.relative_to(root)
        except ValueError:
            violations.append(f"SCRIPT_PATH_ESCAPE:{relative}")
            continue
        if not path.is_file():
            violations.append(f"REFERENCED_SCRIPT_MISSING:{relative}")
            continue
        _scan_text(str(relative), path.read_text(encoding="utf-8"), violations)

    if violations:
        print("S26_MODEL_DOWNLOAD_GUARD=FAIL")
        print("ACTIVE_S26_GGUF_DOWNLOAD_PATHS=" + str(len(violations)))
        for violation in sorted(set(violations)):
            print("S26_MODEL_DOWNLOAD_VIOLATION=" + violation)
        return 2

    print("S26_MODEL_DOWNLOAD_GUARD=PASS")
    print("ACTIVE_S26_GGUF_DOWNLOAD_PATHS=0")
    print("CLOUDFLARE_ROUTE_ACTIVE=PASS")
    print("CLOUDFLARE_FREE_ONLY=PASS")
    print("MODEL_DOWNLOAD_DISABLED=PASS")
    print("LOCAL_GGUF_FALLBACK_DISABLED=PASS")
    print("PAID_FALLBACK_DISABLED=PASS")
    print("S26_ACTIVE_WORKFLOW_COUNT=" + str(len(in_scope)))
    print("S26_PRIMARY_RUNTIME=" + str(route["primary_runtime"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
