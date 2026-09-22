#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CASE = HERE / "cross_gate_external_case_input_governance_v1.json"
G09 = HERE / "g09_cold_replay_v1.py"

GATES = [f"G{i:02d}" for i in range(10)]


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def resolve_dep(nodes: list[dict[str, Any]], dep: str) -> dict[str, Any]:
    matches = [n for n in nodes if str(n["key"]).startswith(dep + "-") or n["key"] == dep]
    assert len(matches) == 1, {
        "code": "EXTERNAL_DEPENDENCY_NOT_UNIQUE",
        "dep": dep,
        "matches": [m["key"] for m in matches],
    }
    return matches[0]


def validate_external_case(case: dict[str, Any]) -> dict[str, Any]:
    assert case["schema_version"] == "LF_WORK_PROTOCOL_CROSS_GATE_EXTERNAL_CASE_V1"
    nodes = case["nodes"]
    assert len(nodes) == 9
    assert len({n["id"] for n in nodes}) == len(nodes)
    assert len({n["key"] for n in nodes}) == len(nodes)

    ordered = sorted(nodes, key=lambda n: n["sequence"])
    assert [n["sequence"] for n in ordered] == list(range(1, 10))

    edges: list[tuple[str, str]] = []
    for node in nodes:
        for dep in node["depends_on"]:
            predecessor = resolve_dep(nodes, dep)
            assert predecessor["sequence"] < node["sequence"], {
                "code": "DEPENDENCY_SEQUENCE_INVALID",
                "predecessor": predecessor["key"],
                "dependent": node["key"],
            }
            edges.append((predecessor["key"], node["key"]))

    critical = [n for n in nodes if n["priority"] == "CRITICA"]
    assert len(critical) == 1
    assert critical[0]["depends_on"] == []

    expected = case["expected_invariants"]
    chain_ids = [resolve_dep(nodes, key)["id"] for key in expected["ordered_dependency_chain"]]
    assert chain_ids == [193, 194, 195]
    assert expected["dependent_cannot_close_before_predecessor"] is True
    assert expected["case_specific_ids_must_not_enter_protocol_branching_logic"] is True

    return {
        "status": "PASS",
        "node_count": len(nodes),
        "edge_count": len(edges),
        "critical_independent_count": len(critical),
        "fixture_sha256": canonical_sha(case),
    }


def run_g09() -> dict[str, Any]:
    proc = subprocess.run(
        [sys.executable, str(G09)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=120,
        check=False,
    )
    assert proc.returncode == 0, {
        "code": "CROSS_GATE_G09_EXECUTION_FAILED",
        "returncode": proc.returncode,
        "stdout": proc.stdout[-4000:],
        "stderr": proc.stderr[-4000:],
    }
    payload = json.loads(proc.stdout)
    assert payload["status"] == "PASS", payload
    assert payload["gate_count"] == 9, payload
    assert payload["dimension_count"] == 5, payload
    assert payload["matrix_case_count"] == 45, payload
    assert payload["cold_replay"]["status"] == "PASS", payload
    assert payload["cold_replay"]["byte_equivalent_canonical_json"] is True, payload
    return payload


def build_real_lineage(seed_sha256: str, g09: dict[str, Any]) -> list[dict[str, Any]]:
    assert len(seed_sha256) == 64
    previous = seed_sha256
    chain: list[dict[str, Any]] = []

    for idx in range(9):
        gate = f"G{idx:02d}"
        row = g09["matrix_results"][gate]
        assert row == {
            "positive": "PASS",
            "negative": "PASS",
            "drift": "PASS",
            "bypass": "PASS",
            "timeout": "PASS",
        }, (gate, row)
        evidence = {
            "gate": gate,
            "matrix_row": row,
            "matrix_sha256": g09["matrix_sha256"],
            "validator_self_test_sha256": g09["validator_self_test_sha256"],
        }
        evidence_sha = canonical_sha(evidence)
        output_sha = canonical_sha({
            "gate": gate,
            "input_digest": previous,
            "evidence_digest": evidence_sha,
            "status": "PASS",
        })
        chain.append({
            "gate": gate,
            "status": "PASS",
            "evidence_source": "G09_EXECUTED_MATRIX",
            "input_digest": previous,
            "evidence_digest": evidence_sha,
            "output_digest": output_sha,
        })
        previous = output_sha

    g09_evidence = {
        "gate": "G09",
        "matrix_sha256": g09["matrix_sha256"],
        "validator_self_test_sha256": g09["validator_self_test_sha256"],
        "cold_replay": g09["cold_replay"],
    }
    evidence_sha = canonical_sha(g09_evidence)
    output_sha = canonical_sha({
        "gate": "G09",
        "input_digest": previous,
        "evidence_digest": evidence_sha,
        "status": "PASS",
    })
    chain.append({
        "gate": "G09",
        "status": "PASS",
        "evidence_source": "G09_COLD_REPLAY",
        "input_digest": previous,
        "evidence_digest": evidence_sha,
        "output_digest": output_sha,
    })
    return chain


def validate_lineage(chain: list[dict[str, Any]]) -> None:
    assert [x["gate"] for x in chain] == GATES
    for idx, gate in enumerate(chain):
        assert gate["status"] == "PASS", {
            "code": "UPSTREAM_GATE_NOT_PASS",
            "gate": gate["gate"],
        }
        if idx:
            assert gate["input_digest"] == chain[idx - 1]["output_digest"], {
                "code": "CROSS_GATE_DIGEST_LINK_BROKEN",
                "predecessor": chain[idx - 1]["gate"],
                "gate": gate["gate"],
            }


def negative_probes(chain: list[dict[str, Any]]) -> dict[str, str]:
    results: dict[str, str] = {}

    missing = [dict(x) for x in chain if x["gate"] != "G02"]
    try:
        validate_lineage(missing)
    except AssertionError:
        results["missing_intermediate_gate_blocks_global_close"] = "PASS"
    else:
        raise AssertionError("missing G02 was accepted")

    tampered = [dict(x) for x in chain]
    tampered[4]["output_digest"] = "0" * 64
    try:
        validate_lineage(tampered)
    except AssertionError:
        results["mutated_predecessor_digest_blocks_successor"] = "PASS"
    else:
        raise AssertionError("tampered G04 output was accepted by G05")

    blocked = [dict(x) for x in chain]
    blocked[7]["status"] = "BLOCKED"
    try:
        validate_lineage(blocked)
    except AssertionError:
        results["blocked_upstream_gate_blocks_downstream_chain"] = "PASS"
    else:
        raise AssertionError("blocked G07 was accepted")

    return results


def main() -> int:
    case = json.loads(CASE.read_text(encoding="utf-8"))
    case_result = validate_external_case(case)
    g09 = run_g09()
    chain = build_real_lineage(case_result["fixture_sha256"], g09)
    validate_lineage(chain)
    probes = negative_probes(chain)

    gate_status = {row["gate"]: "READBACK_CLOSED" for row in chain}
    result = {
        "schema_version": "LF_WORK_PROTOCOL_CROSS_GATE_INTEGRATION_V1",
        "status": "PASS",
        "gate_count": len(chain),
        "link_count": len(chain) - 1,
        "external_case": case_result,
        "g09_summary": {
            "status": g09["status"],
            "gate_count": g09["gate_count"],
            "dimension_count": g09["dimension_count"],
            "matrix_case_count": g09["matrix_case_count"],
            "cold_replay_sha256": g09["cold_replay"]["replay_sha256"],
            "matrix_sha256": g09["matrix_sha256"],
            "validator_self_test_sha256": g09["validator_self_test_sha256"],
        },
        "gate_status": gate_status,
        "lineage_root_sha256": chain[-1]["output_digest"],
        "chain": chain,
        "negative_probes": probes,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
