#!/usr/bin/env python3
"""Shared GitHub API readback boundary for GITHUB_CONTRACT_GATE_LF consumers."""
from __future__ import annotations

import json
import socket
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable

AUTHORITY_ASSET = "GITHUB_CONTRACT_GATE_LF"
RESOLVER_REGISTRY_ASSET = "EVIDENCE_RESOLVER_REGISTRY"
PROVIDER = "GITHUB"
DEFAULT_MAX_ATTEMPTS = 3
DEFAULT_TIMEOUT_SECONDS = 30.0
DEFAULT_BACKOFF_SECONDS = (0.5, 1.5)
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
RETRYABLE_HTTP = {408, 429, 500, 502, 503, 504}


@dataclass(frozen=True)
class GithubReadbackError(ValueError):
    code: str
    classification: str
    detail: str
    attempts: int
    retryable: bool

    def __str__(self) -> str:
        return (
            f"{self.code}: classification={self.classification} "
            f"attempts={self.attempts} retryable={str(self.retryable).lower()} "
            f"detail={self.detail}"
        )


def _is_dns_reason(reason: object) -> bool:
    if isinstance(reason, socket.gaierror):
        return True
    text = str(reason).lower()
    markers = (
        "temporary failure in name resolution",
        "name or service not known",
        "nodename nor servname",
        "getaddrinfo failed",
        "could not resolve host",
    )
    return any(marker in text for marker in markers)


def _sleep_for_attempt(attempt: int, sleeper: Callable[[float], None]) -> None:
    index = min(max(attempt - 1, 0), len(DEFAULT_BACKOFF_SECONDS) - 1)
    sleeper(DEFAULT_BACKOFF_SECONDS[index])


def request_json(
    url: str,
    token: str,
    *,
    user_agent: str,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    max_attempts: int = DEFAULT_MAX_ATTEMPTS,
    opener: Callable[..., Any] = urllib.request.urlopen,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[dict[str, Any], dict[str, str], dict[str, Any]]:
    """Read provider JSON with bounded retries and fail-closed classification."""
    if not token:
        raise GithubReadbackError("FAIL_GITHUB_READBACK_AUTH", "FAIL_AUTH", "token missing", 0, False)
    if max_attempts < 1:
        raise ValueError("max_attempts must be >= 1")

    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": user_agent,
        },
    )

    last_network: urllib.error.URLError | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            with opener(request, timeout=timeout_seconds) as response:
                data = response.read(MAX_RESPONSE_BYTES + 1)
                headers = {key.lower(): value for key, value in response.headers.items()}
            if len(data) > MAX_RESPONSE_BYTES:
                raise GithubReadbackError(
                    "FAIL_GITHUB_READBACK_RESPONSE_TOO_LARGE",
                    "FAIL_EVIDENCE_MISMATCH",
                    "response exceeds 16 MiB",
                    attempt,
                    False,
                )
            try:
                value = json.loads(data.decode("utf-8", "strict"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise GithubReadbackError(
                    "FAIL_GITHUB_READBACK_JSON",
                    "FAIL_EVIDENCE_MISMATCH",
                    str(exc),
                    attempt,
                    False,
                ) from exc
            if not isinstance(value, dict):
                raise GithubReadbackError(
                    "FAIL_GITHUB_READBACK_SHAPE",
                    "FAIL_EVIDENCE_MISMATCH",
                    "response must be a JSON object",
                    attempt,
                    False,
                )
            receipt = {
                "authority_asset": AUTHORITY_ASSET,
                "resolver_registry_asset": RESOLVER_REGISTRY_ASSET,
                "provider": PROVIDER,
                "attempts": attempt,
                "network_retry_used": attempt > 1,
            }
            return value, headers, receipt
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:500]
            if exc.code in {401, 403}:
                raise GithubReadbackError(
                    "FAIL_GITHUB_READBACK_AUTH",
                    "FAIL_AUTH",
                    f"HTTP {exc.code}: {detail}",
                    attempt,
                    False,
                ) from exc
            retryable = exc.code in RETRYABLE_HTTP
            if retryable and attempt < max_attempts:
                _sleep_for_attempt(attempt, sleeper)
                continue
            classification = "BLOCKED_GITHUB_API" if retryable else "FAIL_GITHUB_API"
            raise GithubReadbackError(
                "FAIL_GITHUB_READBACK_HTTP",
                classification,
                f"HTTP {exc.code}: {detail}",
                attempt,
                retryable,
            ) from exc
        except urllib.error.URLError as exc:
            last_network = exc
            if attempt < max_attempts:
                _sleep_for_attempt(attempt, sleeper)
                continue
            classification = "BLOCKED_INFRA_DNS" if _is_dns_reason(exc.reason) else "BLOCKED_GITHUB_API"
            raise GithubReadbackError(
                "FAIL_GITHUB_READBACK_NETWORK",
                classification,
                str(exc.reason),
                attempt,
                True,
            ) from exc

    raise GithubReadbackError(
        "FAIL_GITHUB_READBACK_NETWORK",
        "BLOCKED_GITHUB_API",
        str(last_network.reason if last_network else "unknown network failure"),
        max_attempts,
        True,
    )
