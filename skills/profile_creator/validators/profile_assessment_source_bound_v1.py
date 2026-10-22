#!/usr/bin/env python3
"""Prepare a source-bound PROFILE_ASSESSMENT candidate for the existing Updater.

No external model, Supabase mutation, provider attestation, ledger receipt or
profile write is generated here. A trusted host must supply independent
GitHub/source and evidence-readback callbacks. The canonical Evidence Ledger
must separately verify and anchor a receipt before steps 35/37 may consume it.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[3]
ASSESS_DIR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
if str(ASSESS_DIR) not in sys.path:
    sys.path.insert(0, str(ASSESS_DIR))
from profile_assessment_v1 import assess_profile

_SHA40 = re.compile(r"^[0-9a-f]{40}$")
_SHA64 = re.compile(r"^[0-9a-f]{64}$")
_SLUG = re.compile(r"^[a-z0-9][a-z0-9_]{0,79}$")
_EVIDENCE = (
    "architecture_fit", "domain_task_uplift", "strategy_routing",
    "expert_holdout", "repeated_optimization", "optimization_opportunity",
)


def _digest(data: Any) -> str:
    # Match plan_profile_evolution.py's canonical assessment INPUT digest.
    return hashlib.sha256(json.dumps(
        data, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")).hexdigest()


def _block(code: str) -> dict[str, Any]:
    return {"schema": "PROFILE_ASSESSMENT_SOURCE_PACKET_V1",
            "status": "BLOCKED", "blocking_codes": [code],
            "ledger_write_performed": False, "verified_receipt_issued": False}


def prepare_profile_assessment(
    *, repo: Path, profile_slug: str, source_head_sha: str,
    assessment_input: dict[str, Any],
    trusted_source_readback: Callable[[str, str], dict[str, Any] | None],
    trusted_evidence_readback: Callable[[str, str, str], dict[str, Any] | None],
    evaluate_structural: Callable[[Path, str], dict[str, Any]],
) -> dict[str, Any]:
    """Produce a candidate; caller cannot assert PASS through free-form refs.

    The trusted host must implement callbacks via independently authorized
    GitHub and evidence resolvers. Never bind them to the request payload.
    """
    if not isinstance(profile_slug, str) or not _SLUG.fullmatch(profile_slug):
        return _block("PROFILE_REF_INVALID")
    if not isinstance(source_head_sha, str) or not _SHA40.fullmatch(source_head_sha):
        return _block("PROFILE_SOURCE_HEAD_INVALID")
    if not isinstance(assessment_input, dict) or not all(callable(f) for f in (
            trusted_source_readback, trusted_evidence_readback, evaluate_structural)):
        return _block("ASSESSMENT_PRODUCER_INPUT_INVALID")
    try:
        source = trusted_source_readback(profile_slug, source_head_sha)
    except Exception:
        return _block("PROFILE_SOURCE_READBACK_UNAVAILABLE")
    expected_path = "profiles/" + profile_slug + "/SKILL.md"
    if (not isinstance(source, dict)
        or source.get("status") != "VERIFIED_CURRENT"
        or source.get("profile_slug") != profile_slug
        or source.get("source_head_sha") != source_head_sha
        or source.get("source_path") != expected_path
        or not isinstance(source.get("source_sha256"), str)
        or not _SHA64.fullmatch(source["source_sha256"])
        or source.get("resolver_id") != "LF_GITHUB_SOURCE_READBACK_V1"
        or source.get("resolver_active") is not True
        or source.get("resolver_trust_level") != "TRUSTED_PROVIDER_BOUND"):
        return _block("PROFILE_SOURCE_NOT_PROVIDER_VERIFIED")
    try:
        structure = evaluate_structural(repo, profile_slug)
    except Exception:
        return _block("PROFILE_STRUCTURAL_EVALUATION_FAILED")
    if not isinstance(structure, dict) or structure.get("schema") != "S26_PROFILE_BASELINE_EVALUATION_V1":
        return _block("PROFILE_STRUCTURAL_RESULT_INVALID")
    if structure.get("profile_slug") != profile_slug:
        return _block("PROFILE_STRUCTURAL_IDENTITY_MISMATCH")
    if structure.get("decision") not in (
        "NO_UPDATE_REQUIRED", "UPDATE_REQUIRED", "BLOCKED_AUTHORITY_REQUIRED",
    ):
        return _block("PROFILE_STRUCTURAL_DECISION_INVALID")

    normalized = copy.deepcopy(assessment_input)
    raw_evidence = normalized.get("evidence")
    if not isinstance(raw_evidence, dict) or not isinstance(normalized.get("signals"), dict):
        return _block("PROFILE_ASSESSMENT_EVIDENCE_SHAPE_INVALID")
    checked: dict[str, Any] = {}
    source_ref = "github://" + source["source_path"] + "@" + source_head_sha
    # S26 is an evaluated structural result, not an assertion from the caller.
    if structure["decision"] == "NO_UPDATE_REQUIRED":
        checked["structural_compatibility"] = {
            "status": "PASS", "refs": [source_ref + "#s26-structural-13-of-13"],
        }
    elif structure["decision"] == "UPDATE_REQUIRED":
        checked["structural_compatibility"] = {
            "status": "FAIL", "refs": [source_ref + "#s26-update-required"],
        }
    else:
        checked["structural_compatibility"] = {"status": "UNKNOWN", "refs": []}

    verified_refs: list[dict[str, str]] = []
    rejected_refs: list[str] = []
    for name in _EVIDENCE:
        item = raw_evidence.get(name, {})
        if not isinstance(item, dict):
            item = {}
        status = item.get("status", "UNKNOWN")
        refs = item.get("refs", [])
        if status not in ("PASS", "FAIL", "UNKNOWN") or not isinstance(refs, list):
            return _block("PROFILE_ASSESSMENT_EVIDENCE_INVALID")
        valid = status in ("PASS", "FAIL") and bool(refs)
        if valid:
            for ref in refs:
                if not isinstance(ref, str) or not ref:
                    valid = False
                    rejected_refs.append(str(ref))
                    break
                try:
                    proof = trusted_evidence_readback(ref, profile_slug, source_head_sha)
                except Exception:
                    proof = None
                if (not isinstance(proof, dict)
                    or proof.get("status") != "VERIFIED"
                    or proof.get("ref") != ref
                    or proof.get("profile_slug") != profile_slug
                    or proof.get("source_head_sha") != source_head_sha
                    or proof.get("observed_status") != status
                    or proof.get("resolver_active") is not True
                    or proof.get("resolver_trust_level") != "TRUSTED_PROVIDER_BOUND"
                    or proof.get("resolver_id") not in (
                        "LF_GITHUB_SOURCE_READBACK_V1", "LF_SUPABASE_READBACK_V1")):
                    valid = False
                    rejected_refs.append(ref)
                    break
        checked[name] = {"status": status if valid else "UNKNOWN",
                         "refs": refs if valid else []}
        if valid:
            verified_refs.extend({"dimension": name, "ref": r} for r in refs)

    normalized["evidence"] = checked
    output = assess_profile(normalized)
    digest = _digest(normalized)
    if output.get("write_authorized") is not False or output.get("admission_required") is not True:
        return _block("PROFILE_ASSESSMENT_PRODUCER_ESCALATED")
    enough = output.get("assessment_status") == "EVIDENCE_SUFFICIENT"
    return {
        "schema": "PROFILE_ASSESSMENT_SOURCE_PACKET_V1",
        "status": "EVIDENCE_READY_FOR_LEDGER_REVIEW" if enough else "NEEDS_MORE_EVIDENCE",
        "profile_slug": profile_slug,
        "source_head_sha": source_head_sha,
        "source_path": expected_path,
        "source_sha256": source["source_sha256"],
        "source_resolver_id": source["resolver_id"],
        "subject_type": "PROFILE_ASSESSMENT",
        "subject_ref": profile_slug,
        "subject_sha256": digest,
        "normalized_assessment_input": normalized,
        "assessment_result": output,
        "verified_evidence_refs": verified_refs,
        "rejected_evidence_refs": sorted(set(rejected_refs)),
        "blocking_codes": [] if enough else ["PROFILE_ASSESSMENT_NEEDS_MORE_EVIDENCE"],
        "ledger_write_performed": False,
        "verified_receipt_issued": False,
        "method_execution_permitted": False,
        "production_activation_authorized": False,
    }
