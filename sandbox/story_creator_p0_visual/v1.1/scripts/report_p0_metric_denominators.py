#!/usr/bin/env python3
"""Derive M01-M26 denominator deficits from the canonical architecture table."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ARCHITECTURE = ROOT.parent.parent / "lf_contract_gate_test" / "story_creator_visual_screen_reading_architecture" / "release-v1.2" / "STORY_CREATOR_VISUAL_SCREEN_READING_ARCHITECTURE_SOURCE_v1.1.md"
INDEX = ROOT / "evals" / "p0-p05-evidence-index.json"
METRIC_RE = re.compile(r"^\| (M(\d{2})_[A-Z0-9_]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| (\d+) \| ([^|]+) \| ([^|]+) \|$")

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


def eligible_sources(index: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    eligible = []
    excluded = []
    for source in index.get("sources", []):
        if not isinstance(source, dict):
            continue
        governed = (
            source.get("eligible_for_empirical_denominators") is True
            and source.get("lane") == "EMPIRICAL_ACCEPTANCE"
            and source.get("dataset_disjoint") is True
            and source.get("dataset_frozen_before_results") is True
            and isinstance(source.get("metric_denominators"), dict)
        )
        if governed:
            eligible.append(source)
        else:
            excluded.append({"ref": str(source.get("ref")), "reason": str(source.get("reason") or "source does not satisfy empirical-acceptance governance")})
    return eligible, excluded


def report() -> dict[str, Any]:
    index = load(INDEX)
    metrics = canonical_metrics()
    eligible, excluded = eligible_sources(index)
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
            "no_smoke_or_synthetic_source_counted": len(eligible) == 0 and all_zero,
            "zero_denominator_never_passes": all(item["status"] == "BLOCKED_BENCHMARK" for item in results if item["obtained"] == 0),
            "applicability_not_falsely_frozen": index.get("applicability_frozen") is False and index.get("applicability_manifest_sha256") is None,
        },
        "empirical_acceptance_claimed": False,
    }


def main() -> int:
    evidence = report()
    checks_pass = all(evidence["checks"].values())
    evidence["preflight_result"] = "PASS_WITH_EVIDENCE" if checks_pass else "BLOCKED_CONTROL_FAILURE"
    print(json.dumps(evidence, ensure_ascii=False, sort_keys=True))
    return 0 if checks_pass else 2


if __name__ == "__main__":
    raise SystemExit(main())
