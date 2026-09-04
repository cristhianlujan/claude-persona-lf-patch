#!/usr/bin/env python3
"""Adversarial fixtures for the Strategy 26 Golden Family contract."""
from __future__ import annotations

import copy
import json

import validate_golden_family_contract as validator


def load() -> dict:
    return json.loads(validator.CONTRACT.read_text(encoding="utf-8"))


def expect_fail(name: str, mutate, expected_prefix: str) -> None:
    data = copy.deepcopy(load())
    mutate(data)
    try:
        validator.validate_contract(data)
    except validator.ContractError as exc:
        message = str(exc)
        if not message.startswith(expected_prefix):
            raise AssertionError(f"{name}: expected {expected_prefix}, got {message}") from exc
        return
    raise AssertionError(f"{name}: validator unexpectedly accepted invalid contract")


def main() -> int:
    canonical = load()
    result = validator.validate_contract(canonical)
    if "status=E2E_BLOCKED" not in result:
        raise AssertionError(f"canonical contract must remain blocked, got: {result}")

    expect_fail(
        "inputgov_missing_run_id",
        lambda d: d["input_governance"]["required_receipt_fields"].remove("run_id"),
        "GOLDEN_FAMILY_INPUT_GOVERNANCE_RECEIPT_FIELDS_MISSING:run_id",
    )
    expect_fail(
        "inputgov_wrong_consumer",
        lambda d: d["input_governance"].__setitem__("consumer", "STORY_CREATOR"),
        "GOLDEN_FAMILY_INPUT_GOVERNANCE_CONSUMER_INVALID",
    )
    expect_fail(
        "card_missing_budget",
        lambda d: d["card"]["required_receipt_fields"].remove("budget"),
        "GOLDEN_FAMILY_CARD_RECEIPT_FIELDS_MISSING:budget",
    )
    expect_fail(
        "card_missing_request_id",
        lambda d: d["card"]["required_receipt_fields"].remove("request_id"),
        "GOLDEN_FAMILY_CARD_RECEIPT_FIELDS_MISSING:request_id",
    )
    expect_fail(
        "card_registry_inferred",
        lambda d: d["card"].__setitem__("expected_registry", "public.lf_cards"),
        "GOLDEN_FAMILY_CARD_RUNTIME_REGISTRY_MUST_NOT_BE_INFERRED",
    )
    expect_fail(
        "card_gap_not_blocking",
        lambda d: d.__setitem__("status", "CONTRACT_DEFINED_E2E_NOT_PROVEN"),
        "GOLDEN_FAMILY_CARD_BINDING_GAP_MUST_BLOCK_E2E",
    )
    expect_fail(
        "adapter_missing_version",
        lambda d: d["adapter"]["required_receipt_fields"].remove("adapter_version"),
        "GOLDEN_FAMILY_ADAPTER_RECEIPT_FIELDS_MISSING:adapter_version",
    )
    expect_fail(
        "adapter_missing_target",
        lambda d: d["adapter"]["required_receipt_fields"].remove("target_asset_code"),
        "GOLDEN_FAMILY_ADAPTER_RECEIPT_FIELDS_MISSING:target_asset_code",
    )

    def set_e2e_with_string_proof(d: dict) -> None:
        d["status"] = "E2E_PROVEN"
        d["card"]["runtime_binding_observed_at_research_cut"] = True
        d["runtime_proof"] = "CLAIMED_PASS"

    expect_fail(
        "e2e_string_self_attestation",
        set_e2e_with_string_proof,
        "GOLDEN_FAMILY_E2E_PROVEN_RUNTIME_PROOF_OBJECT_REQUIRED",
    )

    def set_e2e_missing_request(d: dict) -> None:
        d["status"] = "E2E_PROVEN"
        d["card"]["runtime_binding_observed_at_research_cut"] = True
        d["runtime_proof"] = {
            "queue_ref": "private.lf_profile_runtime_queue_v1",
            "runtime_target": "HETZNER",
            "runtime_provider": "hetzner_profile_runtime_api",
            "deployed_worker_revision": "worker-sha",
            "persisted_result_ref": "queue-row",
            "same_request_readback_ref": "queue-row-readback",
        }

    expect_fail(
        "e2e_missing_request_id",
        set_e2e_missing_request,
        "GOLDEN_FAMILY_E2E_PROVEN_RUNTIME_PROOF_FIELDS_MISSING:request_id",
    )

    def set_e2e_backup_runtime(d: dict) -> None:
        d["status"] = "E2E_PROVEN"
        d["card"]["runtime_binding_observed_at_research_cut"] = True
        d["runtime_proof"] = {
            "request_id": "req-1",
            "queue_ref": "private.lf_profile_runtime_queue_v1",
            "runtime_target": "GITHUB_ACTIONS",
            "runtime_provider": "github_actions",
            "deployed_worker_revision": "gha",
            "persisted_result_ref": "queue-row",
            "same_request_readback_ref": "queue-row-readback",
        }

    expect_fail(
        "e2e_backup_cannot_satisfy_primary",
        set_e2e_backup_runtime,
        "GOLDEN_FAMILY_E2E_PROVEN_PRIMARY_RUNTIME_NOT_HETZNER",
    )

    print("GOLDEN_FAMILY_NEGATIVE_FIXTURES_PASS cases=11")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
