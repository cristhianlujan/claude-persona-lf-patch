from __future__ import annotations
from typing import Any

class IgN9IndependentOracle:
    oracle_code = "IG_N9_RAW_FLOW_ORACLE_V1"

    def __init__(self, independent_assurance_receipt: dict[str, Any]):
        self.independent_assurance_receipt = independent_assurance_receipt

    def evaluate(self, baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
        b = baseline.get("observation") or {}
        c = candidate.get("observation") or {}
        if not isinstance(b, dict) or not isinstance(c, dict):
            return {"pass":False,"reason":"RAW_OBSERVATION_INVALID"}
        fields = ("assessment_digest","family_count","pass_count","run_status","retry_status")
        drift = [field for field in fields if b.get(field) != c.get(field)]
        candidate_ok = c.get("error") in (None, "") and c.get("family_count") == c.get("pass_count")
        return {"pass":not drift and candidate_ok,"drift":drift,"candidate_ok":candidate_ok}
