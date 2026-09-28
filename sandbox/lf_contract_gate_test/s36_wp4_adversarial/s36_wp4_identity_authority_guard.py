from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

ALLOWED_REVIEW_MODES = {"INDEPENDENT_HOLDOUT", "INDEPENDENT_REVIEW"}


@dataclass(frozen=True)
class GuardResult:
    decision: str
    code: str

    def as_dict(self) -> dict[str, str]:
        return {"decision": self.decision, "code": self.code}


def evaluate_identity_authority(
    *,
    producer_execution_id: str,
    reviewer_execution_id: str,
    reviewer_mode: str,
    requested_authority: str,
    granted_authorities: Iterable[str],
) -> GuardResult:
    """Historical integration guard over canonical owner inputs.

    Reviewer independence belongs to INDEPENDENT_REVIEW. Requested-vs-granted
    authority belongs to the policy/downstream-authority chain. This guard remains
    only as an integration regression and does not own either capability.
    """
    producer = (producer_execution_id or "").strip()
    reviewer = (reviewer_execution_id or "").strip()
    mode = (reviewer_mode or "").strip()
    requested = (requested_authority or "").strip()
    granted = {str(x).strip() for x in granted_authorities if str(x).strip()}

    if not producer or not reviewer:
        return GuardResult("BLOCK", "REVIEW_IDENTITY_MISSING")
    if producer == reviewer:
        return GuardResult("BLOCK", "PRODUCER_AS_REVIEWER")
    if mode not in ALLOWED_REVIEW_MODES:
        return GuardResult("BLOCK", "REVIEW_MODE_NOT_INDEPENDENT")
    if not requested:
        return GuardResult("BLOCK", "REQUESTED_AUTHORITY_MISSING")
    if requested not in granted:
        return GuardResult("BLOCK", "AUTHORITY_ESCALATION_ATTEMPT")
    return GuardResult("PASS", "IDENTITY_AUTHORITY_INVARIANTS_PROVEN")
