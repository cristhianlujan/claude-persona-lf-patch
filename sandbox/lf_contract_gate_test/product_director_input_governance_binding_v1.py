#!/usr/bin/env python3
"""Compatibility wrapper for the generic LF profile Input Governance binding."""
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
