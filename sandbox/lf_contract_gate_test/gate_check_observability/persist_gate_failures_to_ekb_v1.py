#!/usr/bin/env python3
"""Translate durable LF gate failures into emit-only handoff artifacts.

The deterministic gate runners stay side-effect free. This compatibility adapter
never performs database writes. Productive failure persistence must enter
public.lf_operation_gate_check_results through public.lf_record_gate_checks_v1;
PRE_EKB_GATE then owns the governed route to canonical EKB persistence.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Iterable

SCHEMA_VERSION = "lf-gate-ekb-persistence/v1"
PRODUCER = "LF_GATE_EKB_BRIDGE_V1"


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def sanitize_code(value: str) -> str:
    token = re.sub(r"[^A-Z0-9]+", "-", value.upper()).strip("-")
    return token or "UNKNOWN"


def stable_error_code(gate_id: str, group_id: str, source_path: str, error_class: str) -> str:
    identity = canonical({"gate_id": gate_id, "group_id": group_id, "source_path": source_path, "error_class": error_class})
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:12].upper()
    return f"CI-GATE-{sanitize_code(group_id)[:28]}-{digest}"


def source_ref(run_id: str, group_id: str) -> str:
    repo = os.environ.get("GITHUB_REPOSITORY") or "UNKNOWN_REPOSITORY"
    return f"github-actions://{repo}/actions/runs/{run_id}#group={group_id}"


def payload_from_failure(*, gate_id: str, owner: str, group_id: str, check: dict, run_id: str, report_ref: str) -> dict:
    source_path = str(check.get("source_path") or check.get("input_ref") or "UNKNOWN_SOURCE_PATH")
    error_class = str(check.get("error_class") or "PROCESS_EXIT_NONZERO")
    error_summary = str(check.get("error_summary") or f"Gate check failed rc={check.get('rc')}")
    code = stable_error_code(gate_id, group_id, source_path, error_class)
    evidence = {
        "gate_id": gate_id,
        "group_id": group_id,
        "run_id": run_id,
        "check_id": check.get("check_id"),
        "source_path": source_path,
        "error_class": error_class,
        "error_summary": error_summary,
        "assertion_text": check.get("assertion_text"),
        "failure_id": check.get("failure_id"),
        "trace_id": check.get("trace_id"),
        "traceback_ref": check.get("traceback_ref"),
        "source_commit": check.get("source_commit"),
        "tested_commit": check.get("tested_commit"),
        "report_ref": report_ref,
    }
    roles = ["CI_GATE"]
    if owner and owner not in roles:
        roles.append(owner)
    return {
        "codigo": code,
        "categoria": "CI_GATE_FAILURE",
        "titulo": f"Gate {gate_id} fallo en {group_id}/{Path(source_path).name}",
        "descripcion": error_summary,
        "causa_raiz": "Causa raiz aun no diagnosticada; registro automatico al detectar fallo deterministico.",
        "patron": "Fallo reproducible capturado por LF_GATE_CHECK_OBSERVABILITY_V1.",
        "prevencion": f"Mantener el check {Path(source_path).name} y bloquear cierre hasta corregir y rerun completo.",
        "validacion": f"Rerun dirigido de {group_id} y luego gate completo con full_coverage=true y resultado PASS.",
        "severidad": "High",
        "lifecycle_phase": "CI_ASSURANCE_AND_GATE_EXECUTION",
        "consumer_role": roles,
        "root_cause_family": "UNCLASSIFIED_WITH_REASON",
        "detectability": "LOUD_EARLY",
        "source_context": f"gate={gate_id};group={group_id};run={run_id};source={source_path}",
        "source_ref": source_ref(run_id, group_id),
        "evidencia": canonical(evidence),
        "lote_origen": f"CI-GATE-{run_id}",
        "pr": os.environ.get("GITHUB_PR_NUMBER") or None,
    }


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"json_object_required:{path}")
    return value


def candidates_from_child(report: dict, report_ref: str, group_id: str | None = None, parent_gate: str | None = None) -> list[dict]:
    gate_id = parent_gate or str(report.get("gate_id") or "UNKNOWN_GATE")
    owner = str(report.get("owner") or "UNKNOWN_OWNER")
    gid = group_id or str(report.get("step_id") or "UNGROUPED")
    run_id = str(report.get("run_id") or os.environ.get("GITHUB_RUN_ID") or "LOCAL")
    failures = [x for x in (report.get("checks") or []) if isinstance(x, dict) and x.get("check_status") == "FAIL"]
    return [payload_from_failure(gate_id=gate_id, owner=owner, group_id=gid, check=x, run_id=run_id, report_ref=report_ref) for x in failures]


def candidates_from_group_summary(summary: dict, summary_path: Path) -> list[dict]:
    gate_id = str(summary.get("gate_id") or "UNKNOWN_GATE")
    candidates: list[dict] = []
    for group in summary.get("groups") or []:
        if not isinstance(group, dict) or group.get("result") == "PASS":
            continue
        gid = str(group.get("group_id") or "UNKNOWN_GROUP")
        report_path = Path(str(group.get("report_ref") or ""))
        if report_path.is_file():
            report = load_json(report_path)
            candidates.extend(candidates_from_child(report, str(report_path.as_posix()), gid, gate_id))
    if not candidates and summary.get("gate_result") in {"FAIL", "BLOCKED"}:
        synthetic = {
            "check_id": "GROUP-ORCHESTRATION",
            "source_path": str(summary.get("manifest_ref") or summary_path.as_posix()),
            "error_class": str(summary.get("error_class") or "GROUP_GATE_BLOCKED"),
            "error_summary": str(summary.get("error_summary") or f"Grouped gate result={summary.get('gate_result')}"),
            "rc": 2 if summary.get("gate_result") == "BLOCKED" else 1,
            "source_commit": os.environ.get("GITHUB_SHA"),
            "tested_commit": os.environ.get("GITHUB_SHA"),
        }
        candidates.append(payload_from_failure(
            gate_id=gate_id,
            owner=str(summary.get("owner") or "UNKNOWN_OWNER"),
            group_id="GROUP-ORCHESTRATION",
            check=synthetic,
            run_id=str(summary.get("run_id") or os.environ.get("GITHUB_RUN_ID") or "LOCAL"),
            report_ref=str(summary_path.as_posix()),
        ))
    return candidates


def dedupe(candidates: Iterable[dict]) -> list[dict]:
    result: dict[str, dict] = {}
    for item in candidates:
        result[item["codigo"]] = item
    return [result[key] for key in sorted(result)]


def redact(text: str) -> str:
    return re.sub(r"(?i)(password|secret|token|key)=\S+", r"\1=[REDACTED]", text)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--summary", action="append", default=[])
    p.add_argument("--report", action="append", default=[])
    p.add_argument("--artifact-dir", required=True)
    p.add_argument("--emit-only", action="store_true", required=True)
    p.add_argument("--allow-missing", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.artifact_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    candidates: list[dict] = []
    missing: list[str] = []

    try:
        for raw in args.summary:
            path = Path(raw)
            if not path.is_file():
                missing.append(raw)
                continue
            candidates.extend(candidates_from_group_summary(load_json(path), path))
        for raw in args.report:
            path = Path(raw)
            if not path.is_file():
                missing.append(raw)
                continue
            candidates.extend(candidates_from_child(load_json(path), str(path.as_posix())))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        receipt = {
            "schema_version": SCHEMA_VERSION,
            "producer": PRODUCER,
            "status": "EMIT_BLOCKED",
            "reason": f"INPUT_INVALID:{exc}",
            "direct_ekb_write_allowed": False,
            "timestamp": now(),
        }
        write_json(out_dir / "ekb_persistence_receipt_v1.json", receipt)
        return 2

    if missing and not args.allow_missing:
        receipt = {
            "schema_version": SCHEMA_VERSION,
            "producer": PRODUCER,
            "status": "EMIT_BLOCKED",
            "reason": "INPUT_MISSING",
            "missing": missing,
            "direct_ekb_write_allowed": False,
            "timestamp": now(),
        }
        write_json(out_dir / "ekb_persistence_receipt_v1.json", receipt)
        return 2

    candidates = dedupe(candidates)
    write_json(
        out_dir / "ekb_candidates_v1.json",
        {
            "schema_version": SCHEMA_VERSION,
            "producer": PRODUCER,
            "candidate_count": len(candidates),
            "candidates": candidates,
            "productive_target": "public.lf_operation_gate_check_results",
            "productive_ingress": "public.lf_record_gate_checks_v1",
            "pre_ekb_gate": "PRE_EKB_GATE",
            "direct_ekb_write_allowed": False,
        },
    )

    if not candidates:
        receipt = {
            "schema_version": SCHEMA_VERSION,
            "producer": PRODUCER,
            "status": "NO_FAILURES_NO_WRITE" if not missing else "GATE_NOT_REACHED_NO_WRITE",
            "missing": missing,
            "candidate_count": 0,
            "direct_ekb_write_allowed": False,
            "timestamp": now(),
        }
        write_json(out_dir / "ekb_persistence_receipt_v1.json", receipt)
        print(json.dumps(receipt, sort_keys=True))
        return 0

    receipt = {
        "schema_version": SCHEMA_VERSION,
        "producer": PRODUCER,
        "status": "EMIT_ONLY_LEDGER_REQUIRED",
        "candidate_count": len(candidates),
        "error_codes": [x["codigo"] for x in candidates],
        "productive_target": "public.lf_operation_gate_check_results",
        "productive_ingress": "public.lf_record_gate_checks_v1",
        "pre_ekb_gate": "PRE_EKB_GATE",
        "direct_ekb_write_allowed": False,
        "timestamp": now(),
    }
    write_json(out_dir / "ekb_persistence_receipt_v1.json", receipt)
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
