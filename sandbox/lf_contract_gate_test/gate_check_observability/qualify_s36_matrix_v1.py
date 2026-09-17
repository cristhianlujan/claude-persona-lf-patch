#!/usr/bin/env python3
"""Project grouped gate evidence into the canonical S36 LF test-matrix shape.

This is a projection/qualification adapter only. It creates no parallel matrix
store and mutates no operational state.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path

REQUIRED_COLUMNS = [
    "family",
    "process",
    "scenario",
    "invariant",
    "dimension",
    "assurance_depth",
    "test_implementation",
    "environment",
    "source_sha",
    "input_vector",
    "result",
    "evidence_artifact",
    "timestamp",
    "owner_when_blocked",
]
REQUIRED_DIMENSIONS = {
    "FUNCTIONALITY",
    "QUALITY",
    "DEPTH",
    "PERFORMANCE",
    "EVIDENCE",
}
ALLOWED_DEPTHS = {
    "CONTRACT",
    "INTEGRATION",
    "ROUTER_TO_TERMINAL",
    "PATH_TRAJECTORY",
    "NEGATIVE",
    "EDGE",
    "ADVERSARIAL",
}


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AssertionError(f"OBJECT_REQUIRED:{path}")
    return value


def build_rows(manifest: dict, summary: dict, source_sha: str) -> list[dict]:
    group_results = {
        item["group_id"]: item for item in summary.get("groups") or []
    }
    rows: list[dict] = []
    for group in manifest.get("groups") or []:
        group_id = group["group_id"]
        result = group_results.get(group_id)
        if not result:
            raise AssertionError(f"MATRIX_GROUP_MISSING:{group_id}")

        dimensions = group.get("dimensions") or []
        if not dimensions:
            raise AssertionError(f"MATRIX_DIMENSIONS_MISSING:{group_id}")

        depth = group.get("assurance_depth")
        if depth not in ALLOWED_DEPTHS:
            raise AssertionError(
                f"MATRIX_DEPTH_INVALID:{group_id}:{depth}"
            )

        for dimension in dimensions:
            if dimension not in REQUIRED_DIMENSIONS:
                raise AssertionError(
                    f"MATRIX_DIMENSION_INVALID:{group_id}:{dimension}"
                )
            rows.append(
                {
                    "family": "RUNTIME_GOVERNANCE",
                    "process": "GATE_CHECK_OBSERVABILITY",
                    "scenario": group_id,
                    "invariant": group.get("name") or group_id,
                    "dimension": dimension,
                    "assurance_depth": depth,
                    "test_implementation": ";".join(group.get("tests") or []),
                    "environment": "GITHUB_ACTIONS_PR_EXACT_HEAD",
                    "source_sha": source_sha,
                    "input_vector": (
                        f"{len(group.get('tests') or [])}_DECLARED_TESTS"
                    ),
                    "result": result.get("result"),
                    "evidence_artifact": result.get("report_ref"),
                    "timestamp": summary.get("timestamp"),
                    "owner_when_blocked": (
                        manifest.get("owner")
                        if result.get("result") != "PASS"
                        else ""
                    ),
                }
            )
    return rows


def evaluate(
    manifest: dict,
    summary: dict,
    source_sha: str,
) -> tuple[bool, list[dict], list[str]]:
    errors: list[str] = []

    if manifest.get("canonical_matrix") != "S36_CANONICAL_LF_TEST_MATRIX":
        errors.append("CANONICAL_MATRIX_BINDING")
    if summary.get("gate_result") != "PASS":
        errors.append("GATE_RESULT")
    if summary.get("full_coverage") is not True:
        errors.append("FULL_COVERAGE")
    if summary.get("claim_ready") is not True:
        errors.append("CLAIM_READY")
    if summary.get("excel_ready") is not True:
        errors.append("EXCEL_READY")

    general = summary.get("prueba_a_nivel_general") or {}
    expected_total = int(manifest.get("expected_total_checks") or -2)
    if int(general.get("expected_check_count") or -1) != expected_total:
        errors.append("EXPECTED_CHECK_COUNT")
    if int(general.get("executed_check_count") or -1) != expected_total:
        errors.append("EXECUTED_CHECK_COUNT")

    performance = summary.get("performance_measurement") or {}
    duration = performance.get("total_duration_ms")
    if (
        performance.get("status") != "MEASURED"
        or not isinstance(duration, (int, float))
        or duration < 0
    ):
        errors.append("PERFORMANCE_MEASUREMENT")

    assigned = [
        test
        for group in manifest.get("groups") or []
        for test in group.get("tests") or []
    ]
    if (
        len(assigned) != len(set(assigned))
        or len(assigned) != expected_total
    ):
        errors.append("TEST_ASSIGNMENT")

    try:
        rows = build_rows(manifest, summary, source_sha)
    except AssertionError as exc:
        errors.append(str(exc))
        rows = []

    covered = {
        row["dimension"]
        for row in rows
        if row.get("result") == "PASS"
    }
    if covered != REQUIRED_DIMENSIONS:
        errors.append(
            "DIMENSION_COVERAGE:" + ",".join(sorted(covered))
        )

    for row in rows:
        if set(row) != set(REQUIRED_COLUMNS):
            errors.append("COLUMN_SHAPE")
        if row.get("result") != "PASS":
            errors.append("ROW_NOT_PASS:" + row.get("scenario", "?"))
        evidence = row.get("evidence_artifact")
        if not evidence or not Path(evidence).is_file():
            errors.append(
                "EVIDENCE_NOT_RESOLVABLE:" + row.get("scenario", "?")
            )

    return (not errors), rows, errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--artifact-dir", required=True)
    args = parser.parse_args()

    manifest = load(Path(args.manifest))
    summary = load(Path(args.summary))
    source_sha = os.environ.get("GITHUB_SHA") or "LOCAL"
    ok, rows, errors = evaluate(manifest, summary, source_sha)

    out = Path(args.artifact_dir)
    out.mkdir(parents=True, exist_ok=True)
    result = {
        "schema_version": "s36-canonical-lf-test-matrix-projection/v1",
        "canonical_matrix": "S36_CANONICAL_LF_TEST_MATRIX",
        "process": "GATE_CHECK_OBSERVABILITY",
        "result": "PASS_WITH_EVIDENCE" if ok else "FAIL",
        "row_count": len(rows),
        "required_dimensions": sorted(REQUIRED_DIMENSIONS),
        "covered_dimensions": sorted(
            {
                row["dimension"]
                for row in rows
                if row.get("result") == "PASS"
            }
        ),
        "source_sha": source_sha,
        "prueba_a_nivel_general": summary.get("prueba_a_nivel_general"),
        "prueba_paso_a_paso": summary.get("prueba_paso_a_paso"),
        "performance_measurement": summary.get("performance_measurement"),
        "errors": errors,
        "rows": rows,
    }

    (out / "s36_matrix_qualification_v1.json").write_text(
        json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    with (out / "s36_matrix_qualification_v1.csv").open(
        "w",
        newline="",
        encoding="utf-8",
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=REQUIRED_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    print(
        json.dumps(
            {
                key: result[key]
                for key in (
                    "canonical_matrix",
                    "process",
                    "result",
                    "row_count",
                    "covered_dimensions",
                    "source_sha",
                    "errors",
                )
            },
            sort_keys=True,
        )
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
