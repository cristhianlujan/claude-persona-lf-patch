#!/usr/bin/env python3
"""CP2 operational cohort dispatcher. This is not a release promotion mechanism."""
import argparse
import json
import os
import sys
from urllib.request import Request, urlopen

EXPECTED = "M105_SCOPE_SNAPSHOT_V1"
COUNT = 13

def check_scope(snapshot, release):
    ids = snapshot.get("screen_ids")
    if snapshot.get("schema_version") != EXPECTED or not isinstance(ids, list):
        return "INVALID_SCOPE"
    if len(ids) != COUNT or len(set(ids)) != COUNT or any(type(x) is not int for x in ids):
        return "INVALID_COHORT"
    if not release.get("version") or not release.get("previous_version"):
        return "NO_GENUINE_VNEXT"
    if release["version"] == release["previous_version"]:
        return "NO_GENUINE_VNEXT"
    if len(str(release.get("manifest_sha256", ""))) != 64:
        return "INVALID_MANIFEST"
    return "READY_TO_DISPATCH"

class Transport:
    def __init__(self, endpoint, headers):
        if not endpoint.startswith("https://"):
            raise ValueError("ENDPOINT_NOT_SECURE")
        self.endpoint, self.headers = endpoint.rstrip("/"), headers

    def query(self, route, body=None):
        payload = None if body is None else json.dumps(body).encode()
        req = Request(self.endpoint + route, data=payload, headers=self.headers,
                      method="GET" if payload is None else "POST")
        with urlopen(req, timeout=55) as response:
            return json.load(response)

def execute(snapshot, release, gateway, *, allowed=False):
    gate = check_scope(snapshot, release)
    if gate != "READY_TO_DISPATCH":
        return dict(status=gate, attempts=0, results=[])
    if not allowed:
        return dict(status="PREFLIGHT_ONLY", attempts=0, results=[])
    results = []
    for screen in snapshot["screen_ids"]:
        item = dict(pantalla_id=screen)
        try:
            for attempt in range(1, 11):
                response = gateway.query("/functions/v1/input-governance-agent-v1",
                    dict(pantalla_id=screen, consumer="STORY_CREATOR"))
                result = response.get("result") or {}
                status = response.get("status") or result.get("status")
                item["attempts"] = attempt
                if status == "VALIDATOR_RESUME_REQUIRED":
                    continue
                item["agent_result"] = status
                break
            else:
                item["status"] = "ERROR_CONTINUATION_LIMIT"
            if "status" not in item:
                rows = gateway.query("/rest/v1/rpc/fn_ig_m105_cp2_screen_readback_v1", {"p_pantalla_id": screen})
                if not isinstance(rows, list) or len(rows) != 1:
                    item["status"] = "ERROR_READBACK"
                else:
                    item["run_id"] = rows[0]["run_id"]
                    item["status"] = rows[0]["cp2_verdict"]
                    item["technical"] = rows[0]["technical_verdict"]
        except Exception as exc:
            item["status"] = "ERROR_TRANSPORT"
            item["exception_type"] = type(exc).__name__
        results.append(item)
    return dict(status="RECORDED_NOT_CERTIFIED", attempts=len(results), results=results,
                cp2_pass_count=sum(x["status"] == "PASS_CP2" for x in results))

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--execute", action="store_true")
    args = p.parse_args()
    endpoint = os.environ.get("IG_CANONICAL_ENDPOINT", "")
    credential = os.environ.get("IG_CANONICAL_AUTH", "")
    if not endpoint or not credential:
        print(json.dumps({"status": "AUTHENTICATED_TRANSPORT_UNAVAILABLE", "attempts": 0}))
        return 2
    gateway = Transport(endpoint, {"authorization": "Bearer " + credential,
             "apikey": credential, "content-type": "application/json"})
    try:
        authority = gateway.query("/rest/v1/rpc/fn_ig_m105_cp2_dispatch_context_v1", {})
        if not isinstance(authority, dict) or authority.get("status") != "AUTHORIZED_CONTEXT":
            print(json.dumps({"status": "GOVERNED_DISPATCH_CONTEXT_UNAVAILABLE", "attempts": 0}))
            return 2
        if authority.get("dispatch_permitted") is not True:
            print(json.dumps({"status": "CUTOVER_NOT_AUTHORIZED", "attempts": 0}))
            return 2
        result = execute(authority["scope"], authority["release"], gateway, allowed=args.execute)
    except Exception as exc:
        print(json.dumps({"status": "DISPATCH_TRANSPORT_FAILURE", "exception_type": type(exc).__name__}))
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0 if result["status"] in ("PREFLIGHT_ONLY", "RECORDED_NOT_CERTIFIED") else 2

if __name__ == "__main__":
    sys.exit(main())
