#!/usr/bin/env python3
"""Emit exact-head CI applicability plan.

`--force-full` is retained as a compatibility CLI name. It requests
FULL_REGRESSION verification of the governed plan; it never expands
applicability or means "run everything".
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROUTER_PATH = HERE / "lf_ci_lane_router.py"
PLAN_PATH = HERE / "lf_ci_execution_plan_v2.py"
CURRENTNESS_PATH = HERE / "lf_ci_currentness_bridge_v1.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot_load:{path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ROUTER = _load(ROUTER_PATH, "lf_ci_lane_router_runtime")
PLAN = _load(PLAN_PATH, "lf_ci_execution_plan_v2_runtime")
CURRENTNESS = _load(CURRENTNESS_PATH, "lf_ci_currentness_bridge_v1_runtime")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser()
    p.add_argument("--repo-root", default=".")
    p.add_argument("--base")
    p.add_argument("--head")
    p.add_argument("--authority-current-revision")
    p.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME", "LOCAL"))
    p.add_argument("--event-action", default="")
    p.add_argument("--ref-name", default=os.environ.get("GITHUB_REF_NAME", ""))
    p.add_argument("--output-json", required=True)
    p.add_argument("--github-output")
    p.add_argument(
        "--force-full",
        dest="request_full_regression",
        action="store_true",
        help="Compatibility flag: verify the governed plan with FULL_REGRESSION; never expand controls.",
    )
    p.add_argument("--force-full-reason", dest="full_regression_reason")
    return p


def _changed(repo: Path, base: str | None, head: str | None) -> list[str]:
    if not base or not head:
        return []
    raw = subprocess.check_output(
        ["git", "-C", str(repo), "diff", "--name-only", "--no-renames", base, head],
        text=True,
    )
    return sorted({line.strip() for line in raw.splitlines() if line.strip()})


def main() -> int:
    args = parser().parse_args()
    repo = Path(args.repo_root).resolve()
    changed = _changed(repo, args.base, args.head)

    request_full_regression = args.request_full_regression
    full_regression_reason = args.full_regression_reason
    if args.event_name in {"workflow_dispatch", "schedule"}:
        request_full_regression = True
        full_regression_reason = full_regression_reason or f"{args.event_name.upper()}_FULL_REGRESSION"
    elif args.event_name == "push" and args.ref_name == "main":
        request_full_regression = True
        full_regression_reason = full_regression_reason or "MAIN_PUSH_FULL_REGRESSION"

    lane = ROUTER.classify(changed)
    plan = PLAN.build_plan(
        changed_paths=changed,
        lane_required_controls=lane.required_controls,
        lane_mode=lane.mode,
        repo_root=repo,
        force_full=request_full_regression,
        force_full_reason=full_regression_reason,
        source_ref=args.head or None,
    )
    applicability_sha256 = plan["plan_sha256"]
    current_revision = args.authority_current_revision or args.base or args.head
    if not current_revision:
        raise SystemExit("BLOCK_CI_AUTHORITY_CURRENT_REVISION_MISSING")
    bound_revision = CURRENTNESS.resolve_authority_evidence_revision(
        repo=repo,
        event_name=args.event_name,
        ref_name=args.ref_name,
        diff_base_revision=args.base,
        candidate_head_revision=args.head,
        current_revision=current_revision,
    )
    currentness = CURRENTNESS.evaluate_ci_authority_currentness(
        repo=repo,
        bound_revision=bound_revision,
        current_revision=current_revision,
    )
    CURRENTNESS.require_ready(currentness)

    plan["plan_sha256"] = applicability_sha256
    plan["applicability_sha256"] = applicability_sha256
    plan["source_authority"] = currentness
    plan["authority_evidence_revision"] = bound_revision
    plan["base_sha"] = args.base
    plan["head_sha"] = args.head
    plan["event_name"] = args.event_name
    plan["event_action"] = args.event_action
    evidence_source = dict(plan)
    evidence_source.pop("evidence_sha256", None)
    plan["evidence_sha256"] = PLAN._sha(
        PLAN._canonical(evidence_source).encode("utf-8")
    )

    PLAN.validate_plan_contract(plan)

    out = Path(args.output_json)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    gh_out = Path(args.github_output) if args.github_output else None
    if gh_out is not None:
        carrier = plan.get("carrier_controls") or {}
        values = {
            "plan_sha256": plan["plan_sha256"],
            "applicability_sha256": plan["applicability_sha256"],
            "evidence_sha256": plan["evidence_sha256"],
            "authority_current_revision": plan["source_authority"]["resolved_revision"],
            "currentness_decision": plan["source_authority"]["decision"],
            "lane_mode": plan["lane_mode"],
            "full_regression": str(plan["full_regression"]).lower(),
            "applicability_decision": plan["applicability_decision"],
            "required_controls_json": json.dumps(plan["required_controls"], separators=(",", ":")),
            "lf_contract_controls_json": json.dumps(carrier.get("LF_CONTRACT_CHECK", []), separators=(",", ":")),
            "validate_packs_controls_json": json.dumps(carrier.get("VALIDATE_LF_PACKS", []), separators=(",", ":")),
            "bootstrap_controls_json": json.dumps(carrier.get("LF_BOOTSTRAP_REPRODUCIBILITY", []), separators=(",", ":")),
            "changed_paths_json": json.dumps(plan["changed_paths"], separators=(",", ":")),
        }
        with gh_out.open("a", encoding="utf-8") as handle:
            for key, value in values.items():
                handle.write(f"{key}={value}\n")

    print(json.dumps({
        "schema_version": plan["schema_version"],
        "plan_sha256": plan["plan_sha256"],
        "applicability_sha256": plan["applicability_sha256"],
        "evidence_sha256": plan["evidence_sha256"],
        "currentness_decision": plan["source_authority"]["decision"],
        "lane_mode": plan["lane_mode"],
        "applicability_decision": plan["applicability_decision"],
        "full_regression": plan["full_regression"],
        "full_regression_semantics": plan["full_regression_semantics"],
        "required_controls": plan["required_controls"],
        "changed_paths": plan["changed_paths"],
        "coverage_complete": plan["coverage_complete"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
