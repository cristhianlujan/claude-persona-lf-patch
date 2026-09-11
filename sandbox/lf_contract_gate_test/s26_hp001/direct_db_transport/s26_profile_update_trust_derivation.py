#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

SHA40 = re.compile(r"^[0-9a-f]{40}$")
REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
TARGET_PATH = "profiles/ui_architect/SKILL.md"
EXECUTION_ID = "EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-SEMANTIC-REPROJECTION-20260911-001"
DIRECT_AUTHORITY_SOURCE = "GITHUB_ACTIONS_EXACT_SHA_POSTGRES_POOLER_V1"
CANONICAL_RECORDER_SOURCE = "run-creacion-perfil-lf"


class Blocked(RuntimeError):
    pass


@dataclass(frozen=True)
class DerivationInput:
    baseline: str | None
    current: str | None
    target_blob: str | None
    bound: str | None
    execution_bound: bool
    reread: bool = False
    rebind: bool = False
    rebound_from: str | None = None


def derive(inp: DerivationInput) -> str:
    if not inp.baseline or not SHA40.fullmatch(inp.baseline):
        raise Blocked("PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED")
    if not inp.current or not SHA40.fullmatch(inp.current):
        raise Blocked("PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED")
    if not inp.target_blob or not SHA40.fullmatch(inp.target_blob):
        raise Blocked("PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED")
    if not inp.bound or not SHA40.fullmatch(inp.bound):
        raise Blocked("PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED")
    if not inp.execution_bound:
        raise Blocked("PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED")
    stale = inp.baseline != inp.current
    if stale:
        if not inp.reread:
            raise Blocked("PROFILE_UPDATE_STALE_REREAD_REQUIRED")
        if not inp.rebind:
            raise Blocked("PROFILE_UPDATE_STALE_REBIND_REQUIRED")
        if inp.rebound_from != inp.baseline:
            raise Blocked("PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH")
    if inp.bound != inp.current:
        raise Blocked("PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH")
    return "STALE_REBOUND_CURRENT" if stale else "CURRENT_BOUND"


def _run(*args: str) -> str:
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def _psql_read(sql: str) -> str:
    command = ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-Atq", "-c", f"BEGIN READ ONLY; {sql}; COMMIT;"]
    text = _run(*command)
    return "\n".join(line for line in text.splitlines() if line not in {"BEGIN", "COMMIT"}).strip()


def live_probe(repo_root: Path) -> dict:
    if not os.environ.get("PGPASSWORD", "").strip():
        raise Blocked("S26_DIRECT_DB_PASSWORD_MISSING")
    baseline = _psql_read(
        "select evidence_payload->>'baseline_revision' from public.lf_operation_execution_steps "
        f"where execution_id='{EXECUTION_ID}' and step_id='baseline_read'"
    )
    next_step = _psql_read(
        "select s.step_id from public.lf_operation_steps s "
        "where s.operation_code='ACTUALIZACION_PERFIL_LF' and s.active=true and s.required=true "
        f"and not exists(select 1 from public.lf_operation_execution_steps e where e.execution_id='{EXECUTION_ID}' and e.step_id=s.step_id) "
        "order by s.execution_order limit 1"
    )
    if next_step != "pre_write_execution_binding_gate":
        raise Blocked(f"S26_DIRECT_DB_NEXT_STEP_MISMATCH:{next_step}")

    current = _run("git", "ls-remote", "origin", "refs/heads/main").split()[0]
    if not SHA40.fullmatch(current):
        raise Blocked("PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED")
    _run("git", "fetch", "-q", "origin", current)
    target_blob = _run("git", "rev-parse", f"{current}:{TARGET_PATH}")
    if not SHA40.fullmatch(target_blob):
        raise Blocked("PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED")

    stale = baseline != current
    continuity = derive(
        DerivationInput(
            baseline=baseline,
            current=current,
            target_blob=target_blob,
            bound=current,
            execution_bound=True,
            reread=stale,
            rebind=stale,
            rebound_from=baseline if stale else None,
        )
    )
    return {
        "status": "PASS",
        "mode": "READ_ONLY_TRUST_EQUIVALENCE_PROBE",
        "execution_id": EXECUTION_ID,
        "transport": "POSTGRES_POOLER_DIRECT",
        "authority_source": DIRECT_AUTHORITY_SOURCE,
        "canonical_recorder_currently_requires_source": CANONICAL_RECORDER_SOURCE,
        "recorder_write_eligible": False,
        "reason_write_not_yet_eligible": "AUTHORITY_SOURCE_CONTRACT_NOT_YET_ADAPTED",
        "trust_context_candidate": {
            "resolver": "GITHUB_PUBLIC_API_EXACT_REF_V1",
            "repository": REPOSITORY,
            "ref": "main",
            "revision_sha": current,
            "target_path": TARGET_PATH,
            "target_blob_sha": target_blob,
            "baseline_revision": baseline,
            "bound_revision": current,
            "continuity_state": continuity,
        },
        "stale_rebind": stale,
        "reread_performed": stale,
        "rebind_performed": stale,
        "rebound_from_revision": baseline if stale else None,
    }


def self_test() -> dict:
    A = "a" * 40
    B = "b" * 40
    X = "c" * 40
    blob = "d" * 40
    cases = [
        ("POS_CURRENT_BOUND", DerivationInput(A, A, blob, A, True), "CURRENT_BOUND"),
        ("POS_STALE_REBOUND_CURRENT", DerivationInput(A, B, blob, B, True, True, True, A), "STALE_REBOUND_CURRENT"),
        ("NEG_MISSING_BASELINE", DerivationInput(None, A, blob, A, True), "PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED"),
        ("NEG_MISSING_CURRENT", DerivationInput(A, None, blob, A, True), "PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED"),
        ("NEG_TARGET_BLOB_UNRESOLVED", DerivationInput(A, A, None, A, True), "PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED"),
        ("NEG_BOUND_UNSTRUCTURED", DerivationInput(A, A, blob, "free-text", True), "PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED"),
        ("NEG_EXECUTION_NOT_BOUND", DerivationInput(A, A, blob, A, False), "PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED"),
        ("NEG_STALE_NO_REREAD", DerivationInput(A, B, blob, B, True, False, True, A), "PROFILE_UPDATE_STALE_REREAD_REQUIRED"),
        ("NEG_STALE_NO_REBIND", DerivationInput(A, B, blob, B, True, True, False, A), "PROFILE_UPDATE_STALE_REBIND_REQUIRED"),
        ("NEG_REBOUND_FROM_WRONG_REV", DerivationInput(A, B, blob, B, True, True, True, X), "PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH"),
        ("NEG_BOUND_NOT_CURRENT", DerivationInput(A, B, blob, A, True, True, True, A), "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"),
        ("NEG_CALLER_TRUST_FLAGS_CANNOT_OVERRIDE", DerivationInput(A, B, blob, A, True, True, True, A), "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH"),
    ]
    failures: list[str] = []
    for name, inp, expected in cases:
        try:
            observed = derive(inp)
        except Blocked as exc:
            observed = str(exc)
        if observed != expected:
            failures.append(f"{name}:expected={expected}:observed={observed}")
    if failures:
        raise SystemExit("FAIL_S26_DIRECT_TRUST_EQUIVALENCE=" + ";".join(failures))
    return {"status": "PASS", "decision_matrix": "12/12", "write_performed": False}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--live-probe", action="store_true")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True))
    if args.live_probe:
        print(json.dumps(live_probe(args.repo_root), sort_keys=True))
    if not args.self_test and not args.live_probe:
        parser.error("choose --self-test and/or --live-probe")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
