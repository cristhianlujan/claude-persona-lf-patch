#!/usr/bin/env python3
"""Strict T1 semantic validation for PR #93 LOTE-E.14."""
from __future__ import annotations

import json
import re
from typing import Any

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
HEAD_RE = re.compile(r"^[0-9a-f]{40}$")


def fail(message: str) -> None:
    raise ValueError(message)


def exact_index(lines: list[str], marker: str) -> int:
    hits = [i for i, line in enumerate(lines) if line == marker]
    if len(hits) != 1:
        fail(f"marker {marker!r} must occur exactly once; observed {len(hits)}")
    return hits[0]


def prefix_index(lines: list[str], prefix: str) -> int:
    hits = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(hits) != 1:
        fail(f"prefix {prefix!r} must occur exactly once; observed {len(hits)}")
    return hits[0]


def json_in_segment(lines: list[str], start: int, end: int, label: str) -> dict[str, Any]:
    values: list[dict[str, Any]] = []
    for line in lines[start + 1:end]:
        text = line.strip()
        if not text.startswith("{"):
            continue
        try:
            value = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{label} contains invalid JSON") from exc
        if not isinstance(value, dict):
            fail(f"{label} must contain a JSON object")
        values.append(value)
    if len(values) != 1:
        fail(f"{label} must contain exactly one JSON object; observed {len(values)}")
    return values[0]


def path(value: dict[str, Any], *keys: str) -> Any:
    current: Any = value
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def parse_t1_semantics(data: bytes, expected_head_sha: str) -> dict[str, Any]:
    if HEAD_RE.fullmatch(expected_head_sha) is None:
        fail("expected head SHA is invalid")
    lines = data.decode("utf-8", "strict").splitlines()
    if any(line.startswith("E13_T2_HEAD_SHA=") for line in lines):
        fail("T2 head marker is forbidden inside T1")
    if any(line.startswith("E14_HEAD_SHA=") for line in lines):
        fail("capture-envelope head marker is forbidden inside T1")

    i_begin = exact_index(lines, "E13_T1_BEGIN")
    i_head = prefix_index(lines, "E13_T1_HEAD_SHA=")
    i_corr1 = exact_index(lines, "E13_T1_CORRELATION_BEFORE_SNAPSHOT")
    i_capability = exact_index(lines, "E13_T1_OPTIONAL_SYSTEM_IDENTIFIER_CAPABILITY")
    probe_hits = [i for i, line in enumerate(lines) if line == "E13_T1_OPTIONAL_SYSTEM_IDENTIFIER_PROBE"]
    skipped_hits = [i for i, line in enumerate(lines) if line == "E13_T1_OPTIONAL_SYSTEM_IDENTIFIER_SKIPPED_NO_PRIVILEGE"]
    if len(probe_hits) + len(skipped_hits) != 1:
        fail("optional system identifier mode must be declared exactly once")
    i_optional = probe_hits[0] if probe_hits else skipped_hits[0]
    optional_mode = "PROBE" if probe_hits else "SKIPPED_NO_PRIVILEGE"
    i_snapshot = exact_index(lines, "E13_T1_EXECUTION_CONTEXT_SNAPSHOT")
    i_corr2 = exact_index(lines, "E13_T1_CORRELATION_BEFORE_PREFLIGHT")
    i_preflight = exact_index(lines, "E13_T1_DEPENDENCY_PREFLIGHT")
    i_primary = exact_index(lines, "E13_T1_PRIMARY_25_VECTOR_READBACK")
    i_corr3 = exact_index(lines, "E13_T1_CORRELATION_BEFORE_ADDENDUM")
    i_final = exact_index(lines, "E13_T1_FINAL_INTEGRITY_ADDENDUM")
    i_rollback = exact_index(lines, "E13_T1_ROLLBACK_COMPLETE")

    ordered = [
        i_begin, i_head, i_corr1, i_capability, i_optional, i_snapshot,
        i_corr2, i_preflight, i_primary, i_corr3, i_final, i_rollback,
    ]
    if ordered != sorted(ordered) or len(set(ordered)) != len(ordered):
        fail("T1 markers are not in strict order")
    if lines[i_head].split("=", 1)[1] != expected_head_sha:
        fail("T1 head marker does not match audited head")

    corr1 = json_in_segment(lines, i_corr1, i_capability, "correlation before snapshot")
    optional_probe = None
    if optional_mode == "PROBE":
        optional_probe = json_in_segment(lines, i_optional, i_snapshot, "optional system identifier probe")
    snapshot = json_in_segment(lines, i_snapshot, i_corr2, "execution context snapshot")
    corr2 = json_in_segment(lines, i_corr2, i_preflight, "correlation before preflight")
    preflight = json_in_segment(lines, i_preflight, i_primary, "dependency preflight")
    primary = json_in_segment(lines, i_primary, i_corr3, "primary 25-vector readback")
    corr3 = json_in_segment(lines, i_corr3, i_final, "correlation before addendum")
    final = json_in_segment(lines, i_final, i_rollback, "final integrity addendum")

    correlation_fields = (
        "runtime_cluster_fingerprint", "transaction_correlation_id", "backend_pid",
        "transaction_started_at", "postmaster_started_at", "database_name", "database_oid",
    )
    correlation_context_valid_all = all(c.get("context_valid") is True for c in (corr1, corr2, corr3))
    correlation_match = all(corr1.get(field) == corr2.get(field) == corr3.get(field) for field in correlation_fields)

    cases = path(primary, "definition_checks", "binder_mutation_pattern_controls", "cases")
    vector_count = len(cases) if isinstance(cases, dict) else 0
    vectors_all_pass = isinstance(cases, dict) and vector_count == 25 and all(
        isinstance(case, dict) and case.get("pass") is True for case in cases.values()
    )

    optional_probe_matches = optional_mode == "SKIPPED_NO_PRIVILEGE"
    optional_binding_present = optional_mode == "SKIPPED_NO_PRIVILEGE"
    if optional_probe is not None:
        optional_probe_matches = all(
            optional_probe.get(field) == corr1.get(field)
            for field in ("runtime_cluster_fingerprint", "transaction_correlation_id", "backend_pid", "transaction_started_at")
        )
        binding = optional_probe.get("system_identifier_binding")
        optional_binding_present = (
            optional_probe.get("cluster_identity_strength") == "SYSTEM_IDENTIFIER"
            and isinstance(optional_probe.get("system_identifier"), str)
            and bool(optional_probe.get("system_identifier"))
            and isinstance(binding, str)
            and SHA256_RE.fullmatch(binding) is not None
        )

    checks: dict[str, Any] = {
        "head_match": True,
        "cross_scope_markers_absent": True,
        "correlation_context_valid_all": correlation_context_valid_all,
        "correlation_match": correlation_match,
        "snapshot_context_valid": snapshot.get("context_valid") is True,
        "snapshot_isolation_valid": snapshot.get("transaction_isolation_valid") is True,
        "preflight_ready": preflight.get("preflight_ready") is True,
        "preflight_all_present": preflight.get("all_present") is True,
        "binder_preserves_persisted_effects": path(primary, "definition_checks", "binder_preserves_persisted_effects") is True,
        "binder_digest_matches": path(primary, "definition_checks", "binder_definition_digest", "matches") is True,
        "mutation_controls_all_pass": path(primary, "definition_checks", "binder_mutation_pattern_controls", "all_pass") is True,
        "vector_count": vector_count,
        "vectors_all_pass": vectors_all_pass,
        "trigger_binds_pinned_function": path(primary, "gate_trigger", "binds_pinned_function") is True,
        "final_evidence_chain_ready": final.get("evidence_chain_ready") is True,
        "final_binder_and_trigger_integrity": final.get("binder_and_trigger_integrity") is True,
        "final_failure_domain_none": path(final, "integrity_status", "failure_domain") == "NONE",
        "optional_probe_mode": optional_mode,
        "optional_probe_matches": optional_probe_matches,
        "optional_binding_present": optional_binding_present,
    }
    checks["all_pass"] = all(
        value is True for key, value in checks.items()
        if key not in {"vector_count", "optional_probe_mode", "all_pass"}
    ) and vector_count == 25
    return checks
