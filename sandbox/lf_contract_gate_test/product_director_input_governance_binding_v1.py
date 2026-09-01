#!/usr/bin/env python3
"""Compatibility wrapper for the generic LF profile Input Governance binding.

Product Director was the first consumer canary, but the binding contract is shared by
all governed profile-runtime targets. Keep this path for the existing sandbox fixture
without duplicating implementation logic.
"""
from profile_input_governance_binding_v1 import (  # noqa: F401
    ALLOWED_GOVERNANCE_CONSUMERS,
    SCHEMA,
    GovernanceBindingError,
    build_bound_governance_receipt,
    validate_bound_governance_receipt,
)

__all__ = [
    "ALLOWED_GOVERNANCE_CONSUMERS",
    "SCHEMA",
    "GovernanceBindingError",
    "build_bound_governance_receipt",
    "validate_bound_governance_receipt",
]
