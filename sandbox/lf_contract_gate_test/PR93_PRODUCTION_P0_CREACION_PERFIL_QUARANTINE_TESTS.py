#!/usr/bin/env python3
"""Static fail-closed assertions for the run-creacion-perfil-lf quarantine."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "supabase/migrations/edge_functions/run-creacion-perfil-lf/index.ts"


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise AssertionError(f"forbidden {label}: {needle}")


def main() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    required = {
        'const ENDPOINT_VERSION = "v15-quarantined-pending-secure-redesign";': "quarantine version",
        'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")': "service-role credential",
        "constantTimeEqual(received, expected)": "constant-time comparison",
        'code: "SERVICE_ROLE_REQUIRED"': "function-level authorization",
        'code: "TEMPORARILY_DISABLED_PENDING_SECURE_REDESIGN"': "fail-closed quarantine",
        'data_accessed: false': "no data access declaration",
        'write_executed: false': "no write declaration",
        '"Cache-Control": "no-store"': "no-store response",
        'req.method !== "POST"': "POST-only gate",
        '"Access-Control-Allow-Methods": "POST, OPTIONS"': "bounded methods",
    }
    for needle, label in required.items():
        require(source, needle, label)

    forbidden = {
        '"Access-Control-Allow-Origin": "*"': "wildcard CORS",
        "createClient(": "Supabase client access",
        "SUPABASE_URL": "Supabase URL use",
        "from(": "database relation access",
        "fetch(": "external network access",
        "GITHUB_TOKEN": "GitHub credential use",
        "GH_TOKEN": "GitHub credential use",
    }
    for needle, label in forbidden.items():
        forbid(source, needle, label)

    print("PASS_P0_CREACION_PERFIL_QUARANTINE_STATIC=17/17")


if __name__ == "__main__":
    main()
