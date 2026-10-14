"""Pure candidate checks for optional Profile Evolution math methods.

No selector replacement, model invocation, DB access, admission, or runtime activation.
Probability outputs require explicit calibration reference. All numerical metrics
are observations; result values cannot prove domain expertise or independence.
"""
from __future__ import annotations

from math import isfinite, log2
from typing import Any


def _prob(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) or not 0 <= value <= 1:
        raise ValueError("PROBABILITY_INVALID")
    return float(value)


def _calibrated(calibration_ref: str) -> None:
    if not isinstance(calibration_ref, str) or not calibration_ref.strip():
        raise ValueError("CALIBRATION_REF_REQUIRED")


def bayesian_posterior(*, prior: float, p_e_given_h: float, p_e_given_not_h: float,
                       calibration_ref: str) -> float:
    """Posterior for one calibrated binary observation; never invent priors."""
    _calibrated(calibration_ref)
    p = _prob(prior)
    l_h = _prob(p_e_given_h)
    l_n = _prob(p_e_given_not_h)
    evidence_probability = p * l_h + (1 - p) * l_n
    if evidence_probability == 0:
        raise ValueError("ZERO_PROBABILITY_EVIDENCE")
    return p * l_h / evidence_probability


def _entropy(p: float) -> float:
    p = _prob(p)
    return -(p * log2(p) if p else 0) - ((1-p) * log2(1-p) if p < 1 else 0)


def expected_information_gain(*, prior: float, likelihood_by_outcome: list[tuple[float, float]],
                              calibration_ref: str) -> float:
    """Expected entropy reduction for a calibrated candidate observation."""
    _calibrated(calibration_ref)
    p = _prob(prior)
    if not likelihood_by_outcome:
        raise ValueError("OUTCOMES_MISSING")
    likelihood = [(_prob(a), _prob(b)) for a, b in likelihood_by_outcome]
    if abs(sum(a for a, _ in likelihood) - 1) > 1e-9 or abs(sum(b for _, b in likelihood) - 1) > 1e-9:
        raise ValueError("OUTCOME_DISTRIBUTIONS_INVALID")
    expected = 0.0
    for a, b in likelihood:
        evidence_probability = p*a + (1-p)*b
        if evidence_probability:
            posterior = p*a/evidence_probability
            expected += evidence_probability*_entropy(posterior)
    return max(0.0, _entropy(p)-expected)  # only roundoff may be negative


def pareto_frontier(candidates: list[dict[str, Any]]) -> list[str]:
    """Return nondominated candidates, not a selected method or permission.

    Quality higher is better; observed cost, latency and regression risk lower.
    """
    required = ("quality", "cost", "latency", "risk")
    if not candidates:
        raise ValueError("CANDIDATES_MISSING")
    ids = [row.get("id") for row in candidates]
    if any(not isinstance(i, str) or not i for i in ids) or len(set(ids)) != len(ids):
        raise ValueError("CANDIDATE_ID_INVALID")
    vec = []
    for row in candidates:
        if any(k not in row or isinstance(row[k], bool) or not isinstance(row[k], (int, float))
               or not isfinite(row[k]) for k in required):
            raise ValueError("OBSERVED_METRIC_MISSING")
        if not 0 <= row["quality"] <= 1 or any(row[k] < 0 for k in ("cost", "latency", "risk")):
            raise ValueError("OBSERVED_METRIC_INVALID")
        vec.append((row["quality"], -row["cost"], -row["latency"], -row["risk"]))
    return [ids[i] for i, v in enumerate(vec) if not any(
        all(x >= y for x, y in zip(u, v)) and any(x > y for x, y in zip(u, v))
        for j, u in enumerate(vec) if j != i)]


def next_probe_required(previous_evidence_refs: list[str], proposed_evidence_refs: list[str]) -> bool:
    """Cheap duplicate-read guard. Does not itself prove evidence sufficiency."""
    if not all(isinstance(x, str) and x.strip() for x in previous_evidence_refs + proposed_evidence_refs):
        raise ValueError("EVIDENCE_REF_INVALID")
    return bool(set(proposed_evidence_refs) - set(previous_evidence_refs))
