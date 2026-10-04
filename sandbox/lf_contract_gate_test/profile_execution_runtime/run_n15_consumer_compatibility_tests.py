#!/usr/bin/env python3
"""N-15 deterministic negatives for consumer contract identity/currentness."""
from __future__ import annotations

from pathlib import Path

from runtime_optimization_contract import governance_cache_key, governance_receipt_reusable

TOTAL = 0
PASS = 0


def check(name: str, condition: bool) -> None:
    global TOTAL, PASS
    TOTAL += 1
    if not condition:
        raise AssertionError(name)
    PASS += 1
    print(f"PASS N15 {name}")


revision = "5.13"
digest = "e" * 64
screen = "B2B-CARGA-001"
adapters = [{"adapter_code": "A1", "adapter_metadata": {"canonical_adapter_id": "ADAPTER_LF_SHELL_PROFILE"}}]
ready = {
    "applicable": True,
    "status": "READY",
    "continuation_allowed": True,
    "governance_receipt": {
        "decision": "PASS",
        "currentness": "LIVE_CURRENT",
        "screen_code": screen,
        "snapshot_hash": "b" * 64,
        "governance_version": revision,
        "contract_snapshot_hash": digest,
        "contract_snapshot_sha256": digest,
    },
}

check(
    "current_revision_digest_reusable",
    governance_receipt_reusable(
        ready,
        screen_code=screen,
        expected_contract_revision=revision,
        expected_contract_snapshot_sha256=digest,
    ),
)
check(
    "same_value_stale_revision_blocked",
    not governance_receipt_reusable(
        {**ready, "governance_receipt": {**ready["governance_receipt"], "governance_version": "5.12"}},
        screen_code=screen,
        expected_contract_revision=revision,
        expected_contract_snapshot_sha256=digest,
    ),
)
check(
    "same_value_stale_digest_blocked",
    not governance_receipt_reusable(
        {**ready, "governance_receipt": {**ready["governance_receipt"], "contract_snapshot_hash": "d" * 64, "contract_snapshot_sha256": "d" * 64}},
        screen_code=screen,
        expected_contract_revision=revision,
        expected_contract_snapshot_sha256=digest,
    ),
)
check(
    "partial_digest_projection_blocked",
    not governance_receipt_reusable(
        {**ready, "governance_receipt": {**ready["governance_receipt"], "contract_snapshot_hash": ""}},
        screen_code=screen,
        expected_contract_revision=revision,
        expected_contract_snapshot_sha256=digest,
    ),
)
check(
    "unknown_expected_identity_blocks_material_effect",
    not governance_receipt_reusable(
        ready,
        screen_code=screen,
        expected_contract_revision=revision,
        expected_contract_snapshot_sha256=None,
    ),
)
check(
    "not_required_does_not_global_block",
    governance_receipt_reusable(
        {"applicable": False, "status": "NOT_REQUIRED", "continuation_allowed": True},
        screen_code=None,
        expected_contract_revision=revision,
        expected_contract_snapshot_sha256=digest,
    ),
)

key = governance_cache_key(
    screen_code=screen,
    adapters=adapters,
    input_literal="review B2B-CARGA-001",
    contract_revision=revision,
    contract_snapshot_sha256=digest,
)
check(
    "contract_revision_invalidates_cache",
    key != governance_cache_key(
        screen_code=screen,
        adapters=adapters,
        input_literal="review B2B-CARGA-001",
        contract_revision="5.14",
        contract_snapshot_sha256=digest,
    ),
)
check(
    "contract_digest_invalidates_cache",
    key != governance_cache_key(
        screen_code=screen,
        adapters=adapters,
        input_literal="review B2B-CARGA-001",
        contract_revision=revision,
        contract_snapshot_sha256="c" * 64,
    ),
)

worker = Path(__file__).with_name("github_actions_batch_queue_worker.py").read_text(encoding="utf-8")
check("worker_uses_shared_version_compatibility", "fn_lf_version_compatibility_resolve_source_v1" in worker)
check("worker_has_no_local_readiness_revision_pin", "'5.13'" not in worker and '"5.13"' not in worker and "'5.12'" not in worker and '"5.12"' not in worker)
check("worker_binds_expected_revision", "expected_contract_revision=contract_revision" in worker)
check("worker_binds_expected_digest", "expected_contract_snapshot_sha256=contract_snapshot_sha256" in worker)
check("unknown_blocks_only_current_request", "BLOCK_INPUT_GOVERNANCE_CONTRACT_IDENTITY_UNRESOLVED" in worker and "preblocked[request_id]" in worker)

assert TOTAL == 13, TOTAL
assert PASS == TOTAL, (PASS, TOTAL)
print(f"N15_CONSUMER_COMPATIBILITY_CASES={PASS}/{TOTAL}")
