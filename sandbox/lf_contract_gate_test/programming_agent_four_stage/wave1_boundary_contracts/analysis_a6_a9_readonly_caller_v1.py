"""Read-only DECISION_CONTEXT_ASOF caller with optional advisory A6/A9 shadow.

No deployment, profile execution, model call or write adapter. A trusted RO
transport executes one fixed SELECT. Expected context identity comes separately
from the resolver result; verification failures affect only the observation.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import re
from uuid import UUID

from analysis_a6_a9_shadow_v1 import Observation, ShadowDispatch, shadow_after_response_v1

READ_SQL = """
WITH resolved AS MATERIALIZED (
 SELECT public.fn_lf_decision_context_asof_resolve_v1(%s,%s,%s::timestamptz) AS value
)
SELECT jsonb_build_object(
 'resolution',value,
 'transaction_read_only',current_setting('transaction_read_only')='on',
 'recomputed_context_sha256',CASE WHEN value->>'state'='RESOLVED'
   THEN encode(extensions.digest(convert_to((value->'context')::text,'UTF8'),'sha256'),'hex')
   ELSE NULL END
) FROM resolved
"""
HEX64 = re.compile(r"[0-9a-f]{64}")


@dataclass(frozen=True)
class ExpectedContext:
    consumer_code: str
    subject_ref: str
    as_of: str
    context_id: str
    context_sha256: str

    def valid(self):
        try:
            return (
                all(isinstance(v, str) and v.strip() for v in (
                    self.consumer_code, self.subject_ref, self.as_of,
                    self.context_id, self.context_sha256))
                and str(UUID(self.context_id)) == self.context_id
                and HEX64.fullmatch(self.context_sha256) is not None
                and datetime.fromisoformat(self.as_of.replace("Z", "+00:00")).utcoffset() is not None
            )
        except (ValueError, TypeError, AttributeError):
            return False


class SqlReadPort:
    """read_one(sql, params) must use an authorized read-only transaction.

    No DSN/token/env accepted here. The same SELECT returns the server RO flag
    and PostgreSQL's context digest; Python JSON hashing is not substituted.
    """
    def __init__(self, read_one):
        self._read_one = read_one

    def resolve(self, expected):
        return self._read_one(READ_SQL, (
            expected.consumer_code, expected.subject_ref, expected.as_of))


def _advisory(response, state, code):
    return ShadowDispatch(response, Observation({
        "schema_version": "A6_A9_SHADOW_OBSERVATION_V1",
        "state": state, "error_code": code, "advisory_only": True,
        "route_effect_allowed": False, "planning_allowed": False,
        "execution_allowed": False, "operational_admission": False,
        "persistence_allowed": False,
    }))


def observe_resolution_v1(packet, expected, *, enabled=False, timeout_seconds=1.0):
    """Observe an already returned RO SQL packet, never replace its resolution.

    The packet must come from SqlReadPort/the authenticated RO export, not a
    model/user assertion. Identity validation is not operational admission.
    """
    if not isinstance(packet, dict) or "resolution" not in packet:
        raise ValueError("READ_PORT_PACKET_INVALID")
    original = packet["resolution"]
    if enabled is False:
        return _advisory(original, "DISABLED", "SHADOW_DISABLED")
    if enabled is not True:
        return _advisory(original, "INPUT_REJECTED", "SHADOW_ENABLE_INVALID")
    try:
        if not isinstance(expected, ExpectedContext) or not expected.valid():
            return _advisory(original, "INPUT_REJECTED", "EXPECTED_CONTEXT_INVALID")
        if packet.get("transaction_read_only") is not True:
            return _advisory(original, "INPUT_REJECTED", "READ_ONLY_TRANSACTION_UNVERIFIED")
        if not isinstance(original, dict) or original.get("schema_version") != "LF_DECISION_CONTEXT_ASOF_RESOLUTION_V1":
            return _advisory(original, "INPUT_REJECTED", "RESOLUTION_SCHEMA_INVALID")
        if original.get("state") != "RESOLVED":
            return _advisory(original, "SKIPPED_NO_CONTEXT", "RESOLVER_DID_NOT_RESOLVE")
        if original.get("context_id") != expected.context_id:
            return _advisory(original, "INPUT_REJECTED", "EXACT_CONTEXT_ID_MISMATCH")
        if (original.get("context_sha256") != expected.context_sha256
                or packet.get("recomputed_context_sha256") != expected.context_sha256):
            return _advisory(original, "INPUT_REJECTED", "EXACT_CONTEXT_DIGEST_MISMATCH")
        if (original.get("consumer_code") != expected.consumer_code
                or original.get("subject_ref") != expected.subject_ref
                or original.get("latest_reinterpreted") is not False
                or original.get("resolution_basis") != "IMMUTABLE_RECORDED_CONTEXT"):
            return _advisory(original, "INPUT_REJECTED", "RESOLUTION_BINDING_MISMATCH")
        context = original.get("context")
        if (not isinstance(context, dict)
                or context.get("schema_version") != "LF_DECISION_CONTEXT_ASOF_INPUT_V1"
                or context.get("consumer_code") != expected.consumer_code
                or not isinstance(context.get("subject"), dict)
                or context["subject"].get("ref") != expected.subject_ref):
            return _advisory(original, "INPUT_REJECTED", "CONTEXT_BINDING_MISMATCH")
        extensions = context.get("extensions")
        snapshot = extensions.get("programming_context_snapshot") if isinstance(extensions, dict) else None
        if not isinstance(snapshot, dict):
            return _advisory(original, "INPUT_REJECTED", "PROGRAMMING_SNAPSHOT_MISSING")
        a6 = snapshot.get("implementability_schema")
        # Observation identity only. This is NOT an independent A6 attestation.
        from analysis_a6_a9_preview_v1 import canonical_sha256
        result = shadow_after_response_v1(
            original, snapshot, a6, canonical_sha256(a6),
            enabled=True, timeout_seconds=timeout_seconds)
        if not isinstance(result, ShadowDispatch) or result.active_response is not original:
            return _advisory(original, "ERROR", "SHADOW_RESPONSE_REPLACEMENT_REJECTED")
        return result
    except Exception:
        return _advisory(original, "ERROR", "SHADOW_CALLER_FAILED")


class DecisionContextShadowCaller:
    """Explicit manual/RO caller; no hook into the deployed runtime is added."""
    def __init__(self, read_port):
        self._read_port = read_port

    def resolve(self, expected, *, enabled=False, timeout_seconds=1.0):
        if not isinstance(expected, ExpectedContext) or not expected.valid():
            raise ValueError("EXPECTED_CONTEXT_INVALID")
        # Read/transport errors remain base errors. Never retry or convert them
        # to a successful resolution because shadow mode is advisory.
        packet = self._read_port.resolve(expected)
        return observe_resolution_v1(packet, expected, enabled=enabled,
                                     timeout_seconds=timeout_seconds)
