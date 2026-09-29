from __future__ import annotations

import copy
import json
from unittest.mock import patch

import pytest

from . import test_governed_profile_operation_bridge as bridge

worker = bridge.worker


@pytest.fixture
def relay():
    request = {
        "request_id": "review-1", "profile_code": "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF",
        "profile_slug": "systemic_root_cause_repair_lf", "producer_execution_id": "EXEC-PRODUCER-001",
        "reviewer_execution_id": "EXEC-REVIEWER-001", "producer_execution_receipt_ref": "producer://1",
        "semantic_execution_receipt_ref": "review://1", "candidate": {"profile_pack_id": "PACK"},
        "semantic_result": {"verdict": "PASS_INDEPENDENT_SEMANTIC", "blocking_codes": [], "unsupported_claims": []},
    }
    steps = {
        "execute_profile": {"status": "STEP_PASS_WITH_EVIDENCE", "evidence_ref": "producer://1",
                            "evidence_payload": {"profile_output": request["candidate"]}},
        "output_validate": {"status": "STEP_PASS_WITH_EVIDENCE", "evidence_payload": {}},
    }
    response = {**{key: request[key] for key in ("request_id", "profile_code", "profile_slug")},
                "kind": "semantic_quality_finalize", "result": {
                    "status": "PASS", "blocking_codes": [], "canonical_quality_accepted": True,
                    "quality_receipt": {"decision": "PASS_TO_QUALITY_PACK"},
                }}
    writes = []

    class Cursor:
        def __enter__(self): return self
        def __exit__(self, *_): pass

    class Connection(bridge.FakeConn):
        def cursor(self): return Cursor()

    def record(_cur, _sql, params):
        execution_id, step_id, ref, payload, actor = params
        assert execution_id == actor == request["producer_execution_id"]
        writes.append(step_id)
        steps[step_id] = {"status": "STEP_PASS_WITH_EVIDENCE", "evidence_ref": ref, "evidence_payload": payload.obj}
        return {"outcome": "STEP_RECORDED"}

    with (
        patch.object(worker, "_read_governed_step", side_effect=lambda _cur, _execution, step: steps.get(step)),
        patch.object(worker, "_fetch_json_scalar", side_effect=record),
        patch.object(worker, "_api_json", return_value=response) as api,
    ):
        yield request, steps, response, writes, Connection(), api


def test_review_relay_calls_pure_finalizer_then_records_and_reads_back(relay):
    request, _, _, writes, conn, api = relay
    result = worker.finalize_semantic_quality_review(conn, request)
    api.assert_called_once_with("POST", "/v1/profile/semantic-quality-finalize", request)
    assert writes == ["semantic_judge", "report_output"]
    assert result["status"] == "COMPLETED"
    assert result["persistence_readback"] == "PASS"
    assert result["downstream_authorized"] is False


@pytest.mark.parametrize("mutation", ["candidate", "producer_ref", "predecessor"])
def test_review_relay_rejects_stale_or_unbound_producer_before_api(relay, mutation):
    request, steps, _, writes, conn, api = relay
    request = copy.deepcopy(request)
    if mutation == "candidate": request["candidate"]["changed"] = True
    elif mutation == "producer_ref": request["producer_execution_receipt_ref"] = "producer://other"
    else: steps["output_validate"]["status"] = "BLOCKED"
    result = worker.finalize_semantic_quality_review(conn, request)
    assert result["status"] == "BLOCKED"
    assert not writes
    api.assert_not_called()


@pytest.mark.parametrize("mutation", ["request_id", "failed_review", "blockers", "negative_receipt"])
def test_review_relay_never_persists_nonaccepted_or_mismatched_review(relay, mutation):
    request, _, response, writes, conn, _ = relay
    if mutation == "request_id": response["request_id"] = "other"
    elif mutation == "failed_review": response["result"]["canonical_quality_accepted"] = False
    elif mutation == "blockers": response["result"]["blocking_codes"] = ["UNRESOLVED"]
    else: response["result"]["quality_receipt"]["decision"] = "BLOCK_PIPELINE"
    result = worker.finalize_semantic_quality_review(conn, request)
    assert result["status"] == "BLOCKED"
    assert not writes


def test_recording_success_without_exact_readback_is_not_completion(relay):
    request, steps, _, writes, conn, _ = relay

    def read(_cur, _execution, step):
        return None if step == "report_output" else steps.get(step)

    with patch.object(worker, "_read_governed_step", side_effect=read):
        result = worker.finalize_semantic_quality_review(conn, request)
    assert writes == ["semantic_judge", "report_output"]
    assert result["error_code"] == "SEMANTIC_QUALITY_PERSISTENCE_READBACK_MISMATCH"


def test_worker_review_entrypoint_uses_relay_without_running_producer(relay, tmp_path):
    request, _, _, writes, conn, _ = relay
    path = tmp_path / "independent-review.json"
    path.write_text(json.dumps(request))
    with (
        patch.object(worker, "_connect", return_value=conn),
        patch.object(worker, "run_once", side_effect=AssertionError("producer must not run")),
        patch("sys.argv", ["worker", "--semantic-review", str(path)]),
    ):
        assert worker.main() == 0
    assert writes == ["semantic_judge", "report_output"]
