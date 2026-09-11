#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hmac
import json
import os
import re
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

SHA40 = re.compile(r"^[0-9a-f]{40}$")
LOCAL_KEY = os.environ.get("LOCAL_SERVICE_ROLE_KEY", "")
UPSTREAM = os.environ.get("S26_EXACT_RUNTIME_URL", "http://127.0.0.1:18082").rstrip("/")
FORBIDDEN_SERVER_TRUST_FIELDS = {
    "server_trust_context_valid",
    "server_trust_context_source",
    "server_trust_context",
}


def normalize(payload: dict[str, Any]) -> tuple[dict[str, Any], bool]:
    if payload.get("action") != "record_profile_operation_step_v1":
        return payload, False
    if payload.get("step_id") != "pre_write_execution_binding_gate":
        return payload, False
    evidence = payload.get("evidence_payload")
    if not isinstance(evidence, dict):
        raise ValueError("EVIDENCE_PAYLOAD_INVALID")
    bound = evidence.get("bound_revision")
    if isinstance(bound, str):
        if not SHA40.fullmatch(bound):
            raise ValueError("BOUND_REVISION_STRING_INVALID")
        return payload, False
    if not isinstance(bound, dict) or set(bound) != {"revision_sha"}:
        raise ValueError("BOUND_REVISION_COMPAT_SHAPE_INVALID")
    sha = bound.get("revision_sha")
    if not isinstance(sha, str) or not SHA40.fullmatch(sha):
        raise ValueError("BOUND_REVISION_COMPAT_SHA_INVALID")
    if any(key in evidence for key in FORBIDDEN_SERVER_TRUST_FIELDS):
        raise ValueError("SERVER_TRUST_FIELDS_MUST_BE_DERIVED_BY_RUNTIME")
    out = dict(payload)
    out_evidence = dict(evidence)
    out_evidence["bound_revision"] = sha
    out["evidence_payload"] = out_evidence
    return out, True


def authorized(headers: Any) -> bool:
    if not LOCAL_KEY:
        return False
    expected = f"Bearer {LOCAL_KEY}"
    return hmac.compare_digest(headers.get("authorization", ""), expected)


class Handler(BaseHTTPRequestHandler):
    server_version = "lf-profile-bound-revision-compat/1"

    def log_message(self, fmt: str, *args: Any) -> None:
        print("COMPAT", fmt % args, flush=True)

    def respond(self, status: int, payload: Any) -> None:
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(raw)))
        self.send_header("cache-control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        if self.path == "/health":
            self.respond(200, {"status": "PASS", "adapter": "BOUND_REVISION_REPRESENTATION_ONLY"})
            return
        self.respond(405, {"code": "METHOD_NOT_ALLOWED"})

    def do_POST(self) -> None:
        if self.path != "/":
            self.respond(404, {"code": "PATH_NOT_ALLOWED"})
            return
        if not authorized(self.headers):
            self.respond(403, {"code": "LOCAL_COMPAT_AUTH_REQUIRED"})
            return
        try:
            length = int(self.headers.get("content-length", "0") or "0")
            raw = self.rfile.read(length)
            data = json.loads(raw.decode("utf-8") or "{}")
            if not isinstance(data, dict):
                raise ValueError("BODY_INVALID")
            normalized, changed = normalize(data)
            body = json.dumps(normalized, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            req = urllib.request.Request(
                UPSTREAM,
                data=body,
                method="POST",
                headers={"authorization": self.headers.get("authorization", ""), "content-type": "application/json"},
            )
            try:
                with urllib.request.urlopen(req, timeout=125) as response:
                    upstream_body = response.read()
                    status = response.status
            except urllib.error.HTTPError as exc:
                upstream_body = exc.read()
                status = exc.code
            self.send_response(status)
            self.send_header("content-type", "application/json; charset=utf-8")
            self.send_header("content-length", str(len(upstream_body)))
            self.send_header("x-lf-bound-revision-normalized", "true" if changed else "false")
            self.end_headers()
            self.wfile.write(upstream_body)
        except ValueError as exc:
            self.respond(400, {"code": str(exc)})
        except Exception as exc:
            self.respond(502, {"code": f"LOCAL_COMPAT_PROXY_FAILED:{str(exc)[:1000]}"})


def self_test() -> None:
    sha = "a" * 40
    base = {
        "action": "record_profile_operation_step_v1",
        "step_id": "pre_write_execution_binding_gate",
        "evidence_payload": {
            "bound_revision": {"revision_sha": sha},
            "step_result": "STEP_PASS_WITH_EVIDENCE",
            "blocking_codes": [],
            "trusted_current_revision": {"revision_sha": sha},
            "current_revision_resolved_by_caller": True,
            "declared_current_revision_ignored": True,
        },
    }
    out, changed = normalize(base)
    assert changed is True and out["evidence_payload"]["bound_revision"] == sha
    assert out["evidence_payload"]["current_revision_resolved_by_caller"] is True
    direct = {**base, "evidence_payload": {**base["evidence_payload"], "bound_revision": sha}}
    out2, changed2 = normalize(direct)
    assert changed2 is False and out2 == direct
    other = {"action": "next_profile_operation_step_v1", "evidence_payload": {"bound_revision": {"revision_sha": sha}}}
    out3, changed3 = normalize(other)
    assert changed3 is False and out3 == other
    try:
        normalize({**base, "evidence_payload": {"bound_revision": {"revision_sha": sha}, "server_trust_context_valid": True}})
    except ValueError as exc:
        assert str(exc) == "SERVER_TRUST_FIELDS_MUST_BE_DERIVED_BY_RUNTIME"
    else:
        raise AssertionError("SERVER_TRUST_FAIL_OPEN")
    print("PASS_PROFILE_CREATOR_BOUND_REVISION_COMPAT_SELFTEST=5/5")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18083)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not LOCAL_KEY:
        raise SystemExit("LOCAL_SERVICE_ROLE_KEY_REQUIRED")
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(json.dumps({"status": "READY", "bind": args.bind, "port": args.port, "upstream": UPSTREAM}), flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
