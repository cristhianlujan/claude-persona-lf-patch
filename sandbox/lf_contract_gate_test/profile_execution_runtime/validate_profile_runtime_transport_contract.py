#!/usr/bin/env python3
"""Fail closed if LF profile runtime silently downgrades HETZNER to GitHub Actions."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "supabase" / "migrations"
HARDENING = MIGRATIONS / "20260904055116_lf_profile_runtime_no_implicit_github_fallback_v1.sql"
DEFAULT_ROUTING = MIGRATIONS / "20260903211416_lf_profile_runtime_hetzner_default_routing_v1.sql"


def fail(code: str) -> None:
    raise SystemExit(code)


def main() -> int:
    if not HARDENING.is_file():
        fail("PROFILE_RUNTIME_TRANSPORT_HARDENING_MIGRATION_MISSING")
    if not DEFAULT_ROUTING.is_file():
        fail("PROFILE_RUNTIME_HETZNER_DEFAULT_MIGRATION_MISSING")

    hardening = HARDENING.read_text(encoding="utf-8")
    default_routing = DEFAULT_ROUTING.read_text(encoding="utf-8")

    required_hardening = (
        "HETZNER_REQUEST_ENVELOPE_REQUIRED_NO_IMPLICIT_GITHUB_FALLBACK",
        "Default HETZNER",
        "GITHUB_ACTIONS is explicit backup/fallback only",
    )
    for token in required_hardening:
        if token not in hardening:
            fail(f"PROFILE_RUNTIME_TRANSPORT_HARDENING_TOKEN_MISSING:{token}")

    if "new.runtime_target := 'GITHUB_ACTIONS'" in hardening:
        fail("PROFILE_RUNTIME_IMPLICIT_GITHUB_DOWNGRADE_REINTRODUCED_IN_HARDENING")

    if "alter column runtime_target set default 'HETZNER'" not in default_routing:
        fail("PROFILE_RUNTIME_HETZNER_NOT_DEFAULT")
    if "HETZNER_REQUEST_GITHUB_CLAIM_FORBIDDEN" not in default_routing:
        fail("PROFILE_RUNTIME_HETZNER_GITHUB_CLAIM_GUARD_MISSING")

    # Any migration after the hardening point must not silently assign the backup target.
    for path in sorted(MIGRATIONS.glob("*.sql")):
        if path.name <= HARDENING.name:
            continue
        text = path.read_text(encoding="utf-8")
        if "new.runtime_target := 'GITHUB_ACTIONS'" in text:
            fail(f"PROFILE_RUNTIME_IMPLICIT_GITHUB_DOWNGRADE_REINTRODUCED:{path.name}")

    print("PROFILE_RUNTIME_TRANSPORT_CONTRACT_PASS primary=HETZNER backup=GITHUB_ACTIONS_EXPLICIT_ONLY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
