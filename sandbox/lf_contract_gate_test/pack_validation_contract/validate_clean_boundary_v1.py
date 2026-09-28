#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / ".github/workflows/lf-pack-validation-core.yml"
STAGED = ROOT / "sandbox/lf_contract_gate_test/pack_validation_contract/lf-pack-validation-core.staged.yml"
LEGACY = ROOT / ".github/workflows/validate-lf-packs.yml"

FORBIDDEN_CORE_TOKENS = (
    "PROFILE_RUNTIME_V3",
    "S30_BOUNDED_REGRESSION",
    "S30_BROKER",
    "GATE_CHECK_OBSERVABILITY",
    "SUPABASE",
    "PGPASSWORD",
    "psql ",
    "persist_gate_failures_to_ekb",
    "profile_runtime_api",
)


def main() -> None:
    core = CORE.read_text(encoding="utf-8")
    staged = STAGED.read_text(encoding="utf-8")
    legacy = LEGACY.read_text(encoding="utf-8")

    assert core == staged, "FAIL_PACK_CORE_NOT_BYTE_EQUIVALENT_TO_QUALIFIED_STAGED"
    assert "workflow_call:" in core
    for trigger in ("pull_request:", "push:", "workflow_dispatch:", "schedule:"):
        assert trigger not in core, f"FAIL_PACK_CORE_AUTONOMOUS_TRIGGER:{trigger}"
    for token in FORBIDDEN_CORE_TOKENS:
        assert token.lower() not in core.lower(), f"FAIL_PACK_CORE_FOREIGN_RESPONSIBILITY:{token}"

    # Cleanup lot must not modify or absorb the historical foreign carrier.
    assert "S30 self-governance regression and fresh receipt gate" in legacy
    assert "PROFILE_RUNTIME_V3" in legacy

    print("PACK_VALIDATION_CLEAN_BOUNDARY=PASS")


if __name__ == "__main__":
    main()
