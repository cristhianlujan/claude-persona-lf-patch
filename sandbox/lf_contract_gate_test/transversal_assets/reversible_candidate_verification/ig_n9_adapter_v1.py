from __future__ import annotations
from typing import Any, Callable
from reversible_candidate_verification_v1 import CandidateIdentity, RollbackContract

class IgN9FlowAdapter:
    adapter_code = "IG_N9_FLOW_ADAPTER_V1"
    def __init__(self, n9_runner: Callable[[CandidateIdentity], dict[str, Any]], state_digest_probe: Callable[[], str], residue_probe: Callable[[], int]):
        self._n9_runner = n9_runner
        self._state_digest_probe = state_digest_probe
        self._residue_probe = residue_probe
    def run_rollback_only(self, candidate: CandidateIdentity, rollback: RollbackContract) -> dict[str, Any]:
        before = self._state_digest_probe()
        n9 = self._n9_runner(candidate)
        after = self._state_digest_probe()
        return {
            "baseline":{"state_digest":before,"observation":n9.get("baseline"),"n9_verdict":n9.get("verdict")},
            "candidate":{"state_digest":n9.get("candidate_state_digest") or before,"observation":n9.get("candidate"),"n9_findings":n9.get("findings",[])},
            "rollback":{"status":"ROLLED_BACK" if after == before else "ROLLBACK_DRIFT","post_state_digest":after,"material_residue_count":int(self._residue_probe())},
            "prior_art_capability":"IG_RUNTIME_CANDIDATE_JUDGE",
            "prior_art_receipt":n9,
        }

class IgN9IndependentOracle:
    oracle_code = "IG_N9_RAW_FLOW_ORACLE_V1"
    def evaluate(self, baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
        b = baseline.get("observation") or {}
        c = candidate.get("observation") or {}
        if not isinstance(b, dict) or not isinstance(c, dict):
            return {"pass":False,"reason":"RAW_OBSERVATION_INVALID"}
        fields = ("assessment_digest","family_count","pass_count","run_status","retry_status")
        drift = [field for field in fields if b.get(field) != c.get(field)]
        candidate_ok = c.get("error") in (None, "") and c.get("family_count") == c.get("pass_count")
        return {"pass":not drift and candidate_ok,"drift":drift,"candidate_ok":candidate_ok}
