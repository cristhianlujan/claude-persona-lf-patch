#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

CLIENT_ROLES = {"PUBLIC", "anon", "authenticated"}


def analyze(inventory: dict[str, Any]) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    for row in inventory.get("functions") or []:
        fn = row.get("function")
        grantees = set(row.get("grantees") or [])
        client = sorted(grantees & CLIENT_ROLES)
        internal_surface = row.get("classification") != "REFERENCE_SERVICE_ROLE_ONLY"
        caller_auth = bool(row.get("checks_auth_uid") or row.get("checks_jwt") or row.get("checks_current_user"))
        if internal_surface and client and not caller_auth:
            findings.append({
                "function": fn,
                "client_execute_roles": client,
                "mutates_data": bool(row.get("mutates_data")),
                "caller_auth_present": caller_auth,
                "decision": "HARDEN_TO_SERVICE_ROLE_CANDIDATE",
            })

    return {
        "schema_version": "LF_INTERNAL_RPC_ACL_ANALYSIS_V1",
        "status": "CLIENT_ROLE_EXPOSURE_FOUND" if findings else "NO_UNGOVERNED_CLIENT_EXECUTE_FOUND",
        "finding_count": len(findings),
        "findings": findings,
        "repo_callers_prove_absence": False,
        "live_apply_allowed": False,
        "required_next": [
            "OWNER_CALL_PATH_REVIEW",
            "SOURCE_FIRST_PRIVILEGE_MIGRATION",
            "EXACT_HEAD_CI",
            "ROUTINE_PRIVILEGE_READBACK"
        ] if findings else [],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only analyzer for internal LF RPC ACL drift.")
    ap.add_argument("--inventory", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    ns = ap.parse_args()
    result = analyze(json.loads(ns.inventory.read_text(encoding="utf-8")))
    text = json.dumps(result, sort_keys=True, indent=2)
    if ns.output:
        ns.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
