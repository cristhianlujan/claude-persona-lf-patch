"""Read-only Supabase Management API readback for the governed profile runtime Edge Function.

Scoped to the fixed allowlist below. No deployment or mutation code exists in this file.
Never log the bearer token. Exit codes: 0 PASS, 2 BLOCKED.
"""
from __future__ import annotations

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PROJECT_REF = "mhwmirqcgxxukpctffuv"
# slug -> required verify_jwt value (JWT mode must be preserved, never flipped).
ALLOWED_TARGETS = {"run-creacion-perfil-lf": True}


class ReadbackBlocked(Exception):
    """Sanitized, non-sensitive diagnostic."""


def function_url(slug: str) -> str:
    if slug not in ALLOWED_TARGETS:
        raise ReadbackBlocked("EDGE_TARGET_NOT_ALLOWED")
    return "https://api.supabase.com/v1/projects/" + PROJECT_REF + "/functions/" + slug


def verify_function_metadata(value: object, slug: str, min_version: int = 1) -> dict:
    if slug not in ALLOWED_TARGETS:
        raise ReadbackBlocked("EDGE_TARGET_NOT_ALLOWED")
    if not isinstance(value, dict):
        raise ReadbackBlocked("EDGE_MANAGEMENT_RESPONSE_NOT_OBJECT")
    if value.get("slug") != slug:
        raise ReadbackBlocked("EDGE_MANAGEMENT_WRONG_FUNCTION")
    if value.get("status") != "ACTIVE":
        raise ReadbackBlocked("EDGE_MANAGEMENT_FUNCTION_NOT_ACTIVE")
    version = value.get("version")
    if not isinstance(version, int) or isinstance(version, bool) or version < max(1, min_version):
        raise ReadbackBlocked("EDGE_MANAGEMENT_INVALID_VERSION")
    if value.get("verify_jwt") is not ALLOWED_TARGETS[slug]:
        raise ReadbackBlocked("EDGE_MANAGEMENT_JWT_MODE_DRIFT")
    return {
        "result": "EDGE_MANAGEMENT_READ_PASS",
        "target": slug,
        "version": version,
        "status": "ACTIVE",
        "jwt_mode_preserved": True,
        "method": "GET",
    }


def read_existing_function(token: str, slug: str, min_version: int = 1, opener=urlopen) -> dict:
    if not isinstance(token, str) or not token.strip():
        raise ReadbackBlocked("EDGE_MANAGEMENT_TOKEN_MISSING")
    request = Request(
        function_url(slug),
        headers={"Authorization": "Bearer " + token, "Accept": "application/json", "Cache-Control": "no-store"},
        method="GET",
    )
    try:
        with opener(request, timeout=20) as response:
            if response.status != 200:
                raise ReadbackBlocked("EDGE_MANAGEMENT_NON_200")
            payload = json.loads(response.read(2_000_000))
    except HTTPError as exc:
        if exc.code in (401, 403):
            raise ReadbackBlocked("EDGE_MANAGEMENT_CREDENTIAL_DENIED_" + str(exc.code)) from None
        if exc.code == 404:
            raise ReadbackBlocked("EDGE_MANAGEMENT_TARGET_NOT_FOUND") from None
        if exc.code == 429:
            raise ReadbackBlocked("EDGE_MANAGEMENT_RATE_LIMITED") from None
        raise ReadbackBlocked("EDGE_MANAGEMENT_HTTP_ERROR_" + str(exc.code)) from None
    except (URLError, TimeoutError, OSError):
        raise ReadbackBlocked("EDGE_MANAGEMENT_NETWORK_UNAVAILABLE") from None
    except (json.JSONDecodeError, ValueError):
        raise ReadbackBlocked("EDGE_MANAGEMENT_INVALID_JSON") from None
    return verify_function_metadata(payload, slug, min_version)


def main(argv: list[str]) -> int:
    slug = argv[1] if len(argv) > 1 else ""
    try:
        min_version = int(argv[2]) if len(argv) > 2 else 1
    except ValueError:
        print(json.dumps({"result": "BLOCKED", "reason": "EDGE_MIN_VERSION_INVALID"}))
        return 2
    try:
        result = read_existing_function(os.environ.get("SUPABASE_ACCESS_TOKEN", ""), slug, min_version)
    except ReadbackBlocked as exc:
        print(json.dumps({"result": "BLOCKED", "reason": str(exc)}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
