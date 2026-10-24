"""Technical material binding to CURRENTNESS_AUTHORITY, source-only adapter.

No new freshness classifier. Trusted provider must hydrate observed current
digests independently; echoing requested digests is only a synthetic fixture.
"""
from copy import deepcopy
import json
from pathlib import Path
from typing import Callable

from programming_pg01_receiver_v1 import (
    CanonicalCurrentnessPort, ExpectedHandoff, canonical_sha256,
)

PIN_KEYS = ("standards_catalog", "technical_profile", "control_mechanism",
            "architecture_profile", "consumption_policy")
PACKET_KEYS = {"context_id", "context_sha256", "scope_id", "scope_ids",
               "target", "technical_materials_sha256", "binding"}


def technical_materials(expected, snapshot, scope_id, scope_ids, frame, binding_map, report):
    """Bind verified bytes, pin identity, request parameters and C7 evidence."""
    values = {
        "technical_subject": canonical_sha256({
            "context_id": expected.context_id, "context_sha256": expected.context_sha256,
            "scope_id": scope_id, "scope_ids": sorted(scope_ids), "target": snapshot["target"]}),
        "technical_framework": canonical_sha256(frame),
        "technical_sufficiency_map": canonical_sha256(binding_map),
        "technical_sufficiency_report": canonical_sha256(report),
    }
    for key in PIN_KEYS:
        values["technical_artifact:" + key] = frame[key]["sha256"]
        values["technical_pin:" + key] = canonical_sha256(frame[key])
    return values


class TechnicalCurrentnessPort:
    def __init__(self, repo: Path, provider: Callable):
        self._repo, self._provider = repo, provider

    def evaluate(self, expected: ExpectedHandoff, snapshot: dict, scope_id: str,
                 scope_ids: list, frame: dict, binding_map: dict, report: dict) -> dict:
        additional = technical_materials(expected, snapshot, scope_id, scope_ids,
                                         frame, binding_map, report)
        packet = deepcopy(self._provider(expected, scope_id, tuple(scope_ids),
                                         deepcopy(additional)))
        json.dumps(packet, allow_nan=False)

        def reject(reason):
            return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": reason}

        if not isinstance(packet, dict) or set(packet) != PACKET_KEYS:
            return reject("TECHNICAL_CURRENTNESS_PACKET_INVALID")
        if (packet["context_id"] != expected.context_id
                or packet["context_sha256"] != expected.context_sha256
                or packet["scope_id"] != scope_id
                or packet["scope_ids"] != sorted(scope_ids)
                or packet["target"] != snapshot["target"]
                or packet["technical_materials_sha256"] != canonical_sha256(additional)):
            return reject("TECHNICAL_CURRENTNESS_SUBJECT_MISMATCH")
        # Reuse the existing port's snapshot invariants and canonical evaluator.
        source_packet = {"context_id": packet["context_id"],
                         "context_sha256": packet["context_sha256"],
                         "scope_id": scope_id, "binding": packet["binding"]}
        port = CanonicalCurrentnessPort(self._repo, lambda *args: source_packet)
        return port.evaluate(expected, snapshot, scope_id, additional_materials=additional)
