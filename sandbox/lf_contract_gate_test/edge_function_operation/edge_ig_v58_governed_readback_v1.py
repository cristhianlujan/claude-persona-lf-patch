"""Sandbox-only readback of exact Agent/Validator Edge source and JWT mode.
Uses existing SUPABASE_ACCESS_TOKEN (no service_role/DB/API model credentials).
GET-only; returns sanitized version, sha256 and bundle digest.
"""
from __future__ import annotations
import hashlib
import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

PROJECT_REF="mhwmirqcgxxukpctffuv"
TARGETS={
    "input-governance-agent-v1":"supabase/functions/input-governance-agent-v1/index.ts",
    "input-governance-validator-v1":"supabase/functions/input-governance-validator-v1/index.ts",
}

class ReadbackBlocked(Exception):
    pass

def inspect_metadata(payload, slug, expected_sha=None, min_version=1):
    if slug not in TARGETS: raise ReadbackBlocked("IG_V58_TARGET_NOT_ALLOWED")
    if not isinstance(payload, dict) or payload.get("slug") != slug:
        raise ReadbackBlocked("IG_V58_WRONG_TARGET")
    if payload.get("status") != "ACTIVE" or payload.get("verify_jwt") is not True:
        raise ReadbackBlocked("IG_V58_STATUS_OR_JWT_DRIFT")
    version=payload.get("version")
    if type(version) is not int or version < min_version:
        raise ReadbackBlocked("IG_V58_EDGE_VERSION_NOT_ADVANCED")
    files=payload.get("files")
    if not isinstance(files, list):
        raise ReadbackBlocked("IG_V58_MANAGEMENT_SOURCE_NOT_RETURNED")
    matches=[f for f in files if isinstance(f,dict) and f.get("name") == "index.ts"]
    if len(matches)!=1 or not isinstance(matches[0].get("content"),str):
        raise ReadbackBlocked("IG_V58_SOURCE_READBACK_NOT_EXACTLY_ONE")
    source_sha=hashlib.sha256(matches[0]["content"].encode("utf-8")).hexdigest()
    if expected_sha is not None and source_sha!=expected_sha:
        raise ReadbackBlocked("IG_V58_DEPLOYED_SOURCE_SHA_MISMATCH")
    if slug=="input-governance-agent-v1" and expected_sha:
        if "CURATOR_RECURATION_SUCCESSOR" not in matches[0]["content"]:
            raise ReadbackBlocked("IG_V58_AGENT_CASCADE_NOT_DEPLOYED")
    if slug=="input-governance-validator-v1" and expected_sha:
        if "VALIDATOR_RECURATION_RECEIPT_INVALID" not in matches[0]["content"]:
            raise ReadbackBlocked("IG_V58_VALIDATOR_NEGATIVE_NOT_DEPLOYED")
    return {
        "status":"READBACK_PASS","project_ref":PROJECT_REF,
        "slug":slug,"version":version,"verify_jwt":True,
        "source_sha256":source_sha,
        "ezbr_sha256":payload.get("ezbr_sha256"),
    }

def read_metadata(slug, opener=urlopen):
    if slug not in TARGETS: raise ReadbackBlocked("IG_V58_TARGET_NOT_ALLOWED")
    token=os.environ.get("SUPABASE_ACCESS_TOKEN","")
    if not token: raise ReadbackBlocked("IG_V58_MANAGEMENT_TOKEN_MISSING")
    req=Request(
        "https://api.supabase.com/v1/projects/"+PROJECT_REF+"/functions/"+slug,
        headers={"Authorization":"Bearer "+token,"Accept":"application/json","Cache-Control":"no-store"},method="GET")
    try:
        with opener(req,timeout=20) as res:
            if res.status!=200: raise ReadbackBlocked("IG_V58_MANAGEMENT_NON_200")
            return json.loads(res.read(2000000))
    except HTTPError as ex:
        raise ReadbackBlocked("IG_V58_MANAGEMENT_HTTP_"+str(ex.code)) from None
    except (URLError,OSError,TimeoutError):
        raise ReadbackBlocked("IG_V58_MANAGEMENT_UNAVAILABLE") from None

def main(argv):
    if len(argv) not in (2,3,4):
        print(json.dumps({"status":"BLOCKED","reason":"IG_V58_READBACK_ARGS_INVALID"}))
        return 2
    slug=argv[1]
    min_version=int(argv[2]) if len(argv)>=3 else 1
    expected=argv[3] if len(argv)==4 else None
    try:
        result=inspect_metadata(read_metadata(slug),slug,expected,min_version)
    except (ReadbackBlocked,ValueError,json.JSONDecodeError) as exc:
        print(json.dumps({"status":"BLOCKED","reason":str(exc)}))
        return 2
    print(json.dumps(result,sort_keys=True))
    return 0

if __name__=="__main__":
    sys.exit(main(sys.argv))
