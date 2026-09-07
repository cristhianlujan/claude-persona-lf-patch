#!/usr/bin/env python3
"""Shadow guard for LF profile-runtime transport policy.

Static, dependency-free preflight. It does not contact Hetzner, Supabase or
GitHub, download models, or mutate runtime.

It reuses existing authority instead of creating a new rule:
- PRUNTIME-HETZNER-PRODUCER-003: HETZNER is primary; GITHUB_ACTIONS is only an
  explicitly justified backup.
- PROFILE-RUNTIME-GHA-CACHE-WRITE-DENIED-001: ephemeral runner cache is not a
  substitute for the persistent primary runtime.

Default mode is SHADOW: findings are emitted but do not block. --enforce is
present only so the same implementation can later be promoted after governance
approval and controlled impact testing.
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

HOSTED_RUNNER_PATTERN = re.compile(
    r"runs-on\s*:\s*(?:['\"])?ubuntu(?:-[A-Za-z0-9_.-]+)?", re.I
)
TARGET_PATTERN = re.compile(r"^\s*LF_RUNTIME_TARGET\s*:\s*['\"]?([A-Z_]+)", re.M)
BACKUP_REASON_PATTERN = re.compile(
    r"^\s*LF_RUNTIME_BACKUP_REASON\s*:\s*(.+?)\s*$", re.M
)

HETZNER_ROUTE_PATTERNS = (
    re.compile(r"\bfn_lf_profile_runtime_enqueue_text_v1\b", re.I),
    re.compile(r"\bruntime_target\b.{0,80}\bHETZNER\b", re.I | re.S),
    re.compile(r"\bPROFILE_RUNTIME_LLAMA_BASE_URL\b", re.I),
    re.compile(r"\bhetzner_queue_worker\b", re.I),
)


def _strip_comment_only_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


def _runtime_indicators(text: str) -> list[str]:
    clean = _strip_comment_only_lines(text)
    return sorted(
        name for name, pattern in RUNTIME_PATTERNS.items() if pattern.search(clean)
    )


def _explicit_backup(text: str) -> tuple[bool, str | None]:
    target = TARGET_PATTERN.search(text)
    reason = BACKUP_REASON_PATTERN.search(text)
    target_value = target.group(1).strip() if target else None
    reason_value = reason.group(1).strip().strip("'\"") if reason else None
    if reason_value in {"", "null", "None", "~"}:
        reason_value = None
    return target_value == "GITHUB_ACTIONS" and bool(reason_value), reason_value


def classify_workflow(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    indicators = _runtime_indicators(text)
    hosted = bool(HOSTED_RUNNER_PATTERN.search(text))
    backup_ok, backup_reason = _explicit_backup(text)
    hetzner_route = any(pattern.search(text) for pattern in HETZNER_ROUTE_PATTERNS)

    if hosted and indicators:
        classification = (
            "GITHUB_MODEL_RUNTIME_EXPLICIT_BACKUP"
            if backup_ok
            else "GITHUB_MODEL_RUNTIME_UNJUSTIFIED"
        )
    elif hetzner_route:
        classification = "HETZNER_ROUTE_OR_RUNTIME_COMPONENT"
    else:
        classification = "CI_GOVERNANCE_NO_MODEL_RUNTIME"

    return {
        "workflow": path.name,
        "classification": classification,
        "hosted_runner": hosted,
        "runtime_indicators": indicators,
        "explicit_backup": backup_ok,
        "backup_reason": backup_reason,
        "hetzner_route_signal": hetzner_route,
    }


def scan(workflows_dir: Path) -> list[dict]:
    paths: list[Path] = []
    for glob in WORKFLOW_GLOBS:
        paths.extend(workflows_dir.glob(glob))
    return [classify_workflow(path) for path in sorted(set(paths))]


def summarize(results) -> dict:
    results = list(results)
    counts: dict[str, int] = {}
    offenders: list[str] = []
    for item in results:
        counts[item["classification"]] = counts.get(item["classification"], 0) + 1
        if item["classification"] == "GITHUB_MODEL_RUNTIME_UNJUSTIFIED":
            offenders.append(item["workflow"])
    return {
        "workflow_count": len(results),
        "counts": dict(sorted(counts.items())),
        "unjustified_github_model_runtime": sorted(offenders),
        "policy": {
            "primary_runtime": "HETZNER",
            "github_actions_runtime": "EXPLICIT_BACKUP_ONLY",
            "default_mode": "SHADOW",
        },
    }


def _write_fixture(root: Path, name: str, content: str) -> None:
    (root / name).write_text(
        textwrap.dedent(content).strip() + "\n", encoding="utf-8"
    )


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        _write_fixture(
            root,
            "ci.yml",
            """
            jobs:
              test:
                runs-on: ubuntu-latest
                steps:
                  - run: python3 -m unittest
            """,
        )
        _write_fixture(
            root,
            "bad.yml",
            """
            jobs:
              run:
                runs-on: ubuntu-latest
                steps:
                  - run: |
                      cmake --build build --target llama-server
                      curl -L https://huggingface.co/org/model/resolve/abc/model.gguf -o model.gguf
            """,
        )
        _write_fixture(
            root,
            "backup.yml",
            """
            jobs:
              run:
                runs-on: ubuntu-latest
                env:
                  LF_RUNTIME_TARGET: GITHUB_ACTIONS
                  LF_RUNTIME_BACKUP_REASON: HETZNER_UNAVAILABLE_VERIFIED
                steps:
                  - run: ./llama-server -m model.gguf
            """,
        )
        _write_fixture(
            root,
            "hetzner.yml",
            """
            jobs:
              route:
                runs-on: ubuntu-latest
                steps:
                  - run: echo fn_lf_profile_runtime_enqueue_text_v1 runtime_target=HETZNER
            """,
        )

        results = {item["workflow"]: item for item in scan(root)}
        assert (
            results["ci.yml"]["classification"]
            == "CI_GOVERNANCE_NO_MODEL_RUNTIME"
        ), results
        assert (
            results["bad.yml"]["classification"]
            == "GITHUB_MODEL_RUNTIME_UNJUSTIFIED"
        ), results
        assert (
            results["backup.yml"]["classification"]
            == "GITHUB_MODEL_RUNTIME_EXPLICIT_BACKUP"
        ), results
        assert (
            results["hetzner.yml"]["classification"]
            == "HETZNER_ROUTE_OR_RUNTIME_COMPONENT"
        ), results
        assert summarize(results.values())["unjustified_github_model_runtime"] == [
            "bad.yml"
        ], results

    print("WORKFLOW_RUNTIME_TRANSPORT_GUARD_SELF_TEST_PASS 4/4")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--enforce", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()

    workflows_dir = Path(args.repo_root).resolve() / ".github" / "workflows"
    if not workflows_dir.exists():
        raise SystemExit(f"WORKFLOWS_DIR_MISSING:{workflows_dir}")

    results = scan(workflows_dir)
    payload = {
        "schema": "LF_WORKFLOW_RUNTIME_TRANSPORT_SHADOW_V1",
        "mode": "ENFORCE" if args.enforce else "SHADOW",
        "summary": summarize(results),
        "results": results,
    }

    if args.json:
        print(json.dumps(payload, sort_keys=True, indent=2))
    else:
        print(
            "LF_WORKFLOW_RUNTIME_TRANSPORT_SHADOW="
            + json.dumps(payload, sort_keys=True)
        )

    offenders = payload["summary"]["unjustified_github_model_runtime"]
    if args.enforce and offenders:
        print(
            "BLOCK_UNJUSTIFIED_GITHUB_MODEL_RUNTIME=" + ",".join(offenders),
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
