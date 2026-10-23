#!/usr/bin/env python3
"""Candidate read-only A9 -> PG-01 boundary; never execution permission.

Trusted ports resolve the recorded context and hydrate currentness inputs.
No caller-supplied 'VALID', 'CURRENT' or guard boolean is an authority input.
C4/C7 and durable handoff persistence remain separate pending gates.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Callable
from uuid import UUID

from validate_wave1_boundary_contracts_v1 import (
    ContractError, validate_handoff_parity, validate_programming_entry,
    validate_programming_snapshot_payload_v1,
)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/material_currentness"))
from lf_currentness_authority_v1 import evaluate_authority
from lf_material_currentness_v1 import canonical_sha256

HEX64 = re.compile(r"^[0-9a-f]{64}$")
SNAPSHOT_SCHEMA = "PROGRAMMING_CONTEXT_SNAPSHOT_V1"
READ_SQL = """
WITH resolved AS MATERIALIZED (
  SELECT programacion.fn_programming_context_resolve_v1(%s,%s,%s::timestamptz) AS value
)
SELECT jsonb_build_object(
  'resolution',value,
  'exact_receipt_valid',programacion.fn_analysis_pg01_exact_receipt_guard_v1(value,%s,%s,%s),
  'snapshot_validation',CASE WHEN value->>'state'='RESOLVED'
    THEN programacion.fn_programming_context_snapshot_validate_v1(value->'context')
    ELSE NULL END
) FROM resolved
"""


@dataclass(frozen=True)
class ExpectedHandoff:
    """Values must originate from admitted A9, independently of the read port."""
    context_id: str
    context_sha256: str
    snapshot_schema_digest_sha256: str
    consumer_code: str
    subject_ref: str
    as_of: str
    snapshot_schema_version: str = SNAPSHOT_SCHEMA

    def valid(self) -> bool:
        try:
            return (
                str(UUID(self.context_id)) == self.context_id
                and bool(HEX64.fullmatch(self.context_sha256))
                and bool(HEX64.fullmatch(self.snapshot_schema_digest_sha256))
                and self.snapshot_schema_version == SNAPSHOT_SCHEMA
                and isinstance(self.consumer_code, str) and bool(self.consumer_code.strip())
                and isinstance(self.subject_ref, str) and bool(self.subject_ref.strip())
                and datetime.fromisoformat(self.as_of.replace("Z", "+00:00")).utcoffset() is not None
            )
        except (ValueError, TypeError, AttributeError):
            return False


class SqlReadPort:
    """One fixed SELECT, parameterized by a trusted read-only query adapter.

    The adapter must use a read-only connection/transaction. No URLs, keys or
    record/write operation are accepted by this component.
    """
    def __init__(self, query: Callable[[str, tuple], dict]):
        self._query = query

    def read(self, expected: ExpectedHandoff) -> dict:
        return self._query(READ_SQL, (
            expected.consumer_code, expected.subject_ref, expected.as_of,
            expected.context_id, expected.context_sha256,
            expected.snapshot_schema_version,
        ))


class CanonicalCurrentnessPort:
    """Adapter to the existing engine, not a second currentness classifier.

    Provider hydrates bound/current material evidence from trusted sources.
    A dict from the caller is never accepted as a ready/current decision.
    Provider provenance is a separate operational admission requirement.
    """
    def __init__(self, repo: Path, provider: Callable[[ExpectedHandoff, str], dict]):
        self._repo, self._provider = repo, provider

    def evaluate(self, expected: ExpectedHandoff, snapshot: dict, scope_id: str) -> dict:
        packet = deepcopy(self._provider(expected, scope_id))
        if not isinstance(packet, dict) or packet.get("context_id") != expected.context_id or packet.get("context_sha256") != expected.context_sha256 or packet.get("scope_id") != scope_id:
            return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": "CURRENTNESS_SUBJECT_MISMATCH"}
        binding = packet.get("binding")
        if not isinstance(binding, dict):
            return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": "CURRENTNESS_BINDING_MISSING"}
        expected_materials = {
            "context": expected.context_sha256,
            "snapshot_schema": expected.snapshot_schema_digest_sha256,
            "snapshot_authority": snapshot["authority_fingerprint_sha256"],
            "snapshot_source": snapshot["source_snapshot_sha256"],
        }
        materials = binding.get("materials")
        if not isinstance(materials, list) or any(not isinstance(row, dict) for row in materials):
            return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": "CURRENTNESS_MATERIALS_MISSING"}
        by_id = {row.get("material_id"): row for row in materials}
        if len(by_id) != len(materials) or not set(expected_materials).issubset(binding.get("root_material_ids") or []):
            return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": "CURRENTNESS_ROOTS_INCOMPLETE"}
        for name, digest in expected_materials.items():
            row = by_id.get(name) or {}
            if row.get("kind") != "DIGEST" or row.get("bound_digest") != digest:
                return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": "CURRENTNESS_MATERIAL_BINDING_MISMATCH:" + name}
        if binding.get("contract_identity") != SNAPSHOT_SCHEMA + ":" + expected.snapshot_schema_digest_sha256 or binding.get("implementation_binding") != "PG-01:" + scope_id:
            return {"ready": False, "decision": "UNKNOWN_FAIL_CLOSED", "reason": "CURRENTNESS_CONTRACT_BINDING_MISMATCH"}
        result = evaluate_authority(binding, self._repo)
        # These are snapshot contract invariants, stricter than compatibility.
        for name in ("context", "snapshot_schema", "snapshot_authority"):
            if by_id[name].get("current_digest") != expected_materials[name]:
                return {**result, "ready": False, "reason": "SNAPSHOT_REBUILD_REQUIRED:" + name}
        return result


class ReadOnlyReceiver:
    def __init__(self, reader: SqlReadPort, currentness: CanonicalCurrentnessPort):
        self._reader, self._currentness = reader, currentness
        entry_bytes = (HERE / "programming_entry_contract_v1.json").read_bytes()
        self._entry = json.loads(entry_bytes)
        self._parity = json.loads((HERE / "analysis_programming_handoff_parity_contract_v1.json").read_text())
        validate_programming_entry(self._entry)
        validate_handoff_parity(self._parity)
        self.contract_digest = hashlib.sha256(entry_bytes).hexdigest()

    def consume(self, expected: ExpectedHandoff, scope_id: str, *, proposed_projection: dict | None = None) -> dict:
        """Return a boundary result; C4/C7 remain pending even on ACCEPT.

        No persistent cache: every call reuses exact bounded inputs/ports, with
        no discovery. No timestamps or random IDs in the resulting receipt.
        """
        evidence = {
            "schema_version": "PG01_READ_ONLY_BOUNDARY_RESULT_V1",
            "scope_id": scope_id,
            "execution_allowed": False,
            "pending_gates": ["PG-01_C4", "PG-01_C7", "PG-01_C6_PERSISTENCE"],
            "admission_level": "SOURCE_ONLY_READ_ONLY_BOUNDARY",
        }

        def blocked(code: str, receipt=None, **extra):
            return {**evidence, "state": "BLOCK", "code": code, "receipt": receipt, **extra}

        if not isinstance(expected, ExpectedHandoff) or not expected.valid():
            return blocked("EXPECTED_HANDOFF_INVALID_OR_MISSING")
        if not isinstance(scope_id, str) or not scope_id.strip():
            return blocked("REQUESTED_SCOPE_MISSING")
        if expected.snapshot_schema_digest_sha256 != self.contract_digest:
            return blocked("HANDOFF_SCHEMA_DIGEST_MISMATCH")
        try:
            readback = self._reader.read(expected)
        except Exception as exc:
            return blocked("READ_PORT_UNAVAILABLE", error_type=type(exc).__name__)
        if not isinstance(readback, dict):
            return blocked("READ_PORT_RESULT_INVALID")
        resolved = readback.get("resolution")
        if not isinstance(resolved, dict) or resolved.get("state") != "RESOLVED":
            diagnostic = resolved if isinstance(resolved, dict) else {}
            return blocked("CONTEXT_NOT_RESOLVED", upstream_code=diagnostic.get("code"), validation=diagnostic.get("validation"))
        if readback.get("exact_receipt_valid") is not True or resolved.get("context_id") != expected.context_id or resolved.get("context_sha256") != expected.context_sha256:
            return blocked("EXACT_RECEIPT_MISMATCH")
        if resolved.get("consumer_code") != expected.consumer_code or resolved.get("subject_ref") != expected.subject_ref:
            return blocked("CONTEXT_SUBJECT_MISMATCH")
        validation = readback.get("snapshot_validation")
        if not isinstance(validation, dict) or validation.get("state") != "VALID":
            return blocked("SNAPSHOT_SQL_VALIDATION_FAILED", validation=validation)
        context = resolved.get("context")
        if not isinstance(context, dict) or not isinstance(context.get("extensions"), dict):
            return blocked("RESOLVED_CONTEXT_INVALID")
        snapshot = deepcopy(context["extensions"].get("programming_context_snapshot"))
        if not isinstance(snapshot, dict):
            return blocked("SNAPSHOT_MISSING")
        required = {key.removesuffix("[]") for key in self._entry["programming_context_snapshot"]["required_fields"]}
        if not required.issubset(snapshot) or set(snapshot) - required - {"schema_version", "human_decision_queue"}:
            return blocked("SNAPSHOT_MATERIAL_FIELDS_MISSING_OR_UNKNOWN")
        if snapshot.get("snapshot_schema_digest_sha256") != self.contract_digest:
            return blocked("PRODUCER_RECEIVER_SCHEMA_DIGEST_MISMATCH")
        try:
            validate_programming_snapshot_payload_v1(snapshot)
        except (ContractError, TypeError, KeyError, ValueError, AttributeError) as exc:
            return blocked("SNAPSHOT_PYTHON_VALIDATION_FAILED", validation_code=str(exc))
        # Conservative identity projection: all material data is preserved. It is
        # not yet a context-budgeted Worker projection or a parallel snapshot.
        projection = {"scope_id": scope_id, "snapshot": deepcopy(snapshot)}
        paths = sorted("extensions.programming_context_snapshot." + key for key in required)

        def receipt(verdict: str):
            return {
                "schema_version": "PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1",
                "context_id": expected.context_id,
                "context_sha256": expected.context_sha256,
                "snapshot_schema_digest_sha256": snapshot["snapshot_schema_digest_sha256"],
                "receiver_schema_digest_sha256": self.contract_digest,
                "material_projection_sha256": canonical_sha256(projection),
                "validated_material_paths": paths,
                "verdict": verdict,
            }

        def reject_identified(code: str, **extra):
            return blocked(code, receipt("BLOCK"), material_projection=projection, **extra)

        if proposed_projection is not None:
            try:
                if canonical_sha256(proposed_projection) != canonical_sha256(projection):
                    return reject_identified("MATERIAL_PROJECTION_LOSS_OR_MISMATCH")
            except (TypeError, ValueError):
                return reject_identified("MATERIAL_PROJECTION_INVALID")
        scopes = {row["scope_id"]: row for row in snapshot["scope_readiness"]}
        if not any(row["status"] == "READY" for row in scopes.values()):
            return reject_identified("NO_READY_SCOPE")
        if snapshot.get("package_readiness") not in self._entry["admission"]["allowed_analysis_verdicts"]:
            return reject_identified("PACKAGE_NOT_ADMISSIBLE")
        if scope_id not in scopes or scopes[scope_id]["status"] != "READY":
            return reject_identified("REQUESTED_SCOPE_NOT_READY_OR_UNKNOWN")
        closure, pending = set(), [scope_id]
        while pending:
            sid = pending.pop()
            if sid in closure:
                continue
            if sid not in scopes or scopes[sid]["status"] != "READY" or scopes[sid].get("blockers"):
                return reject_identified("SCOPE_DEPENDENCY_NOT_READY")
            closure.add(sid)
            pending.extend(scopes[sid]["depends_on_scope_ids"])
        if any(row["scope_id"] in closure and row["effect_on_scope"] == "BLOCKS" for row in snapshot["scope_front_matrix"]):
            return reject_identified("SCOPE_HAS_BLOCKING_FRONT")
        try:
            currentness = self._currentness.evaluate(expected, snapshot, scope_id)
        except Exception as exc:
            return reject_identified("CURRENTNESS_UNAVAILABLE", error_type=type(exc).__name__)
        if currentness.get("ready") is not True or currentness.get("decision") not in ("CURRENT", "CURRENT_REBOUND"):
            return reject_identified("CURRENTNESS_NOT_ADMISSIBLE", currentness=currentness)
        if currentness.get("bounded_validation_required") is True:
            return reject_identified("BOUNDED_VALIDATION_REQUIRED", currentness=currentness)
        return {**evidence, "state": "ACCEPT", "code": "READ_ONLY_BOUNDARY_ACCEPTED", "receipt": receipt("ACCEPT"), "material_projection": projection, "admitted_scope_ids": sorted(closure), "currentness": currentness}
