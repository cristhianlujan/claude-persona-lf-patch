"""Source-only composition of the existing boundary and pure C4/C7 checks.

No alternate snapshot/runtime, connections or discovery. Evidence ports are
trusted constructor dependencies; their operational admission is still pending.
"""
from copy import deepcopy
import json
from typing import Callable

from programming_pg01_receiver_v1 import ReadOnlyReceiver, ExpectedHandoff, canonical_sha256
from programming_pg01_preplanning_checks_v1 import (
    validate_technical_framework, validate_sufficiency, strings,
)

PACKET_SCHEMA = "PG01_PREPLANNING_EVIDENCE_CANDIDATE_V1"
PACKET_KEYS = {
    "schema_version", "context_id", "context_sha256", "scope_ids",
    "snapshot_sha256", "target", "technical_framework", "binding_map",
}
OPERATIONAL_GATES = [
    "TECHNICAL_SOURCE_ADMISSION", "A9_BINDING_MAP_AGREEMENT",
    "CANONICAL_VALUE_READBACK", "CURRENTNESS_AUTHORITY_TECHNICAL_BINDING",
]


class SourcePreplanningReceiver:
    """Never permission to plan/program; ACCEPT is structural candidate only."""

    def __init__(self, boundary: ReadOnlyReceiver, provider: Callable,
                 artifact_reader: Callable, technical_currentness=None):
        self._boundary = boundary
        self._provider = provider
        self._artifact_reader = artifact_reader
        self._technical_currentness = technical_currentness

    def consume(self, expected: ExpectedHandoff, scope_id: str, *,
                proposed_projection: dict | None = None) -> dict:
        base = self._boundary.consume(expected, scope_id)
        # A rejected/absent source context must never query technical evidence.
        if base.get("state") != "ACCEPT":
            return {**base, "preplanning_evaluated": False}
        projection = deepcopy(base["material_projection"])
        snapshot = projection["snapshot"]
        scopes = list(base["admitted_scope_ids"])
        envelope = {k: deepcopy(v) for k, v in base.items()
                    if k not in {"receipt", "material_projection", "admitted_scope_ids"}}
        envelope.update({
            "schema_version": "PG01_SOURCE_PREPLANNING_RESULT_V1",
            "admission_level": "SOURCE_ONLY_PREPLANNING_STRUCTURE",
            "boundary_scope_ids": scopes,
            "preplanning_evaluated": False,
            "planning_allowed": False,
            "execution_allowed": False,
            "operational_admission": False,
            "pending_gates": sorted(set(base["pending_gates"] + OPERATIONAL_GATES)),
        })
        paths = list(base["receipt"]["validated_material_paths"])

        def emit(state, code, **extra):
            receipt = deepcopy(base["receipt"])
            receipt.update(verdict=state,
                           material_projection_sha256=canonical_sha256(projection),
                           validated_material_paths=sorted(set(paths)))
            return {**envelope, "state": state, "code": code,
                    "receipt": receipt, "material_projection": deepcopy(projection),
                    **extra}

        try:
            packet = deepcopy(self._provider(expected, scope_id, tuple(scopes)))
            # The projection must be strict JSON and deterministic.
            json.dumps(packet, allow_nan=False)
        except Exception as exc:
            return emit("BLOCK", "PREPLANNING_EVIDENCE_UNAVAILABLE",
                        error_type=type(exc).__name__)
        if not isinstance(packet, dict) or set(packet) != PACKET_KEYS or packet.get("schema_version") != PACKET_SCHEMA:
            return emit("BLOCK", "PREPLANNING_EVIDENCE_PACKET_INVALID")
        if (packet["context_id"] != expected.context_id
                or packet["context_sha256"] != expected.context_sha256
                or not strings(packet["scope_ids"], nonempty=True)
                or sorted(packet["scope_ids"]) != sorted(scopes)
                or packet["snapshot_sha256"] != canonical_sha256(snapshot)
                or packet["target"] != snapshot["target"]):
            return emit("BLOCK", "PREPLANNING_EVIDENCE_SUBJECT_MISMATCH")

        # Preserve all supplied material exactly once; never modify A9.
        projection.update({
            "preplanning_binding": {k: deepcopy(v) for k, v in packet.items()
                                   if k not in {"technical_framework", "binding_map"}},
            "technical_framework": deepcopy(packet["technical_framework"]),
            "sufficiency_binding_map": deepcopy(packet["binding_map"]),
        })
        try:
            framework = validate_technical_framework(
                packet["technical_framework"], snapshot["target"]["repo_full_name"],
                self._artifact_reader)
            sufficiency = validate_sufficiency(snapshot, scopes, packet["binding_map"])
        except Exception as exc:
            return emit("BLOCK", "PREPLANNING_VALIDATION_UNAVAILABLE",
                        error_type=type(exc).__name__)
        technical_currentness = {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED",
                                 "reason": "STRUCTURE_INCOMPLETE_NOT_EVALUATED"}
        if framework["status"] == "COMPLETE" and sufficiency["status"] == "COMPLETE":
            if self._technical_currentness is None:
                technical_currentness["reason"] = "TECHNICAL_CURRENTNESS_PORT_MISSING"
            else:
                try:
                    observed = self._technical_currentness.evaluate(
                        expected, snapshot, scope_id, scopes,
                        packet["technical_framework"], packet["binding_map"], sufficiency)
                    json.dumps(observed, allow_nan=False)
                    if not isinstance(observed, dict):
                        raise ValueError("CURRENTNESS_OBJECT_REQUIRED")
                    if observed.get("ready") is True:
                        receipt_payload = {k: v for k, v in observed.items() if k != "receipt_sha256"}
                        if (observed.get("schema_version") != "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1"
                                or observed.get("authority_layer") != "CURRENTNESS_AUTHORITY"
                                or observed.get("contract_identity") != "PROGRAMMING_CONTEXT_SNAPSHOT_V1:" + expected.snapshot_schema_digest_sha256
                                or observed.get("implementation_binding") != "PG-01:" + scope_id
                                or observed.get("receipt_sha256") != canonical_sha256(receipt_payload)):
                            raise ValueError("CURRENTNESS_AUTHORITY_RECEIPT_INVALID")
                    technical_currentness = deepcopy(observed)
                except Exception as exc:
                    technical_currentness = {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED",
                                             "reason": "TECHNICAL_CURRENTNESS_UNAVAILABLE",
                                             "error_type": type(exc).__name__}
        projection.update(technical_framework_validation=framework,
                          sufficiency_report=sufficiency,
                          technical_currentness=technical_currentness)
        paths.extend([
            "material_projection.preplanning_binding",
            "material_projection.technical_framework_validation",
            "material_projection.sufficiency_report",
            "material_projection.technical_currentness",
        ])
        envelope["preplanning_evaluated"] = True
        reports = {"technical_framework": deepcopy(framework),
                   "sufficiency_report": deepcopy(sufficiency),
                   "technical_currentness": deepcopy(technical_currentness)}
        if proposed_projection is not None:
            try:
                json.dumps(proposed_projection, allow_nan=False)
                if canonical_sha256(proposed_projection) != canonical_sha256(projection):
                    return emit("BLOCK", "PREPLANNING_PROJECTION_LOSS_OR_MISMATCH", **reports)
            except (TypeError, ValueError):
                return emit("BLOCK", "PREPLANNING_PROJECTION_INVALID", **reports)
        returns = []
        if framework["status"] != "COMPLETE":
            returns.append("PROJECT_TECHNICAL_AUTHORITY")
        if sufficiency["status"] != "COMPLETE":
            returns.append("ANALYSIS")
        if returns:
            code = ("PREPLANNING_REQUIRES_DECISION" if framework["status"] == "REQUIRES_DECISION"
                    else "PREPLANNING_CONTRADICTION" if sufficiency["status"] == "CONTRADICTION"
                    else "PREPLANNING_INPUTS_INCOMPLETE")
            return emit("BLOCK", code, return_targets=returns, **reports)
        if (technical_currentness.get("ready") is not True
                or technical_currentness.get("decision") not in ("CURRENT", "CURRENT_REBOUND")
                or technical_currentness.get("bounded_validation_required") is not False):
            return emit("BLOCK", "TECHNICAL_CURRENTNESS_NOT_ADMISSIBLE",
                        return_targets=["PROJECT_TECHNICAL_AUTHORITY"], **reports)
        return emit("ACCEPT", "SOURCE_PREPLANNING_STRUCTURE_ACCEPTED",
                    structurally_complete_scope_ids=scopes, return_targets=[],
                    **reports)
