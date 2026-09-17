#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

path = Path(__file__).with_name("qualify_s36_matrix_v1.py")
spec = importlib.util.spec_from_file_location("matrix_qualifier", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temp_dir:
    root = Path(temp_dir)
    groups = []
    results = []
    definitions = [
        ("G1", ["FUNCTIONALITY", "EVIDENCE"], "CONTRACT"),
        ("G2", ["QUALITY", "DEPTH"], "ADVERSARIAL"),
        ("G3", ["PERFORMANCE"], "INTEGRATION"),
    ]
    for index, (group_id, dimensions, depth) in enumerate(definitions, 1):
        evidence = root / f"{group_id}.json"
        evidence.write_text("{}\n", encoding="utf-8")
        groups.append(
            {
                "group_id": group_id,
                "name": group_id,
                "dimensions": dimensions,
                "assurance_depth": depth,
                "tests": [f"test_{index}.py"],
            }
        )
        results.append(
            {
                "group_id": group_id,
                "result": "PASS",
                "report_ref": str(evidence),
                "duration_ms": 1.0,
            }
        )

    manifest = {
        "canonical_matrix": "S36_CANONICAL_LF_TEST_MATRIX",
        "owner": "TEST_OWNER",
        "expected_total_checks": 3,
        "groups": groups,
    }
    summary = {
        "gate_result": "PASS",
        "full_coverage": True,
        "claim_ready": True,
        "excel_ready": True,
        "timestamp": "2026-09-17T00:00:00Z",
        "performance_measurement": {
            "status": "MEASURED",
            "total_duration_ms": 3.0,
        },
        "prueba_a_nivel_general": {
            "expected_check_count": 3,
            "executed_check_count": 3,
        },
        "prueba_paso_a_paso": results,
        "groups": results,
    }

    ok, rows, errors = module.evaluate(
        manifest,
        summary,
        "a" * 40,
    )
    assert ok, (rows, errors)

    bad = json.loads(json.dumps(summary))
    bad["full_coverage"] = False
    assert not module.evaluate(manifest, bad, "a" * 40)[0]

print("S36_MATRIX_QUALIFIER_SELFTEST_PASS")
