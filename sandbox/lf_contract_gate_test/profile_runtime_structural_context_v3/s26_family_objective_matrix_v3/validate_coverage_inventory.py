from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
INVENTORY = ROOT / "coverage_inventory.json"
CONTRACT = ROOT / "matrix_contract.json"


def git_object_exists(commit: str, path: str) -> bool:
    proc = subprocess.run(
        ["git", "cat-file", "-e", f"{commit}:{path}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode == 0


def projected_dimensions(objective: dict, contract: dict) -> tuple[dict[str, str], bool]:
    dims = dict(objective["dimensions"])
    oid = objective["objective_id"]
    allowed_na = set(contract["na_policy"]["allowed_dimensions"])
    reclassifications = contract["na_policy"].get("performance_na_reclassification", {})
    policy = reclassifications.get(oid)
    reclassified = False

    if policy is not None:
        assert dims.get("performance") == "N_A", f"RECLASSIFICATION_TARGET_NOT_NA:{oid}:{dims.get('performance')}"
        projected = policy["effective_status"]
        assert projected in {"COVERED", "PENDING"}, f"BAD_PERFORMANCE_RECLASSIFICATION:{oid}:{projected}"
        required_refs = set(policy.get("required_evidence_refs", []))
        actual_refs = set(objective.get("evidence_refs", []))
        assert required_refs <= actual_refs, f"PERFORMANCE_RECLASSIFICATION_EVIDENCE_MISSING:{oid}:{sorted(required_refs - actual_refs)}"
        dims["performance"] = projected
        reclassified = True

    invalid_na = [
        name for name, value in dims.items()
        if value == "N_A" and name not in allowed_na
    ]
    if invalid_na:
        raise AssertionError(f"INVALID_NA:{oid}:{','.join(invalid_na)}")
    return dims, reclassified


def effective_status(objective: dict, contract: dict) -> tuple[str, bool]:
    declared = objective["status"]
    dims, reclassified = projected_dimensions(objective, contract)
    pending = [name for name, value in dims.items() if value == "PENDING"]
    partial = [name for name, value in dims.items() if value == "PARTIAL"]
    if declared == "NEW_CASE_REQUIRED":
        return "NEW_CASE_REQUIRED", reclassified
    if pending:
        return ("NOT_DEMONSTRATED" if declared == "NOT_DEMONSTRATED" else "PARTIAL"), reclassified
    if partial:
        return "PARTIAL", reclassified
    return "COVERED", reclassified


def main() -> None:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))

    assert inventory["master_structure"] == contract["master_structure"], "MASTER_STRUCTURE_MISMATCH"
    assert inventory["hierarchy"] == contract["hierarchy"], "HIERARCHY_MISMATCH"
    families = inventory["families"]
    assert len(families) == contract["families_required"], f"FAMILY_COUNT:{len(families)}"

    frozen = inventory["source_authority"]["frozen_candidate_commit"]
    root = inventory["source_authority"]["root"].rstrip("/")
    assert frozen == "48916fd36bcaff8eadd60944848e81adbea55c54", "UNEXPECTED_FROZEN_SOURCE"
    assert inventory["source_authority"]["main_is_evidence_authority"] is False
    assert inventory["source_authority"]["merge_ref_is_evidence_authority"] is False
    assert inventory["source_authority"]["wrong_substrate_disposition"] == "CLOSED_UNMERGED_NOT_S26_EVIDENCE"

    objective_ids: set[str] = set()
    declared_counts: Counter[str] = Counter()
    effective_counts: Counter[str] = Counter()
    family_summaries: list[dict] = []
    missing_provenance: list[str] = []
    reclassified_ids: set[str] = set()

    allowed_obj = set(contract["objective_statuses"])
    allowed_dim = set(contract["dimension_statuses"])
    required_dims = set(contract["required_dimensions"])

    for family in families:
        objectives = family["objectives"]
        assert len(objectives) == contract["objectives_per_family"], f"OBJECTIVE_COUNT:{family['family_id']}:{len(objectives)}"
        assert len({o["objective"] for o in objectives}) == len(objectives), f"DUPLICATE_OBJECTIVE_TEXT:{family['family_id']}"

        family_effective: Counter[str] = Counter()
        holdout_slots = 0
        for objective in objectives:
            oid = objective["objective_id"]
            assert oid not in objective_ids, f"DUPLICATE_OBJECTIVE_ID:{oid}"
            objective_ids.add(oid)
            assert objective["status"] in allowed_obj, f"BAD_OBJECTIVE_STATUS:{oid}"
            assert set(objective["dimensions"]) == required_dims, f"BAD_DIMENSION_KEYS:{oid}"
            assert set(objective["dimensions"].values()) <= allowed_dim, f"BAD_DIMENSION_STATUS:{oid}"
            assert str(objective.get("learning", "")).strip(), f"MISSING_LEARNING:{oid}"

            declared_counts[objective["status"]] += 1
            eff, was_reclassified = effective_status(objective, contract)
            if was_reclassified:
                reclassified_ids.add(oid)
            effective_counts[eff] += 1
            family_effective[eff] += 1
            if objective["status"] in {"NEW_CASE_REQUIRED", "NOT_DEMONSTRATED"}:
                holdout_slots += 1

            refs = objective.get("evidence_refs", [])
            if objective["status"] in {"COVERED", "PARTIAL"}:
                assert refs, f"MATERIAL_STATUS_WITHOUT_EVIDENCE:{oid}"
            for ref in refs:
                path = f"{root}/{ref}"
                if not git_object_exists(frozen, path):
                    missing_provenance.append(f"{oid}:{path}")

        assert holdout_slots >= 1, f"NO_UNSEEN_HOLDOUT_SLOT:{family['family_id']}"
        family_summaries.append({
            "family_id": family["family_id"],
            "declared": dict(Counter(o["status"] for o in objectives)),
            "effective": dict(family_effective),
            "final_family_pass": family_effective.get("COVERED", 0) == contract["objectives_per_family"],
            "unseen_holdout_slots": holdout_slots,
        })

    expected_reclassified = set(contract["na_policy"].get("performance_na_reclassification", {}))
    assert reclassified_ids == expected_reclassified, {
        "missing_reclassifications": sorted(expected_reclassified - reclassified_ids),
        "unexpected_reclassifications": sorted(reclassified_ids - expected_reclassified),
    }
    assert len(objective_ids) == contract["families_required"] * contract["objectives_per_family"], "OBJECTIVE_TOTAL"
    assert not missing_provenance, f"MISSING_FROZEN_EVIDENCE:{missing_provenance}"

    final_family_pass_count = sum(1 for item in family_summaries if item["final_family_pass"])
    summary = {
        "schema": "S26_FAMILY_OBJECTIVE_MATRIX_V3_INVENTORY_VALIDATION_V1",
        "structural_validation": "PASS",
        "source_provenance_validation": "PASS",
        "families": len(families),
        "objectives": len(objective_ids),
        "declared_status_counts": dict(declared_counts),
        "effective_status_counts": dict(effective_counts),
        "performance_na_reclassified": sorted(reclassified_ids),
        "family_pass_now": final_family_pass_count,
        "family_total": len(families),
        "system_certified": False,
        "family_summaries": family_summaries,
        "next_gate": "DESIGN_AND_EXECUTE_ONLY_GENUINE_MISSING_OBJECTIVES_AFTER_FINAL_CANDIDATE_PREREQUISITES",
        "claim_ceiling": "INVENTORY_VALIDATED_NOT_CERTIFICATION_NOT_GATE_G_NOT_GOLDEN"
    }
    print(json.dumps(summary, sort_keys=True))

    # Inventory validation must not accidentally be interpreted as certification.
    assert summary["system_certified"] is False
    assert final_family_pass_count < len(families), "INVENTORY_UNEXPECTEDLY_CLAIMS_ALL_FAMILIES_PASS"


if __name__ == "__main__":
    main()
