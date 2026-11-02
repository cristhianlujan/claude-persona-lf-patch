#!/usr/bin/env python3
"""Fail-closed, offline first-install readiness classifier. Never authorizes deployment.

An absent previous version is NOT a rollback baseline. This classifier requires
external, authenticated governance and preflight evidence before even describing
a first install as eligible for review. It has zero provider effects.
"""
from __future__ import annotations

SLUG = "lf-pg01-oidc-authority-v1"
PROJECT = "mhwmirqcgxxukpctffuv"

def assess(snapshot: object) -> dict:
    blockers = []
    if not isinstance(snapshot, dict):
        return {"decision": "BLOCKED", "blockers": ["SNAPSHOT_INVALID"], "effect_executed": False}
    if snapshot.get("slug") != SLUG or snapshot.get("project_ref") != PROJECT:
        blockers.append("TARGET_SCOPE_MISMATCH")
    if snapshot.get("predeploy_readback") != "AUTHENTICATED_404":
        blockers.append("FIRST_INSTALL_ABSENCE_UNPROVEN")
    if snapshot.get("baseline_version") is not None:
        blockers.append("FIRST_INSTALL_BASELINE_MUST_BE_NULL")
    if snapshot.get("governance_authority") != "SIGNED_INDEPENDENT_VERIFIED":
        blockers.append("SIGNED_INDEPENDENT_AUTHORITY_MISSING")
    if snapshot.get("operation_status") != "OP_OPERATIONAL":
        blockers.append("OPERATION_NOT_OPERATIONAL")
    if snapshot.get("effect_guard") != "RESERVED_EXACT":
        blockers.append("EFFECT_RESERVATION_MISSING")
    if snapshot.get("r17_preflight") != "CANONICAL_PASS":
        blockers.append("R17_CANONICAL_PREFLIGHT_MISSING")
    if snapshot.get("source_parity") != "EXACT_MAIN_BUNDLE_VERIFIED":
        blockers.append("EXACT_SOURCE_UNVERIFIED")
    if snapshot.get("failure_remediation") != "GOVERNED_DISABLE_AND_READBACK_VERIFIED":
        blockers.append("FIRST_INSTALL_RECOVERY_NOT_VERIFIED")
    return {
        "decision": "ELIGIBLE_FOR_INDEPENDENT_REVIEW" if not blockers else "BLOCKED",
        "blockers": blockers,
        "effect_executed": False,
        "deploy_authorized": False,
    }
