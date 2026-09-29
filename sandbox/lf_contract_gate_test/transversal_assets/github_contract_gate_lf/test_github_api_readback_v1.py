#!/usr/bin/env python3
"""Deterministic tests for shared GitHub provider readback boundary."""
from __future__ import annotations

import argparse
import importlib.util
import io
import json
import socket
import sys
import urllib.error
from pathlib import Path


class FakeResponse:
    def __init__(self, payload: bytes, headers: dict[str, str] | None = None) -> None:
        self.payload = payload
        self.headers = headers or {}

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        return None

    def read(self, _limit: int) -> bytes:
        return self.payload


def load_boundary(path: Path):
    spec = importlib.util.spec_from_file_location("lf_github_api_readback_v1_tested", path)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_GITHUB_BOUNDARY_TEST_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--boundary", type=Path, required=True)
    args = parser.parse_args()
    boundary = load_boundary(args.boundary.resolve())
    url = "https://api.github.com/repos/o/r/actions/runs"
    token = "synthetic-token"

    sleeps: list[float] = []
    payload, _, receipt = boundary.request_json(
        url,
        token,
        user_agent="lf-test",
        opener=lambda *_args, **_kwargs: FakeResponse(b'{"ok":true}'),
        sleeper=sleeps.append,
    )
    assert payload == {"ok": True}
    assert receipt["authority_asset"] == "GITHUB_CONTRACT_GATE_LF"
    assert receipt["resolver_registry_asset"] == "EVIDENCE_RESOLVER_REGISTRY"
    assert receipt["attempts"] == 1 and receipt["network_retry_used"] is False
    assert sleeps == []
    print("PASS_GITHUB_READBACK_01=success-first-attempt")

    dns_calls = {"count": 0}
    dns_sleeps: list[float] = []

    def dns_opener(*_args, **_kwargs):
        dns_calls["count"] += 1
        raise urllib.error.URLError(socket.gaierror(-3, "Temporary failure in name resolution"))

    try:
        boundary.request_json(url, token, user_agent="lf-test", opener=dns_opener, sleeper=dns_sleeps.append)
        raise SystemExit("dns case unexpectedly passed")
    except boundary.GithubReadbackError as exc:
        assert exc.code == "FAIL_GITHUB_READBACK_NETWORK"
        assert exc.classification == "BLOCKED_INFRA_DNS"
        assert exc.attempts == 3 and exc.retryable is True
        assert dns_calls["count"] == 3 and len(dns_sleeps) == 2
    print("PASS_GITHUB_READBACK_02=dns-bounded-retry")

    transient_calls = {"count": 0}
    transient_sleeps: list[float] = []

    def transient_opener(*_args, **_kwargs):
        transient_calls["count"] += 1
        if transient_calls["count"] == 1:
            raise urllib.error.HTTPError(url, 503, "busy", {}, io.BytesIO(b'{"message":"busy"}'))
        return FakeResponse(b'{"ok":true}')

    payload, _, receipt = boundary.request_json(
        url,
        token,
        user_agent="lf-test",
        opener=transient_opener,
        sleeper=transient_sleeps.append,
    )
    assert payload == {"ok": True}
    assert receipt["attempts"] == 2 and receipt["network_retry_used"] is True
    assert transient_calls["count"] == 2 and len(transient_sleeps) == 1
    print("PASS_GITHUB_READBACK_03=retryable-http-recovers")

    auth_calls = {"count": 0}

    def auth_opener(*_args, **_kwargs):
        auth_calls["count"] += 1
        raise urllib.error.HTTPError(url, 401, "unauthorized", {}, io.BytesIO(b'{}'))

    try:
        boundary.request_json(url, token, user_agent="lf-test", opener=auth_opener, sleeper=lambda _s: None)
        raise SystemExit("auth case unexpectedly passed")
    except boundary.GithubReadbackError as exc:
        assert exc.classification == "FAIL_AUTH"
        assert exc.attempts == 1 and exc.retryable is False
        assert auth_calls["count"] == 1
    print("PASS_GITHUB_READBACK_04=auth-no-retry")

    try:
        boundary.request_json(
            url,
            token,
            user_agent="lf-test",
            opener=lambda *_args, **_kwargs: FakeResponse(b"not-json"),
            sleeper=lambda _s: None,
        )
        raise SystemExit("malformed case unexpectedly passed")
    except boundary.GithubReadbackError as exc:
        assert exc.code == "FAIL_GITHUB_READBACK_JSON"
        assert exc.classification == "FAIL_EVIDENCE_MISMATCH"
        assert exc.attempts == 1 and exc.retryable is False
    print("PASS_GITHUB_READBACK_05=malformed-evidence-no-retry")

    try:
        boundary.request_json(
            url,
            token,
            user_agent="lf-test",
            opener=lambda *_args, **_kwargs: (_ for _ in ()).throw(
                urllib.error.HTTPError(url, 404, "missing", {}, io.BytesIO(b'{}'))
            ),
            sleeper=lambda _s: None,
        )
        raise SystemExit("404 case unexpectedly passed")
    except boundary.GithubReadbackError as exc:
        assert exc.classification == "FAIL_GITHUB_API"
        assert exc.attempts == 1 and exc.retryable is False
    print("PASS_GITHUB_READBACK_06=nonretryable-http")

    print("PASS_GITHUB_API_READBACK_V1=6/6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
