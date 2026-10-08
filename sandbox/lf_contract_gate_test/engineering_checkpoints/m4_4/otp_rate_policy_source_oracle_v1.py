#!/usr/bin/env python3
"""IG M4.4 dedicated OTP rate-limit source oracle (shadow/read-only).

Only judges the observed rule -> policy relation for a requested screen/run.
Never imports a Curator classifier, copies Curator conclusions, or awards
Validator/Readiness PASS. Domain-specific by design, not a global judge.
"""
from __future__ import annotations

from typing import Any, Mapping

CONTRACT = "IG_OTP_RATE_LIMIT_SOURCE_ORACLE_V1"
FAMILY = "RATE_LIMIT"


def _int(v: Any) -> bool:
    return type(v) is int and v > 0


def _out(status: str, code: str, run_id: int, screen_id: int,
         *, findings: list[str] | None = None, source_refs: list[str] | None = None,
         ignored_candidate_count: int = 0) -> dict[str, Any]:
    return {
        "contract": CONTRACT,
        "status": status,
        "code": code,
        "run_id": run_id,
        "pantalla_id": screen_id,
        "family_code": FAMILY,
        "findings": findings or [],
        "source_refs": source_refs or [],
        "ignored_candidate_count": ignored_candidate_count,
        "scope": "OTP_RULE_TO_CANONICAL_RATE_POLICY_ONLY",
        "semantic_pass_authorized": False,
        "validator_pass_authorized": False,
        "runtime_enforcement_verified": False,
        "production_authorized": False,
        "decisional": False,
    }


def evaluate(snapshot: Mapping[str, Any], *, expected_run_id: int,
             expected_screen_id: int) -> dict[str, Any]:
    """Evaluate caller-provided independently resolved canonical readback.

    The caller must separately verify provenance/freshness of the readback.
    Identity, domain, candidate exclusion and contradiction checks fail closed.
    """
    if not isinstance(snapshot, Mapping) or not _int(expected_run_id) or not _int(expected_screen_id):
        return _out("BLOCKED", "INVALID_INPUT", expected_run_id, expected_screen_id)
    run_id, screen_id = snapshot.get("run_id"), snapshot.get("pantalla_id")
    if run_id != expected_run_id or screen_id != expected_screen_id or snapshot.get("family_code") != FAMILY:
        return _out("BLOCKED", "SOURCE_IDENTITY_MISMATCH", expected_run_id, expected_screen_id)
    bindings = snapshot.get("rule_bindings")
    if not isinstance(bindings, list):
        return _out("BLOCKED", "SOURCE_BINDINGS_UNREADABLE", run_id, screen_id)
    ignored = sum(1 for b in bindings if isinstance(b, Mapping) and b.get("status") != "VIGENTE")
    active = [b for b in bindings if isinstance(b, Mapping)
              and b.get("status") == "VIGENTE"
              and b.get("category") == "rate_limiting"
              and isinstance(b.get("rule_config"), Mapping)
              and b["rule_config"].get("scope") == "por_numero_celular_cross_session"]
    if len(active) == 0:
        return _out("UNRESOLVED", "NO_SCOPED_VIGENTE_OTP_RATE_RULE", run_id, screen_id,
                    ignored_candidate_count=ignored)
    if len(active) != 1:
        return _out("BLOCKED", "AMBIGUOUS_SCOPED_RATE_RULES", run_id, screen_id,
                    ignored_candidate_count=ignored)

    binding = active[0]
    cfg = binding["rule_config"]
    policy = binding.get("policy")
    name = binding.get("rule_code")
    refs = [f"lf_ops.reglas:{name}"] if isinstance(name, str) and name else []
    policy_code = cfg.get("canonical_rate_policy_code")
    if isinstance(policy_code, str) and policy_code:
        refs.append(f"lf_ops.politicas_rate_limit:{policy_code}")
    if not isinstance(policy, Mapping) or not isinstance(policy_code, str) or not policy_code:
        return _out("UNRESOLVED", "CANONICAL_RATE_POLICY_MISSING", run_id, screen_id,
                    source_refs=refs, ignored_candidate_count=ignored)

    findings: list[str] = []
    def verify(condition: bool, code: str) -> None:
        if not condition:
            findings.append(code)
    verify(policy.get("policy_code") == policy_code, "POLICY_CODE_MISMATCH")
    verify(policy.get("status") == "VIGENTE", "POLICY_NOT_VIGENTE")
    verify(policy.get("resource_code") == "CLIENT_OTP_SEND", "RESOURCE_NOT_OTP_SEND")
    verify(_int(cfg.get("ventana_minutos")) and _int(policy.get("window_seconds"))
           and policy["window_seconds"] == cfg["ventana_minutos"] * 60,
           "WINDOW_SECONDS_CONTRADICTS_RULE")
    verify(_int(cfg.get("max_codigos")) and _int(policy.get("max_requests"))
           and policy["max_requests"] == cfg["max_codigos"],
           "MAX_REQUESTS_CONTRADICTS_RULE")
    verify(policy.get("scope_key") == "PHONE_HASH"
           and cfg.get("phone_key_storage") == "HASH_ONLY"
           and cfg.get("raw_phone_in_logs") == "DENY",
           "PHONE_HASH_SCOPE_OR_PRIVACY_INVALID")
    verify(cfg.get("reset_on_new_session") is False, "CROSS_SESSION_RESET_INVALID")
    verify(cfg.get("enforcement_side") == "SERVER"
           and cfg.get("atomic_enforcement_required") is True,
           "SERVER_ATOMIC_ENFORCEMENT_NOT_REQUIRED_BY_RULE")
    verify(_int(policy.get("burst_limit")) and policy["burst_limit"] <= policy["max_requests"],
           "BURST_LIMIT_UNBOUNDED")

    return _out("CONTRADICTION" if findings else "SOURCE_CONSISTENT",
                "CANONICAL_RATE_POLICY_CONTRADICTION" if findings
                else "SCOPED_SOURCE_RELATION_CONSISTENT_NOT_SEMANTIC_PASS",
                run_id, screen_id, findings=findings, source_refs=refs,
                ignored_candidate_count=ignored)
