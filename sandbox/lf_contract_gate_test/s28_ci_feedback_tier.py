#!/usr/bin/env python3
"""Strategy 28 sandbox-only CI feedback tier classifier.

This helper does not validate artifacts and does not replace any existing gate.
It only decides whether iterative feedback may use the FAST tier or must retain
DEEP assurance. Unknown/mixed/high-impact surfaces and final evidence always
route DEEP.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Iterable

FAST_PREFIXES = (
    "profiles/",
    "docs/",
)

DEEP_PREFIXES = (
    ".github/",
    "supabase/",
    "scripts/",
    "sandbox/",
)


@dataclass(frozen=True)
class Decision:
    tier: str
    reason: str
    affected_surface: str
    deep_required: bool
    paths: tuple[str, ...]

    def as_dict(self) -> dict[str, object]:
        return {
            "tier": self.tier,
            "reason": self.reason,
            "affected_surface": self.affected_surface,
            "deep_required": self.deep_required,
            "paths": list(self.paths),
        }


def _normalize(path: str) -> str:
    value = path.strip().replace("\\", "/")
    if not value:
        raise ValueError("EMPTY_PATH")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts:
        raise ValueError(f"UNSAFE_PATH:{value}")
    normalized = pure.as_posix()
    if normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def classify(paths: Iterable[str], *, final_evidence: bool = False) -> Decision:
    try:
        normalized = tuple(sorted({_normalize(path) for path in paths}))
    except ValueError as exc:
        return Decision("DEEP", str(exc), "INVALID_PATH", True, tuple())

    if final_evidence:
        return Decision("DEEP", "FINAL_EVIDENCE_REQUIRES_DEEP", "FINAL_GATE", True, normalized)
    if not normalized:
        return Decision("DEEP", "NO_CHANGED_PATHS_FAIL_CLOSED", "UNKNOWN", True, normalized)

    deep = [path for path in normalized if path.startswith(DEEP_PREFIXES)]
    if deep:
        return Decision("DEEP", "HIGH_IMPACT_OR_CONTROL_SURFACE", "CONTROL_OR_RUNTIME", True, normalized)

    unmapped = [path for path in normalized if not path.startswith(FAST_PREFIXES)]
    if unmapped:
        return Decision("DEEP", "UNKNOWN_OR_UNMAPPED_SURFACE", "UNKNOWN", True, normalized)

    surfaces = {path.split("/", 1)[0] for path in normalized}
    return Decision(
        "FAST",
        "EXPLICIT_LOW_IMPACT_ITERATIVE_SURFACE",
        "+".join(sorted(surfaces)),
        False,
        normalized,
    )


def _self_test() -> None:
    cases = [
        (("profiles/ui_architect/profile.yaml",), False, "FAST", "EXPLICIT_LOW_IMPACT_ITERATIVE_SURFACE"),
        (("docs/audits/example.md",), False, "FAST", "EXPLICIT_LOW_IMPACT_ITERATIVE_SURFACE"),
        (("supabase/migrations/20260904000000_probe.sql",), False, "DEEP", "HIGH_IMPACT_OR_CONTROL_SURFACE"),
        (("profiles/ui_architect/profile.yaml", "supabase/migrations/x.sql"), False, "DEEP", "HIGH_IMPACT_OR_CONTROL_SURFACE"),
        (("profiles/ui_architect/profile.yaml",), True, "DEEP", "FINAL_EVIDENCE_REQUIRES_DEEP"),
        (("unmapped/new-runtime.txt",), False, "DEEP", "UNKNOWN_OR_UNMAPPED_SURFACE"),
        (tuple(), False, "DEEP", "NO_CHANGED_PATHS_FAIL_CLOSED"),
    ]
    for paths, final_evidence, tier, reason in cases:
        decision = classify(paths, final_evidence=final_evidence)
        assert decision.tier == tier, (paths, decision)
        assert decision.reason == reason, (paths, decision)
    print(f"PASS_S28_ROUTING_SELF_TEST={len(cases)}/{len(cases)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--final-evidence", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0

    print(json.dumps(classify(args.paths, final_evidence=args.final_evidence).as_dict(), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
