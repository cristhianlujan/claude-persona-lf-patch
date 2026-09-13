#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parent
DEFAULT_POLICY = ROOT / "s30_interim_dependency_currentness_policy_v1.json"


def load_policy(path: Path = DEFAULT_POLICY) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != "S30_INTERIM_DEPENDENCY_CURRENTNESS_POLICY_V1":
        raise ValueError("POLICY_SCHEMA_INVALID")
    return data


def _matches_prefix(path: str, prefixes: Iterable[str]) -> bool:
    return any(path.startswith(prefix) for prefix in prefixes)


def classify_paths(policy: dict[str, Any], changed_paths: Iterable[str]) -> dict[str, Any]:
    paths = sorted({p.strip() for p in changed_paths if p and p.strip()})
    owned_prefixes = tuple(policy.get("s30_owned_prefixes") or [])
    consumed_contracts = set(policy.get("declared_consumed_contract_paths") or [])
    nondeps = policy.get("known_shared_implementation_non_dependencies") or {}
    nondep_exact = set(nondeps.get("exact_paths") or [])
    nondep_prefixes = tuple(nondeps.get("prefixes") or [])
    reviewed_exact = set(policy.get("reviewed_no_impact_exact_paths_for_observed_delta") or [])

    buckets: dict[str, list[str]] = {
        "s30_owned": [],
        "declared_consumed_contract": [],
        "known_shared_implementation_non_dependency": [],
        "reviewed_no_impact_exact": [],
        "unknown": [],
    }

    for path in paths:
        if _matches_prefix(path, owned_prefixes):
            buckets["s30_owned"].append(path)
        elif path in consumed_contracts:
            buckets["declared_consumed_contract"].append(path)
        elif path in nondep_exact or _matches_prefix(path, nondep_prefixes):
            buckets["known_shared_implementation_non_dependency"].append(path)
        elif path in reviewed_exact:
            buckets["reviewed_no_impact_exact"].append(path)
        else:
            buckets["unknown"].append(path)

    if buckets["s30_owned"]:
        result = "FULL_S30_REVALIDATION_REQUIRED"
        reason = "S30_OWNED_SURFACE_CHANGED"
    elif buckets["declared_consumed_contract"] or buckets["unknown"]:
        result = "TARGETED_IMPACT_REVIEW_REQUIRED"
        reason = (
            "DECLARED_CONSUMED_CONTRACT_CHANGED"
            if buckets["declared_consumed_contract"] and not buckets["unknown"]
            else "UNKNOWN_OR_MIXED_DEPENDENCY_CHANGE"
        )
    else:
        result = "NO_S30_REVALIDATION_REQUIRED"
        reason = "ONLY_REVIEWED_OR_IMPLEMENTATION_ONLY_NONDEPENDENCY_CHANGES"

    return {
        "schema_version": "S30_INTERIM_DEPENDENCY_IMPACT_RESULT_V1",
        "result": result,
        "reason": reason,
        "changed_path_count": len(paths),
        "buckets": buckets,
        "main_sha_drift_alone_invalidates_s30": False,
        "safety_ceiling": policy.get("safety_ceiling") or {},
    }


def verify_observed_delta(policy: dict[str, Any], changed_paths: Iterable[str]) -> dict[str, Any]:
    result = classify_paths(policy, changed_paths)
    observed = policy.get("observed_delta") or {}
    expected = observed.get("expected_result")
    if result["result"] != expected:
        raise AssertionError(f"OBSERVED_DELTA_CLASSIFICATION_MISMATCH:{result['result']}!={expected}")
    surfaces = policy.get("semantic_currentness_surfaces") or {}
    mismatched = [
        path
        for path, binding in surfaces.items()
        if binding.get("freeze_blob_sha") != binding.get("observed_head_blob_sha")
    ]
    if mismatched:
        raise AssertionError("S30_CURRENTNESS_SURFACE_CHANGED:" + ",".join(sorted(mismatched)))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", default=str(DEFAULT_POLICY))
    parser.add_argument("--changed-path", action="append", default=[])
    parser.add_argument("--changed-paths-json")
    parser.add_argument("--verify-observed", action="store_true")
    args = parser.parse_args()

    policy = load_policy(Path(args.policy))
    paths = list(args.changed_path)
    if args.changed_paths_json:
        payload = json.loads(Path(args.changed_paths_json).read_text(encoding="utf-8"))
        if not isinstance(payload, list) or not all(isinstance(x, str) for x in payload):
            raise SystemExit("CHANGED_PATHS_JSON_INVALID")
        paths.extend(payload)

    result = verify_observed_delta(policy, paths) if args.verify_observed else classify_paths(policy, paths)
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
