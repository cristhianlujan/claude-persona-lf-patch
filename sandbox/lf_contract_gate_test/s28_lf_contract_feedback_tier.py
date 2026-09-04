#!/usr/bin/env python3
"""Strategy 28 sandbox router for LF contract FAST/DEEP feedback.

This file does not replace scripts/lf_contract_check.py. It imports the canonical
validator and only decides whether a preflight-passing surface can use the
iterative P0-docs FAST lane or must stay DEEP.
"""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import statistics
import time
from pathlib import Path

VALIDATOR_PATH = Path("scripts/lf_contract_check.py")


def load_validator():
    spec = importlib.util.spec_from_file_location("lf_contract_check_s28_tier", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("FAIL_S28_CANONICAL_VALIDATOR_LOAD")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


VALIDATOR = load_validator()


def _failure_code(output: str) -> str:
    for line in output.splitlines():
        token = line.strip().split(":", 1)[0]
        if token.startswith("FAIL_"):
            return token
    return "FAIL_UNKNOWN_CANONICAL_PREFLIGHT"


def classify(paths: list[str], *, final_evidence: bool = False) -> tuple[str, str]:
    if not paths:
        return "DEEP", "NO_PATHS_FAIL_CLOSED"

    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            governed = VALIDATOR.validate_changed_files(paths)
            VALIDATOR.validate_governed_receipt(paths, governed)
            VALIDATOR.validate_forbidden_terms(paths)
    except SystemExit:
        return "BLOCK_EARLY", _failure_code(buffer.getvalue())

    if final_evidence:
        return "DEEP", "FINAL_EVIDENCE_FORCE_DEEP"

    p0_docs = VALIDATOR.P0_CLOSURE_EVIDENCE_ALLOWED_EXACT
    if all(path in p0_docs for path in paths):
        return "FAST_P0_DOCS", "CANONICAL_P0_CLOSURE_EVIDENCE_ONLY"

    return "DEEP", "NON_P0_DOC_OR_MIXED_SURFACE"


def self_test() -> None:
    allowed = sorted(VALIDATOR.P0_CLOSURE_EVIDENCE_ALLOWED_EXACT)
    cases: list[tuple[str, list[str], bool, str, str | None]] = []
    for index, path in enumerate(allowed, start=1):
        cases.append((f"P0_{index:02d}", [path], False, "FAST_P0_DOCS", None))

    cases.extend(
        [
            ("INVALID_DOC_PR509", ["docs/audits/s28_prod_docs_fast_canary_20260904.md"], False, "BLOCK_EARLY", "FAIL_SCOPE_INVALID"),
            ("UNSCOPED_P0_LOOKALIKE", ["docs/p0/UNSCOPED.md"], False, "BLOCK_EARLY", "FAIL_SCOPE_INVALID"),
            ("COMPACT_PROTOCOL_DOC", ["docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md"], False, "DEEP", None),
            ("MIGRATION", ["supabase/migrations/20990101000000_lf_future_probe.sql"], False, "DEEP", None),
            ("AUTHORIZED_WORKFLOW", [".github/workflows/lf-contract-check.yml"], False, "DEEP", None),
            ("MIXED_P0_MIGRATION", [allowed[0], "supabase/migrations/20990101000000_lf_future_probe.sql"], False, "DEEP", None),
            ("PRODUCTION_BLOCKED", ["production/unexpected.txt"], False, "BLOCK_EARLY", "FAIL_BLOCKED_SCOPE_RISK"),
            ("NO_PATHS", [], False, "DEEP", None),
            ("FINAL_EVIDENCE_P0", [allowed[0]], True, "DEEP", None),
            ("PROFILE_NO_RECEIPT", ["profiles/quality_pack/SKILL.md"], False, "BLOCK_EARLY", "FAIL_RECEIPT_MISSING"),
        ]
    )

    false_fast = 0
    for case_id, paths, final_evidence, expected_tier, expected_reason in cases:
        tier, reason = classify(paths, final_evidence=final_evidence)
        if tier == "FAST_P0_DOCS" and expected_tier != "FAST_P0_DOCS":
            false_fast += 1
        if tier != expected_tier:
            raise SystemExit(
                f"FAIL_S28_TIER case={case_id} expected={expected_tier} actual={tier} reason={reason}"
            )
        if expected_reason and reason != expected_reason:
            raise SystemExit(
                f"FAIL_S28_REASON case={case_id} expected={expected_reason} actual={reason}"
            )
        print(f"PASS_S28_TIER case={case_id} tier={tier} reason={reason}")

    if false_fast:
        raise SystemExit(f"FAIL_S28_FALSE_FAST count={false_fast}")
    print(f"PASS_S28_TIER_SELFTEST={len(cases)}/{len(cases)} false_fast=0 p0_fast={len(allowed)}")


def benchmark(samples: int) -> None:
    probes = {
        "valid_p0": ["docs/p0/MATRIZ_OPCIONES_OCR_CV.md"],
        "invalid_doc": ["docs/audits/s28_prod_docs_fast_canary_20260904.md"],
        "deep_migration": ["supabase/migrations/20990101000000_lf_future_probe.sql"],
    }
    for name, paths in probes.items():
        timings = []
        observed = None
        for _ in range(samples):
            start = time.perf_counter_ns()
            observed = classify(paths)[0]
            timings.append((time.perf_counter_ns() - start) / 1000.0)
        ordered = sorted(timings)
        p95 = ordered[max(0, int(len(ordered) * 0.95) - 1)]
        print(
            f"S28_TIER_BENCH name={name} tier={observed} samples={samples} "
            f"median_us={statistics.median(timings):.3f} p95_us={p95:.3f}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--benchmark", type=int, default=0)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    if args.benchmark:
        benchmark(args.benchmark)
    if not args.self_test and not args.benchmark:
        parser.error("choose --self-test and/or --benchmark")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
