"""Pure C4/C7 candidate checks. No operational admission, discovery or writes.

Artifact readers and binding maps are trusted adapter inputs. Their admission,
canonical value readback and CURRENTNESS_AUTHORITY wiring remain separate gates.
COMPLETE means local structural completeness, never permission to program.
"""
from __future__ import annotations

from copy import deepcopy
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import PurePosixPath
import re
from typing import Callable

from programming_pg01_receiver_v1 import canonical_sha256

HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")
DIMENSIONS = ("messages", "errors", "navigation", "history", "consents")
MAP_SCHEMA = "PG01_SUFFICIENCY_BINDING_MAP_CANDIDATE_V1"
DECISION_SCHEMA = "PG01_SUFFICIENCY_DECISION_CANDIDATE_V1"


def text(value):
    return isinstance(value, str) and bool(value.strip())


def strings(value, *, nonempty=False):
    return isinstance(value, list) and (bool(value) or not nonempty) and all(text(v) for v in value) and len(value) == len(set(value))


def result(status, issues, **extra):
    return {"status": status, "validation_level": "SOURCE_ONLY_LOCAL_STRUCTURE",
            "execution_allowed": False, "operational_admission": False,
            "issues": issues, **extra}


class InvalidEvidence(ValueError):
    pass


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise InvalidEvidence("DUPLICATE_JSON_KEY")
        value[key] = item
    return value


def invalid_constant(value):
    raise InvalidEvidence("NONFINITE_JSON_CONSTANT")


def read_pin(pin, reader):
    if not isinstance(pin, dict) or not all(text(pin.get(k)) for k in ("repo", "commit", "path", "sha256")):
        raise InvalidEvidence("PIN_MISSING")
    path = PurePosixPath(pin["path"])
    if not HEX40.fullmatch(pin["commit"]) or not HEX64.fullmatch(pin["sha256"]) or path.is_absolute() or ".." in path.parts:
        raise InvalidEvidence("PIN_INVALID")
    raw = reader(deepcopy(pin))
    if not isinstance(raw, bytes) or not raw.strip() or hashlib.sha256(raw).hexdigest() != pin["sha256"]:
        raise InvalidEvidence("ARTIFACT_DIGEST_MISMATCH")
    return raw


def number(value):
    if not isinstance(value, str):
        raise InvalidEvidence("DECIMAL_STRING_REQUIRED")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]{1,12})?", value) or sum(c.isdigit() for c in value) > 24:
        raise InvalidEvidence("DECIMAL_INVALID")
    try:
        parsed = Decimal(value)
    except InvalidOperation as exc:
        raise InvalidEvidence("DECIMAL_INVALID") from exc
    if not parsed.is_finite() or parsed < 0:
        raise InvalidEvidence("DECIMAL_INVALID")
    return parsed


def validate_technical_framework(frame: dict, target_repo: str, reader: Callable) -> dict:
    """Validate pinned bytes; reader must resolve exact identity, never 'latest'.

    This does not attest that the artifacts are operationally admitted/current.
    Catalog state is retained, not promoted. Missing budget remains MEASURE_ONLY.
    """
    issues, artifacts, pins = [], {}, {}
    if not text(target_repo) or not isinstance(frame, dict) or frame.get("target_repo") != target_repo or not text(frame.get("project_ref")):
        return result("BLOCK", [{"path": "technical_framework", "code": "TARGET_OR_PROJECT_MISMATCH"}])
    for key in ("standards_catalog", "technical_profile", "control_mechanism", "architecture_profile", "consumption_policy"):
        pin = frame.get(key)
        try:
            raw = read_pin(pin, reader)
            value = raw.decode("utf-8") if key == "architecture_profile" else json.loads(raw, object_pairs_hook=unique_object, parse_constant=invalid_constant)
            if key != "architecture_profile" and not isinstance(value, dict):
                raise InvalidEvidence("ARTIFACT_OBJECT_REQUIRED")
            if key != "architecture_profile" and not text(pin.get("version")):
                raise InvalidEvidence("ARTIFACT_VERSION_MISSING")
            artifacts[key], pins[key] = value, deepcopy(pin)
        except Exception as exc:
            issues.append({"path": key, "code": str(exc) if isinstance(exc, InvalidEvidence) else "EVIDENCE_UNAVAILABLE_OR_MALFORMED"})
    if issues:
        return result("MISSING", issues, artifact_pins=pins)
    catalog, profile, control, policy = (artifacts[k] for k in
        ("standards_catalog", "technical_profile", "control_mechanism", "consumption_policy"))

    def require(condition, path, code):
        if not condition:
            issues.append({"path": path, "code": code})

    require(catalog.get("schema_version") == "LF_STANDARDS_CATALOG_V1" and catalog.get("catalog_version") == pins["standards_catalog"]["version"], "standards_catalog", "CATALOG_VERSION_MISMATCH")
    require(profile.get("schema_version") == "PG01_PROJECT_TECHNICAL_PROFILE_CANDIDATE_V1" and profile.get("version") == pins["technical_profile"]["version"], "technical_profile", "TECHNICAL_PROFILE_VERSION")
    require(pins["technical_profile"]["repo"] == target_repo and profile.get("target_repo") == target_repo and profile.get("project_ref") == frame["project_ref"], "technical_profile", "TECHNICAL_PROFILE_TARGET_MISMATCH")
    require(text(profile.get("namespace")), "technical_profile.namespace", "PROJECT_NAMESPACE_MISSING")
    codes = profile.get("rule_codes")
    require(strings(codes) and type(profile.get("use_catalog_defaults")) is bool and ((bool(codes) and profile.get("use_catalog_defaults") is False) or (codes == [] and profile.get("use_catalog_defaults") is True)), "technical_profile.rule_codes", "TECHNICAL_RULE_SELECTION_UNRESOLVED")
    require(control.get("schema_version") == "PG01_CONTROL_MECHANISM_CANDIDATE_V1" and control.get("version") == pins["control_mechanism"]["version"] and control.get("target_repo") == target_repo and strings(control.get("control_refs"), nonempty=True), "control_mechanism", "CONTROL_MECHANISM_UNRESOLVED")
    platform = target_repo == "cristhianlujan/claude-persona-lf-patch"
    require(control.get("kind") == ("LF_PLATFORM" if platform else "PRODUCT_PIPELINE"), "control_mechanism.kind", "CONTROL_DESTINATION_MISMATCH")
    if platform:
        require(strings(control.get("control_refs"), nonempty=True) and {"ROUTER", "PASE", "MERGE_TRAIN"}.issubset(control["control_refs"]), "control_mechanism.control_refs", "PLATFORM_CONTROLS_INCOMPLETE")
    require(pins["architecture_profile"].get("project_ref") == frame["project_ref"] and strings(pins["architecture_profile"].get("applies_to_repos"), nonempty=True) and target_repo in pins["architecture_profile"]["applies_to_repos"], "architecture_profile", "ARCHITECTURE_PROJECT_MISMATCH")
    require(policy.get("policy_version") == pins["consumption_policy"]["version"], "consumption_policy", "CONSUMPTION_POLICY_VERSION")
    modes = policy.get("modes")
    mode = modes.get(frame.get("optimization_mode")) if isinstance(modes, dict) and isinstance(frame.get("optimization_mode"), str) else None
    require(isinstance(mode, dict) and isinstance(mode.get("controls"), dict) and all(mode["controls"].get(k) is True for k in ("standards", "reviews", "tests")) and mode.get("difficulty_model_routing") is False, "optimization_mode", "OPTIMIZATION_MODE_INVALID_OR_RELAXES_CONTROLS")
    if issues:
        return result("BLOCK", issues, artifact_pins=pins, catalog_status=catalog.get("status"))
    budget = policy.get("budget")
    requested = frame.get("request_budget")
    if not isinstance(budget, dict) or not isinstance(requested, dict):
        return result("MISSING", [{"path": "request_budget", "code": "REQUEST_BUDGET_MISSING"}], artifact_pins=pins)
    if budget.get("amount") == "POR_DEFINIR":
        return result("MISSING", [{"path": "request_budget.amount", "code": "BUDGET_UNCONFIGURED_MEASURE_ONLY"}],
                      artifact_pins=pins, budget_state="MEASURE_ONLY", catalog_status=catalog.get("status"))
    try:
        cap, spent = number(budget.get("amount")), number(requested.get("spent"))
        if cap <= 0 or requested.get("amount") != budget["amount"] or not text(budget.get("currency")) or requested.get("currency") != budget["currency"] or budget.get("warning_percent") != 80 or budget.get("decision_percent") != 100:
            raise InvalidEvidence("BUDGET_POLICY_MISMATCH")
    except InvalidEvidence as exc:
        return result("BLOCK", [{"path": "request_budget", "code": str(exc)}], artifact_pins=pins)
    state = "EXHAUSTED" if spent >= cap else "WARNING" if spent >= cap * Decimal("0.8") else "WITHIN_BUDGET"
    return result("REQUIRES_DECISION" if state == "EXHAUSTED" else "COMPLETE", [], artifact_pins=pins,
                  budget_state=state, catalog_status=catalog.get("status"),
                  pending_operational_gates=["TECHNICAL_SOURCE_ADMISSION", "CURRENTNESS_AUTHORITY_BINDING"])


def validate_sufficiency(snapshot: dict, scope_ids: list, binding_map: dict) -> dict:
    """Strict candidate mapping over A6 bindings, no added snapshot fields.

    The map and normalized decision shape are source-only adapter proposals.
    An agreed A9 mapping/semantic readback is required before operational use.
    """
    missing, contradictions, checked = [], [], []
    if not strings(scope_ids, nonempty=True) or not isinstance(snapshot, dict):
        return result("MISSING", [{"path": "scope_ids", "code": "SCOPES_MISSING"}], return_target="ANALYSIS")
    if not isinstance(binding_map, dict) or binding_map.get("schema_version") != MAP_SCHEMA or binding_map.get("snapshot_sha256") != canonical_sha256(snapshot) or not text(binding_map.get("source_ref")):
        return result("MISSING", [{"path": "binding_map", "code": "BINDING_MAP_MISSING_OR_SNAPSHOT_MISMATCH"}], return_target="ANALYSIS")
    mapping = binding_map.get("binding_kinds")
    if not isinstance(mapping, dict) or set(mapping) != set(DIMENSIONS) or not all(text(v) for v in mapping.values()) or len(set(mapping.values())) != len(DIMENSIONS):
        return result("MISSING", [{"path": "binding_map", "code": "BINDING_MAP_INCOMPLETE_OR_AMBIGUOUS"}], return_target="ANALYSIS")
    a6 = snapshot.get("implementability_schema")
    requirements = a6.get("requirements") if isinstance(a6, dict) else None
    bindings = a6.get("canonical_implementation_bindings") if isinstance(a6, dict) else None
    scopes = snapshot.get("scope_readiness")
    if not isinstance(requirements, list) or not all(isinstance(r, dict) for r in requirements) or not isinstance(bindings, list) or not all(isinstance(b, dict) for b in bindings) or not isinstance(scopes, list) or not all(isinstance(s, dict) for s in scopes):
        return result("MISSING", [{"path": "implementability_schema", "code": "A6_MATERIAL_MISSING"}], return_target="ANALYSIS")
    if any(not text(r.get("requirement_id")) or not strings(r.get("scope_refs"), nonempty=True) for r in requirements) or any(not strings(b.get("scope_refs"), nonempty=True) or not text(b.get("binding_kind")) for b in bindings):
        return result("MISSING", [{"path": "implementability_schema", "code": "A6_IDENTITIES_OR_SCOPES_INVALID"}], return_target="ANALYSIS")
    requirement_ids = [r["requirement_id"] for r in requirements]
    scope_keys = [s.get("scope_id") for s in scopes]
    if len(requirement_ids) != len(set(requirement_ids)) or not all(text(v) for v in scope_keys) or len(scope_keys) != len(set(scope_keys)):
        return result("CONTRADICTION", [{"path": "implementability_schema", "code": "DUPLICATE_REQUIREMENT_OR_SCOPE"}], return_target="ANALYSIS")
    scope_by_id = {s.get("scope_id"): s for s in scopes if text(s.get("scope_id"))}
    selected = set(scope_ids)
    for sid in scope_ids:
        scope = scope_by_id.get(sid) or {}
        if scope.get("status") != "READY" or scope.get("blockers") or not strings(scope.get("depends_on_scope_ids")) or not set(scope["depends_on_scope_ids"]).issubset(selected):
            return result("MISSING", [{"path": sid, "code": "READY_DEPENDENCY_CLOSURE_REQUIRED"}], return_target="ANALYSIS")
    all_ids = [b.get("binding_id") for b in bindings]
    if not all(text(v) for v in all_ids) or len(all_ids) != len(set(all_ids)):
        return result("CONTRADICTION", [{"path": "bindings", "code": "DUPLICATE_OR_INVALID_BINDING_ID"}], return_target="ANALYSIS")
    for sid in sorted(scope_ids):
        required_ids = {r.get("requirement_id") for r in requirements if sid in (r.get("scope_refs") or [])}
        if not required_ids or not all(text(v) for v in required_ids):
            missing.append({"path": sid, "code": "REQUIREMENTS_MISSING"})
            continue
        for dimension in DIMENSIONS:
            path = sid + "." + dimension
            candidates = [b for b in bindings if b.get("binding_kind") == mapping[dimension] and sid in (b.get("scope_refs") or [])]
            if len(candidates) != 1:
                (contradictions if len(candidates) > 1 else missing).append({"path": path, "code": "CONFLICTING_DECISIONS" if candidates else "SUFFICIENCY_DECISION_MISSING"})
                continue
            binding = candidates[0]
            value = binding.get("resolved_current_value")
            if not text(binding.get("canonical_ref")) or not text(binding.get("currentness_ref")) or not text(binding.get("resolver_ref")) or not strings(binding.get("evidence_refs"), nonempty=True) or binding.get("blockers") != [] or binding.get("value_transport") != "INLINE_RESOLVED_VALUE_PLUS_CANONICAL_REF" or not isinstance(value, dict):
                missing.append({"path": path, "code": "CANONICAL_RESOLVED_BINDING_REQUIRED"})
                continue
            refs = value.get("requirement_ids")
            if value.get("schema_version") != DECISION_SCHEMA or value.get("dimension") != dimension or not text(value.get("reason")) or not strings(refs, nonempty=True) or set(refs) != required_ids:
                missing.append({"path": path, "code": "DECISION_REQUIREMENT_COVERAGE_MISSING"})
                continue
            disposition = value.get("disposition")
            items = value.get("items")
            valid = disposition == "NOT_APPLICABLE" and items == []
            if disposition == "APPLICABLE" and isinstance(items, list) and items:
                fields = {"messages": ("text",), "errors": ("code", "text"), "navigation": ("event_code",), "history": ("entity_ref",), "consents": ("document_ref", "document_version")}
                valid = all(isinstance(item, dict) and text(item.get("canonical_ref")) and all(text(item.get(k)) for k in fields[dimension]) for item in items)
                if dimension == "history":
                    valid = valid and all(type(item.get("requires_history")) is bool for item in items)
                if dimension == "consents":
                    valid = valid and all(item.get("document_state") == "CURRENT" for item in items)
            if not valid:
                missing.append({"path": path, "code": "MATERIAL_VALUE_MISSING_OR_NOT_APPLICABLE_UNPROVEN"})
                continue
            checked.append({"scope_id": sid, "dimension": dimension, "binding_id": binding["binding_id"], "canonical_ref": binding["canonical_ref"], "decision": deepcopy(value)})
    status = "CONTRADICTION" if contradictions else "MISSING" if missing else "COMPLETE"
    return result(status, contradictions + missing, evaluated_scope_ids=sorted(scope_ids),
                  checked_dimensions=checked, return_target="ANALYSIS" if status != "COMPLETE" else None,
                  pending_operational_gates=["A9_BINDING_MAP_AGREEMENT", "CANONICAL_VALUE_READBACK", "CURRENTNESS_AUTHORITY_BINDING"])
