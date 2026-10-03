#!/usr/bin/env python3
"""Emit the exact-head CI applicability plan from CI_FAST_DEEP_LANE_ROUTER."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Mapping

HERE = Path(__file__).resolve().parent
ROUTER_PATH = HERE / "lf_ci_lane_router.py"
PLAN_PATH = HERE / "lf_ci_execution_plan_v2.py"
CURRENTNESS_PATH = HERE / "lf_ci_currentness_bridge_v1.py"
HANDOFF_PATH = HERE / "lf_contract_check_resolution_handoff_v1.py"
REPAIR_ENFORCEMENT_PATH = HERE / "lf_pase_control_repair_quarantine_v1.py"


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
HANDOFF = _load(HANDOFF_PATH, "lf_contract_check_resolution_handoff_v1_runtime")
REPAIR_ENFORCEMENT = _load(
    REPAIR_ENFORCEMENT_PATH,
    "lf_pase_control_repair_quarantine_v1_runtime",
)


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
    p.add_argument("--force-full", action="store_true")
    p.add_argument("--force-full-reason")
    return p


def _changed(repo: Path, base: str | None, head: str | None) -> list[str]:
    if not base or not head:
        return []
    raw = subprocess.check_output(
        ["git", "-C", str(repo), "diff", "--name-only", "--no-renames", base, head],
        text=True,
    )
    return sorted({line.strip() for line in raw.splitlines() if line.strip()})


def _candidate_manifest_data(
    repo: Path,
    changed: list[str],
    head: str | None,
) -> Mapping[str, Any] | None:
    """Read one changeset manifest from the exact candidate Git object as data.

    This keeps base-anchored consumers on trusted base code while allowing the
    candidate's declarative classification manifest to participate in routing.
    Candidate Python/workflow code is never imported or executed here.
    """
    family_registry = ROUTER.load_family_registry()
    manifest_paths = sorted(
        path for path in changed
        if family_registry.family_for(path) == "CHANGESET_MANIFEST"
    )
    if len(manifest_paths) != 1:
        return None

    manifest_path = manifest_paths[0]
    if head:
        completed = subprocess.run(
            ["git", "-C", str(repo), "show", f"{head}:{manifest_path}"],
            text=True,
            capture_output=True,
            check=False,
        )
        if completed.returncode != 0:
            raise SystemExit(f"BLOCK_CI_CHANGESET_MANIFEST_EXACT_HEAD_READ:{manifest_path}")
        raw = completed.stdout
    else:
        target = repo / manifest_path
        if not target.is_file():
            return None
        raw = target.read_text(encoding="utf-8")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"BLOCK_CI_CHANGESET_MANIFEST_JSON:{manifest_path}:{exc.__class__.__name__}"
        ) from exc
    if not isinstance(data, Mapping):
        raise SystemExit(f"BLOCK_CI_CHANGESET_MANIFEST_SHAPE:{manifest_path}")
    return data


def main() -> int:
    args = parser().parse_args()
    repo = Path(args.repo_root).resolve()
    changed = _changed(repo, args.base, args.head)
    manifest_data = _candidate_manifest_data(repo, changed, args.head)

    force_full = args.force_full
    force_reason = args.force_full_reason
    if args.event_name in {"workflow_dispatch", "schedule"}:
        force_full = True
        force_reason = force_reason or f"{args.event_name.upper()}_FULL_REGRESSION"
    elif args.event_name == "push" and args.ref_name == "main":
        force_full = True
        force_reason = force_reason or "MAIN_PUSH_FULL_REGRESSION"

    lane = ROUTER.classify(changed, manifest_data=manifest_data)
    plan = PLAN.build_plan(
        changed_paths=changed,
        lane_required_controls=lane.required_controls,
        lane_mode=lane.mode,
        repo_root=repo,
        force_full=force_full,
        force_full_reason=force_reason,
        source_ref=args.head or None,
    )
    plan["contract_check_resolution_request"] = HANDOFF.build_resolution_request(
        lane=lane,
        plan=plan,
        repo_root=repo,
        manifest_data=manifest_data,
    )
    plan["pase_control_enforcement"] = REPAIR_ENFORCEMENT.project_enforcement(
        plan,
        REPAIR_ENFORCEMENT.load_policy(),
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

    out = Path(args.output_json)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    gh_out = Path(args.github_output) if args.github_output else None
    if gh_out is not None:
        carrier = plan.get("carrier_controls") or {}
        handoff = plan["contract_check_resolution_request"]
        enforcement = plan["pase_control_enforcement"]
        values = {
            "plan_sha256": plan["plan_sha256"],
            "applicability_sha256": plan["applicability_sha256"],
            "evidence_sha256": plan["evidence_sha256"],
            "authority_current_revision": plan["source_authority"]["resolved_revision"],
            "currentness_decision": plan["source_authority"]["decision"],
            "lane_mode": plan["lane_mode"],
            "full_regression": str(plan["full_regression"]).lower(),
            "required_controls_json": json.dumps(plan["required_controls"], separators=(",", ":")),
            "lf_contract_controls_json": json.dumps(carrier.get("LF_CONTRACT_CHECK", []), separators=(",", ":")),
            "validate_packs_controls_json": json.dumps(carrier.get("VALIDATE_LF_PACKS", []), separators=(",", ":")),
            "db_regression_controls_json": json.dumps(carrier.get("LF_DB_REGRESSION", []), separators=(",", ":")),
            "changed_paths_json": json.dumps(plan["changed_paths"], separators=(",", ":")),
            "contract_check_handoff_state": handoff["handoff_state"],
            "contract_check_resolution_request_json": json.dumps(handoff, separators=(",", ":"), sort_keys=True),
            "pase_control_enforcement_json": json.dumps(enforcement, separators=(",", ":"), sort_keys=True),
            "pase_blocking_controls_json": json.dumps(enforcement["blocking_controls"], separators=(",", ":")),
            "pase_observe_only_controls_json": json.dumps(enforcement["observe_only_controls"], separators=(",", ":")),
            "pase_repair_policy_id": enforcement["policy_id"],
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
        "full_regression": plan["full_regression"],
        "required_controls": plan["required_controls"],
        "changed_paths": plan["changed_paths"],
        "contract_check_handoff_state": plan["contract_check_resolution_request"]["handoff_state"],
        "pase_repair_policy_id": plan["pase_control_enforcement"]["policy_id"],
        "pase_blocking_controls": plan["pase_control_enforcement"]["blocking_controls"],
        "pase_observe_only_controls": plan["pase_control_enforcement"]["observe_only_controls"],
        "coverage_complete": plan["coverage_complete"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
