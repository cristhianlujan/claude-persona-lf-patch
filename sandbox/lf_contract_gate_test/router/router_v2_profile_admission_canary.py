#!/usr/bin/env python3
"""Governed live canary: GitHub OIDC -> Router V2 -> EJECUCION_PERFIL_LF admission.

No service_role keys or other runtime secrets are used here. The Edge caller
authenticates exact GitHub OIDC identity and alone can access the service role.
"""
import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error

PROJECT_REF = "mhwmirqcgxxukpctffuv"
AUDIENCE = "lf-profiles-governance-caller-v1"
EDGE_URL = f"https://{PROJECT_REF}.supabase.co/functions/v1/lf-profiles-governance-caller-v1"


def post_json(url, data, headers):
    request = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json", **headers},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=75) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read(16384)
        try:
            payload = json.loads(body)
        except (ValueError, UnicodeDecodeError):
            payload = {"code": "NON_JSON_RESPONSE", "http_status": exc.code}
        return exc.code, payload


def main():
    request_url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    request_token = os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    glue = "&" if "?" in request_url else "?"
    request = urllib.request.Request(
        f"{request_url}{glue}audience={urllib.parse.quote(AUDIENCE)}",
        headers={"Authorization": f"Bearer {request_token}"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        oidc_response = json.load(response)
    oidc_token = oidc_response.get("value")
    if not oidc_token:
        raise RuntimeError("GITHUB_OIDC_TOKEN_MISSING")

    status, result = post_json(
        EDGE_URL,
        {"action": "router_profile_login_b2b_canary_v2"},
        {"Authorization": f"Bearer {oidc_token}"},
    )
    # Print only governed result data; never the OIDC token or other secrets.
    summary = {
        "http_status": status,
        "outcome": result.get("outcome"),
        "code": result.get("code"),
        "profile": result.get("profile"),
        "execution_id": result.get("execution_id"),
        "next_action": result.get("next_action"),
        "trace": result.get("trace"),
        "admission": result.get("admission", {}).get("blocking_code") if isinstance(result.get("admission"), dict) else None,
    }
    print(json.dumps(summary, ensure_ascii=False))
    if status != 200 or result.get("outcome") != "NATIVE_EXECUTION_READY" or not result.get("execution_id"):
        print("ROUTER_V2_GOVERNED_PROFILE_LIVE_CANARY_FAILED", file=sys.stderr)
        sys.exit(1)
    print("ROUTER_V2_GOVERNED_PROFILE_LIVE_CANARY_PASS")


if __name__ == "__main__":
    main()
