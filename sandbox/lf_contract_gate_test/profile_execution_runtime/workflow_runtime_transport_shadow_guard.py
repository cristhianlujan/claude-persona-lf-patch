#!/usr/bin/env python3
"""Capability-aware SHADOW guard for LF workflow runtime transport.

Static and dependency-free. It never contacts Hetzner, Supabase or GitHub and
never downloads a model. It reuses existing governance:
- PRUNTIME-HETZNER-PRODUCER-003: HETZNER is primary; GITHUB_ACTIONS is only an
  explicitly justified backup.
- PROFILE-RUNTIME-GHA-CACHE-WRITE-DENIED-001: ephemeral cache is not a
  replacement for persistent runtime.

The guard is deliberately job-level and exact-asset-aware. Presence of a live
llama-server is not enough: a job may require a different pinned model/mmproj or
multiple mutually exclusive model assets. It also distinguishes the existing
GitHub backup queue workers from ordinary hosted model execution: the DB claim
guard may protect HETZNER requests, but expensive provisioning must not happen
before the cheap target/backup-reason preflight.

SHADOW mode never blocks.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import tempfile
import textwrap

WORKFLOW_GLOBS = ("*.yml", "*.yaml")

RUNTIME_PATTERNS = {
    "huggingface_download": re.compile(r"https://huggingface\.co/", re.I),
    "gguf_artifact": re.compile(r"\.gguf\b", re.I),
    "llama_server_build_or_exec": re.compile(r"\bllama-server\b|\bllama_server\b", re.I),
    "semantic_model_path": re.compile(r"\bLF_SEMANTIC_MODEL_PATH\b"),
    "llama_server_path": re.compile(r"\bLF_LLAMA_SERVER_PATH\b"),
}

HEAVY_PREP_PATTERN = re.compile(
    r"https://huggingface\.co/|cmake\s+--build|git\s+clone[^\n]*llama\.cpp|actions/cache@",
    re.I,
)
BACKUP_WORKER_PATTERN = re.compile(
    r"\bgithub_actions_(?:batch_)?queue_worker\.py\b",
    re.I,
)
EARLY_TRANSPORT_PREFLIGHT_PATTERN = re.compile(
    r"\b(?:runtime_target|runtime_backup_reason)\b.{0,300}\bGITHUB_ACTIONS\b|"
    r"\bpreflight[^\n]*(?:runtime|transport|queue)\b",
    re.I | re.S,
)

HOSTED_RUNNER_PATTERN = re.compile(
    r"runs-on\s*:\s*(?:['\"])?ubuntu(?:-[A-Za-z0-9_.-]+)?", re.I
)
TARGET_PATTERN = re.compile(r"^\s*LF_RUNTIME_TARGET\s*:\s*['\"]?([A-Z_]+)", re.M)
BACKUP_REASON_PATTERN = re.compile(r"^\s*LF_RUNTIME_BACKUP_REASON\s*:\s*(.+?)\s*$", re.M)

MODEL_SHA_PATTERN = re.compile(
    r"^\s*(?:MODEL_SHA256|JUDGE_SHA256|LF_S26_PRIMARY_CANDIDATE_SHA256)\s*:\s*['\"]?([a-fA-F0-9]{64})",
    re.M,
)
MMPROJ_SHA_PATTERN = re.compile(
    r"^\s*MMPROJ_SHA256\s*:\s*['\"]?([a-fA-F0-9]{64})",
    re.M,
)
LLAMA_COMMIT_PATTERN = re.compile(
    r"^\s*(?:LLAMA_COMMIT|LF_LLAMA_SOURCE_COMMIT)\s*:\s*['\"]?([a-fA-F0-9]{40})",
    re.M,
)

HETZNER_ROUTE_PATTERNS = (
    re.compile(r"\bfn_lf_profile_runtime_enqueue_text_v1\b", re.I),
    re.compile(r"\bruntime_target\b.{0,80}\bHETZNER\b", re.I | re.S),
    re.compile(r"\bPROFILE_RUNTIME_LLAMA_BASE_URL\b", re.I),
    re.compile(r"\bhetzner_queue_worker\b", re.I),
)


def _strip_comment_only_lines(text: str) -> str:
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


def _runtime_indicators(text: str) -> list[str]:
    clean = _strip_comment_only_lines(text)
    return sorted(name for name, pattern in RUNTIME_PATTERNS.items() if pattern.search(clean))


def _explicit_backup(text: str) -> tuple[bool, str | None]:
    target = TARGET_PATTERN.search(text)
    reason = BACKUP_REASON_PATTERN.search(text)
    target_value = target.group(1).strip() if target else None
    reason_value = reason.group(1).strip().strip("'\"") if reason else None
    if reason_value in {"", "null", "None", "~"}:
        reason_value = None
    return target_value == "GITHUB_ACTIONS" and bool(reason_value), reason_value


def _split_jobs(text: str) -> list[tuple[str, str]]:
    """Split ordinary GitHub Actions jobs without requiring YAML."""
    lines = text.splitlines()
    in_jobs = False
    current_name: str | None = None
    current: list[str] = []
    found: list[tuple[str, str]] = []
    job_key = re.compile(r"^  ([A-Za-z0-9_.-]+):\s*$")
    top_level = re.compile(r"^[A-Za-z0-9_.-]+:\s*")
    for line in lines:
        if not in_jobs:
            if re.fullmatch(r"jobs:\s*", line):
                in_jobs = True
            continue
        if top_level.match(line) and not line.startswith(" "):
            break
        match = job_key.match(line)
        if match:
            if current_name is not None:
                found.append((current_name, "\n".join(current)))
            current_name = match.group(1)
            current = [line]
        elif current_name is not None:
            current.append(line)
    if current_name is not None:
        found.append((current_name, "\n".join(current)))
    return found


def _requirements(text: str) -> dict:
    return {
        "model_sha256": sorted({m.lower() for m in MODEL_SHA_PATTERN.findall(text)}),
        "mmproj_sha256": sorted({m.lower() for m in MMPROJ_SHA_PATTERN.findall(text)}),
        "llama_commits": sorted({m.lower() for m in LLAMA_COMMIT_PATTERN.findall(text)}),
    }


def _capability_match(requirements: dict, capability: dict | None) -> tuple[bool, list[str]]:
    if not capability:
        return False, ["HETZNER_CAPABILITY_NOT_SUPPLIED"]
    reasons: list[str] = []
    resident_model = str(capability.get("model_sha256") or "").lower()
    resident_mmproj = str(capability.get("mmproj_sha256") or "").lower()
    resident_llama = str(capability.get("llama_commit") or "").lower()
    models = requirements["model_sha256"]
    mmprojs = requirements["mmproj_sha256"]
    llamas = requirements["llama_commits"]
    if not models:
        reasons.append("MODEL_SHA_UNRESOLVED")
    elif len(models) > 1:
        reasons.append("MULTI_MODEL_JOB_REQUIRES_MORE_THAN_RESIDENT_MODEL")
    elif models[0] != resident_model:
        reasons.append("MODEL_SHA_MISMATCH")
    if mmprojs and (len(mmprojs) > 1 or mmprojs[0] != resident_mmproj):
        reasons.append("MMPROJ_SHA_MISMATCH")
    if llamas and (len(llamas) > 1 or resident_llama not in llamas):
        reasons.append("LLAMA_COMMIT_MISMATCH")
    return not reasons, reasons


def _backup_worker_state(text: str) -> dict:
    worker = BACKUP_WORKER_PATTERN.search(text)
    if not worker:
        return {"is_backup_queue_worker": False, "early_transport_preflight": False, "late_preflight_risk": False}
    heavy = HEAVY_PREP_PATTERN.search(text)
    preflight = EARLY_TRANSPORT_PREFLIGHT_PATTERN.search(text)
    early = bool(preflight and (not heavy or preflight.start() < heavy.start()))
    return {
        "is_backup_queue_worker": True,
        "early_transport_preflight": early,
        "late_preflight_risk": bool(heavy and not early),
    }


def classify_job(workflow: str, job: str, text: str, capability: dict | None) -> dict:
    indicators = _runtime_indicators(text)
    hosted = bool(HOSTED_RUNNER_PATTERN.search(text))
    backup_ok, backup_reason = _explicit_backup(text)
    hetzner_route = any(pattern.search(text) for pattern in HETZNER_ROUTE_PATTERNS)
    requirements = _requirements(text)
    exact_assets, gap_reasons = _capability_match(requirements, capability) if indicators else (False, [])
    backup_worker = _backup_worker_state(text)

    if not indicators:
        classification = "CI_GOVERNANCE_NO_MODEL_RUNTIME"
    elif backup_worker["is_backup_queue_worker"] and backup_worker["late_preflight_risk"]:
        classification = "GITHUB_BACKUP_WORKER_LATE_TRANSPORT_PREFLIGHT"
    elif backup_worker["is_backup_queue_worker"] and backup_worker["early_transport_preflight"]:
        classification = "GITHUB_BACKUP_WORKER_EARLY_PREFLIGHT_PRESENT"
    elif hetzner_route and not hosted:
        classification = "HETZNER_ROUTE_OR_RUNTIME_COMPONENT"
    elif hosted and exact_assets:
        classification = (
            "GITHUB_MODEL_RUNTIME_EXPLICIT_BACKUP_EXACT_ASSET_MATCH"
            if backup_ok
            else "GITHUB_MODEL_RUNTIME_DUPLICATES_HETZNER_EXACT_ASSETS"
        )
    elif hosted:
        classification = (
            "GITHUB_MODEL_RUNTIME_EXPLICIT_BACKUP_CAPABILITY_GAP"
            if backup_ok
            else "HETZNER_CAPABILITY_GAP_GITHUB_MODEL_RUNTIME"
        )
    else:
        classification = "MODEL_RUNTIME_REVIEW_REQUIRED"

    return {
        "workflow": workflow,
        "job": job,
        "classification": classification,
        "hosted_runner": hosted,
        "runtime_indicators": indicators,
        "explicit_backup": backup_ok,
        "backup_reason": backup_reason,
        "hetzner_route_signal": hetzner_route,
        "requirements": requirements,
        "hetzner_exact_asset_match": exact_assets,
        "capability_gap_reasons": gap_reasons,
        **backup_worker,
    }


def scan(workflows_dir: Path, capability: dict | None = None) -> list[dict]:
    paths: list[Path] = []
    for glob in WORKFLOW_GLOBS:
        paths.extend(workflows_dir.glob(glob))
    results: list[dict] = []
    for path in sorted(set(paths)):
        text = path.read_text(encoding="utf-8")
        jobs = _split_jobs(text)
        if not jobs:
            results.append(classify_job(path.name, "<unparsed>", text, capability))
            continue
        results.extend(classify_job(path.name, name, block, capability) for name, block in jobs)
    return results


def summarize(results) -> dict:
    results = list(results)
    counts: dict[str, int] = {}
    exact_duplicates: list[str] = []
    gaps: list[str] = []
    explicit_backups: list[str] = []
    late_preflight: list[str] = []
    for item in results:
        cls = item["classification"]
        counts[cls] = counts.get(cls, 0) + 1
        label = f"{item['workflow']}::{item['job']}"
        if cls == "GITHUB_MODEL_RUNTIME_DUPLICATES_HETZNER_EXACT_ASSETS":
            exact_duplicates.append(label)
        if cls == "HETZNER_CAPABILITY_GAP_GITHUB_MODEL_RUNTIME":
            gaps.append(label)
        if cls.startswith("GITHUB_MODEL_RUNTIME_EXPLICIT_BACKUP"):
            explicit_backups.append(label)
        if cls == "GITHUB_BACKUP_WORKER_LATE_TRANSPORT_PREFLIGHT":
            late_preflight.append(label)
    return {
        "job_count": len(results),
        "counts": dict(sorted(counts.items())),
        "exact_asset_duplicates": sorted(exact_duplicates),
        "capability_gap_jobs": sorted(gaps),
        "backup_workers_late_transport_preflight": sorted(late_preflight),
        "explicit_backup_jobs": sorted(explicit_backups),
        "policy": {
            "primary_runtime": "HETZNER_WHEN_EXACT_CAPABILITY_MATCHES",
            "github_actions_runtime": "EXPLICIT_BACKUP_ONLY",
            "backup_worker_rule": "CHECK_TARGET_AND_BACKUP_REASON_BEFORE_HEAVY_PROVISIONING",
            "capability_match_requires": "MODEL_SHA_AND_OPTIONAL_MMPROJ_AND_LLAMA_COMMIT",
            "default_mode": "SHADOW",
        },
    }


def _write_fixture(root: Path, name: str, content: str) -> None:
    (root / name).write_text(textwrap.dedent(content).strip() + "\n", encoding="utf-8")


def self_test() -> None:
    model = "a" * 64
    mmproj = "b" * 64
    other = "c" * 64
    llama = "d" * 40
    capability = {"model_sha256": model, "mmproj_sha256": mmproj, "llama_commit": llama}
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        _write_fixture(root, "ci.yml", """
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - run: python3 -m unittest
        """)
        _write_fixture(root, "duplicate.yml", f"""
        jobs:
          run:
            runs-on: ubuntu-latest
            env:
              MODEL_SHA256: {model}
              MMPROJ_SHA256: {mmproj}
              LLAMA_COMMIT: {llama}
            steps:
              - run: ./llama-server -m model.gguf
        """)
        _write_fixture(root, "gap.yml", f"""
        jobs:
          run:
            runs-on: ubuntu-latest
            env:
              MODEL_SHA256: {other}
              LLAMA_COMMIT: {llama}
            steps:
              - run: ./llama-server -m model.gguf
        """)
        _write_fixture(root, "backup-late.yml", f"""
        jobs:
          run:
            runs-on: ubuntu-latest
            env:
              MODEL_SHA256: {model}
            steps:
              - run: curl -L https://huggingface.co/org/model/model.gguf -o model.gguf
              - run: python3 github_actions_queue_worker.py --request-id x
        """)
        _write_fixture(root, "backup-early.yml", f"""
        jobs:
          run:
            runs-on: ubuntu-latest
            env:
              MODEL_SHA256: {model}
            steps:
              - run: echo preflight runtime_target GITHUB_ACTIONS runtime_backup_reason required
              - run: curl -L https://huggingface.co/org/model/model.gguf -o model.gguf
              - run: python3 github_actions_queue_worker.py --request-id x
        """)
        _write_fixture(root, "multi.yml", f"""
        jobs:
          run:
            runs-on: ubuntu-latest
            env:
              MODEL_SHA256: {model}
              JUDGE_SHA256: {other}
            steps:
              - run: ./llama-server -m model.gguf
        """)
        by_label = {(i["workflow"], i["job"]): i for i in scan(root, capability)}
        assert by_label[("ci.yml", "test")]["classification"] == "CI_GOVERNANCE_NO_MODEL_RUNTIME"
        assert by_label[("duplicate.yml", "run")]["classification"] == "GITHUB_MODEL_RUNTIME_DUPLICATES_HETZNER_EXACT_ASSETS"
        assert by_label[("gap.yml", "run")]["classification"] == "HETZNER_CAPABILITY_GAP_GITHUB_MODEL_RUNTIME"
        assert by_label[("backup-late.yml", "run")]["classification"] == "GITHUB_BACKUP_WORKER_LATE_TRANSPORT_PREFLIGHT"
        assert by_label[("backup-early.yml", "run")]["classification"] == "GITHUB_BACKUP_WORKER_EARLY_PREFLIGHT_PRESENT"
        assert "MULTI_MODEL_JOB_REQUIRES_MORE_THAN_RESIDENT_MODEL" in by_label[("multi.yml", "run")]["capability_gap_reasons"]
    print("WORKFLOW_RUNTIME_TRANSPORT_GUARD_SELF_TEST_PASS 6/6")


def _load_capability(path: str | None) -> dict | None:
    if not path:
        return None
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit("HETZNER_CAPABILITY_JSON_MUST_BE_OBJECT")
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--hetzner-capability-json")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--enforce", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
    capability = _load_capability(args.hetzner_capability_json)
    workflows_dir = Path(args.repo_root).resolve() / ".github" / "workflows"
    if not workflows_dir.exists():
        raise SystemExit(f"WORKFLOWS_DIR_MISSING:{workflows_dir}")
    results = scan(workflows_dir, capability)
    payload = {
        "schema": "LF_WORKFLOW_RUNTIME_TRANSPORT_SHADOW_V3",
        "mode": "ENFORCE" if args.enforce else "SHADOW",
        "hetzner_capability": capability,
        "summary": summarize(results),
        "results": results,
    }
    if args.json:
        print(json.dumps(payload, sort_keys=True, indent=2))
    else:
        print("LF_WORKFLOW_RUNTIME_TRANSPORT_SHADOW=" + json.dumps(payload, sort_keys=True))
    blockers = (
        payload["summary"]["exact_asset_duplicates"]
        + payload["summary"]["capability_gap_jobs"]
        + payload["summary"]["backup_workers_late_transport_preflight"]
    )
    if args.enforce and blockers:
        print("BLOCK_RUNTIME_TRANSPORT_REVIEW=" + ",".join(blockers), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
