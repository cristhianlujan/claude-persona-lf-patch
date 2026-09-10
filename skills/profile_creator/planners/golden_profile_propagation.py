#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONTRACT = ROOT / "contracts" / "golden_profile_propagation_v1.json"


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def require_text(value: Any, code: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(code)
    return value.strip()


def build_plan(payload: Dict[str, Any], contract: Dict[str, Any]) -> Dict[str, Any]:
    golden = payload.get("golden")
    targets = payload.get("targets")
    delta = payload.get("authorized_delta")
    if not isinstance(golden, dict):
        raise ValueError("GOLDEN_PROFILE_REQUIRED")
    if not isinstance(targets, list) or not targets:
        raise ValueError("TARGETS_REQUIRED")
    if not isinstance(delta, list) or not delta:
        raise ValueError("AUTHORIZED_DELTA_REQUIRED")

    golden_code = require_text(golden.get("profile_code"), "GOLDEN_PROFILE_CODE_REQUIRED")
    golden_fingerprint = require_text(golden.get("fingerprint"), "GOLDEN_FINGERPRINT_REQUIRED")
    golden_e2e_status = require_text(golden.get("e2e_status"), "GOLDEN_E2E_STATUS_REQUIRED")

    allowed = set(contract["allowed_shared_components"])
    preserved = set(contract["preserved_profile_specific_components"])
    normalized_delta = []
    for item in delta:
        if not isinstance(item, dict):
            raise ValueError("AUTHORIZED_DELTA_ITEM_INVALID")
        component = require_text(item.get("component"), "AUTHORIZED_DELTA_COMPONENT_REQUIRED")
        source_ref = require_text(item.get("source_ref"), "AUTHORIZED_DELTA_SOURCE_REF_REQUIRED")
        action = require_text(item.get("action"), "AUTHORIZED_DELTA_ACTION_REQUIRED")
        if component in preserved:
            raise ValueError("PROFILE_SPECIFIC_COMPONENT_PROPAGATION_FORBIDDEN")
        if component not in allowed:
            raise ValueError("UNKNOWN_SHARED_COMPONENT_FORBIDDEN")
        normalized_delta.append({"component": component, "source_ref": source_ref, "action": action})

    normalized_delta = sorted(normalized_delta, key=lambda x: (x["component"], x["source_ref"], x["action"]))
    delta_sha = canonical_sha256(normalized_delta)
    parent_material = {
        "contract_code": contract["contract_code"],
        "golden_profile_code": golden_code,
        "golden_fingerprint": golden_fingerprint,
        "authorized_delta_sha256": delta_sha,
    }
    parent_plan_id = f"GPP-{canonical_sha256(parent_material)[:20]}"

    seen = set()
    children = []
    for raw in targets:
        if not isinstance(raw, dict):
            raise ValueError("TARGET_ITEM_INVALID")
        target_code = require_text(raw.get("profile_code"), "TARGET_PROFILE_CODE_REQUIRED")
        target_path = require_text(raw.get("target_path"), "TARGET_PATH_REQUIRED")
        if target_code == golden_code:
            raise ValueError("GOLDEN_PROFILE_CANNOT_BE_TARGET")
        if target_code in seen:
            raise ValueError("DUPLICATE_TARGET_FORBIDDEN")
        seen.add(target_code)
        child_key_material = {
            "parent_plan_id": parent_plan_id,
            "target_code": target_code,
            "target_path": target_path,
            "operation_code": contract["child_execution"]["operation_code"],
            "delta_sha256": delta_sha,
        }
        children.append({
            "target_code": target_code,
            "target_path": target_path,
            "operation_code": contract["child_execution"]["operation_code"],
            "execution_mode": "ISOLATED_CHILD_UPDATE",
            "idempotency_key": f"GPP-CHILD-{canonical_sha256(child_key_material)[:24]}",
            "authorized_delta_sha256": delta_sha,
            "required_preservations": contract["preserved_profile_specific_components"],
            "execution_id": None,
            "repository_write_authorized": False,
            "runtime_transition_authorized": False,
            "automatic_promotion_authorized": False,
        })

    golden_ready = golden_e2e_status == contract["golden_source"]["apply_requires_e2e_status"]
    return {
        "contract_code": contract["contract_code"],
        "mode": contract["planning_rules"]["mode"],
        "parent_plan_id": parent_plan_id,
        "golden_profile_code": golden_code,
        "golden_fingerprint": golden_fingerprint,
        "golden_e2e_status": golden_e2e_status,
        "authorized_delta": normalized_delta,
        "authorized_delta_sha256": delta_sha,
        "target_count": len(children),
        "children": children,
        "apply_gate": "READY_FOR_CHILD_CANARY" if golden_ready else "BLOCKED_GOLDEN_NOT_E2E_PASS",
        "repository_write_authorized": False,
        "supabase_profile_mutation_authorized": False,
        "runtime_transition_authorized": False,
        "family_pass_claimable": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Plan dry-run Golden Profile propagation without repository or runtime mutation.")
    parser.add_argument("input_json", help="JSON file with golden, targets and authorized_delta")
    parser.add_argument("--contract", default=str(DEFAULT_CONTRACT))
    args = parser.parse_args()
    payload = json.loads(Path(args.input_json).read_text(encoding="utf-8"))
    contract = json.loads(Path(args.contract).read_text(encoding="utf-8"))
    print(json.dumps(build_plan(payload, contract), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
