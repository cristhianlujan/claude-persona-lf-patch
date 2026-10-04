from __future__ import annotations
import copy
from typing import Any, Callable
from reversible_candidate_verification_v1 import CandidateIdentity, RollbackContract, canonical_digest

class TransactionalMappingFlowAdapter:
    adapter_code = "TRANSACTIONAL_MAPPING_FLOW_V1"
    def __init__(self, initial_state: dict[str, Any], resolver: Callable[[CandidateIdentity], dict[str, Any]]):
        self.state = copy.deepcopy(initial_state)
        self._resolver = resolver
    def run_rollback_only(self, candidate: CandidateIdentity, rollback: RollbackContract) -> dict[str, Any]:
        baseline_state = copy.deepcopy(self.state)
        baseline_digest = canonical_digest(baseline_state)
        patch = self._resolver(candidate)
        self.state.update(copy.deepcopy(patch))
        candidate_state = copy.deepcopy(self.state)
        candidate_digest = canonical_digest(candidate_state)
        self.state = baseline_state
        post_digest = canonical_digest(self.state)
        return {
            "baseline":{"state_digest":baseline_digest,"observation":baseline_state},
            "candidate":{"state_digest":candidate_digest,"observation":candidate_state},
            "rollback":{"status":"ROLLED_BACK","post_state_digest":post_digest,"material_residue_count":0},
        }
