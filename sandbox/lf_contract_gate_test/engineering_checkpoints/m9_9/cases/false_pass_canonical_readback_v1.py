"""Canonical read-only M9.9 evidence consumer.

Reads ONLY authorized Supabase provenance rows; it neither emits receipts nor
executes the canary. It fails closed when a stage, pin or issuer is missing.
A caller-supplied 'verified' dict has no standing at this boundary.
"""
from __future__ import annotations

import re
import uuid
from typing import Any

SHA = re.compile(r"^[0-9a-f]{64}$")
STAGES = ("OBSERVATION", "INDEPENDENT_ORACLE", "ROLLBACK_ACTION")
SCHEMA = "IG_CANARY_OBSERVATION_V1"


class CanonicalM99EvidenceReadback:
    """Requires a dedicated DB transaction-capable connection, no secret storage."""

    def __init__(self, connection: Any):
        if connection is None or getattr(connection, "autocommit", True) is not False:
            raise ValueError("M99_READONLY_TRANSACTIONAL_CONNECTION_REQUIRED")
        self._connection = connection

    def __call__(self, candidate: Any, prior: dict[str, Any]) -> dict[str, Any]:
        meta = candidate.metadata if isinstance(candidate.metadata, dict) else {}
        cohort = meta.get("cohort_type_code")
        run_ref = meta.get("canary_run_ref")
        observation_sha = meta.get("canary_observation_sha256")
        baseline_sha = meta.get("baseline_manifest_sha256")
        ids = (meta.get("canary_observation_receipt_id"),
               meta.get("canary_oracle_receipt_id"),
               meta.get("canary_rollback_receipt_id"))
        if (not isinstance(cohort, str) or not cohort.strip()
            or not isinstance(run_ref, str) or not run_ref.strip()
            or not isinstance(observation_sha, str) or not SHA.fullmatch(observation_sha)
            or not isinstance(baseline_sha, str) or not SHA.fullmatch(baseline_sha)
            or len(set(ids)) != 3 or any(type(v) is not int or v <= 0 for v in ids)):
            raise ValueError("M99_RECEIPT_SELECTOR_OR_PIN_INVALID")

        records: list[dict[str, Any]] = []
        connection = self._connection
        try:
            with connection.cursor() as cur:
                cur.execute("SET TRANSACTION READ ONLY")
                for receipt_id, expected_stage in zip(ids, STAGES):
                    cur.execute(
                        """SELECT id,receipt_kind,subject_type,subject_ref,
                                  subject_sha256,receipt_sha256,issuer_channel,
                                  head_sha,payload
                           FROM programacion.provenance_receipts WHERE id=%s""",
                        (receipt_id,),
                    )
                    row = cur.fetchone()
                    if row is None:
                        raise ValueError("M99_CANONICAL_RECEIPT_NOT_FOUND")
                    if isinstance(row, dict):
                        item = row
                    else:
                        cols = ("id","receipt_kind","subject_type","subject_ref",
                                "subject_sha256","receipt_sha256","issuer_channel",
                                "head_sha","payload")
                        item = dict(zip(cols,row))
                    payload = item.get("payload")
                    if not isinstance(payload, dict):
                        raise ValueError("M99_CANONICAL_PAYLOAD_INVALID")
                    if not (
                        item["id"] == receipt_id
                        and item["receipt_kind"] == "EVIDENCE_VERIFICATION"
                        and item["subject_type"] == "IG_CANARY_OBSERVATION"
                        and item["subject_ref"] == "IG_CANARY:" + cohort
                        and item["issuer_channel"] == "EVIDENCE_VERIFIER_V1"
                        and isinstance(item["receipt_sha256"],str)
                        and SHA.fullmatch(item["receipt_sha256"])
                        and payload.get("schema_version") == SCHEMA
                        and payload.get("verification_status") == "VERIFIED"
                        and isinstance(payload.get("verifier_identity"),str)
                        and bool(payload["verifier_identity"].strip())
                        and payload.get("stage") == expected_stage
                        and payload.get("run_ref") == run_ref
                        and payload.get("cohort_type_code") == cohort
                        and payload.get("baseline_manifest_sha256") == baseline_sha
                        and payload.get("candidate_sha256") == candidate.candidate_sha256
                        and payload.get("head_sha") == item["head_sha"]
                        and payload.get("subject_sha256") == item["subject_sha256"]
                    ):
                        raise ValueError("M99_RECEIPT_IDENTITY_OR_ISSUER_DRIFT")
                    records.append(item)

                if records[0]["subject_sha256"] != observation_sha:
                    raise ValueError("M99_OBSERVATION_SUBJECT_SHA_DRIFT")
                cur.execute(
                    """SELECT programacion.fn_ig_m99_canary_receipt_gate_v1(
                           %s,%s,%s)""", (ids[0],observation_sha,cohort)
                )
                decision_row = cur.fetchone()
                decision = next(iter(decision_row.values())) if isinstance(decision_row,dict) else decision_row[0]
                if not isinstance(decision,dict) or decision.get("receipt_id") != ids[0]:
                    raise ValueError("M99_RECEIPT_GATE_NOT_PROVEN")

                # The independent verdict must use the CURRENT governed
                # independent-assurance asset, not a free-text INDEPENDENT flag.
                measure = records[1]["payload"].get("independent_oracle")
                if not isinstance(measure,dict):
                    raise ValueError("M99_INDEPENDENT_ASSURANCE_BINDING_MISSING")
                cur.execute(
                    """SELECT version,manifest_sha256 FROM public.lf_capability_current
                       WHERE capability_code=%s""",
                    ("INDEPENDENT_ASSURANCE",),
                )
                current = cur.fetchone()
                if isinstance(current,dict):
                    ver,manifest = current.get("version"),current.get("manifest_sha256")
                elif current is not None:
                    ver,manifest = current
                else:
                    ver,manifest = None,None
                if not (
                    ver == "2.0.1" and isinstance(manifest,str)
                    and SHA.fullmatch(manifest)
                    and measure.get("independent_assurance_capability_code") == "INDEPENDENT_ASSURANCE"
                    and measure.get("independent_assurance_version") == ver
                    and measure.get("independent_assurance_manifest_sha256") == manifest
                    and isinstance(measure.get("measurement_ref"),str)
                    and bool(measure["measurement_ref"].strip())
                ):
                    raise ValueError("M99_INDEPENDENT_ASSURANCE_NOT_CURRENT_OR_UNATTESTED")
                # Do not infer independence from a field inside a canary receipt.
                # Resolve the separately issued reviewer output in Evidence Ledger.
                review_ref = measure.get("review_receipt_id")
                try:
                    review_id = str(uuid.UUID(review_ref))
                except (TypeError, ValueError, AttributeError):
                    raise ValueError("M99_INDEPENDENT_REVIEW_LEDGER_ID_REQUIRED")
                cur.execute(
                    """SELECT receipt_id,receipt_sha256,subject_type,subject_ref,
                              subject_sha256,source_head_sha,capability_code,
                              verification_state,execution_id,receipt_payload
                       FROM private.lf_evidence_ledger_v1
                       WHERE receipt_id=%s::uuid""",
                    (review_id,),
                )
                review_row = cur.fetchone()
                cols = ("receipt_id","receipt_sha256","subject_type","subject_ref",
                        "subject_sha256","source_head_sha","capability_code",
                        "verification_state","execution_id","receipt_payload")
                review = (review_row if isinstance(review_row,dict)
                          else dict(zip(cols,review_row)) if review_row is not None else {})
                review_body = review.get("receipt_payload")
                review_body = review_body if isinstance(review_body,dict) else {}
                independence = review_body.get("independence_measure")
                independence = independence if isinstance(independence,dict) else {}
                producer_id = review_body.get("producer_execution_id")
                reviewer_id = review_body.get("reviewer_identity")
                if not (
                    str(review.get("receipt_id")) == review_id
                    and review.get("capability_code") == "INDEPENDENT_ASSURANCE"
                    and review.get("verification_state") == "VERIFIED"
                    and review.get("subject_type") == "IG_CANARY_OBSERVATION"
                    and review.get("subject_ref") == "IG_CANARY:" + cohort
                    and review.get("subject_sha256") == observation_sha
                    and review.get("source_head_sha") == records[0]["head_sha"]
                    and review.get("receipt_sha256") == measure.get("review_receipt_sha256")
                    and isinstance(producer_id,str) and bool(producer_id.strip())
                    and isinstance(reviewer_id,str) and bool(reviewer_id.strip())
                    and reviewer_id != producer_id
                    and independence.get("state") == "INDEPENDENT"
                    and review_body.get("run_ref") == run_ref
                    and review_body.get("candidate_sha256") == candidate.candidate_sha256
                ):
                    raise ValueError("M99_INDEPENDENT_REVIEW_NOT_PROVIDER_BOUND")

        finally:
            connection.rollback()  # Always leave even the readback transaction closed.

        observation,oracle,action = (r["payload"] for r in records)
        # Decision is returned from the current DB gate, never from client input.
        independent = dict(oracle.get("independent_oracle",{}))
        rollback = dict(action.get("rollback_action",{}))
        independent.update(receipt_id=ids[1],receipt_sha256=records[1]["receipt_sha256"],
                           issuer_channel=records[1]["issuer_channel"])
        rollback.update(receipt_id=ids[2],receipt_sha256=records[2]["receipt_sha256"],
                        issuer_channel=records[2]["issuer_channel"])
        return {
            "readback_authority": "CANONICAL_PROVENANCE_DB",
            "canary_gate_readback": decision,
            "independent_oracle_readback": independent,
            "rollback_action_readback": rollback,
            "evidence_identity": {
                "read_from": "programacion.provenance_receipts",
                "receipt_ids": list(ids),
                "run_ref": run_ref,
                "cohort_type_code": cohort,
                "observation_subject_sha256": observation_sha,
                "baseline_manifest_sha256": baseline_sha,
            },
        }
