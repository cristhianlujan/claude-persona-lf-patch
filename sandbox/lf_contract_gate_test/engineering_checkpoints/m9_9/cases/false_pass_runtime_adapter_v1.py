"""IG M9.9 FALSO PASS: receipt-bound consumer adapter for the existing RCV core.

Never infer automatic rollback from N9's equal before/after digest alone.
The injected readback MUST query canonical provenance independently of N9.
Mocked readbacks prove contract behaviour only, never real canary closure.
No production activation or evidence issuance.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path
from typing import Any, Callable
RCV_DIR = Path(__file__).resolve().parents[3] / "transversal_assets" / "reversible_candidate_verification"
if str(RCV_DIR) not in sys.path:
    sys.path.insert(0, str(RCV_DIR))
from ig_n9_adapter_v1 import IgN9FlowAdapter
from false_pass_canonical_readback_v1 import CanonicalM99EvidenceReadback
from reversible_candidate_verification_v1 import CandidateIdentity, RollbackContract

SHA256 = re.compile(r"^[0-9a-f]{64}$")

def _obj(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}

def _sha(value: Any) -> bool:
    return isinstance(value, str) and SHA256.fullmatch(value) is not None

class IgM99FalsePassFlowAdapter:
    adapter_code = "IG_M99_FALSE_PASS_FLOW_ADAPTER_V1"

    def __init__(self, n9_runner: Callable, state_digest_probe: Callable[[], str],
                 residue_probe: Callable[[], int],
                 verified_readback: Callable[[CandidateIdentity, dict[str, Any]], dict[str, Any]]):
        self._inner = IgN9FlowAdapter(n9_runner, state_digest_probe, residue_probe)
        self._verified_readback = verified_readback

    def run_rollback_only(self, candidate: CandidateIdentity,
                          rollback: RollbackContract) -> dict[str, Any]:
        meta = _obj(candidate.metadata)
        preflight: list[str] = []
        if not isinstance(self._verified_readback, CanonicalM99EvidenceReadback):
            preflight.append("CANONICAL_DB_READBACK_PROVIDER_REQUIRED")
        if rollback.mutation_policy != "ROLLBACK_ONLY":
            preflight.append("ROLLBACK_ONLY_REQUIRED")
        if not isinstance(meta.get("canary_run_ref"), str) or not meta["canary_run_ref"].strip():
            preflight.append("CANARY_RUN_REF_REQUIRED")
        if not _sha(meta.get("baseline_manifest_sha256")):
            preflight.append("BASELINE_MANIFEST_PIN_REQUIRED")
        if not _sha(candidate.candidate_sha256):
            preflight.append("CANDIDATE_SHA256_INVALID")
        if preflight:
            return {
                "baseline": {}, "candidate": {},
                "rollback": {"status": "UNVERIFIED_AUTOMATIC_ROLLBACK",
                             "post_state_digest": None, "material_residue_count": None},
                "m99_false_pass_proof": {
                    "case_code": "FALSE_PASS", "findings": sorted(set(preflight)),
                    "automatic_rollback_verified": False,
                    "production_authorized": False,
                    "proof_scope": "CONSUMER_ADAPTER_CONTRACT",
                },
            }
        source = self._inner.run_rollback_only(candidate, rollback)
        prior = _obj(source.get("prior_art_receipt"))
        before = _obj(source.get("baseline")).get("state_digest")
        after = _obj(source.get("rollback")).get("post_state_digest")
        residue = _obj(source.get("rollback")).get("material_residue_count")
        meta = _obj(candidate.metadata)
        run_ref = meta.get("canary_run_ref")
        baseline_pin = meta.get("baseline_manifest_sha256")
        failures: list[str] = []
        if rollback.mutation_policy != "ROLLBACK_ONLY":
            failures.append("ROLLBACK_ONLY_REQUIRED")
        if not isinstance(run_ref, str) or not run_ref.strip():
            failures.append("CANARY_RUN_REF_REQUIRED")
        if not _sha(baseline_pin):
            failures.append("BASELINE_MANIFEST_PIN_REQUIRED")
        if not _sha(candidate.candidate_sha256):
            failures.append("CANDIDATE_SHA256_INVALID")

        evidence: dict[str, Any] = {}
        if not failures:
            try:
                evidence = _obj(self._verified_readback(candidate, prior))
            except Exception:
                failures.append("CANONICAL_READBACK_FAILED")
        decision = _obj(evidence.get("canary_gate_readback"))
        oracle = _obj(evidence.get("independent_oracle_readback"))
        action = _obj(evidence.get("rollback_action_readback"))

        if evidence.get("readback_authority") != "CANONICAL_PROVENANCE_DB":
            failures.append("CANONICAL_PROVENANCE_REQUIRED")
        if not (
            decision.get("action") == "ROLLBACK_REQUIRED"
            and decision.get("readback_only") is True
            and "FALSE_PASS" in (decision.get("reason_codes") or [])
            and decision.get("subject_sha256") == meta.get("canary_observation_sha256")
            and _sha(decision.get("receipt_sha256"))
            and isinstance(decision.get("receipt_id"), int)
        ):
            failures.append("VERIFIED_FALSE_PASS_DECISION_MISSING")
        if not (
            oracle.get("verification_status") == "VERIFIED"
            and oracle.get("case_code") == "FALSE_PASS"
            and oracle.get("producer_decision") == "PASS"
            and oracle.get("independent_decision") == "FAIL"
            and oracle.get("independence_state") == "INDEPENDENT"
            and oracle.get("run_ref") == run_ref
            and oracle.get("candidate_sha256") == candidate.candidate_sha256
            and oracle.get("issuer_channel") == "EVIDENCE_VERIFIER_V1"
            and _sha(oracle.get("receipt_sha256"))
            and type(oracle.get("receipt_id")) is int
        ):
            failures.append("INDEPENDENT_LIVE_ORACLE_REQUIRED")
        if not (
            action.get("verification_status") == "VERIFIED"
            and action.get("issuer_channel") == "EVIDENCE_VERIFIER_V1"
            and action.get("case_code") == "FALSE_PASS"
            and action.get("run_ref") == run_ref
            and action.get("candidate_sha256") == candidate.candidate_sha256
            and action.get("baseline_manifest_sha256") == baseline_pin
            and action.get("executed_automatically") is True
            and action.get("rollback_executed") is True
            and action.get("pre_state_digest") == before
            and action.get("post_state_digest") == after
            and action.get("material_residue_count") == 0
            and _sha(action.get("receipt_sha256"))
            and isinstance(action.get("receipt_id"), int)
            and action.get("receipt_id") != decision.get("receipt_id")
            and action.get("receipt_id") != oracle.get("receipt_id")
            and action.get("decision_receipt_id") == decision.get("receipt_id")
            and action.get("oracle_receipt_id") == oracle.get("receipt_id")
        ):
            failures.append("AUTOMATIC_ROLLBACK_RECEIPT_REQUIRED")
        if not (isinstance(before, str) and bool(before)
                and before == after and residue == 0):
            failures.append("POSTSTATE_OR_RESIDUE_MISMATCH")
        identity = _obj(evidence.get("evidence_identity"))
        if not (
            identity.get("read_from") == "programacion.provenance_receipts"
            and identity.get("run_ref") == run_ref
            and identity.get("observation_subject_sha256") == meta.get("canary_observation_sha256")
            and identity.get("baseline_manifest_sha256") == baseline_pin
            and identity.get("receipt_ids") == [
                decision.get("receipt_id"), oracle.get("receipt_id"), action.get("receipt_id")
            ]
        ):
            failures.append("CANONICAL_RECEIPT_IDENTITY_CHAIN_INVALID")
        if prior.get("production_authorized") is True:
            failures.append("UNAUTHORIZED_PRODUCTION_FLAG")

        result = dict(source)
        result["rollback"] = dict(_obj(source.get("rollback")))
        result["rollback"]["status"] = (
            "ROLLED_BACK" if not failures else "UNVERIFIED_AUTOMATIC_ROLLBACK"
        )
        result["m99_false_pass_proof"] = {
            "case_code": "FALSE_PASS",
            "findings": sorted(set(failures)),
            "automatic_rollback_verified": not failures,
            "production_authorized": False,
            "proof_scope": "CONSUMER_ADAPTER_CONTRACT",
            "source": "EXTERNAL_CANONICAL_READBACK_REQUIRED",
        }
        return result
