#!/usr/bin/env python3
"""Generic OIDC-driven Router admission for EJECUCION_PERFIL_LF.

Forwards a Router context envelope (GATE2_DERIVED_PENDING_GOVERNED_ADMISSION) and
a native executor mode to the governed edge action. It never selects a profile,
never runs a model and never writes product data; authority stays in Supabase.
"""
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request

EDGE_URL = os.environ.get("LF_PROFILE_EDGE_URL", "").rstrip("/")
AUDIENCE = "lf-profiles-governance-caller-v1"
ACTION = "router_profile_admit_context_v2"
NATIVE_MODES = ("GPT_NATIVE", "CLAUDE_NATIVE")
MAX_CONTEXT_CHARS = 60000
ISSUE_LABEL = "lf-profile-admit-governed"


def call_json(url, payload, headers):
    headers = {"content-type": "application/json", **headers}
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            return exc.code, json.load(exc)
        except ValueError:
            return exc.code, {"code": "NON_JSON_HTTP_FAILURE"}


def oidc():
    request_url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    request_token = os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    delim = "&" if "?" in request_url else "?"
    url = f"{request_url}{delim}audience={urllib.parse.quote(AUDIENCE)}"
    req = urllib.request.Request(url, headers={"authorization": f"Bearer {request_token}"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)["value"]


def _validate(context, mode):
    if not isinstance(context, dict):
        raise ValueError("ROUTER_ADMIT_CONTEXT_NOT_OBJECT")
    if (context.get("schema_version") != "LF_ROUTER_EXECUTION_PIPELINE_V1"
            or context.get("status") != "GATE2_DERIVED_PENDING_GOVERNED_ADMISSION"
            or context.get("transport_mode") != "CONTEXT_TRANSPORT"):
        raise ValueError("ROUTER_ADMIT_CONTEXT_ENVELOPE_INVALID")
    if mode not in NATIVE_MODES:
        raise ValueError("ROUTER_ADMIT_EXECUTOR_MODE_INVALID")
    return context, mode


def governed_request():
    """Validate bounded dispatch or issue data; the database re-validates everything."""
    if os.getenv("LF_PROFILE_ADMIT_REQUEST_MODE") == "ISSUE":
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        issue = event.get("issue", {})
        expected_url = "https://api.github.com/repos/" + os.environ["GITHUB_REPOSITORY"]
        if (os.environ.get("GITHUB_EVENT_NAME") != "issues"
                or event.get("action") != "labeled"
                or event.get("label", {}).get("name") != ISSUE_LABEL
                or issue.get("state") != "open"
                or issue.get("pull_request") is not None
                or issue.get("repository_url") != expected_url):
            raise ValueError("ROUTER_ADMIT_ISSUE_TRIGGER_INVALID")
        raw = issue.get("body")
        if not isinstance(raw, str) or len(raw) > MAX_CONTEXT_CHARS + 2048:
            raise ValueError("ROUTER_ADMIT_ISSUE_BODY_INVALID")
        data = json.loads(raw)
        if (not isinstance(data, dict)
                or set(data) != {"schema_version", "router_context", "executor_mode"}
                or data["schema_version"] != "LF_PROFILE_ROUTER_ADMIT_REQUEST_V1"):
            raise ValueError("ROUTER_ADMIT_ISSUE_SCHEMA_INVALID")
        if len(json.dumps(data["router_context"])) > MAX_CONTEXT_CHARS:
            raise ValueError("ROUTER_ADMIT_CONTEXT_SIZE_INVALID")
        return _validate(data["router_context"], data["executor_mode"])
    raw = os.environ.get("ROUTER_CONTEXT_JSON", "")
    if not raw or len(raw) > MAX_CONTEXT_CHARS:
        raise ValueError("ROUTER_ADMIT_CONTEXT_SIZE_INVALID")
    return _validate(json.loads(raw), os.environ.get("EXECUTOR_MODE", ""))


def main():
    context, mode = governed_request()
    headers = {"authorization": f"Bearer {oidc()}"}
    code, response = call_json(
        EDGE_URL,
        {"action": ACTION, "context": context, "executor_mode": mode},
        headers,
    )
    result = response.get("result") if isinstance(response.get("result"), dict) else {}
    # Never print the context or tokens in CI logs.
    print(json.dumps({
        "http_status": code,
        "outcome": response.get("outcome"),
        "code": response.get("code"),
        "execution_id": result.get("execution_id"),
        "profile_code": result.get("profile_code"),
        "executor_mode": mode,
        "next_action": result.get("next_action"),
    }, ensure_ascii=False))
    return 0 if code == 200 else 1


if __name__ == "__main__":
    sys.exit(main())
