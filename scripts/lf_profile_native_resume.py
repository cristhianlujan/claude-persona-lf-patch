#!/usr/bin/env python3
"""Generic OIDC-driven native bridge resume; never selects screens or runs a model.

One invocation follows the existing execution until the next governed semantic,
Input Governance, or native model boundary. It cannot modify product records.
"""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import urllib.error
import urllib.parse
import urllib.request

EDGE_URL = os.environ["LF_PROFILE_EDGE_URL"].rstrip("/")
AUDIENCE = "lf-profiles-governance-caller-v1"


def call_json(url, payload, headers=None):
    headers = {"content-type": "application/json", **(headers or {})}
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            result = json.load(exc)
        except ValueError:
            result = {"code": "NON_JSON_HTTP_FAILURE"}
        return exc.code, result


def oidc():
    request_url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"]
    request_token = os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    delim = "&" if "?" in request_url else "?"
    url = f"{request_url}{delim}audience={urllib.parse.quote(AUDIENCE)}"
    req = urllib.request.Request(url, headers={"authorization": f"Bearer {request_token}"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)["value"]


def main():
    execution_id = os.environ["PROFILE_EXECUTION_ID"]
    source_revision = os.environ["GITHUB_SHA"]
    token = oidc()
    headers = {"authorization": f"Bearer {token}"}

    code, source = call_json(EDGE_URL, {
        "action": "profile_native_source_bind_v1",
        "execution_id": execution_id,
    }, headers)
    if code != 200 or source.get("outcome") != "SOURCE_BINDING_REQUIRED":
        print(json.dumps({"phase": "SOURCE_BIND", "status": code, "code": source.get("code")}))
        return 1
    target_path = source.get("target_path")
    if (source.get("execution_id") != execution_id
        or source.get("source_revision_required") != source_revision
        or source.get("target_repo") != os.environ["GITHUB_REPOSITORY"]
        or not isinstance(target_path, str)):
        print("SOURCE_BINDING_MISMATCH")
        return 1

    path = PurePosixPath(target_path)
    if (len(path.parts) != 3 or path.parts[0] != "profiles"
        or path.parts[-1] != "SKILL.md" or ".." in path.parts
        or path.is_absolute()):
        print("SOURCE_PATH_NOT_CANONICAL")
        return 1
    file = (Path.cwd() / str(path)).resolve()
    root = (Path.cwd() / "profiles").resolve()
    if not file.is_file() or not file.is_relative_to(root):
        print("PROFILE_SOURCE_NOT_IN_EXACT_CHECKOUT")
        return 1

    digest = "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest()
    payload = {
        "action": "profile_native_continue_v1",
        "execution_id": execution_id,
        "source_revision": source_revision,
        "source_digest": digest,
    }
    raw_draft = os.getenv("PROFILE_SCREEN_SELECTION_DRAFT_JSON", "").strip()
    if raw_draft:
        draft = json.loads(raw_draft)
        if not isinstance(draft, dict):
            print("SCREEN_SELECTION_DRAFT_NOT_JSON_OBJECT")
            return 1
        payload["screen_selection_draft"] = draft

    code, result = call_json(EDGE_URL, payload, headers)
    if code != 200:
        print(json.dumps({"phase": "PREPARE", "status": code, "code": result.get("code")}))
        return 1

    # Input Governance is a runtime concern, not a profile/Router bypass.
    # Reinvoke only on an explicit DIRECT_EDGE_INVOCATION ticket and READY.
    for _ in range(3):
        if result.get("phase") != "INPUT_GOVERNANCE_RUNTIME_REQUIRED":
            break
        runtime = result.get("result", {}).get("input_governance_runtime_request", {})
        ticket = runtime.get("request_headers", {}).get("X-LF-Profile-Runtime-Ticket")
        body = runtime.get("request_body")
        if (runtime.get("transport") != "DIRECT_EDGE_INVOCATION"
            or runtime.get("queue_required") is not False
            or runtime.get("polling_required") is not False
            or not isinstance(ticket, str) or not isinstance(body, dict)
            or body.get("action") != "input_readiness_context_pack_runtime_v1"
            or body.get("execution_id") != execution_id):
            print("PROFILE_INPUT_GOVERNANCE_TICKET_INVALID")
            return 1
        ig_code, ig = call_json(EDGE_URL, body, {"X-LF-Profile-Runtime-Ticket": ticket})
        if ig_code != 200 or ig.get("outcome") != "TERMINAL" or ig.get("terminal_status") != "READY":
            print(json.dumps({
                "phase": "INPUT_GOVERNANCE", "status": ig_code,
                "outcome": ig.get("outcome"), "code": ig.get("code"),
            }))
            return 1
        payload.pop("screen_selection_draft", None)
        code, result = call_json(EDGE_URL, payload, headers)
        if code != 200:
            print(json.dumps({"phase": "PREPARE_AFTER_IG", "status": code, "code": result.get("code")}))
            return 1

    phase = result.get("phase")
    # Deliberately do not print context packs or runtime tickets in CI logs.
    print(json.dumps({
        "execution_id": execution_id,
        "profile_code": result.get("profile_code"),
        "phase": phase,
        "next_action": result.get("next_action"),
    }, ensure_ascii=False))
    if phase == "NATIVE_MODEL_INPUT_READY":
        print("PROFILE_NATIVE_PRE_MODEL_PREPARATION_PASS_MODEL_OUTPUT_NOT_PRODUCED")
        return 0
    if phase in ("SCREEN_SELECTION_REQUIRED", "INPUT_GOVERNANCE_RUNTIME_REQUIRED"):
        print("PROFILE_NATIVE_SEMANTIC_OR_IG_CONTINUATION_REQUIRED_NOT_COMPLETE")
        return 0
    print("PROFILE_NATIVE_BRIDGE_BLOCKED_OR_MANUAL_DECISION_REQUIRED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
