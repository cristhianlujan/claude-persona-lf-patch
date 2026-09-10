from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lf_data_access import (  # noqa: E402
    BLOCKED,
    PASS,
    INTERFACE,
    LFDataAccess,
    SchemaContractResolver,
    execute_prepared,
    load_registry,
)


def table_receipt(binding: dict, *, source: str = "SYNTHETIC_SCHEMA_BACKEND") -> dict:
    fields = list(binding["fields"])
    return {
        "object_identity": binding["object_identity"],
        "schema": binding["object_identity"].split(".", 1)[0],
        "object_type": binding["object_type"],
        "exact_columns": [{"name": f, "ordinal_position": i} for i, f in enumerate(fields, start=1)],
        "data_types": {f: "synthetic" for f in fields},
        "nullability": {f: True for f in fields},
        "defaults": {f: None for f in fields},
        "is_identity": {f: False for f in fields},
        "identity_generation": {f: None for f in fields},
        "constraints": [],
        "indexes": [],
        "key_fields": list(binding["key_fields"]),
        "allowed_filters": list(binding["allowed_filters"]),
        "schema_fingerprint": binding["schema_fingerprint"],
        "fingerprint_provider": binding["fingerprint_provider"],
        "freshness": {"state": "CURRENT", "source": source},
    }


def unknown_table_receipt() -> dict:
    names = ["id", "regla_codigo", "error_codigo", "regla", "justificacion", "prioridad", "activa", "created_at", "categoria", "lifecycle_phase", "consumer_role"]
    return {
        "object_identity": "public.lf_prevention_rules",
        "schema": "public",
        "object_type": "TABLE",
        "exact_columns": [{"name": f, "ordinal_position": i} for i, f in enumerate(names, start=1)],
        "data_types": {"id":"uuid","regla_codigo":"text","error_codigo":"text","regla":"text","justificacion":"text","prioridad":"integer","activa":"boolean","created_at":"timestamp with time zone","categoria":"text","lifecycle_phase":"text","consumer_role":"ARRAY"},
        "nullability": {k: True for k in names},
        "defaults": {k: None for k in names},
        "is_identity": {k: False for k in names},
        "identity_generation": {k: None for k in names},
        "constraints": [],
        "indexes": [],
        "key_fields": ["regla_codigo"],
        "allowed_filters": ["regla_codigo", "error_codigo", "prioridad", "activa", "categoria"],
        "schema_fingerprint": "9677f2d45e07f7c4b9957df31e9371173603b4e8366e620ed68a2cb2b8f7e67a",
        "fingerprint_provider": "ARCHITECTURE_OBJECT_DEFINITION_V3",
        "freshness": {"state": "CURRENT", "source": "LIVE_CANARY_CAPTURE_2026-09-10T01:37:58Z"},
    }


def function_receipt(identity: str = "private.fn_demo") -> dict:
    return {
        "object_identity": identity,
        "schema": identity.split(".", 1)[0],
        "object_type": "FUNCTION",
        "function_identity": identity,
        "exact_signature": f"{identity}(p_code text, p_limit integer)",
        "arguments": [
            {"order": 1, "name": "p_code", "type": "text", "has_default": False},
            {"order": 2, "name": "p_limit", "type": "integer", "has_default": True},
        ],
        "return_contract": "TABLE(code text)",
        "relevant_permissions": ["EXECUTE:test-only"],
        "schema_fingerprint": "a" * 64,
        "freshness": {"state": "CURRENT", "source": "SYNTHETIC_SCHEMA_BACKEND"},
    }


def assert_blocked_without_backend(result: dict, expected_code: str) -> None:
    calls = []
    executed = execute_prepared(result, lambda plan: calls.append(plan))
    assert executed["status"] == BLOCKED, executed
    assert executed["code"] == expected_code, executed
    assert executed["backend_executed"] is False, executed
    assert calls == [], f"backend must not execute for {expected_code}"


def main() -> None:
    registry = load_registry(HERE / "data_access_registry_v2.json")
    access = LFDataAccess.from_registry(registry)
    resolver = SchemaContractResolver()

    expected_sources = {
        "ROUTER_SOURCE", "EKB", "OPERATION_REGISTRY", "OPERATION_CONTRACTS", "OPERATION_STEPS",
        "OPERATION_STEP_CONTRACTS", "OPERATION_JUDGES", "OPERATION_STEP_JUDGE_BINDINGS",
        "OPERATION_POLICY_BINDINGS", "STRATEGY_SNAPSHOTS", "ASSETS_PROFILES", "EVENTS",
        "INPUT_GOVERNANCE", "ADAPTER_BINDINGS", "MIGRATION_LEDGER",
    }
    assert set(registry["sources"]) == expected_sources
    assert registry["free_sql_policy"] == "FORBIDDEN_FOR_REGISTERED_SOURCE_KEYS"
    assert registry["stale_policy"] == "BLOCK_AND_RERESOLVE"
    assert registry["unknown_source_policy"] == "SCHEMA_CONTRACT_RESOLVER_FIRST"
    assert registry["schema_resolution_call_policy"] == "SEPARATE_INFORMATION_SCHEMA_CALL_BEFORE_DEPENDENT_BACKEND"

    negative_codes: list[str] = []

    b = registry["sources"]["STRATEGY_SNAPSHOTS"]
    result = access.read_strategy_snapshots(fields=["id", "field_that_does_not_exist"], schema_receipt=table_receipt(b))
    assert_blocked_without_backend(result, "BLOCK_FIELD_NOT_IN_BINDING"); negative_codes.append(result["code"])

    b = registry["sources"]["ROUTER_SOURCE"]
    result = access.read_router_source(fields=["codigo_activo"], schema_receipt=table_receipt(b), requested_object="public.lf_activos")
    assert_blocked_without_backend(result, "BLOCK_REGISTERED_SOURCE_OBJECT_MISMATCH"); negative_codes.append(result["code"])

    fr = function_receipt("private.fn_demo")
    result = resolver.prepare_function_call(function_identity="public.fn_demo", arguments={"p_code": "X"}, schema_receipt=fr)
    assert_blocked_without_backend(result, "BLOCK_FUNCTION_SCHEMA_OR_IDENTITY_MISMATCH"); negative_codes.append(result["code"])

    result = resolver.prepare_function_call(function_identity="private.fn_demo", arguments={"p_code": "X", "invented_arg": 1}, schema_receipt=fr)
    assert_blocked_without_backend(result, "BLOCK_FUNCTION_ARGUMENT_NOT_IN_RECEIPT"); negative_codes.append(result["code"])

    b = registry["sources"]["EKB"]
    stale = table_receipt(b); stale["schema_fingerprint"] = "b" * 64
    result = access.read_ekb(fields=["codigo"], schema_receipt=stale)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_FINGERPRINT_STALE"); negative_codes.append(result["code"])

    result = access.read_ekb(schema_receipt=table_receipt(b), free_sql="select * from public.lf_error_knowledge")
    assert_blocked_without_backend(result, "BLOCK_REGISTERED_SOURCE_FREE_SQL"); negative_codes.append(result["code"])

    result = resolver.prepare_unknown_read(object_identity="public.unregistered_demo", fields=["id"], filters={"id": 1}, schema_receipt=None)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_RECEIPT_REQUIRED"); negative_codes.append(result["code"])

    stale_currentness = unknown_table_receipt(); stale_currentness["freshness"] = {"state": "STALE", "source": "TEST"}
    result = resolver.prepare_unknown_read(object_identity="public.lf_prevention_rules", fields=["regla_codigo"], filters={}, schema_receipt=stale_currentness)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_RECEIPT_STALE"); negative_codes.append(result["code"])

    missing_identity = unknown_table_receipt(); del missing_identity["is_identity"]
    result = resolver.prepare_unknown_read(object_identity="public.lf_prevention_rules", fields=["regla_codigo"], filters={}, schema_receipt=missing_identity)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_RECEIPT_INCOMPLETE"); negative_codes.append(result["code"])

    bad_identity = unknown_table_receipt(); bad_identity["is_identity"]["id"] = True; bad_identity["identity_generation"]["id"] = None
    result = resolver.prepare_unknown_read(object_identity="public.lf_prevention_rules", fields=["id"], filters={}, schema_receipt=bad_identity)
    assert_blocked_without_backend(result, "BLOCK_IDENTITY_GENERATION_UNRESOLVED"); negative_codes.append(result["code"])

    bad_fr = function_receipt(); del bad_fr["arguments"][0]["type"]
    result = resolver.prepare_function_call(function_identity="private.fn_demo", arguments={"p_code": "X"}, schema_receipt=bad_fr)
    assert_blocked_without_backend(result, "BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID"); negative_codes.append(result["code"])

    bad_schema = unknown_table_receipt(); bad_schema["schema"] = "private"
    result = resolver.prepare_unknown_read(object_identity="public.lf_prevention_rules", fields=["regla_codigo"], filters={}, schema_receipt=bad_schema)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_RECEIPT_SCHEMA_MISMATCH"); negative_codes.append(result["code"])

    b = registry["sources"]["OPERATION_REGISTRY"]
    wrong_provider = table_receipt(b); wrong_provider["fingerprint_provider"] = "INVENTED_PROVIDER"
    result = access.read_operation_registry(fields=["operation_code"], schema_receipt=wrong_provider)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_FINGERPRINT_PROVIDER_MISMATCH"); negative_codes.append(result["code"])

    result = {"interface": INTERFACE, "status": PASS, "code": "FORGED_PASS", "evidence_refs": []}
    assert_blocked_without_backend(result, "BLOCK_PASS_WITHOUT_BOUND_PLAN"); negative_codes.append("BLOCK_PASS_WITHOUT_BOUND_PLAN")

    events: list[str] = []
    stale_resolved = unknown_table_receipt(); stale_resolved["freshness"] = {"state": "STALE", "source": "SCHEMA_BACKEND"}
    result = resolver.resolve_bind_execute_unknown_read(
        object_identity="public.lf_prevention_rules", fields=["regla_codigo"], filters={"activa": True},
        schema_backend=lambda request: events.append("schema") or stale_resolved,
        dependent_backend=lambda plan: events.append("dependent") or {"rows": 1}, expected_object_type="TABLE")
    assert result["status"] == BLOCKED and result["code"] == "BLOCK_SCHEMA_RECEIPT_STALE"
    assert result["backend_executed"] is False and events == ["schema"]
    negative_codes.append(result["code"])

    positives = [
        ("STRATEGY_SNAPSHOTS", ["id", "snapshot_code"], {"id": 35}),
        ("OPERATION_REGISTRY", ["operation_code", "version", "status"], {}),
        ("OPERATION_CONTRACTS", ["operation_code", "contract_code", "status"], {}),
        ("EKB", ["codigo", "titulo", "prevencion"], {"estado": "activo"}),
        ("ROUTER_SOURCE", ["codigo_activo", "nombre_canonico", "estado_documental", "estado_operativo"], {}),
    ]
    positive_codes: list[str] = []
    for source_key, fields, filters in positives:
        binding = registry["sources"][source_key]
        call_order: list[str] = []
        executed = access.resolve_bind_execute_registered_read(
            source_key=source_key, fields=fields, filters=filters,
            schema_backend=lambda request, b=binding: call_order.append("schema") or table_receipt(b),
            dependent_backend=lambda plan: call_order.append("dependent") or {"rows": 1, "source_key": plan["source_key"]})
        assert executed["status"] == PASS and executed["backend_executed"] is True
        assert call_order == ["schema", "dependent"] and executed["readback"]["source_key"] == source_key
        positive_codes.append(source_key)

    call_order: list[str] = []
    executed = resolver.resolve_bind_execute_unknown_read(
        object_identity="public.lf_prevention_rules",
        fields=["regla_codigo", "error_codigo", "prioridad", "activa", "categoria"], filters={"activa": True},
        schema_backend=lambda request: call_order.append("schema") or copy.deepcopy(unknown_table_receipt()),
        dependent_backend=lambda plan: call_order.append("dependent") or {"rows": 3}, expected_object_type="TABLE")
    assert executed["status"] == PASS and executed["backend_executed"] is True and call_order == ["schema", "dependent"]

    call_order = []
    executed = resolver.resolve_bind_execute_function_call(
        function_identity="private.fn_demo", arguments={"p_limit": 2, "p_code": "ABC"},
        schema_backend=lambda request: call_order.append("schema") or function_receipt(),
        dependent_backend=lambda plan: call_order.append("dependent") or {"ok": True, "args": plan["arguments"]})
    assert executed["status"] == PASS and call_order == ["schema", "dependent"]
    assert [a["name"] for a in executed["plan"]["arguments"]] == ["p_code", "p_limit"]
    assert [a["declared_type"] for a in executed["plan"]["arguments"]] == ["text", "integer"]

    print(json.dumps({
        "result": "PASS", "interface": INTERFACE, "registry_contract_version": registry["contract_version"],
        "base_main_sha": registry["base_main_sha"], "registered_source_count": len(registry["sources"]),
        "required_positive_readers": positive_codes, "negative_cases": len(negative_codes),
        "negative_backend_escape_count": 0, "schema_before_dependent_enforced": True,
        "freshness_current_enforced": True, "identity_metadata_enforced": True,
        "function_argument_types_resolved": True, "generic_unknown_source_resolver": "PASS",
        "function_signature_binding": "PASS"}, sort_keys=True))


if __name__ == "__main__":
    main()
