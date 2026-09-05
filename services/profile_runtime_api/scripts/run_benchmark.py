#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image

ARTIFACT_SHA256 = "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287"
ARTIFACT_FILENAME = "B2B_CARGA_001_HISTORIAL_DESKTOP_LIGHT_v0.1_CANDIDATO.png"
ARTIFACT_SIZE = (1600, 1000)
BASELINE_MS = {
    "PERFIL-PRODUCT-DIRECTOR-LF": 348_682,
    "PERFIL-UI-ARCHITECT": 672_969,
    "PERFIL-QUALITY-PACK": 439_227,
    "batch_p2": 787_911,
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_observations(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        payload = payload.get("observations", payload.get("data"))
    if not isinstance(payload, list):
        raise ValueError("OBSERVATIONS_MUST_BE_ARRAY_OR_OBJECT_WITH_OBSERVATIONS")
    output: list[dict[str, Any]] = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            raise ValueError(f"OBSERVATION_NOT_OBJECT:{index}")
        bbox = item.get("bbox")
        if not isinstance(bbox, (list, tuple)) or len(bbox) != 4:
            bbox = [item.get("left"), item.get("top"), item.get("width"), item.get("height")]
        output.append(
            {
                "id": item.get("id", index),
                "text": item.get("text"),
                "bbox": bbox,
                "conf": item.get("conf", item.get("confidence", 100)),
            }
        )
    return output


def request_json(method: str, url: str, token: str, payload: Any | None = None) -> Any:
    body = canonical_bytes(payload) if payload is not None else None
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read(2000).decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP_{exc.code}:{detail}") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the fixed B2B-CARGA-001 batch benchmark")
    parser.add_argument("--api-base", default="http://127.0.0.1:8090")
    parser.add_argument("--token-env", default="PROFILE_RUNTIME_API_TOKEN")
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--observations", required=True, type=Path)
    parser.add_argument("--governance-receipt", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("--deadline-seconds", type=int, default=1800)
    args = parser.parse_args()

    token = os.getenv(args.token_env, "")
    if not token:
        raise ValueError(f"TOKEN_ENV_EMPTY:{args.token_env}")
    image_bytes = args.image.read_bytes()
    if sha256(image_bytes) != ARTIFACT_SHA256:
        raise ValueError("FIXED_ARTIFACT_SHA256_MISMATCH")
    with Image.open(args.image) as image:
        if image.size != ARTIFACT_SIZE or image.format != "PNG":
            raise ValueError("FIXED_ARTIFACT_DIMENSIONS_OR_FORMAT_MISMATCH")

    observations_raw = load_json(args.observations)
    observations = normalize_observations(observations_raw)
    governance_raw = load_json(args.governance_receipt)
    governance = governance_raw.get("input_governance", governance_raw)
    fixture_path = (
        Path(__file__).resolve().parents[3]
        / "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/fixtures"
        / "semantic_candidate_b2b_carga_001.json"
    )
    fixture = load_json(fixture_path)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    batch_id = f"B2B-CARGA-001-HETZNER-API-{run_id}"
    profiles = []
    for item in fixture["requests"]:
        profiles.append(
            {
                "request_id": f"{batch_id}:{item['profile_slug']}",
                "operation_code": "EJECUCION_PERFIL_LF",
                "profile_code": item["profile_code"],
                "profile_slug": item["profile_slug"],
                "profile_source_paths": item["profile_source_paths"],
                "input_literal": item["input_literal"],
                "lf_adapter_sources": [],
                "send_image_to_model": False,
            }
        )
    payload = {
        "batch_id": batch_id,
        "artifact": {
            "screen_code": "B2B-CARGA-001",
            "filename": ARTIFACT_FILENAME,
            "image_sha256": ARTIFACT_SHA256,
            "width_px": ARTIFACT_SIZE[0],
            "height_px": ARTIFACT_SIZE[1],
            "observations": observations,
            "image_base64": base64.b64encode(image_bytes).decode("ascii"),
            "image_media_type": "image/png",
        },
        "input_governance": governance,
        "profiles": profiles,
    }
    submitted_at = time.perf_counter()
    accepted = request_json("POST", args.api_base.rstrip("/") + "/v1/profile/batch", token, payload)
    job_url = args.api_base.rstrip("/") + accepted["status_url"]
    deadline = time.monotonic() + args.deadline_seconds
    while True:
        job = request_json("GET", job_url, token)
        if job["status"] in {"COMPLETED", "FAILED"}:
            break
        if time.monotonic() >= deadline:
            raise TimeoutError("BENCHMARK_JOB_DEADLINE_EXCEEDED")
        time.sleep(args.poll_seconds)
    api_wall_ms = round((time.perf_counter() - submitted_at) * 1000, 3)
    comparison: dict[str, Any] = {}
    runtime_result = job.get("result") if isinstance(job, dict) else None
    if isinstance(runtime_result, dict):
        for item in runtime_result.get("profile_results") or []:
            if not isinstance(item, dict):
                continue
            code = str(item.get("profile_code") or "")
            elapsed = item.get("elapsed_ms")
            baseline = BASELINE_MS.get(code)
            if isinstance(elapsed, (int, float)) and baseline:
                comparison[code] = {
                    "historical_ms": baseline,
                    "candidate_ms": elapsed,
                    "delta_ms": round(float(elapsed) - baseline, 3),
                    "historical_over_candidate_ratio": round(
                        baseline / max(float(elapsed), 0.001), 3
                    ),
                    "runtime_completion": (item.get("runtime_completion") or {}).get(
                        "status"
                    ),
                    "profile_contract_valid": (
                        item.get("profile_contract_valid") or {}
                    ).get("status"),
                    "semantic_utility": (item.get("semantic_utility") or {}).get("status"),
                }
        comparison["batch_p2_reference"] = {
            "historical_ms": BASELINE_MS["batch_p2"],
            "candidate_api_wall_ms": api_wall_ms,
            "delta_ms": round(api_wall_ms - BASELINE_MS["batch_p2"], 3),
        }
    report = {
        "schema": "lf-profile-runtime-api-benchmark/v1",
        "batch_id": batch_id,
        "artifact": {
            "filename": ARTIFACT_FILENAME,
            "sha256": ARTIFACT_SHA256,
            "width_px": ARTIFACT_SIZE[0],
            "height_px": ARTIFACT_SIZE[1],
            "bytes": len(image_bytes),
        },
        "input_lineage": {
            "observations_file_sha256": sha256(args.observations.read_bytes()),
            "normalized_observations_sha256": sha256(canonical_bytes(observations)),
            "observation_count": len(observations),
            "governance_receipt_file_sha256": sha256(args.governance_receipt.read_bytes()),
        },
        "historical_baseline_ms": BASELINE_MS,
        "api_wall_ms": api_wall_ms,
        "comparison": comparison,
        "job": job,
        "classification": "INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY",
        "ready_claimed": False,
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    sys.stdout.write(rendered)
    return 0 if job["status"] == "COMPLETED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
