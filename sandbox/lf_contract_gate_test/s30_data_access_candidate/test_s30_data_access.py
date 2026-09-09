from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lf_data_access import (
    BLOCKED,
    PASS,
    LFDataAccess,
    SchemaContractResolver,
    execute_prepared,
    load_registry,
)


def table_receipt(binding: dict) -> dict:
    fields = list(binding["fields"])
    return {
        "object_identity": binding["object_identity"],
        "schema": binding["object_identity"].split(".", 1)[0],
        "object_type": binding["object_type"],
        "exact_columns": [{"name": f} for f in fields],
        "data_types": {f: "synthetic" for f in fields},
        "nullability": {f: True for f in fields},
        "defaults": {f: None for f in fields},
        "identity_generation": {f: None for f in fields},
        "constraints": [],
        "indexes": [],
        "key_fields": list(binding["key_fields"]),
        "allowed_filters": list(binding["allowed_filters"]),
        "schema_fingerprint": binding["schema_fingerprint"],
        "freshness": {"state": "CURRENT", "source": "SYNTHETIC_GUARD_FIXTURE"},
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
        "freshness": {"state": "CURRENT", "source": "SYNTHETIC_GUARD_FIXTURE"},
    }


def assert_blocked_without_backend(result: dict, expected_code: str) -> None:
    calls = []
    executed = execute_prepared(result, lambda plan: calls.append(plan))
    assert executed["status"] == BLOCKED, executed
    assert executed["code"] == expected_code, executed
    assert calls == [], f"backend must not execute for {expected_code}"


def main() -> None:
    registry = load_registry(HERE / "data_access_registry_v1.json")
    access = LFDataAccess.from_registry(registry)
    resolver = SchemaContractResolver()

    expected_sources = {
        "ROUTER_SOURCE",
        "EKB",
        "OPERATION_REGISTRY",
        "OPERATION_CONTRACTS",
        "OPERATION_STEPS",
        "OPERATION_STEP_CONTRACTS",
        "OPERATION_JUDGES",
        "OPERATION_STEP_JUDGE_BINDINGS",
        "OPERATION_POLICY_BINDINGS",
        "STRATEGY_SNAPSHOTS",
        "ASSETS_PROFILES",
        "EVENTS",
        "INPUT_GOVERNANCE",
        "ADAPTER_BINDINGS",
        "MIGRATION_LEDGER",
    }
    assert set(registry["sources"]) == expected_sources
    assert registry["free_sql_policy"] == "FORBIDDEN_FOR_REGISTERED_SOURCE_KEYS"
    assert registry["stale_policy"] == "BLOCK_AND_RERESOLVE"
    assert registry["unknown_source_policy"] == "SCHEMA_CONTRACT_RESOLVER_FIRST"

    # Negative 1: nonexistent/unregistered column.
    b = registry["sources"]["STRATEGY_SNAPSHOTS"]
    r = table_receipt(b)
    result = access.read_strategy_snapshots(fields=["id", "field_that_does_not_exist"], schema_receipt=r)
    assert_blocked_without_backend(result, "BLOCK_FIELD_NOT_IN_BINDING")

    # Negative 2: wrong table/view for a registered source key.
    b = registry["sources"]["ROUTER_SOURCE"]
    r = table_receipt(b)
    result = access.read_router_source(
        fields=["codigo_activo"],
        schema_receipt=r,
        requested_object="public.lf_activos",
    )
    assert_blocked_without_backend(result, "BLOCK_REGISTERED_SOURCE_OBJECT_MISMATCH")

    # Negative 3: wrong function schema/identity.
    fr = function_receipt("private.fn_demo")
    result = resolver.prepare_function_call(
        function_identity="public.fn_demo",
        arguments={"p_code": "X"},
        schema_receipt=fr,
    )
    assert_blocked_without_backend(result, "BLOCK_FUNCTION_SCHEMA_OR_IDENTITY_MISMATCH")

    # Negative 4: nonexistent function argument.
    result = resolver.prepare_function_call(
        function_identity="private.fn_demo",
        arguments={"p_code": "X", "invented_arg": 1},
        schema_receipt=fr,
    )
    assert_blocked_without_backend(result, "BLOCK_FUNCTION_ARGUMENT_NOT_IN_RECEIPT")

    # Negative 5: stale registered binding.
    b = registry["sources"]["EKB"]
    stale = table_receipt(b)
    stale["schema_fingerprint"] = "b" * 64
    result = access.read_ekb(fields=["codigo"], schema_receipt=stale)
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_FINGERPRINT_STALE")

    # Negative 6: registered source trying to use free SQL.
    current = table_receipt(b)
    result = access.read_ekb(schema_receipt=current, free_sql="select * from public.lf_error_knowledge")
    assert_blocked_without_backend(result, "BLOCK_REGISTERED_SOURCE_FREE_SQL")

    # Negative 7: unknown source without a prior schema receipt.
    result = resolver.prepare_unknown_read(
        object_identity="public.unregistered_demo",
        fields=["id"],
        filters={"id": 1},
        schema_receipt=None,
    )
    assert_blocked_without_backend(result, "BLOCK_SCHEMA_RECEIPT_REQUIRED")

    # Positive required set: each produces a bound plan and only then reaches backend.
    positives = [
        ("STRATEGY_SNAPSHOTS", access.read_strategy_snapshots, ["id", "snapshot_code"], {"id": 35}),
        ("OPERATION_REGISTRY", access.read_operation_registry, ["operation_code", "version", "status"], {}),
        ("OPERATION_CONTRACTS", access.read_operation_contracts, ["operation_code", "contract_code", "status"], {}),
        ("EKB", access.read_ekb, ["codigo", "titulo", "prevencion"], {"estado": "activo"}),
        (
            "ROUTER_SOURCE",
            access.read_router_source,
            ["codigo_activo", "nombre_canonico", "estado_documental", "estado_operativo"],
            {},
        ),
    ]
    positive_codes = []
    for source_key, fn, fields, filters in positives:
        binding = registry["sources"][source_key]
        receipt = table_receipt(binding)
        prepared = fn(fields=fields, filters=filters, schema_receipt=receipt)
        assert prepared["status"] == PASS, prepared
        calls = []
        executed = execute_prepared(prepared, lambda plan: calls.append(plan) or {"rows": 1})
        assert executed["status"] == PASS, executed
        assert executed["backend_executed"] is True
        assert len(calls) == 1
        assert calls[0]["source_key"] == source_key
        positive_codes.append(source_key)

    # Positive generic long-tail resolver: receipt first, query binding second.
    unknown_receipt = {
        "object_identity": "public.unregistered_demo",
        "schema": "public",
        "object_type": "VIEW",
        "exact_columns": [{"name": "id"}, {"name": "label"}],
        "data_types": {"id": "bigint", "label": "text"},
        "nullability": {"id": False, "label": True},
        "defaults": {"id": None, "label": None},
        "identity_generation": {"id": None, "label": None},
        "constraints": [],
        "indexes": [],
        "key_fields": ["id"],
        "allowed_filters": ["id"],
        "schema_fingerprint": "c" * 64,
        "freshness": {"state": "CURRENT", "source": "SYNTHETIC_SCHEMA_FIRST"},
    }
    prepared = resolver.prepare_unknown_read(
        object_identity="public.unregistered_demo",
        fields=["id", "label"],
        filters={"id": 1},
        schema_receipt=unknown_receipt,
    )
    assert prepared["status"] == PASS, prepared
    calls = []
    executed = execute_prepared(prepared, lambda plan: calls.append(plan) or {"rows": 1})
    assert executed["status"] == PASS
    assert len(calls) == 1
    assert calls[0]["kind"] == "SCHEMA_BOUND_READ"

    # Positive function binding preserves exact argument order/signature.
    prepared = resolver.prepare_function_call(
        function_identity="private.fn_demo",
        arguments={"p_limit": 2, "p_code": "ABC"},
        schema_receipt=fr,
    )
    assert prepared["status"] == PASS, prepared
    assert [a["name"] for a in prepared["plan"]["arguments"]] == ["p_code", "p_limit"]

    print(
        json.dumps(
            {
                "result": "PASS",
                "interface": "PREEXECUTION_DATA_ACCESS_RESULT",
                "registered_source_count": len(registry["sources"]),
                "required_positive_readers": positive_codes,
                "negative_backend_escape_count": 0,
                "negative_cases": 7,
                "generic_unknown_source_resolver": "PASS",
                "function_signature_binding": "PASS",
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
