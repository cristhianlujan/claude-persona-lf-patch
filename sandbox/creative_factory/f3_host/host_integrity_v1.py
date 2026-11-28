#!/usr/bin/env python3
"""Fail-closed byte-integrity gate for F3 host transport harness.

This module proves the local host contract only. It does not attest a real
provider call, production host, or historical execution channel.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from typing import Callable, Any

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class HostIntegrityResult:
    status: str
    reference: str
    expected_sha256: str
    downloaded_sha256: str
    byte_count: int
    provider_calls: int
    native_transmitted: bool
    provider_receipt: Any = None

    def as_dict(self) -> dict[str, Any]:
        return self.__dict__.copy()


def verify_then_transmit(
    reference: str,
    expected_sha256: str,
    downloaded_bytes: bytes,
    provider_send: Callable[[bytes], Any],
) -> HostIntegrityResult:
    if not reference or not isinstance(reference, str):
        raise ValueError("HOST_REFERENCE_REQUIRED")
    if not isinstance(expected_sha256, str) or not SHA256_RE.fullmatch(expected_sha256):
        raise ValueError("HOST_EXPECTED_SHA256_INVALID")
    if not isinstance(downloaded_bytes, bytes):
        raise TypeError("HOST_DOWNLOADED_BYTES_REQUIRED")

    actual = hashlib.sha256(downloaded_bytes).hexdigest()
    if actual != expected_sha256:
        return HostIntegrityResult(
            status="BLOCKED_HASH_MISMATCH",
            reference=reference,
            expected_sha256=expected_sha256,
            downloaded_sha256=actual,
            byte_count=len(downloaded_bytes),
            provider_calls=0,
            native_transmitted=False,
            provider_receipt=None,
        )

    receipt = provider_send(downloaded_bytes)
    if receipt is None:
        raise RuntimeError("HOST_PROVIDER_RECEIPT_REQUIRED")
    return HostIntegrityResult(
        status="VERIFIED_TRANSMITTED",
        reference=reference,
        expected_sha256=expected_sha256,
        downloaded_sha256=actual,
        byte_count=len(downloaded_bytes),
        provider_calls=1,
        native_transmitted=True,
        provider_receipt=receipt,
    )
