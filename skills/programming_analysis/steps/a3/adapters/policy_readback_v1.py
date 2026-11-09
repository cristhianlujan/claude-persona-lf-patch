"""A3 policy projection: existing effective-rule inventory + LF screen contract.

The host acquires lf_ops.reglas.valor_config and the existing
lf_ops.fn_screen_contract_v1 contract.policies (no extra resolver or SQL here).
A source readback is not a currentness attestation or runtime permission.
"""
from __future__ import annotations
from copy import deepcopy
from typing import Any

FAMILIES = {
    "lf_ops.politicas_seguridad": "security_policy_id",
    "lf_ops.politicas_sesion": "session_policy_id",
    "lf_ops.politicas_rate_limit": "rate_limit_policy_id",
    "lf_ops.politicas_timeout": "timeout_policy_id",
}


def blocked(code: str) -> dict:
    return {"status": "BLOCKED", "blocking_code": code}


def _references(config: Any, prefix: str = "$") -> list[dict]:
    result = []
    if isinstance(config, dict):
        for key, val in config.items():
            pointer = prefix + "/" + str(key).replace("~", "~0").replace("/", "~1")
            if key.endswith("_policy_id"):
                if type(val) is int and val > 0:
                    result.append({"role": key, "id": val, "path": pointer})
                elif val is not None:
                    result.append({"role": key, "id": None, "path": pointer,
                                   "unresolved_reason": "POLICY_ID_NOT_POSITIVE_INTEGER"})
            elif isinstance(val, (dict, list)):
                result.extend(_references(val, pointer))
    elif isinstance(config, list):
        for i, val in enumerate(config):
            if isinstance(val, (dict, list)):
                result.extend(_references(val, prefix + "/" + str(i)))
    return result


def project(effective: Any, policy_links: Any, readback: Any,
            *, target_ref: str, screen_ref: str) -> dict:
    if not isinstance(readback, dict):
        return blocked("A3_POLICY_DEFINITIONS_READ_REQUIRED")
    if (readback.get("schema_version") != "LF_SCREEN_POLICIES_READBACK_V1"
            or readback.get("source_function") != "lf_ops.fn_screen_contract_v1"
            or readback.get("business") != "LF"
            or readback.get("target_ref") != target_ref
            or readback.get("source_ref") != screen_ref
            or readback.get("source_attested") is not False):
        return blocked("A3_POLICY_DEFINITIONS_SOURCE_IDENTITY_INVALID")
    if (not isinstance(effective, dict)
            or not isinstance(effective.get("rules"), list)
            or not isinstance(policy_links, list)):
        return blocked("A3_POLICY_INVENTORY_INPUT_INVALID")
    records = readback.get("policy_objects")
    if not isinstance(records, list):
        return blocked("A3_POLICY_DEFINITIONS_ITEMS_MISSING")
    by_ref, approved_objects, excluded_objects = {}, [], []
    for obj in records:
        if not isinstance(obj, dict):
            return blocked("A3_POLICY_OBJECT_INVALID")
        table, pk, pid = obj.get("table"), obj.get("primary_key"), obj.get("policy_id")
        status, policy_code = obj.get("status"), obj.get("policy_code")
        values = obj.get("parameters")
        if (table not in FAMILIES or pk != FAMILIES[table]
                or type(pid) is not int or pid < 1
                or not isinstance(policy_code, str) or not policy_code
                or not isinstance(status, str) or not status
                or not isinstance(values, dict) or not values):
            return blocked("A3_POLICY_OBJECT_SOURCE_FIELDS_INVALID")
        ref = "supabase://" + table + "/" + str(pid)
        if obj.get("source_ref") != ref or ref in by_ref:
            return blocked("A3_POLICY_OBJECT_DUPLICATE_OR_REF_DRIFT")
        entry = {"source_ref": ref, "policy_code": policy_code,
                 "status": status, "parameter_values": deepcopy(values),
                 "source_attested": False}
        by_ref[ref] = entry
        (approved_objects if status == "VIGENTE" else excluded_objects).append(entry)
    bindings = {}
    link_items = []
    for link in policy_links:
        if not isinstance(link, dict):
            return blocked("A3_POLICY_LINK_INVALID")
        target = link.get("policy_target_ref")
        role = link.get("reference_role")
        status = link.get("status")
        if (not isinstance(target, str) or not target.startswith("supabase://lf_ops.")
                or not isinstance(role, str) or not role.endswith("_policy_id")
                or not isinstance(status, str) or not status):
            return blocked("A3_POLICY_LINK_TARGET_UNRESOLVED")
        if target not in by_ref:
            return blocked("A3_POLICY_LINK_TARGET_NOT_READ")
        key = (role, target)
        if key in bindings:
            return blocked("A3_POLICY_LINK_DUPLICATE")
        bindings[key] = status
        link_items.append({
            "source_ref": link["source_ref"], "reference_role": role,
            "policy_target_ref": target, "link_status": status,
            "policy_status": by_ref[target]["status"],
            "approved_for_binding": status == "VIGENTE" and by_ref[target]["status"] == "VIGENTE",
        })
    dependencies, impacted, eligible = [], set(), set()
    total_refs = 0
    for row in effective["rules"]:
        if not isinstance(row, dict) or "config" not in row:
            return blocked("A3_POLICY_RULE_CONFIG_READ_REQUIRED")
        code, status, pending = row.get("code"), row.get("status"), row.get("pending_decision")
        if not isinstance(code, str) or status is None or type(pending) is not bool:
            return blocked("A3_POLICY_RULE_STATUS_INVALID")
        if status != "VIGENTE" or pending:
            continue
        config = row["config"]
        if config is not None and not isinstance(config, (dict, list)):
            return blocked("A3_POLICY_RULE_CONFIG_INVALID")
        refs = _references(config)
        if not refs:
            eligible.add(code)
            continue
        applicable = True
        for p in refs:
            total_refs += 1
            options = [table for table, pk in FAMILIES.items() if p["role"].endswith(pk)]
            if p["id"] is None or len(options) != 1:
                dependencies.append({
                    "rule_code": code, "reference_role": p["role"], "path": p["path"],
                    "status": "UNRESOLVED_POLICY_REFERENCE", "eligible_for_implementation": False,
                })
                applicable = False
                continue
            target = "supabase://" + options[0] + "/" + str(p["id"])
            obj = by_ref.get(target)
            bind_status = bindings.get((p["role"], target))
            if obj is None:
                disposition = "POLICY_TARGET_MISSING"
            elif obj["status"] != "VIGENTE":
                disposition = "POLICY_NOT_VIGENTE"
            elif bind_status == "VIGENTE":
                disposition = "APPROVED_POLICY_AND_BINDING"
            else:
                # Approved central object cannot turn a candidate or unknown
                # screen-level association into a granted implementation.
                disposition = "POLICY_BINDING_NOT_APPROVED_OR_UNRESOLVED"
            ok = disposition == "APPROVED_POLICY_AND_BINDING"
            applicable = applicable and ok
            dependencies.append({
                "rule_code": code, "reference_role": p["role"], "path": p["path"],
                "policy_target_ref": target,
                "policy_status": obj["status"] if obj else "NOT_FOUND",
                "policy_code": obj["policy_code"] if obj else None,
                "binding_status": bind_status or "NOT_FOUND",
                "status": disposition,
                "eligible_for_implementation": ok,
            })
        if applicable:
            eligible.add(code)
        else:
            impacted.add(code)
    return {
        "status": "POLICIES_PROJECTED_UNATTESTED",
        "policy_source_ref": screen_ref, "policy_source_function": readback["source_function"],
        "approved_policy_objects": approved_objects,
        "excluded_policy_objects": excluded_objects,
        "policy_link_resolution": link_items,
        "rule_policy_dependencies": dependencies,
        "rule_codes_policy_dependency_pending": sorted(impacted),
        "rule_codes_without_unapproved_policy_dependency": sorted(eligible),
        "counts": {
            "policy_objects": len(records),
            "policy_objects_vigente": len(approved_objects),
            "policy_objects_excluded": len(excluded_objects),
            "screen_policy_links": len(policy_links),
            "rules_with_unapproved_or_unresolved_policy": len(impacted),
            "referenced_policy_occurrences": total_refs,
        },
        "source_attested": False, "currentness_attested": False,
        "no_write_performed": True, "a4_allowed": False,
    }
