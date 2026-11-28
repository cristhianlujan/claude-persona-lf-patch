#!/usr/bin/env python3
import hashlib
from host_integrity_v1 import verify_then_transmit


class ProviderProbe:
    def __init__(self):
        self.calls = []

    def send(self, payload: bytes):
        self.calls.append(payload)
        return {"provider_probe_receipt": "LOCAL-HARNESS-1"}


official = b"official-f3-host-asset\x00v1\n"
expected = hashlib.sha256(official).hexdigest()

positive_provider = ProviderProbe()
positive = verify_then_transmit(
    "fixture://official-f3-host-asset",
    expected,
    official,
    positive_provider.send,
)
assert positive.status == "VERIFIED_TRANSMITTED"
assert positive.downloaded_sha256 == expected
assert positive.expected_sha256 == expected
assert positive.byte_count == len(official)
assert positive.provider_calls == 1
assert positive.native_transmitted is True
assert positive_provider.calls == [official]
print("HOST01|PASS_HARNESS")

negative_provider = ProviderProbe()
tampered = official + b"tampered"
negative = verify_then_transmit(
    "fixture://official-f3-host-asset",
    expected,
    tampered,
    negative_provider.send,
)
assert negative.status == "BLOCKED_HASH_MISMATCH"
assert negative.downloaded_sha256 != expected
assert negative.provider_calls == 0
assert negative.native_transmitted is False
assert negative.provider_receipt is None
assert negative_provider.calls == []
print("HOST02|PASS_HARNESS")

try:
    verify_then_transmit("fixture://x", "not-a-sha", official, positive_provider.send)
except ValueError as exc:
    assert str(exc) == "HOST_EXPECTED_SHA256_INVALID"
else:
    raise AssertionError("invalid expected digest was admitted")
print("F3B-HASH-FORMAT|PASS")
