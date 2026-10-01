#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE_PATH = HERE / "capability_execution_contract_v1.py"


def load_module():
    spec = importlib.util.spec_from_file_location("capability_execution_contract_v1_tested", MODULE_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def sha(ch: str) -> str:
    return ch * 64


def authorities() -> dict:
    return {
        "governance_admin": {"ref": "contract://LF_GOVERNANCE_SUPER_ADMIN_V1", "revision": "v1", "digest": sha("a")},
        "owner_runner_carrier": {"ref": "github://OWNER_RUNNER_CARRIER_AUTHORITY_V1", "revision": "bdad31a", "digest": sha("b")},
        "entry_guard": {"ref": "supabase://fn_lf_capability_orchestrator_entry_guard_v1", "revision": "20260930082944", "digest": sha("c")},
        "evidence_ledger": {"ref": "supabase://private.lf_evidence_ledger_v1", "revision": "20260930133539", "digest": sha("d")},
    }


def guard(receipt_id: str) -> dict:
    return {
        "ready": True,
        "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
        "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "orchestrator_execution_id": "EXEC-ORCH-001",
        "receipt_id": receipt_id,
    }


def expect_block(R, fn, marker: str) -> None:
    try:
        fn()
    except R.ContractError as exc:
        assert marker in str(exc), (marker, str(exc))
    else:
        raise AssertionError(f"expected block: {marker}")


def main() -> None:
    R = load_module()
    receipt_id = "11111111-1111-4111-8111-111111111111"
    request = R.build_request(
        orchestrator_execution_id="EXEC-ORCH-001",
        consumer_execution_id="EXEC-CONSUMER-001",
        capability_code="MIGRATION_SOURCE_PARITY",
        plan_digest=sha("1"),
        dispatch_receipt_id=receipt_id,
        dispatch_scope={"subject_ref": "github://repo/pr/1", "control_id": "MIGRATION_SOURCE_PARITY"},
        entry_guard_readback=guard(receipt_id),
        authority_refs=authorities(),
        input_ref="github://repo@head/input.json",
        input_digest=sha("2"),
        source_revision="0123456789abcdef0123456789abcdef01234567",
    )
    checks = 0
    R.validate_request(request)
    checks += 1

    receipt = R.build_receipt(
        request,
        output_ref="evidence://migration-source-parity/result",
        output_digest=sha("3"),
        evidence_refs=[{"ref": "ledger://receipt/1", "digest": sha("4")}],
    )
    R.validate_receipt(request, receipt)
    checks += 1

    bad = copy.deepcopy(request)
    bad["entry_guard_readback"]["decision"] = "OTHER"
    bad["request_digest"] = R.digest({k: v for k, v in bad.items() if k != "request_digest"})
    expect_block(R, lambda: R.validate_request(bad), "BLOCK_ORCHESTRATOR_ENTRY_DECISION")
    checks += 1

    bad = copy.deepcopy(request)
    bad["entry_guard_readback"]["receipt_id"] = "22222222-2222-4222-8222-222222222222"
    bad["request_digest"] = R.digest({k: v for k, v in bad.items() if k != "request_digest"})
    expect_block(R, lambda: R.validate_request(bad), "BLOCK_DISPATCH_RECEIPT_CROSSBIND")
    checks += 1

    bad = copy.deepcopy(request)
    bad["dispatch_scope"]["control_id"] = "OTHER"
    bad["request_digest"] = R.digest({k: v for k, v in bad.items() if k != "request_digest"})
    expect_block(R, lambda: R.validate_request(bad), "BLOCK_DISPATCH_SCOPE_DIGEST")
    checks += 1

    bad = copy.deepcopy(request)
    del bad["authority_refs"]["evidence_ledger"]
    bad["request_digest"] = R.digest({k: v for k, v in bad.items() if k != "request_digest"})
    expect_block(R, lambda: R.validate_request(bad), "BLOCK_AUTHORITY_REF_MISSING")
    checks += 1

    bad = copy.deepcopy(request)
    bad["authority_refs"]["entry_guard"]["digest"] = "bad"
    bad["request_digest"] = R.digest({k: v for k, v in bad.items() if k != "request_digest"})
    expect_block(R, lambda: R.validate_request(bad), "BLOCK_AUTHORITY_REF_INVALID:entry_guard")
    checks += 1

    bad = copy.deepcopy(request)
    bad["plan_digest"] = "bad"
    bad["request_digest"] = R.digest({k: v for k, v in bad.items() if k != "request_digest"})
    expect_block(R, lambda: R.validate_request(bad), "BLOCK_REQUEST_DIGEST")
    checks += 1

    bad_receipt = copy.deepcopy(receipt)
    bad_receipt["consumed_request_digest"] = sha("5")
    bad_receipt["receipt_digest"] = R.digest({k: v for k, v in bad_receipt.items() if k != "receipt_digest"})
    expect_block(R, lambda: R.validate_receipt(request, bad_receipt), "BLOCK_REQUEST_CONSUMPTION")
    checks += 1

    bad_receipt = copy.deepcopy(receipt)
    bad_receipt["capability_code"] = "OTHER"
    bad_receipt["receipt_digest"] = R.digest({k: v for k, v in bad_receipt.items() if k != "receipt_digest"})
    expect_block(R, lambda: R.validate_receipt(request, bad_receipt), "BLOCK_RECEIPT_CROSSBIND:capability_code")
    checks += 1

    bad_receipt = copy.deepcopy(receipt)
    bad_receipt["output_digest"] = "bad"
    bad_receipt["receipt_digest"] = R.digest({k: v for k, v in bad_receipt.items() if k != "receipt_digest"})
    expect_block(R, lambda: R.validate_receipt(request, bad_receipt), "BLOCK_OUTPUT_EVIDENCE")
    checks += 1

    bad_receipt = copy.deepcopy(receipt)
    bad_receipt["evidence_refs"] = []
    bad_receipt["receipt_digest"] = R.digest({k: v for k, v in bad_receipt.items() if k != "receipt_digest"})
    expect_block(R, lambda: R.validate_receipt(request, bad_receipt), "BLOCK_EVIDENCE_REFS")
    checks += 1

    bad_receipt = copy.deepcopy(receipt)
    bad_receipt["self_authorized"] = True
    bad_receipt["receipt_digest"] = R.digest({k: v for k, v in bad_receipt.items() if k != "receipt_digest"})
    expect_block(R, lambda: R.validate_receipt(request, bad_receipt), "BLOCK_SELF_AUTHORIZATION")
    checks += 1

    bad_receipt = copy.deepcopy(receipt)
    bad_receipt["receipt_digest"] = sha("f")
    expect_block(R, lambda: R.validate_receipt(request, bad_receipt), "BLOCK_RECEIPT_DIGEST_MISMATCH")
    checks += 1

    print(f"PASS_CAPABILITY_EXECUTION_CONTRACT_V1 checks={checks}")


if __name__ == "__main__":
    main()
