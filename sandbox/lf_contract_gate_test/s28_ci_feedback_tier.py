#!/usr/bin/env python3
"""Strategy 28 sandbox-only CI feedback tier classifier.

This helper does not validate artifacts and does not replace any existing gate.
It only decides whether iterative feedback may use the FAST tier or must retain
DEEP assurance. Unknown/mixed/high-impact surfaces and final evidence always
route DEEP.

Trust boundary: profile FAST eligibility additionally requires a server-derived
assurance context. Caller claims must never be treated as authority. Any
server-derived risk signal forces DEEP. The sandbox helper models this contract;
production materialization remains a separate governed integration step.
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


def _normalize_risks(signals: Iterable[str]) -> tuple[str, ...]:
    return tuple(sorted({str(signal).strip() for signal in signals if str(signal).strip()}))


def classify(
    paths: Iterable[str],
    *,
    final_evidence: bool = False,
    server_context_resolved: bool = False,
    server_risk_signals: Iterable[str] = (),
) -> Decision:
    try:
        normalized = tuple(sorted({_normalize(path) for path in paths}))
    except ValueError as exc:
        return Decision("DEEP", str(exc), "INVALID_PATH", True, tuple())

    risks = _normalize_risks(server_risk_signals)

    if final_evidence:
        return Decision("DEEP", "FINAL_EVIDENCE_REQUIRES_DEEP", "FINAL_GATE", True, normalized)
    if risks:
        return Decision("DEEP", "SERVER_DERIVED_RISK_REQUIRES_DEEP:" + ",".join(risks), "ASSURANCE_CONTEXT", True, normalized)
    if not normalized:
        return Decision("DEEP", "NO_CHANGED_PATHS_FAIL_CLOSED", "UNKNOWN", True, normalized)

    deep = [path for path in normalized if path.startswith(DEEP_PREFIXES)]
    if deep:
        return Decision("DEEP", "HIGH_IMPACT_OR_CONTROL_SURFACE", "CONTROL_OR_RUNTIME", True, normalized)

    unmapped = [path for path in normalized if not path.startswith(FAST_PREFIXES)]
    if unmapped:
        return Decision("DEEP", "UNKNOWN_OR_UNMAPPED_SURFACE", "UNKNOWN", True, normalized)

    surfaces = {path.split("/", 1)[0] for path in normalized}
    if "profiles" in surfaces and not server_context_resolved:
        return Decision("DEEP", "SERVER_CURRENTNESS_CONTEXT_REQUIRED", "+".join(sorted(surfaces)), True, normalized)

    return Decision(
        "FAST",
        "EXPLICIT_LOW_IMPACT_ITERATIVE_SURFACE",
        "+".join(sorted(surfaces)),
        False,
        normalized,
    )


def _self_test() -> None:
    cases = [
        (("profiles/ui_architect/profile.yaml",), False, True, tuple(), "FAST", "EXPLICIT_LOW_IMPACT_ITERATIVE_SURFACE"),
        (("profiles/ui_architect/profile.yaml",), False, False, tuple(), "DEEP", "SERVER_CURRENTNESS_CONTEXT_REQUIRED"),
        (("profiles/ui_architect/profile.yaml",), False, True, ("SOURCE_RUNTIME_MISMATCH",), "DEEP", "SERVER_DERIVED_RISK_REQUIRES_DEEP:SOURCE_RUNTIME_MISMATCH"),
        (("docs/audits/example.md",), False, False, tuple(), "FAST", "EXPLICIT_LOW_IMPACT_ITERATIVE_SURFACE"),
        (("supabase/migrations/20260904000000_probe.sql",), False, False, tuple(), "DEEP", "HIGH_IMPACT_OR_CONTROL_SURFACE"),
        (("profiles/ui_architect/profile.yaml", "supabase/migrations/x.sql"), False, True, tuple(), "DEEP", "HIGH_IMPACT_OR_CONTROL_SURFACE"),
        (("profiles/ui_architect/profile.yaml",), True, True, tuple(), "DEEP", "FINAL_EVIDENCE_REQUIRES_DEEP"),
        (("unmapped/new-runtime.txt",), False, False, tuple(), "DEEP", "UNKNOWN_OR_UNMAPPED_SURFACE"),
        (tuple(), False, False, tuple(), "DEEP", "NO_CHANGED_PATHS_FAIL_CLOSED"),
    ]
    for paths, final_evidence, resolved, risks, tier, reason in cases:
        decision = classify(
            paths,
            final_evidence=final_evidence,
            server_context_resolved=resolved,
            server_risk_signals=risks,
        )
        assert decision.tier == tier, (paths, decision)
        assert decision.reason == reason, (paths, decision)
    print(f"PASS_S28_ROUTING_SELF_TEST={len(cases)}/{len(cases)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--final-evidence", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    # Sandbox-only contract modeling flags. They are not caller-authority in a
    # production integration; a trusted server-side resolver must materialize them.
    parser.add_argument("--server-context-resolved", action="store_true")
    parser.add_argument("--server-risk", action="append", default=[])
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0

    print(json.dumps(classify(
        args.paths,
        final_evidence=args.final_evidence,
        server_context_resolved=args.server_context_resolved,
        server_risk_signals=args.server_risk,
    ).as_dict(), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
