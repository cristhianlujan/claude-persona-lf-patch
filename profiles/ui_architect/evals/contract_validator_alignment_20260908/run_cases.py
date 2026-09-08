#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
VALIDATOR_PATH = ROOT / "profiles/ui_architect/validators/validate_ui_architect_output.py"
RUN_C_PATH = ROOT / "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_003/raw_output.json"


def load_validator():
    spec = importlib.util.spec_from_file_location("ui_contract_alignment_validator", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("validator load failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.validate


def error_codes(errors):
    return {item.get("code") for item in errors if isinstance(item, dict)}


def canonicalize_action(action, *, authority_type, claim_boundary, precision_mode, value_or_rule, source_refs):
    action = deepcopy(action)
    action["semantic_authority"] = {
        "source_refs": list(source_refs),
        "authority_type": authority_type,
        "claim_boundary": claim_boundary,
    }
    action["precision_basis"] = {
        "mode": precision_mode,
        "source_refs": list(source_refs) if precision_mode in {"CANONICAL_TOKEN", "UPSTREAM_VALUE"} else [],
        "value_or_rule": value_or_rule,
        "proposal_status": "NOT_APPLICABLE" if precision_mode in {"CANONICAL_TOKEN", "UPSTREAM_VALUE"} else "PROPOSED_NOT_CANONICAL",
    }
    return action


def repaired_run_c(run_c):
    repaired = deepcopy(run_c)
    actions = repaired["deliverable_created"]["remediation_actions"]
    pagination_refs = [
        "sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_003/input.txt",
        "visual-artifact:ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287",
    ]
    overflow_refs = [
        "visual-artifact:ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287",
    ]
    actions[0] = canonicalize_action(
        actions[0],
        authority_type="RAW_INPUT",
        claim_boundary="Pagination behavior is limited to the observed total, page size and current-page state.",
        precision_mode="RELATIVE_GUIDANCE",
        value_or_rule="page_count = ceil(total_records / page_size); next enabled only when current_page < page_count",
        source_refs=pagination_refs,
    )
    actions[1] = canonicalize_action(
        actions[1],
        authority_type="RAW_INPUT",
        claim_boundary="Overflow behavior is limited to observed table fit and preserving access under real horizontal overflow.",
        precision_mode="RELATIVE_GUIDANCE",
        value_or_rule="hide scroll chrome when scrollWidth <= clientWidth; retain overflow auto when scrollWidth > clientWidth",
        source_refs=overflow_refs,
    )
    return repaired


def main():
    validate = load_validator()
    run_c = json.loads(RUN_C_PATH.read_text(encoding="utf-8"))
    passed = 0

    # Frozen Run C is historical evidence and must now fail the written contract.
    frozen_errors = validate(run_c)
    frozen_codes = error_codes(frozen_errors)
    assert "PRECISION_BASIS_MISSING" in frozen_codes
    assert "SEMANTIC_AUTHORITY_LEGACY_SCOPE_FORBIDDEN" in frozen_codes
    assert "SEMANTIC_AUTHORITY_MISSING" in frozen_codes
    passed += 1

    # Positive: same semantic direction with contract-complete per-action bindings.
    repaired = repaired_run_c(run_c)
    assert validate(repaired) == []
    passed += 1

    # Negative: legacy claim_scope cannot substitute authority_type + claim_boundary.
    legacy = repaired_run_c(run_c)
    legacy_action = legacy["deliverable_created"]["remediation_actions"][0]
    legacy_action["semantic_authority"] = {
        "source_refs": ["input:/literal"],
        "claim_scope": "INPUT_SUPPORTED",
    }
    codes = error_codes(validate(legacy))
    assert "SEMANTIC_AUTHORITY_TYPE_INVALID" in codes
    assert "SEMANTIC_AUTHORITY_BOUNDARY_INVALID" in codes
    assert "SEMANTIC_AUTHORITY_LEGACY_SCOPE_FORBIDDEN" in codes
    passed += 1

    # Negative: material state behavior without precision_basis fails closed.
    missing_precision = repaired_run_c(run_c)
    missing_precision["deliverable_created"]["remediation_actions"][1].pop("precision_basis")
    assert "PRECISION_BASIS_MISSING" in error_codes(validate(missing_precision))
    passed += 1

    # Negative: canonical/upstream precision claims require source refs.
    missing_ref = repaired_run_c(run_c)
    precision = missing_ref["deliverable_created"]["remediation_actions"][0]["precision_basis"]
    precision.update({
        "mode": "UPSTREAM_VALUE",
        "source_refs": [],
        "value_or_rule": "page_count derived from upstream state contract",
        "proposal_status": "NOT_APPLICABLE",
    })
    assert "PRECISION_BASIS_REFS_REQUIRED" in error_codes(validate(missing_ref))
    passed += 1

    # Negative: unsupported precision mode cannot silently pass.
    bad_mode = repaired_run_c(run_c)
    bad_mode["deliverable_created"]["remediation_actions"][0]["precision_basis"]["mode"] = "OBSERVED_RELATIVE_GUIDANCE"
    assert "PRECISION_BASIS_MODE_INVALID" in error_codes(validate(bad_mode))
    passed += 1

    print(f"UI_CONTRACT_VALIDATOR_ALIGNMENT_TESTS_PASS {passed}/6")


if __name__ == "__main__":
    main()
