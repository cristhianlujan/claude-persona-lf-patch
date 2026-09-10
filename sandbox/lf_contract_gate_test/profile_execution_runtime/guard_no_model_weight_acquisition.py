#!/usr/bin/env python3
"""Fail closed when an active S26/profile-runtime workflow acquires model weights."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Iterable

S26_SCOPE_MARKERS = (
    "profile_execution_runtime",
    "lf-profile-runtime",
    "profile driven screen generation",
    "s26",
)

FORBIDDEN_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("HUGGINGFACE_DOWNLOAD", re.compile(r"huggingface\.co/", re.I)),
    ("GGUF_WEIGHT", re.compile(r"\.gguf(?:\b|[?\"'])", re.I)),
    ("SAFETENSORS_WEIGHT", re.compile(r"\.safetensors(?:\b|[?\"'])", re.I)),
    ("HF_HUB_DOWNLOAD", re.compile(r"\bhf_hub_download\b", re.I)),
    ("HF_SNAPSHOT_DOWNLOAD", re.compile(r"\bsnapshot_download\s*\(", re.I)),
    ("MODEL_FROM_PRETRAINED", re.compile(r"\bfrom_pretrained\s*\(", re.I)),
)


def is_s26_active_workflow(text: str) -> bool:
    lowered = text.lower()
    return any(marker in lowered for marker in S26_SCOPE_MARKERS)


def scan_workflow(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    if not is_s26_active_workflow(text):
        return []
    findings: list[str] = []
    for code, pattern in FORBIDDEN_PATTERNS:
        if pattern.search(text):
            findings.append(f"{path.as_posix()}:{code}")
    return findings


def scan_workflows(workflow_dir: Path) -> list[str]:
    findings: list[str] = []
    for pattern in ("*.yml", "*.yaml"):
        for path in sorted(workflow_dir.glob(pattern)):
            findings.extend(scan_workflow(path))
    return sorted(set(findings))


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workflow-dir", type=Path, default=Path(".github/workflows"))
    args = parser.parse_args(list(argv) if argv is not None else None)
    findings = scan_workflows(args.workflow_dir)
    if findings:
        print("BLOCK_S26_MODEL_WEIGHT_ACQUISITION")
        for finding in findings:
            print(finding)
        return 1
    print("PASS_S26_NO_MODEL_WEIGHT_ACQUISITION")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
