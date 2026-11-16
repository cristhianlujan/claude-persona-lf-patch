"""Pure OFFLINE audit helpers. These do not grant permissions or execute effects.

Authority snapshots must be resolved by the auditing model from current sources.
A caller-provided verified flag is not independent verification of real authority.
"""
from __future__ import annotations

import hashlib
import json
import re

SHA = re.compile(r"[0-9a-f]{64}")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(",", ":")).encode("utf8")).hexdigest()


def assess_authorization(evaluation, policy, evidence):
    """Derive the expected decision UNDER the supplied, already-resolved policy."""
    blocks = []
    valid = (evaluation.get("context_pass") is True and evaluation.get("spec_pass") is True
             and evaluation.get("eval_pass") is True and bool(evaluation.get("evidence_refs")))
    independent = (evidence.get("independence_verified") is True
                   and evidence.get("isolated_context_verified") is True
                   and bool(evidence.get("independence_ref")))
    if not valid:
        blocks.append("EVALUATION_NOT_VALID")
    if (policy.get("verified") is not True or policy.get("current") is not True
            or not policy.get("source_ref") or not policy.get("version")
            or not isinstance(policy.get("sha256"), str) or not SHA.fullmatch(policy["sha256"])
            or type(policy.get("requires_independence")) is not bool
            or type(policy.get("allow_contextual")) is not bool
            or policy.get("effect") not in ("REQUEST_PROMOTION", "APPROVE_PROMOTION", "APPLY_PROMOTION")):
        blocks.append("AUTHORITY_NOT_VERIFIED_CURRENT")
    for key in ("actor", "object_id", "scope_sha256", "effect"):
        if not policy.get(key) or policy.get(key) != evidence.get(key):
            blocks.append("AUTHORITY_BINDING_MISMATCH:" + key)
    if policy.get("requires_independence") is True and not independent:
        blocks.append("INDEPENDENCE_REQUIRED_BY_CONTRACT")
    elif not independent and policy.get("allow_contextual") is not True:
        blocks.append("CONTEXTUAL_REVIEW_NOT_ADMITTED")
    if evidence.get("material_blockers") != []:
        blocks.append("MATERIAL_BLOCKERS_UNRESOLVED")
    return {"evaluation_valid": valid,
            "independence_status": "PROVEN" if independent else "NOT_PROVEN",
            "promotion_authorized": not blocks, "effect": policy.get("effect"),
            "policy_ref": policy.get("source_ref"), "blocking_codes": blocks,
            "assessment_only": True}


def assess_step(required_inputs, provided, required_outputs, output):
    missing_inputs = sorted(set(required_inputs) - set(provided))
    missing_outputs = sorted(set(required_outputs) - set(output if isinstance(output, dict) else {}))
    return {"missing_inputs": missing_inputs, "missing_outputs": missing_outputs,
            "code": "STEP_CONTEXT_INSUFFICIENT" if missing_inputs else
                    "OUTPUT_NOT_ACTIONABLE" if missing_outputs else "SUFFICIENT"}


def data_strategy(*, repeated_reads, stable_scope, immediate_freshness, invalidation_proven,
                  security_equivalent, equivalence_proven, measured_operations_saved):
    if immediate_freshness:
        return {"recommendation": "KEEP_LIVE_READ", "materialization_admissible": False,
                "reason": "Immediate freshness takes precedence over read reduction"}
    suitable = (repeated_reads > 1 and stable_scope and invalidation_proven
                and security_equivalent and equivalence_proven and measured_operations_saved > 0)
    return {"recommendation": "SNAPSHOT_CANDIDATE" if suitable else "MEASURE_OR_KEEP_CURRENT",
            "materialization_admissible": False,
            "reason": "Snapshot is optional; no materialized view without a refresh/freshness contract"}


def snapshot(payload, *, run_id, tenant, object_id, source_revision, authority_sha256):
    if (not all(isinstance(x, str) and x.strip() for x in (run_id, tenant, object_id, source_revision))
            or not isinstance(authority_sha256, str) or not SHA.fullmatch(authority_sha256)):
        raise ValueError("SNAPSHOT_REQUIRED_IDENTITY_MISSING")
    body = {"run_id": run_id, "tenant": tenant, "object_id": object_id,
            "source_revision": source_revision, "authority_sha256": authority_sha256,
            "payload": payload}
    # JSON roundtrip prevents caller mutation; check hash again on each read.
    copy = json.loads(json.dumps(body))
    return {"body": copy, "sha256": digest(copy)}


def read_snapshot(value, *, run_id, tenant, object_id, source_revision, authority_sha256):
    body = value["body"]
    if value["sha256"] != digest(body):
        raise ValueError("SNAPSHOT_HASH_MISMATCH")
    expected = {"run_id": run_id, "tenant": tenant, "object_id": object_id,
                "source_revision": source_revision, "authority_sha256": authority_sha256}
    for key, wanted in expected.items():
        if body.get(key) != wanted:
            raise ValueError("SNAPSHOT_IDENTITY_OR_CURRENTNESS_MISMATCH:" + key)
    return json.loads(json.dumps(body["payload"]))
