#!/usr/bin/env python3
"""Boundary-safe handoff from Changeset Governance toward Contract Resolution.

Changeset Governance decides whether LF_CONTRACT_CORE applies and transports
changeset identity/context. It does not select contracts, resolve operation
identity, or produce term verdicts. Contract Resolution consumes an
already-resolved caller operation_code plus authority contract rows and returns
resolved_contracts. Contract Check owns contractual evaluation.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Mapping

SCHEMA_VERSION = "lf-contract-check-resolution-request/v1"
PLAN_SCHEMA_VERSION = "lf-ci-execution-plan/v2"
CONTROL_ID = "LF_CONTRACT_CORE"
CONTRACT_RESOLUTION_OWNER = "CONTRACT_RESOLUTION"
CONTRACT_CHECK_OWNER = "CONTRACT_CHECK"
_FAMILY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")

_CHANGESET_PATH = Path(__file__).with_name("lf_changeset_governance.py")
_CHANGESET_SPEC = importlib.util.spec_from_file_location(
    "lf_changeset_governance_for_contract_handoff", _CHANGESET_PATH
)
if _CHANGESET_SPEC is None or _CHANGESET_SPEC.loader is None:
    raise ImportError(f"cannot load Changeset Governance helper: {_CHANGESET_PATH}")
_CHANGESET = importlib.util.module_from_spec(_CHANGESET_SPEC)
sys.modules[_CHANGESET_SPEC.name] = _CHANGESET
_CHANGESET_SPEC.loader.exec_module(_CHANGESET)


class ContractCheckHandoffError(ValueError):
    pass


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _families_from_lane_reasons(reasons: Any) -> dict[str, str]:
    if not isinstance(reasons, (tuple, list)):
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_LANE_REASONS")
    families: dict[str, str] = {}
    for reason in reasons:
        if not isinstance(reason, str) or not reason.startswith("CHANGE_FAMILY:"):
            continue
        _, family, path = reason.split(":", 2)
        if _FAMILY_RE.fullmatch(family) is None or not path:
            raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_FAMILY_REASON")
        previous = families.get(path)
        if previous is not None and previous != family:
            raise ContractCheckHandoffError(
                f"FAIL_CONTRACT_CHECK_HANDOFF_FAMILY_CONFLICT:{path}:{previous}:{family}"
            )
        families[path] = family
    return dict(sorted(families.items()))


def _manifest_path(families: Mapping[str, str]) -> str | None:
    paths = sorted(path for path, family in families.items() if family == "CHANGESET_MANIFEST")
    if len(paths) > 1:
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_MULTIPLE_MANIFESTS")
    return paths[0] if paths else None


def _solution_ref(
    repo_root: Path,
    manifest_path: str | None,
    *,
    manifest_data: Mapping[str, Any] | None = None,
) -> str | None:
    if manifest_path is None:
        return None
    if manifest_data is None:
        target = repo_root / manifest_path
        if not target.is_file():
            raise ContractCheckHandoffError(
                f"FAIL_CONTRACT_CHECK_HANDOFF_MANIFEST_MISSING:{manifest_path}"
            )
        try:
            data = json.loads(target.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise ContractCheckHandoffError(
                f"FAIL_CONTRACT_CHECK_HANDOFF_MANIFEST_READ:{manifest_path}:{exc.__class__.__name__}"
            ) from exc
    else:
        data = dict(manifest_data)
    try:
        solution_ref, _ = _CHANGESET.parse_manifest(data, manifest_path=manifest_path)
    except Exception as exc:
        code = getattr(exc, "code", exc.__class__.__name__)
        raise ContractCheckHandoffError(
            f"FAIL_CONTRACT_CHECK_HANDOFF_MANIFEST_INVALID:{manifest_path}:{code}"
        ) from exc
    return solution_ref


def build_resolution_request(
    *,
    lane: Any,
    plan: Mapping[str, Any],
    repo_root: Path,
    manifest_data: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    if not isinstance(plan, Mapping) or plan.get("schema_version") != PLAN_SCHEMA_VERSION:
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_PLAN_SCHEMA")
    changed_paths = plan.get("changed_paths")
    required_controls = plan.get("required_controls")
    reasons_by_control = plan.get("required_control_reasons")
    if (
        not isinstance(changed_paths, list)
        or any(not isinstance(path, str) or not path for path in changed_paths)
        or changed_paths != sorted(set(changed_paths))
    ):
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_CHANGED_PATHS")
    if not isinstance(required_controls, list) or any(not isinstance(v, str) for v in required_controls):
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_REQUIRED_CONTROLS")
    if not isinstance(reasons_by_control, Mapping):
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_CONTROL_REASONS")

    lane_mode = getattr(lane, "mode", None)
    lane_reasons = getattr(lane, "reasons", None)
    if not isinstance(lane_mode, str) or not lane_mode:
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_LANE_MODE")

    families = _families_from_lane_reasons(lane_reasons)
    manifest_path = _manifest_path(families)
    solution_ref = _solution_ref(
        Path(repo_root), manifest_path, manifest_data=manifest_data
    )
    applicable = CONTROL_ID in required_controls
    classification_required = lane_mode == "CLASSIFICATION_REQUIRED"

    if not applicable:
        state = "NOT_APPLICABLE"
    elif classification_required:
        state = "CLASSIFICATION_PENDING_REPORT_ONLY"
    elif solution_ref is None:
        state = "IDENTITY_PENDING_REPORT_ONLY"
    else:
        state = "READY_FOR_OPERATION_CONTEXT_BINDING"

    control_reasons = reasons_by_control.get(CONTROL_ID, []) if applicable else []
    if not isinstance(control_reasons, list) or any(not isinstance(v, str) for v in control_reasons):
        raise ContractCheckHandoffError("FAIL_CONTRACT_CHECK_HANDOFF_LF_CONTRACT_REASONS")

    request: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "control_id": CONTROL_ID,
        "applicability": "APPLICABLE" if applicable else "NOT_APPLICABLE",
        "handoff_state": state,
        "changeset": {
            "solution_ref": solution_ref,
            "manifest_path": manifest_path,
            "classification_mode": lane_mode,
            "classification_required": classification_required,
            "changed_paths": list(changed_paths),
            "families": families,
        },
        "applicability_reasons": sorted(control_reasons),
        "applicability_plan_sha256": plan.get("plan_sha256"),
        "resolution_request": {
            "owner": CONTRACT_RESOLUTION_OWNER,
            "required": applicable,
            "invocation_ready": False,
            "selection_performed": False,
            "operation_code_source": "CALLER_OPERATION_CONTEXT",
            "required_inputs": ["operation_code", "authority_contracts"],
            "required_outputs": ["resolved_contracts"],
        },
        "contract_check_boundary": {
            "owner": CONTRACT_CHECK_OWNER,
            "contract_selection_allowed": False,
            "upstream_term_verdicts_allowed": False,
        },
    }
    request["request_sha256"] = _sha256(request)
    return request
