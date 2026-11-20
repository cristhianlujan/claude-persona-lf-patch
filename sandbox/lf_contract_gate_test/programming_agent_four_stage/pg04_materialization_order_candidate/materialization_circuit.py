"""Local deterministic order-check of LF materialization milestones.

A simulation of state transitions, not a DB writer, receipt verifier or executor.
No step grants authority to dispatch or seal in Supabase.
"""
from dataclasses import dataclass, field

class CircuitBlocked(ValueError):
    pass

@dataclass
class Circuit:
    history: list[str] = field(default_factory=list)
    stage: str = 'PG04_CANDIDATE'
    dispatch_allowed: bool = False

    def advance(self, action: str, *, authenticated: bool = False) -> dict:
        transitions = {
            'PG04_CANDIDATE': ('PG01_ADMITTED', 'FUNCTIONAL_SOURCE_VERIFIED'),
            'FUNCTIONAL_SOURCE_VERIFIED': ('TASK_DRAFT_CREATED', 'TASK_DRAFT'),
            'TASK_DRAFT': ('TASK_SEALED_BY_DB', 'TASK_SEALED'),
            'TASK_SEALED': ('BLIND_TEST_CONTRACT_DRAFT', 'TEST_DRAFT'),
            'TEST_DRAFT': ('BLIND_TEST_CONTRACT_SEALED_BY_DB', 'TEST_SEALED'),
            'TEST_SEALED': ('DELIVERY_CONTRACT_DRAFT', 'DELIVERY_DRAFT'),
            'DELIVERY_DRAFT': ('DELIVERY_CONTRACT_SEALED_BY_DB', 'DELIVERY_SEALED'),
            'DELIVERY_SEALED': ('DB_READINESS_CONFIRMED', 'READINESS_CONFIRMED'),
        }
        if self.stage not in transitions or transitions[self.stage][0] != action:
            raise CircuitBlocked('INVALID_ORDER:' + self.stage + ':' + action)
        if not authenticated:
            raise CircuitBlocked('EXTERNAL_AUTHORITY_EVIDENCE_REQUIRED:' + action)
        self.stage = transitions[self.stage][1]
        self.history.append(action)
        return self.snapshot()

    def snapshot(self) -> dict:
        return {'schema_version': 'LF_MATERIALIZATION_ORDER_SIMULATION_V1',
                'stage': self.stage, 'history': list(self.history),
                'dispatch_allowed': False, 'production_authority': False,
                'state_is_simulated': True}
