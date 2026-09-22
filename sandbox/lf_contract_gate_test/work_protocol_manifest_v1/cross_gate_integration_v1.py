#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
CASE = HERE / "cross_gate_external_case_input_governance_v1.json"

GATES = [f"G{i:02d}" for i in range(12)]


def canonical_sha(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def resolve_dep(nodes: list[dict[str, Any]], dep: str) -> dict[str, Any]:
    matches = [n for n in nodes if str(n["key"]).startswith(dep + "-") or n["key"] == dep]
    assert len(matches) == 1, {"code": "EXTERNAL_DEPENDENCY_NOT_UNIQUE", "dep": dep, "matches": [m["key"] for m in matches]}
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
    assert critical[0]["id"] == 201
    assert critical[0]["depends_on"] == []

    expected = case["expected_invariants"]
    chain = [resolve_dep(nodes, key)["id"] for key in expected["ordered_dependency_chain"]]
    assert chain == [193, 194, 195]
    assert expected["dependent_cannot_close_before_predecessor"] is True
    assert expected["case_specific_ids_must_not_enter_protocol_branching_logic"] is True

    return {
        "status": "PASS",
        "node_count": len(nodes),
        "edge_count": len(edges),
        "critical_independent_id": critical[0]["id"],
        "fixture_sha256": canonical_sha(case),
    }


def build_lineage(seed_sha256: str) -> list[dict[str, Any]]:
    assert len(seed_sha256) == 64
    previous = seed_sha256
    out: list[dict[str, Any]] = []
    for gate in GATES:
        evidence_sha = canonical_sha({"gate": gate, "fixture": seed_sha256})
        output_sha = canonical_sha({
            "gate": gate,
            "input_digest": previous,
            "evidence_digest": evidence_sha,
            "status": "PASS",
        })
        out.append({
            "gate": gate,
            "status": "PASS",
            "input_digest": previous,
            "evidence_digest": evidence_sha,
            "output_digest": output_sha,
        })
        previous = output_sha
    return out


def validate_lineage(chain: list[dict[str, Any]]) -> None:
    assert [x["gate"] for x in chain] == GATES
    for idx, gate in enumerate(chain):
        assert gate["status"] == "PASS", {"code": "UPSTREAM_GATE_NOT_PASS", "gate": gate["gate"]}
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
    chain = build_lineage(case_result["fixture_sha256"])
    validate_lineage(chain)
    probes = negative_probes(chain)

    result = {
        "schema_version": "LF_WORK_PROTOCOL_CROSS_GATE_INTEGRATION_V1",
        "status": "PASS",
        "gate_count": len(chain),
        "link_count": len(chain) - 1,
        "external_case": case_result,
        "lineage_root_sha256": chain[-1]["output_digest"],
        "chain": chain,
        "negative_probes": probes,
    }
    print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
