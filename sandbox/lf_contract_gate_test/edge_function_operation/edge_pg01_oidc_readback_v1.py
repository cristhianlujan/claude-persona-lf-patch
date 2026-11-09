#!/usr/bin/env python3
"""Read-only exact-slug PG-01 OIDC Management API metadata check."""
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

URL = "https://api.supabase.com/v1/projects/mhwmirqcgxxukpctffuv/functions/lf-pg01-oidc-authority-v1"

def check(mode, token, min_version=1, opener=urlopen):
    if mode not in ("predeploy", "postdeploy"):
        raise ValueError("INVALID_MODE")
    if not token:
        raise ValueError("TOKEN_MISSING")
    if type(min_version) is not int or min_version < 1:
        raise ValueError("INVALID_MIN_VERSION")
    req = Request(URL, headers={"Authorization": "Bearer " + token, "Accept": "application/json"}, method="GET")
    try:
        with opener(req, timeout=20) as resp:
            doc = json.loads(resp.read(1000000))
    except HTTPError as e:
        if mode == "predeploy" and e.code == 404:
            return {"result": "PREDEPLOY_ABSENT", "slug": "lf-pg01-oidc-authority-v1"}
        raise ValueError("READBACK_HTTP_" + str(e.code)) from None
    except (URLError, OSError, json.JSONDecodeError):
        raise ValueError("READBACK_UNAVAILABLE") from None
    if not isinstance(doc, dict) or doc.get("slug") != "lf-pg01-oidc-authority-v1":
        raise ValueError("SLUG_MISMATCH")
    if doc.get("status") != "ACTIVE" or doc.get("verify_jwt") is not False:
        raise ValueError("STATUS_OR_JWT_MODE_MISMATCH")
    version = doc.get("version")
    if type(version) is not int or version < min_version:
        raise ValueError("VERSION_NOT_ADVANCED")
    return {"result": "READBACK_PASS", "slug": doc["slug"], "status": "ACTIVE", "version": version, "verify_jwt": False}

if __name__ == "__main__":
    try:
        minimum = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        print(json.dumps(check(sys.argv[1], os.environ.get("SUPABASE_ACCESS_TOKEN", ""), minimum)))
    except (ValueError, IndexError) as exc:
        print(json.dumps({"result": "BLOCKED", "reason": str(exc)}))
        sys.exit(2)
