"""Synthetic G4 contract tests; callbacks are fakes, not valid production receipts."""
import copy
import unittest
from datetime import datetime, timezone
from ig_g4_authority_contract_probe_v1 import check_authority_contract

NOW = datetime(2026, 10, 28, tzinfo=timezone.utc)
REQ = {"rule_ref": "fixture:rule", "rule_sha256": "hash-rule", "selector_sha256": "hash-selector", "scope_diff_sha256": "hash-diff", "consumer": "CONTEXT_PACK", "operation": "CHANGE_RULE_SCOPE", "execution_id": "EXEC-FIXTURE-ROOT", "ig_run_id": 123}


def fixture(domains=("D1",)):
    source = {**REQ, "source_ref": "fixture:source", "source_sha256": "hash-source", "required_domains": list(domains), "allowed_consumers": ["CONTEXT_PACK"], "status": "ACTIVE"}
    routes = [{"domain": d, "operation": REQ["operation"], "status": "ACTIVE", "authority_ref": "fixture:authority:" + d} for d in domains]
    receipts = [{**REQ, "domain": d, "status": "VERIFIED", "authority_ref": "fixture:authority:" + d, "expires_at": "2026-12-01T00:00:00Z"} for d in domains]
    return source, routes, receipts


def check(source, routes, receipts, request=None, **kwargs):
    return check_authority_contract(request or REQ, source, routes, receipts, now=NOW, verify_source=lambda r: True, verify_receipt=lambda r: True, verify_run_binding=lambda r: True, **kwargs)


class G4Contract(unittest.TestCase):
    def setUp(self):
        self.source, self.routes, self.receipts = fixture()

    def test_one_domain_valid_shape(self):
        self.assertEqual(check(self.source, self.routes, self.receipts), "PROOF_READY_FOR_TECHNICAL_ADMISSION")

    def test_two_domains_both_required(self):
        source, routes, receipts = fixture(("D1", "D2"))
        self.assertEqual(check(source, routes, receipts), "PROOF_READY_FOR_TECHNICAL_ADMISSION")
        self.assertEqual(check(source, routes, receipts[:1]), "HOLD_RECEIPT_MISSING_OR_DUPLICATE")

    def test_unverified_source(self):
        result = check_authority_contract(REQ, self.source, self.routes, self.receipts, now=NOW, verify_run_binding=lambda r: True, verify_receipt=lambda r: True)
        self.assertEqual(result, "HOLD_SOURCE_UNVERIFIED")

    def test_unverified_receipt(self):
        result = check_authority_contract(REQ, self.source, self.routes, self.receipts, now=NOW, verify_run_binding=lambda r: True, verify_source=lambda r: True)
        self.assertEqual(result, "HOLD_RECEIPT_VERIFIER_MISSING")

    def test_wrong_operation(self):
        self.source["operation"] = "PROFILE_UPDATE"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_OPERATION_OR_SOURCE_MISMATCH")

    def test_wrong_source_selector(self):
        self.source["selector_sha256"] = "another"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_SOURCE_SCOPE_MISMATCH")

    def test_wrong_receipt_rule(self):
        self.receipts[0]["rule_ref"] = "other"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_SCOPE_MISMATCH")

    def test_wrong_receipt_consumer(self):
        self.receipts[0]["consumer"] = "MANUAL"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_SCOPE_MISMATCH")

    def test_wrong_receipt_diff(self):
        self.receipts[0]["scope_diff_sha256"] = "other"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_SCOPE_MISMATCH")

    def test_expired_receipt(self):
        self.receipts[0]["expires_at"] = "2026-01-01T00:00:00Z"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_EXPIRED")

    def test_revoked_receipt(self):
        self.receipts[0]["revoked"] = True
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_INACTIVE")

    def test_route_pending(self):
        self.routes[0]["status"] = "PENDING_AUTHORITY"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_ROUTE_NOT_UNIQUE_ACTIVE")

    def test_route_veto(self):
        self.routes[0]["veto"] = True
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_POLICY_VETO")

    def test_duplicate_receipt(self):
        self.receipts.append(copy.deepcopy(self.receipts[0]))
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_MISSING_OR_DUPLICATE")

    def test_duplicate_required_domain(self):
        self.source["required_domains"] = ["D1", "D1"]
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_AUTHORITY_DOMAINS_UNRESOLVED")

    def test_unapproved_consumer(self):
        self.source["allowed_consumers"] = ["MANUAL"]
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_CONSUMER_NOT_AUTHORIZED")

    def test_source_revoked(self):
        self.source["revoked"] = True
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_SOURCE_INACTIVE")

    def test_provenance_callback_false(self):
        result = check_authority_contract(REQ, self.source, self.routes, self.receipts, now=NOW, verify_run_binding=lambda r: True, verify_source=lambda r: True, verify_receipt=lambda r: False)
        self.assertEqual(result, "HOLD_RECEIPT_PROVENANCE_UNVERIFIED")

    def test_untrusted_domain_from_request_ignored(self):
        req = {**REQ, "required_domains": ["EASY"]}
        self.assertEqual(check(self.source, self.routes, self.receipts, req), "PROOF_READY_FOR_TECHNICAL_ADMISSION")

    def test_missing_root(self):
        request = dict(REQ)
        request.pop("execution_id")
        self.assertEqual(check(self.source, self.routes, self.receipts, request), "HOLD_RUN_BINDING_MISSING")

    def test_missing_child_run(self):
        request = dict(REQ, ig_run_id=None)
        self.assertEqual(check(self.source, self.routes, self.receipts, request), "HOLD_RUN_BINDING_MISSING")

    def test_no_trusted_run_link(self):
        outcome = check_authority_contract(
            REQ, self.source, self.routes, self.receipts, now=NOW,
            verify_source=lambda r: True, verify_receipt=lambda r: True)
        self.assertEqual(outcome, "HOLD_RUN_BINDING_UNVERIFIED")

    def test_receipt_with_other_root(self):
        self.receipts[0]["execution_id"] = "EXEC-OTHER"
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_RUN_MISMATCH")

    def test_receipt_with_other_child_run(self):
        self.receipts[0]["ig_run_id"] = 999
        self.assertEqual(check(self.source, self.routes, self.receipts), "HOLD_RECEIPT_RUN_MISMATCH")

    def test_run_link_rejected_by_canonical_reader(self):
        outcome = check_authority_contract(
            REQ, self.source, self.routes, self.receipts, now=NOW,
            verify_run_binding=lambda r: False, verify_source=lambda r: True,
            verify_receipt=lambda r: True)
        self.assertEqual(outcome, "HOLD_RUN_BINDING_UNVERIFIED")

    def test_no_authority_source(self):
        self.assertEqual(check(None, self.routes, self.receipts), "HOLD_SOURCE_UNVERIFIED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
