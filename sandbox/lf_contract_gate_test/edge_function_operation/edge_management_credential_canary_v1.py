"""One read-only Supabase Management API canary, scoped to one existing Edge Function.

No deployment or mutation code exists in this file. Never log the bearer token.
"""
from __future__ import annotations

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PROJECT_REF = "mhwmirqcgxxukpctffuv"
TARGET_SLUG = "lf-profiles-governance-caller-v1"
GET_URL = (
    "https://api.supabase.com/v1/projects/"
    + PROJECT_REF + "/functions/" + TARGET_SLUG
)


class CanaryBlocked(Exception):
    """Sanitized, non-sensitive diagnostic."""


def verify_function_metadata(value: object) -> dict:
    if not isinstance(value, dict):
        raise CanaryBlocked("EDGE_MANAGEMENT_RESPONSE_NOT_OBJECT")
    if value.get("slug") != TARGET_SLUG:
        raise CanaryBlocked("EDGE_MANAGEMENT_WRONG_FUNCTION")
    if value.get("status") != "ACTIVE":
        raise CanaryBlocked("EDGE_MANAGEMENT_FUNCTION_NOT_ACTIVE")
    version = value.get("version")
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        raise CanaryBlocked("EDGE_MANAGEMENT_INVALID_VERSION")
    if value.get("verify_jwt") is not False:
        raise CanaryBlocked("EDGE_MANAGEMENT_JWT_MODE_DRIFT")
    # Deliberately expose only public, non-sensitive metadata. Do not infer
    # runtime source equality from the version or source digest alone.
    return {
        "result": "EDGE_MANAGEMENT_READ_PASS",
        "target": TARGET_SLUG,
        "version": version,
        "status": "ACTIVE",
        "jwt_mode_preserved": True,
        "method": "GET",
        "deployed": False,
        "r17_authorized": False,
        "cp2_runs_started": 0,
    }


def read_existing_function(token: str, opener=urlopen) -> dict:
    if not isinstance(token, str) or not token.strip():
        raise CanaryBlocked("EDGE_MANAGEMENT_TOKEN_MISSING")
    request = Request(
        GET_URL,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
            "Cache-Control": "no-store",
        },
        method="GET",
    )
    try:
        with opener(request, timeout=20) as response:
            if response.status != 200:
                raise CanaryBlocked("EDGE_MANAGEMENT_NON_200")
            payload = json.loads(response.read(2_000_000))
    except HTTPError as exc:
        if exc.code in (401, 403):
            raise CanaryBlocked("EDGE_MANAGEMENT_CREDENTIAL_DENIED_" + str(exc.code)) from None
        if exc.code == 404:
            raise CanaryBlocked("EDGE_MANAGEMENT_TARGET_NOT_FOUND") from None
        if exc.code == 429:
            raise CanaryBlocked("EDGE_MANAGEMENT_RATE_LIMITED") from None
        raise CanaryBlocked("EDGE_MANAGEMENT_HTTP_ERROR_" + str(exc.code)) from None
    except (URLError, TimeoutError, OSError):
        raise CanaryBlocked("EDGE_MANAGEMENT_NETWORK_UNAVAILABLE") from None
    except (json.JSONDecodeError, ValueError):
        raise CanaryBlocked("EDGE_MANAGEMENT_INVALID_JSON") from None
    return verify_function_metadata(payload)


def main() -> int:
    try:
        result = read_existing_function(os.environ.get("SUPABASE_ACCESS_TOKEN", ""))
    except CanaryBlocked as exc:
        print(json.dumps({"result": "BLOCKED", "reason": str(exc),
                          "deployed": False, "cp2_runs_started": 0}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
