#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RESULT = HERE / "s30_d_r09_frozen_result.json"
CORPUS = HERE / "r09_corpus_v1.json"
MANIFEST = HERE / "r09_manifest_v1.json"
MATRIX = HERE / "receipt_matrix_v1.json"
ROUTE = HERE / "snapshot_reconciliation_route_v1.json"
C_RECEIPT = ROOT / "sandbox/lf_contract_gate_test/s30_c_reliability_harness/s30_c_frozen_receipt_r02.json"
C_DIR = C_RECEIPT.parent


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def blobsha(path):
    b = path.read_bytes()
    return hashlib.sha1(f"blob {len(b)}\0".encode("ascii") + b).hexdigest()


def verify():
    required = [RESULT, CORPUS, MANIFEST, MATRIX, ROUTE, C_RECEIPT]
    missing = [str(p.relative_to(ROOT)) for p in required if not p.is_file()]
    assert not missing, f"MISSING:{missing}"
    result, corpus, manifest, matrix, route, c = map(load, required)
    assert result["result"] == "S30_P0_SELF_GOVERNANCE_R09_PASS"
    assert result["r09"]["source_commit_sha"] == "e3607db04dc5e6589ef5764e8a4666c5ae7bd905"
    assert result["r09"]["workflow_run_id"] == 34415172598
    assert result["r09"]["job_id"] == 102678344050
    assert result["r09"]["workflow_conclusion"] == "SUCCESS"
    assert result["r09"]["r09_step_conclusion"] == "SUCCESS"
    observed_corpus_sha = sha256(CORPUS)
    assert observed_corpus_sha == "1a515ab6b11e441f7c21451061e391e7f86be16c39393c3a2049bd33546348fa"
    assert manifest["corpus_sha256"] == observed_corpus_sha
    assert corpus["case_count"] == 46 and len(corpus["cases"]) == 46
    assert len({row[0] for row in corpus["cases"]}) == 46
    metrics = result["metrics"]
    assert metrics["TOTAL_REPLAY_CASES"] == 46
    assert all(value == 0 for key, value in metrics.items() if key != "TOTAL_REPLAY_CASES")
    assert result["expected_not_applicable"] == {"count": 2, "correct": True, "cases": ["E03", "E04"]}
    assert result["self_application"]["case_count"] == 7
    assert result["self_application"]["all_blocked_at_expected_first_bad_hop"] is True
    assert all(matrix["lanes"][lane]["status"] == "CURRENT" for lane in ("A", "B", "C"))
    assert result["interfaces"] == {"PREEXECUTION_ASSURANCE_RESULT": "PASS", "PREEXECUTION_DATA_ACCESS_RESULT": "PASS", "S30_C_FROZEN_EVIDENCE": "VALID"}
    for name, expected in c["artifacts"].items():
        path = C_DIR / name
        assert path.is_file() and blobsha(path) == expected, f"C_BLOB_DRIFT:{name}"
    assert route["snapshot"]["id"] == 35
    assert route["snapshot"]["status"] == "CANDIDATO_READ_ONLY"
    assert route["snapshot"]["runtime_state"] == "PLAN_ONLY"
    assert route["snapshot"]["impact_policy"] == "BLOQUEADO"
    assert route["governed_operation"]["operation_code"] == "ACTUALIZACION_ESTRATEGIA_LF"
    allowed = route["governed_operation"]["allowed"]
    assert allowed["existing_snapshot_update"] is True and allowed["supabase_snapshot_write"] is True
    assert allowed["runtime_change"] is False and allowed["production_change"] is False
    assert route["route_result"] == "GOVERNED_RECONCILIATION_PATH_AVAILABLE"
    assert route["write_executed"] is False
    assert result["open_blockers"] == []
    assert result["next_gate"] == "C05_DYNAMIC_IDEMPOTENCY_LEASE_FIRE_TEST_BEFORE_OPERATION_BOOTSTRAP"
    assert result["current_main_sha"] == "d75b7c15dac66ed9ae9f7b1cf78fb8ee3872d921"
    return {"receipt_version": "S30-D-R09-INDEPENDENT-READBACK-v1", "result": "PASS", "frozen_result": result["result"], "r09_source_commit_sha": result["r09"]["source_commit_sha"], "r09_workflow_run_id": result["r09"]["workflow_run_id"], "corpus_sha256_recomputed": observed_corpus_sha, "total_replay_cases": 46, "preventable_first_hop_escape_count": 0, "self_application_case_count": 7, "snapshot_reconciliation_path": route["route_result"], "snapshot_write_executed": False}


if __name__ == "__main__":
    print(json.dumps(verify(), sort_keys=True))
