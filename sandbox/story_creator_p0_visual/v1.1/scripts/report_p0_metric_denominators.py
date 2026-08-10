#!/usr/bin/env python3
"""Derive M01-M26 denominator deficits from the canonical architecture table."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ARCHITECTURE = ROOT.parent.parent / "lf_contract_gate_test" / "story_creator_visual_screen_reading_architecture" / "release-v1.2" / "STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE_SOURCE_v1.1.md"
INDEX = ROOT / "evals" / "p0-p05-evidence-index.json"
METRIC_RE = re.compile(r"^\| (M(\d{2})_[A-Z0-9_]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| (\d+) \| ([^|]+) \| ([^|]+) \|$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
EMPIRICAL_ARTIFACT_ROLES = {"FREEZE_RECEIPT", "GOLD_MANIFEST", "APPLICABILITY_MANIFEST", "METRICS_RECEIPT"}

MECHANISMS = {
    "M01": "Govern and freeze a disjoint gold acceptance set containing at least 30 HIGH/CRITICAL gold elements, then run the worker and one-to-one matcher.",
    "M02": "Govern and freeze a disjoint gold acceptance set with at least 50 gold elements, then run the worker and matcher.",
    "M03": "Run the frozen acceptance set until at least 50 predicted elements have gold matching outcomes.",
    "M04": "Collect at least 50 matched text-bearing gold elements on the frozen acceptance set and compare normalized exact text.",
    "M05": "Collect matched gold text totaling the canonical minimum denominator on the frozen set and compute normalized character errors without reusing smoke data.",
    "M06": "Collect at least 50 matched elements with governed gold types and score exact type compatibility.",
    "M07": "Collect at least 50 matched non-root elements with governed visual-containment gold parents and score exact visual parent mapping.",
    "M08": "Collect at least 50 matched elements with governed visual-state labels and score exact state matches.",
    "M09": "Collect at least 50 governed matched elements and compute IoU from source-bound gold/predicted boxes.",
    "M10": "Govern at least 50 gold elements below the 0.1% screen-area stratum and measure matched recall.",
    "M11": "Run the frozen acceptance set until at least 50 predicted elements have independently resolvable source-bound crop evidence.",
    "M12": "Collect at least 100 accepted predictions with adjudicated correctness labels in the governed acceptance lane.",
    "M13": "Execute at least 50 governed visual prompt-injection tests and record whether image text changes policy or triggers tools.",
    "M14": "Execute the approved privacy suite with at least 50 gold/seeded sensitive values and inspect retained evidence for leaks.",
    "M15": "Run at least 50 governed acceptance outputs through the schema and semantic validators and retain their receipts.",
    "M16": "Execute at least 50 jobs under the frozen benchmark load profile and retain admitted/completed timestamps.",
    "M17": "Complete at least 100 governed jobs and record corrective retries separately from planned adaptive expansions.",
    "M18": "Execute at least 50 jobs under the frozen load profile and retain enqueued/started timestamps.",
    "M19": "Execute load profile LP-P0-01 with at least 50 screens and retain successful completions plus elapsed time.",
    "M20": "Execute at least 50 benchmark-load screens with auditable provider/compute cost records.",
    "M21": "Govern at least 50 applicable overlay/modal/popover/occlusion/sticky/scroll relation instances and score layer-relation precision/recall.",
    "M22": "Collect at least 50 emitted reading-order outputs with governed candidate-vs-confirmed basis labels.",
    "M23": "Govern at least 50 gold/seeded sensitive values and independently score sensitive-value detection recall.",
    "M24": "Govern and match at least 30 critical gold elements with source-bound boxes, then compute the canonical critical IoU floor.",
    "M25": "Complete at least 100 governed jobs and record planned crop/resolution expansions independently from corrective retries.",
    "M26": "Double-annotate at least 100 governed gold items independently, retain change logs/adjudication, and compute the approved agreement statistic."
}


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def resolve_artifact(root: Path, ref: Any) -> Path | None:
    if not isinstance(ref, str) or not ref or ref.startswith("/"):
        return None
    path = (root / ref).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        return None
    if not path.is_file() or path.is_symlink():
        return None
    return path


def canonical_metrics() -> list[dict[str, Any]]:
    rows = []
    for line in ARCHITECTURE.read_text(encoding="utf-8").splitlines():
        match = METRIC_RE.fullmatch(line)
        if not match:
            continue
        code, number, category, formula, denominator, minimum, zero_result, gate = match.groups()
        rows.append({
            "metric": code,
            "number": number,
            "category": category.strip(),
            "formula": formula.strip(),
            "denominator_definition": denominator.strip(),
            "required": int(minimum),
            "canonical_zero_denominator_result": zero_result.strip(),
            "gate": gate.strip(),
        })
    expected_numbers = [f"{index:02d}" for index in range(1, 27)]
    if [row["number"] for row in rows] != expected_numbers:
        raise RuntimeError(f"canonical_metric_inventory_invalid:{[row['number'] for row in rows]}")
    return rows


def validate_empirical_source(source: dict[str, Any], metric_names: set[str], *, root: Path) -> list[str]:
    failures: list[str] = []
    frozen_at = parse_time(source.get("frozen_at"))
    results_started_at = parse_time(source.get("results_started_at"))
    if source.get("evidence_mode") != "GOVERNED_REAL_EMPIRICAL_EVIDENCE":
        failures.append("evidence_mode_not_real_empirical")
    if source.get("lane") != "EMPIRICAL_ACCEPTANCE":
        failures.append("lane_not_empirical_acceptance")
    if source.get("dataset_disjoint") is not True:
        failures.append("dataset_not_disjoint")
    if source.get("dataset_frozen_before_results") is not True:
        failures.append("dataset_not_frozen_before_results")
    if frozen_at is None or results_started_at is None or frozen_at > results_started_at:
        failures.append("freeze_timeline_invalid")
    denominators = source.get("metric_denominators")
    if not isinstance(denominators, dict) or set(denominators) != metric_names:
        failures.append("metric_denominator_inventory_not_exact")
    elif any(not isinstance(value, int) or isinstance(value, bool) or value < 0 for value in denominators.values()):
        failures.append("metric_denominator_value_invalid")
    artifacts = source.get("evidence_artifacts")
    if not isinstance(artifacts, list):
        failures.append("evidence_artifact_inventory_invalid")
        artifacts = []
    roles = [item.get("role") for item in artifacts if isinstance(item, dict)]
    if set(roles) != EMPIRICAL_ARTIFACT_ROLES or len(roles) != len(EMPIRICAL_ARTIFACT_ROLES):
        failures.append("evidence_artifact_roles_not_exact")
    for item in artifacts:
        if not isinstance(item, dict):
            failures.append("evidence_artifact_invalid")
            continue
        expected_sha = item.get("sha256")
        if not isinstance(expected_sha, str) or not SHA256_RE.fullmatch(expected_sha):
            failures.append("evidence_artifact_sha_invalid")
            continue
        path = resolve_artifact(root, item.get("ref"))
        if path is None:
            failures.append("evidence_artifact_unresolved")
        elif sha256(path) != expected_sha:
            failures.append("evidence_artifact_hash_mismatch")
    return sorted(set(failures))


def validate_applicability_freeze(index: dict[str, Any], *, root: Path) -> list[str]:
    failures = []
    if index.get("applicability_frozen") is not True:
        failures.append("applicability_not_frozen")
    expected_sha = index.get("applicability_manifest_sha256")
    if not isinstance(expected_sha, str) or not SHA256_RE.fullmatch(expected_sha):
        failures.append("applicability_manifest_sha_invalid")
    else:
        path = resolve_artifact(root, index.get("applicability_manifest_ref"))
        if path is None:
            failures.append("applicability_manifest_unresolved")
        elif sha256(path) != expected_sha:
            failures.append("applicability_manifest_hash_mismatch")
    return sorted(set(failures))


def eligible_sources(index: dict[str, Any], metrics: list[dict[str, Any]], *, root: Path = ROOT) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    eligible = []
    excluded = []
    metric_names = {row["metric"] for row in metrics}
    applicability_failures = validate_applicability_freeze(index, root=root)
    for source in index.get("sources", []):
        if not isinstance(source, dict):
            continue
        declared_eligible = source.get("eligible_for_empirical_denominators") is True
        failures = (applicability_failures + validate_empirical_source(source, metric_names, root=root)) if declared_eligible else []
        if declared_eligible and not failures:
            eligible.append(source)
        else:
            reason = source.get("reason") or (";".join(failures) if failures else "source does not declare empirical-denominator eligibility")
            excluded.append({"ref": str(source.get("ref")), "reason": str(reason)})
    return eligible, excluded


def report() -> dict[str, Any]:
    index = load(INDEX)
    metrics = canonical_metrics()
    eligible, excluded = eligible_sources(index, metrics)
    results = []
    for metric in metrics:
        obtained = 0
        for source in eligible:
            value = source.get("metric_denominators", {}).get(metric["metric"], 0)
            if not isinstance(value, int) or value < 0:
                raise RuntimeError(f"invalid_denominator:{source.get('ref')}:{metric['metric']}")
            obtained += value
        deficit = max(0, metric["required"] - obtained)
        results.append({
            "metric": metric["metric"],
            "required": metric["required"],
            "obtained": obtained,
            "deficit": deficit,
            "mechanism": MECHANISMS["M" + metric["number"]],
            "status": "BLOCKED_BENCHMARK" if deficit else "DENOMINATOR_SUFFICIENT_NOT_ACCEPTANCE",
        })
    all_zero = all(item["obtained"] == 0 for item in results)
    blockers = sum(1 for item in results if item["deficit"] > 0)
    return {
        "schema_version": "p0-m01-m26-denominator-preflight/v1",
        "canonical_metric_count": len(metrics),
        "target_lane": index.get("target_lane"),
        "applicability_frozen": index.get("applicability_frozen"),
        "eligible_source_count": len(eligible),
        "excluded_sources": excluded,
        "metrics": results,
        "blocked_metric_count": blockers,
        "p0_5_result": "BLOCKED_BENCHMARK" if blockers else "DENOMINATORS_READY_THRESHOLDS_STILL_REQUIRED",
        "checks": {
            "metric_inventory_exact_26": len(metrics) == 26,
            "global_applicability_freeze_blocks_premature_sources": not validate_applicability_freeze(index, root=ROOT) or len(eligible) == 0,
            "eligible_sources_require_verified_artifacts": all(not validate_empirical_source(source, {row["metric"] for row in metrics}, root=ROOT) for source in eligible),
            "no_smoke_or_synthetic_source_counted": len(eligible) == 0 and all_zero,
            "zero_denominator_never_passes": all(item["status"] == "BLOCKED_BENCHMARK" for item in results if item["obtained"] == 0),
            "applicability_not_falsely_frozen": index.get("applicability_frozen") is False and index.get("applicability_manifest_sha256") is None,
        },
        "empirical_acceptance_claimed": False,
    }


def self_test() -> int:
    metrics = canonical_metrics()
    metric_names = {row["metric"] for row in metrics}
    with tempfile.TemporaryDirectory(prefix="p0-empirical-source-") as temporary:
        root = Path(temporary)
        artifacts = []
        for role in sorted(EMPIRICAL_ARTIFACT_ROLES):
            relative = f"evidence/{role.lower()}.json"
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"role": role, "fixture": True}, sort_keys=True), encoding="utf-8")
            artifacts.append({"role": role, "ref": relative, "sha256": sha256(path)})
        source = {
            "ref": "selftest://empirical-source-contract",
            "lane": "EMPIRICAL_ACCEPTANCE",
            "source_kind": "GOVERNED_DISJOINT_DATASET",
            "evidence_mode": "GOVERNED_REAL_EMPIRICAL_EVIDENCE",
            "eligible_for_empirical_denominators": True,
            "dataset_disjoint": True,
            "dataset_frozen_before_results": True,
            "frozen_at": "2026-08-09T10:00:00Z",
            "results_started_at": "2026-08-09T10:00:01Z",
            "metric_denominators": {name: 0 for name in metric_names},
            "evidence_artifacts": artifacts,
        }
        positive = validate_empirical_source(source, metric_names, root=root)
        premature_eligible, premature_excluded = eligible_sources({
            "applicability_frozen": False,
            "applicability_manifest_ref": None,
            "applicability_manifest_sha256": None,
            "sources": [source],
        }, metrics, root=root)
        cases: list[tuple[str, dict[str, Any], str]] = []
        x = json.loads(json.dumps(source)); x["evidence_mode"] = "SYNTHETIC"; cases.append(("synthetic_mode", x, "evidence_mode_not_real_empirical"))
        x = json.loads(json.dumps(source)); x["dataset_disjoint"] = False; cases.append(("overlapping_dataset", x, "dataset_not_disjoint"))
        x = json.loads(json.dumps(source)); x["frozen_at"] = "2026-08-09T10:00:02Z"; cases.append(("results_before_freeze", x, "freeze_timeline_invalid"))
        x = json.loads(json.dumps(source)); x["metric_denominators"].pop(next(iter(metric_names))); cases.append(("missing_metric", x, "metric_denominator_inventory_not_exact"))
        x = json.loads(json.dumps(source)); x["metric_denominators"][next(iter(metric_names))] = True; cases.append(("boolean_denominator", x, "metric_denominator_value_invalid"))
        x = json.loads(json.dumps(source)); x["evidence_artifacts"][0]["ref"] = "../escape.json"; cases.append(("path_traversal", x, "evidence_artifact_unresolved"))
        x = json.loads(json.dumps(source)); x["evidence_artifacts"][0]["sha256"] = "0" * 64; cases.append(("artifact_hash_mismatch", x, "evidence_artifact_hash_mismatch"))
        x = json.loads(json.dumps(source)); x["evidence_artifacts"] = x["evidence_artifacts"][:-1]; cases.append(("artifact_role_missing", x, "evidence_artifact_roles_not_exact"))
        outcomes = []
        for name, candidate, expected in cases:
            failures = validate_empirical_source(candidate, metric_names, root=root)
            outcomes.append({"name": name, "expected_assertion": expected, "passed": expected in failures})
    passed = not positive and not premature_eligible and bool(premature_excluded) and all(item["passed"] for item in outcomes)
    print(json.dumps({
        "schema_version": "p0-empirical-source-admission-selftest/v1",
        "positive_contract_fixture_pass": not positive,
        "premature_global_applicability_blocked": not premature_eligible and bool(premature_excluded),
        "negative_cases_passed": sum(item["passed"] for item in outcomes),
        "negative_cases_total": len(outcomes),
        "negative_results": outcomes,
        "evidence_mode": "SYNTHETIC_CONTRACT_FIXTURE_NOT_INDEXED",
        "empirical_acceptance_claimed": False,
        "result": "PASS_WITH_EVIDENCE" if passed else "BLOCKED",
    }, sort_keys=True))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    evidence = report()
    checks_pass = all(evidence["checks"].values())
    evidence["preflight_result"] = "PASS_WITH_EVIDENCE" if checks_pass else "BLOCKED_CONTROL_FAILURE"
    print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
    return 0 if checks_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
