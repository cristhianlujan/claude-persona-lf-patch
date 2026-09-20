from __future__ import annotations

import json
import statistics
import sys
from pathlib import Path
from typing import Any, Mapping

RECEIPT_SCHEMA = "LF_4D_AB_RECEIPT_V1"
REQUIRED_DIMENSIONS = ("quality", "functionality", "depth", "performance")


def _ratio(passed: Any, total: Any) -> float | None:
    if not isinstance(passed, int) or isinstance(passed, bool):
        return None
    if not isinstance(total, int) or isinstance(total, bool) or total <= 0:
        return None
    if passed < 0 or passed > total:
        return None
    return passed / total


def _mean_ratio(parts: list[float | None]) -> float | None:
    if any(v is None for v in parts):
        return None
    return sum(float(v) for v in parts) / len(parts)


def _quality(block: Mapping[str, Any]) -> tuple[float | None, list[str]]:
    errors: list[str] = []
    semantic = _ratio(block.get("semantic_checks_passed"), block.get("semantic_checks_total"))
    authority = _ratio(block.get("authority_checks_passed"), block.get("authority_checks_total"))
    score = _mean_ratio([semantic, authority])
    if score is None:
        errors.append("QUALITY_METRICS_INVALID")
    unsupported = block.get("unsupported_claims")
    if not isinstance(unsupported, int) or isinstance(unsupported, bool) or unsupported < 0:
        errors.append("QUALITY_UNSUPPORTED_CLAIMS_INVALID")
    elif unsupported != 0:
        errors.append("QUALITY_UNSUPPORTED_CLAIMS_PRESENT")
    return score, errors


def _functionality(block: Mapping[str, Any]) -> tuple[float | None, list[str]]:
    errors: list[str] = []
    ratios = [
        _ratio(block.get("required_behaviors_passed"), block.get("required_behaviors_total")),
        _ratio(block.get("positive_cases_passed"), block.get("positive_cases_total")),
        _ratio(block.get("negative_cases_passed"), block.get("negative_cases_total")),
    ]
    score = _mean_ratio(ratios)
    if score is None:
        errors.append("FUNCTIONALITY_METRICS_INVALID")
    failures = block.get("guard_failures")
    if not isinstance(failures, int) or isinstance(failures, bool) or failures < 0:
        errors.append("FUNCTIONALITY_GUARD_FAILURES_INVALID")
    elif failures != 0:
        errors.append("FUNCTIONALITY_GUARD_FAILURES_PRESENT")
    return score, errors


def _depth(block: Mapping[str, Any]) -> tuple[float | None, list[str]]:
    errors: list[str] = []
    ratios = [
        _ratio(block.get("obligations_preserved"), block.get("obligations_total")),
        _ratio(block.get("relationships_preserved"), block.get("relationships_total")),
        _ratio(block.get("exceptions_preserved"), block.get("exceptions_total")),
        _ratio(block.get("causal_checks_passed"), block.get("causal_checks_total")),
    ]
    score = _mean_ratio(ratios)
    if score is None:
        errors.append("DEPTH_METRICS_INVALID")
    return score, errors


def _performance(block: Mapping[str, Any], minimum_runs: int) -> tuple[dict[str, float | int | None] | None, list[str]]:
    errors: list[str] = []
    samples = block.get("elapsed_ms_samples")
    if not isinstance(samples, list) or len(samples) < minimum_runs or any(
        not isinstance(v, (int, float)) or isinstance(v, bool) or v < 0 for v in samples
    ):
        errors.append("PERFORMANCE_ELAPSED_SAMPLES_INVALID")
        return None, errors
    metrics: dict[str, float | int | None] = {"elapsed_ms_median": float(statistics.median(samples))}
    for key in ("input_tokens", "output_tokens", "transport_bytes", "model_calls", "tool_calls"):
        value = block.get(key)
        if value is not None and (not isinstance(value, (int, float)) or isinstance(value, bool) or value < 0):
            errors.append(f"PERFORMANCE_{key.upper()}_INVALID")
        metrics[key] = value
    if metrics["input_tokens"] is None or metrics["output_tokens"] is None:
        if metrics["transport_bytes"] is None:
            errors.append("PERFORMANCE_TOKENS_OR_TRANSPORT_REQUIRED")
    if metrics["model_calls"] is None or metrics["tool_calls"] is None:
        errors.append("PERFORMANCE_CALL_COUNTS_REQUIRED")
    return metrics if not errors else None, errors


def _judge_ok(arm: Mapping[str, Any]) -> bool:
    judge = arm.get("independent_semantic_judge")
    return isinstance(judge, Mapping) and judge.get("executed") is True and judge.get("status") == "PASS"


def evaluate(receipt: Mapping[str, Any], contract: Mapping[str, Any]) -> dict:
    errors: list[str] = []
    if receipt.get("schema") != RECEIPT_SCHEMA:
        errors.append("RECEIPT_SCHEMA_INVALID")
    a = receipt.get("arm_a")
    b = receipt.get("arm_b")
    if not isinstance(a, Mapping) or not isinstance(b, Mapping):
        return {"status": "INCOMPLETE", "decision": "NO_GO", "errors": ["AB_ARMS_REQUIRED"]}
    if a.get("input_sha256") != b.get("input_sha256") or not a.get("input_sha256"):
        errors.append("AB_INPUT_IDENTITY_MISMATCH")
    semantic_case = receipt.get("semantic_case") is True
    if semantic_case:
        for key in ("provider", "model", "parameters_sha256"):
            if a.get(key) != b.get(key) or not a.get(key):
                errors.append(f"AB_{key.upper()}_MISMATCH")
        if not _judge_ok(a) or not _judge_ok(b):
            errors.append("SEMANTIC_INDEPENDENT_JUDGE_REQUIRED")

    minimum_runs = int((contract.get("ab_contract") or {}).get("minimum_repeated_runs_per_arm", 3))
    scores: dict[str, dict[str, Any]] = {}
    for label, arm in (("A", a), ("B", b)):
        missing = [d for d in REQUIRED_DIMENSIONS if not isinstance(arm.get(d), Mapping)]
        if missing:
            errors.extend(f"{label}_{d.upper()}_MISSING" for d in missing)
            continue
        q, qe = _quality(arm["quality"])
        f, fe = _functionality(arm["functionality"])
        d, de = _depth(arm["depth"])
        p, pe = _performance(arm["performance"], minimum_runs)
        errors.extend(f"{label}_{e}" for e in qe + fe + de + pe)
        scores[label] = {"quality": q, "functionality": f, "depth": d, "performance": p}

    if errors:
        return {"status": "INCOMPLETE", "decision": "NO_GO", "errors": sorted(set(errors)), "scores": scores}

    qa, qb = scores["A"]["quality"], scores["B"]["quality"]
    fa, fb = scores["A"]["functionality"], scores["B"]["functionality"]
    da, db = scores["A"]["depth"], scores["B"]["depth"]
    pa, pb = scores["A"]["performance"], scores["B"]["performance"]
    assert qa is not None and qb is not None and fa is not None and fb is not None and da is not None and db is not None
    assert pa is not None and pb is not None

    gates = {
        "quality_no_regression": qb >= qa,
        "functionality_candidate_complete": fb == 1.0,
        "functionality_no_regression": fb >= fa,
        "depth_no_regression": db >= da,
        "elapsed_no_regression": pb["elapsed_ms_median"] <= pa["elapsed_ms_median"],
    }
    resource_keys = ("input_tokens", "output_tokens", "transport_bytes", "model_calls", "tool_calls")
    comparable = [key for key in resource_keys if pa.get(key) is not None and pb.get(key) is not None]
    gates["performance_resource_improvement"] = any(pb[key] < pa[key] for key in comparable)
    winner = all(gates.values())
    return {
        "status": "PASS" if winner else "NO_GO",
        "decision": "SELECT_B" if winner else "KEEP_A",
        "gates": gates,
        "scores": scores,
        "errors": [],
    }


def main() -> int:
    if len(sys.argv) != 3:
        print(json.dumps({"status": "INCOMPLETE", "decision": "NO_GO", "errors": ["USAGE: validate_4d_ab_receipt.py <contract.json> <receipt.json>"]}))
        return 2
    contract = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    receipt = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    result = evaluate(receipt, contract)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
