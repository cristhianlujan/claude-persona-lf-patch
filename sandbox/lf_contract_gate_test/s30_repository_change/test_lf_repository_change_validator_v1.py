#!/usr/bin/env python3
from __future__ import annotations

import copy
import unittest

from lf_repository_change_validator_v1 import request_sha256, validate_receipt, validate_request

PROVIDER = "s30-git-broker://S30_GIT_WRITE_BROKER_V2"
PROVIDERS = {PROVIDER}


def valid_request() -> dict:
    request = {
        "request_version": "LF_REPOSITORY_CHANGE_REQUEST_V1",
        "owner_code": "S30",
        "operation_code": "ACTUALIZACION_ADAPTER_LF",
        "execution_id": "EXEC-REPO-CHANGE-001",
        "repository_full_name": "cristhianlujan/claude-persona-lf-patch",
        "target_branch": "lf/s30-example",
        "expected_head": "1" * 40,
        "allowed_paths": ["sandbox/lf_contract_gate_test/s30_example/**"],
        "requested_paths": ["sandbox/lf_contract_gate_test/s30_example/a.json"],
        "request_sha256": "",
        "idempotency_key": "S30:REPO:001",
        "transport_provider_ref": PROVIDER,
        "authority_receipt_ref": "evidence://currentness/receipt-001",
        "change_manifest": {"intent": "TEST_ONLY"},
    }
    request["request_sha256"] = request_sha256(request)
    return request


def valid_receipt(request: dict) -> dict:
    return {
        "receipt_version": "LF_REPOSITORY_CHANGE_RECEIPT_V1",
        "result": "PASS_REPOSITORY_CHANGE_WITH_READBACK",
        "owner_code": request["owner_code"],
        "operation_code": request["operation_code"],
        "execution_id": request["execution_id"],
        "repository_full_name": request["repository_full_name"],
        "target_branch": request["target_branch"],
        "before_head": request["expected_head"],
        "after_head": "2" * 40,
        "request_sha256": request["request_sha256"],
        "idempotency_key": request["idempotency_key"],
        "transport_provider_ref": PROVIDER,
        "transport_provider_version": "v0.6",
        "changed_paths": list(request["requested_paths"]),
        "path_readbacks": [
            {
                "path": request["requested_paths"][0],
                "blob_sha": "3" * 40,
                "sha256": "4" * 64,
            }
        ],
        "remote_head_readback": "2" * 40,
        "merge_authorized": False,
    }


class RepositoryChangeValidatorV1Test(unittest.TestCase):
    def test_valid_request_and_receipt_pass(self) -> None:
        request = valid_request()
        self.assertEqual("PASS", validate_request(request, PROVIDERS)["status"])
        result = validate_receipt(request, valid_receipt(request), PROVIDERS)
        self.assertEqual("PASS", result["status"])
        self.assertEqual("ACCEPT_PASS", result["disposition"])

    def test_main_target_is_blocked(self) -> None:
        request = valid_request()
        request["target_branch"] = "main"
        request["request_sha256"] = request_sha256(request)
        result = validate_request(request, PROVIDERS)
        self.assertEqual("BLOCKED", result["status"])
        self.assertIn("TARGET_BRANCH_INVALID_OR_PROTECTED_MAIN", result["findings"])

    def test_cross_owner_scope_is_blocked(self) -> None:
        request = valid_request()
        request["requested_paths"] = ["profiles/foreign/file.json"]
        request["request_sha256"] = request_sha256(request)
        result = validate_request(request, PROVIDERS)
        self.assertIn("BLOCK_SCOPE_VIOLATION", result["findings"])

    def test_unknown_provider_is_blocked(self) -> None:
        request = valid_request()
        request["transport_provider_ref"] = "direct-github-rest://forbidden"
        request["request_sha256"] = request_sha256(request)
        result = validate_request(request, PROVIDERS)
        self.assertIn("BLOCK_PROVIDER_NOT_GOVERNED", result["findings"])

    def test_tampered_request_hash_is_blocked(self) -> None:
        request = valid_request()
        request["change_manifest"]["intent"] = "TAMPERED"
        result = validate_request(request, PROVIDERS)
        self.assertIn("BLOCK_REQUEST_IDENTITY_MISMATCH", result["findings"])

    def test_receipt_wrong_request_binding_is_blocked(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt["before_head"] = "5" * 40
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertTrue(any(x.startswith("RECEIPT_REQUEST_BINDING_MISMATCH") for x in result["findings"]))

    def test_unintended_changed_path_is_blocked(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt["changed_paths"] = ["sandbox/lf_contract_gate_test/s30_example/other.json"]
        receipt["path_readbacks"][0]["path"] = receipt["changed_paths"][0]
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertIn("BLOCK_READBACK_MISMATCH:CHANGED_PATH_SET", result["findings"])

    def test_remote_head_mismatch_is_blocked(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt["remote_head_readback"] = "6" * 40
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertIn("BLOCK_READBACK_MISMATCH:REMOTE_HEAD", result["findings"])

    def test_missing_path_readback_is_blocked(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt["path_readbacks"] = []
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertIn("BLOCK_READBACK_MISMATCH:PATH_READBACK_SET", result["findings"])

    def test_unknown_outcome_requires_reconciliation_without_asserted_heads(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt.update({
            "result": "RECONCILIATION_REQUIRED_UNKNOWN_OUTCOME",
            "after_head": None,
            "remote_head_readback": None,
            "changed_paths": [],
            "path_readbacks": [],
            "unknown_outcome_detail": "transport acknowledgement lost",
        })
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertEqual("RECONCILIATION_REQUIRED", result["status"])
        self.assertEqual("RECONCILE_DO_NOT_REDISPATCH", result["disposition"])

    def test_unknown_outcome_must_not_fabricate_head(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt.update({
            "result": "RECONCILIATION_REQUIRED_UNKNOWN_OUTCOME",
            "changed_paths": [],
            "path_readbacks": [],
            "unknown_outcome_detail": "transport acknowledgement lost",
        })
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertIn("UNKNOWN_OUTCOME_MUST_NOT_ASSERT_HEADS", result["findings"])

    def test_merge_authority_is_never_inherited(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt["merge_authorized"] = True
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertIn("MERGE_AUTHORITY_MUST_REMAIN_FALSE", result["findings"])

    def test_noop_requires_prior_receipt_reference(self) -> None:
        request = valid_request()
        receipt = valid_receipt(request)
        receipt.update({
            "result": "NOOP_IDEMPOTENT_ALREADY_APPLIED",
            "changed_paths": [],
            "path_readbacks": [],
        })
        result = validate_receipt(request, receipt, PROVIDERS)
        self.assertIn("NOOP_PRIOR_RECEIPT_REF_REQUIRED", result["findings"])


if __name__ == "__main__":
    unittest.main()
