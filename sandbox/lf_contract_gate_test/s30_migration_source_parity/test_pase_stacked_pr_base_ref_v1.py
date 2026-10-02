#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PASE = ROOT / ".github/workflows/pase.yml"


def main() -> int:
    text = PASE.read_text(encoding="utf-8")
    marker = "  migration-source-parity:\n"
    if marker not in text:
        raise SystemExit("FAIL_STACKED_BASE_REF_MIGRATION_JOB_MISSING")
    block = text.split(marker, 1)[1]

    expected = (
        "base_ref: ${{ github.event_name == 'pull_request' && "
        "github.event.pull_request.base.ref || 'main' }}"
    )
    if expected not in block:
        raise SystemExit("FAIL_STACKED_BASE_REF_NOT_PROPAGATED")
    if "base_ref: main" in block:
        raise SystemExit("FAIL_STACKED_BASE_REF_HARDCODED_MAIN")
    if "base_sha: ${{ needs.lf-pase.outputs.resolved_base_sha }}" not in block:
        raise SystemExit("FAIL_STACKED_BASE_SHA_NOT_CANONICAL")
    if "event_name: ${{ github.event_name }}" not in block:
        raise SystemExit("FAIL_STACKED_EVENT_NAME_NOT_PROPAGATED")

    print("PASS_PASE_STACKED_PR_BASE_REF=4/4")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
