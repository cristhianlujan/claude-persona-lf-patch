#!/usr/bin/env python3
"""Development reference ONLY for T-REMED scope proposal triage.

Not an LF runtime function, a rule engine, or an authority to promote rules.
No database access, no hardcoded rule IDs, no activation, no API calls.
Three independently evidenced 0..2 criteria; selector evaluation remains N-4.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Sequence

CRITERIA = ("semantic_reuse", "conditional_scope", "authority_evidence")


@dataclass(frozen=True)
class ScopeProposal:
    hypothesis: str
    selector_proposal: Mapping[str, Any]  # UNAPPROVED: never consumed by N-4
    scores: Mapping[str, int]
    evidence: Mapping[str, Sequence[str]]
    hard_conflicts: Sequence[str] = ()


def _validate(proposal: ScopeProposal) -> tuple[int, list[str]]:
    problems: list[str] = []
    if not proposal.hypothesis.strip():
        problems.append("MISSING_HYPOTHESIS")
    if not isinstance(proposal.selector_proposal, Mapping) or not proposal.selector_proposal:
        problems.append("MISSING_SELECTOR_PROPOSAL")
    total = 0
    for criterion in CRITERIA:
        value = proposal.scores.get(criterion)
        if type(value) is not int or not (0 <= value <= 2):
            problems.append("INVALID_SCORE:" + criterion)
        else:
            total += value
        refs = proposal.evidence.get(criterion)
        if not isinstance(refs, (list, tuple)) or not refs or not all(
            isinstance(ref, str) and ref.strip() for ref in refs
        ):
            problems.append("MISSING_EVIDENCE:" + criterion)
    unknown = set(proposal.scores) - set(CRITERIA)
    if unknown:
        problems.append("UNKNOWN_CRITERIA")
    return total, problems


def triage(
    proposals: Sequence[ScopeProposal],
    *,
    ready_floor: int = 5,
    minimum_gap: int = 2,
) -> dict[str, Any]:
    """Result is advisory. No score, even 6/6, may activate a selector.

    Tunable parameters are dev-only calibration candidates, not approved
    thresholds or estimated probabilities of correctness.
    """
    if not (0 <= ready_floor <= 6 and 0 <= minimum_gap <= 6):
        raise ValueError("Invalid calibration range")
    if not proposals:
        return {"status": "HUMAN_REQUIRED", "reason": "NO_PROPOSALS", "ranks": []}
    rankings: list[dict[str, Any]] = []
    for proposal in proposals:
        total, problems = _validate(proposal)
        rankings.append({
            "hypothesis": proposal.hypothesis,
            "score": total,
            "problems": problems,
            "hard_conflicts": list(proposal.hard_conflicts),
            "selector_authorized": False,
        })
    rankings.sort(key=lambda r: (-r["score"], r["hypothesis"]))
    if any(item["hard_conflicts"] for item in rankings):
        return {"status": "BLOCKED_CONFLICT", "reason": "POLICY_OR_AUTHORITY_VETO", "ranks": rankings}
    if any(item["problems"] for item in rankings):
        return {"status": "HUMAN_REQUIRED", "reason": "INVALID_OR_MISSING_EVIDENCE", "ranks": rankings}
    first = rankings[0]
    second = rankings[1] if len(rankings) > 1 else None
    if second and first["score"] == second["score"]:
        return {"status": "HUMAN_REQUIRED", "reason": "TIE", "ranks": rankings}
    if second and first["score"] - second["score"] < minimum_gap:
        return {"status": "HUMAN_REQUIRED", "reason": "CLOSE_SCORES", "ranks": rankings}
    if first["score"] < ready_floor:
        return {"status": "HUMAN_REQUIRED", "reason": "WEAK_SUPPORT", "ranks": rankings}
    return {
        "status": "PROPOSAL_READY_FOR_GOVERNANCE_REVIEW",
        "reason": "EVIDENCE_SUFFICIENT_FOR_REVIEW_NOT_AUTHORIZATION",
        "ranks": rankings,
    }


def _sample(name: str, score: tuple[int, int, int],
            *, conflict: bool = False, missing: bool = False) -> ScopeProposal:
    return ScopeProposal(
        hypothesis=name,
        selector_proposal={"all": [{"path": ["target", "module", "module_code"], "op": "EXISTS"}]},
        scores=dict(zip(CRITERIA, score)),
        evidence={
            key: ([] if missing and key == "conditional_scope" else ["ekb://evidence/" + key])
            for key in CRITERIA
        },
        hard_conflicts=("POLICY_SECURITY_CONFLICT",) if conflict else (),
    )


def selftest() -> None:
    assert triage([_sample("contextual", (2, 2, 2)), _sample("local", (1, 1, 1))])["status"] == "PROPOSAL_READY_FOR_GOVERNANCE_REVIEW"
    assert triage([_sample("contextual", (2, 1, 2)), _sample("local", (2, 1, 2))])["reason"] == "TIE"
    assert triage([_sample("contextual", (2, 2, 2)), _sample("local", (2, 2, 1))])["reason"] == "CLOSE_SCORES"
    assert triage([_sample("contextual", (1, 1, 2))])["reason"] == "WEAK_SUPPORT"
    assert triage([_sample("contextual", (2, 2, 2), conflict=True)])["status"] == "BLOCKED_CONFLICT"
    assert triage([_sample("contextual", (2, 2, 2), missing=True)])["reason"] == "INVALID_OR_MISSING_EVIDENCE"
    assert triage([])["reason"] == "NO_PROPOSALS"
    assert triage([_sample("contextual", (2, 2, 2))])["ranks"][0]["selector_authorized"] is False
    print("8/8 scope triage reference tests passed (local-only; no runtime validation)")


if __name__ == "__main__":
    selftest()
