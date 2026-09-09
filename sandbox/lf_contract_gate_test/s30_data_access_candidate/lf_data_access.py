from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Optional, Sequence

PASS = "PASS"
BLOCKED = "BLOCKED"
INTERFACE = "PREEXECUTION_DATA_ACCESS_RESULT"
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _result(status: str, *, code: str, evidence_refs: Sequence[str], detail: str = "", plan: Optional[dict] = None) -> dict:
    out = {
        "interface": INTERFACE,
        "status": status,
        "code": code,
        "evidence_refs": list(evidence_refs),
        "detail": detail,
    }
    if plan is not None:
        out["plan"] = plan
    return out


def _block(code: str, detail: str, *refs: str) -> dict:
    return _result(BLOCKED, code=code, detail=detail, evidence_refs=refs)


def _pass(code: str, plan: dict, *refs: str) -> dict:
    return _result(PASS, code=code, evidence_refs=refs, plan=plan)


def load_registry(path: str | Path) -> dict:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {
        "contract_version",
        "base_main_sha",
        "fingerprint_method",
        "free_sql_policy",
        "stale_policy",
        "unknown_source_policy",
        "sources",
    }
    missing = sorted(required - set(payload))
    if missing:
        raise ValueError(f"registry missing keys: {missing}")
    if not isinstance(payload["sources"], dict) or not payload["sources"]:
        raise ValueError("registry sources must be a non-empty object")
    return payload


def exact_column_names(receipt: Mapping[str, Any]) -> tuple[str, ...]:
    cols = receipt.get("exact_columns")
    if not isinstance(cols, list):
        return ()
    names = []
    for col in cols:
        if isinstance(col, str):
            names.append(col)
        elif isinstance(col, Mapping) and isinstance(col.get("name"), str):
            names.append(col["name"])
    return tuple(names)


class SchemaContractResolver:
    """Validate a separately obtained schema receipt before dependent backend access."""

    _TABLE_REQUIRED = {
        "object_identity",
        "schema",
        "object_type",
        "exact_columns",
        "data_types",
        "nullability",
        "defaults",
        "identity_generation",
        "constraints",
        "indexes",
        "key_fields",
        "allowed_filters",
        "schema_fingerprint",
        "freshness",
    }
    _FUNCTION_REQUIRED = {
        "object_identity",
        "schema",
        "object_type",
        "function_identity",
        "exact_signature",
        "arguments",
        "return_contract",
        "relevant_permissions",
        "schema_fingerprint",
        "freshness",
    }

    def validate_receipt(self, receipt: Optional[Mapping[str, Any]]) -> dict:
        if receipt is None:
            return _block("BLOCK_SCHEMA_RECEIPT_REQUIRED", "dependent access requires a prior schema receipt")
        object_type = receipt.get("object_type")
        required = self._FUNCTION_REQUIRED if object_type == "FUNCTION" else self._TABLE_REQUIRED
        missing = sorted(k for k in required if k not in receipt)
        if missing:
            return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"missing receipt fields: {missing}")
        fp = receipt.get("schema_fingerprint")
        if not isinstance(fp, str) or not _SHA256_RE.fullmatch(fp):
            return _block("BLOCK_SCHEMA_FINGERPRINT_INVALID", "schema_fingerprint must be lowercase sha256")
        if object_type in {"TABLE", "VIEW"}:
            names = exact_column_names(receipt)
            if not names:
                return _block("BLOCK_SCHEMA_RECEIPT_NO_COLUMNS", "table/view receipt has no exact columns")
            if len(names) != len(set(names)):
                return _block("BLOCK_SCHEMA_RECEIPT_DUPLICATE_COLUMN", "duplicate exact column names")
            for field_name in ("data_types", "nullability", "defaults", "identity_generation"):
                mapping = receipt.get(field_name)
                if not isinstance(mapping, Mapping):
                    return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"{field_name} must be a mapping")
                missing_names = sorted(set(names) - set(mapping))
                if missing_names:
                    return _block("BLOCK_SCHEMA_RECEIPT_COLUMN_METADATA_GAP", f"{field_name} missing {missing_names}")
        else:
            if object_type != "FUNCTION":
                return _block("BLOCK_SCHEMA_OBJECT_TYPE_UNSUPPORTED", f"unsupported object_type={object_type}")
            args = receipt.get("arguments")
            if not isinstance(args, list):
                return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "arguments must be an ordered list")
            observed_orders = [a.get("order") for a in args if isinstance(a, Mapping)]
            if observed_orders != list(range(1, len(args) + 1)):
                return _block("BLOCK_FUNCTION_ARGUMENT_ORDER_INVALID", "function arguments must be explicitly ordered from 1")
        ref = f"schema://{receipt['object_identity']}#{receipt['schema_fingerprint']}"
        return _pass("SCHEMA_RECEIPT_VALID", {"kind": "SCHEMA_RECEIPT"}, ref)

    def prepare_unknown_read(
        self,
        *,
        object_identity: str,
        fields: Sequence[str],
        filters: Optional[Mapping[str, Any]],
        schema_receipt: Optional[Mapping[str, Any]],
    ) -> dict:
        vr = self.validate_receipt(schema_receipt)
        if vr["status"] != PASS:
            return vr
        assert schema_receipt is not None
        if schema_receipt["object_type"] not in {"TABLE", "VIEW"}:
            return _block("BLOCK_OBJECT_KIND_MISMATCH", "read requires TABLE or VIEW receipt")
        if schema_receipt["object_identity"] != object_identity:
            return _block(
                "BLOCK_SCHEMA_RECEIPT_IDENTITY_MISMATCH",
                f"receipt is for {schema_receipt['object_identity']}, requested {object_identity}",
            )
        columns = set(exact_column_names(schema_receipt))
        bad_fields = sorted(set(fields) - columns)
        if bad_fields:
            return _block("BLOCK_FIELD_NOT_IN_SCHEMA_RECEIPT", f"unresolved fields: {bad_fields}")
        filters = dict(filters or {})
        allowed_filters = set(schema_receipt.get("allowed_filters") or [])
        bad_filters = sorted(set(filters) - allowed_filters)
        if bad_filters:
            return _block("BLOCK_FILTER_NOT_ALLOWED_BY_SCHEMA_RECEIPT", f"unresolved filters: {bad_filters}")
        plan = {
            "kind": "SCHEMA_BOUND_READ",
            "object_identity": object_identity,
            "fields": list(fields),
            "filters": filters,
            "schema_fingerprint": schema_receipt["schema_fingerprint"],
        }
        ref = f"schema://{object_identity}#{schema_receipt['schema_fingerprint']}"
        return _pass("UNKNOWN_SOURCE_BOUND_TO_SCHEMA_RECEIPT", plan, ref)

    def prepare_function_call(
        self,
        *,
        function_identity: str,
        arguments: Mapping[str, Any],
        schema_receipt: Optional[Mapping[str, Any]],
    ) -> dict:
        vr = self.validate_receipt(schema_receipt)
        if vr["status"] != PASS:
            return vr
        assert schema_receipt is not None
        if schema_receipt["object_type"] != "FUNCTION":
            return _block("BLOCK_OBJECT_KIND_MISMATCH", "function call requires FUNCTION receipt")
        if schema_receipt["function_identity"] != function_identity or schema_receipt["object_identity"] != function_identity:
            return _block(
                "BLOCK_FUNCTION_SCHEMA_OR_IDENTITY_MISMATCH",
                f"receipt identity={schema_receipt['function_identity']} requested={function_identity}",
            )
        arg_contract = schema_receipt["arguments"]
        contract_names = [a["name"] for a in arg_contract]
        unknown = sorted(set(arguments) - set(contract_names))
        if unknown:
            return _block("BLOCK_FUNCTION_ARGUMENT_NOT_IN_RECEIPT", f"unknown arguments: {unknown}")
        required = [a["name"] for a in arg_contract if not a.get("has_default", False)]
        missing = [name for name in required if name not in arguments]
        if missing:
            return _block("BLOCK_FUNCTION_REQUIRED_ARGUMENT_MISSING", f"missing arguments: {missing}")
        ordered_args = [{"name": name, "value": arguments[name]} for name in contract_names if name in arguments]
        plan = {
            "kind": "SCHEMA_BOUND_FUNCTION_CALL",
            "function_identity": function_identity,
            "arguments": ordered_args,
            "exact_signature": schema_receipt["exact_signature"],
            "return_contract": schema_receipt["return_contract"],
            "schema_fingerprint": schema_receipt["schema_fingerprint"],
        }
        ref = f"schema://{function_identity}#{schema_receipt['schema_fingerprint']}"
        return _pass("FUNCTION_BOUND_TO_SCHEMA_RECEIPT", plan, ref)


@dataclass(frozen=True)
class TypedReader:
    registry: Mapping[str, Any]
    resolver: SchemaContractResolver

    def prepare(
        self,
        *,
        source_key: str,
        fields: Optional[Sequence[str]] = None,
        filters: Optional[Mapping[str, Any]] = None,
        schema_receipt: Optional[Mapping[str, Any]] = None,
        requested_object: Optional[str] = None,
        free_sql: Optional[str] = None,
    ) -> dict:
        sources = self.registry["sources"]
        binding = sources.get(source_key)
        if binding is None:
            return _block(
                "BLOCK_SOURCE_NOT_REGISTERED_USE_SCHEMA_RESOLVER",
                f"{source_key} has no canonical reader; resolve schema first",
            )
        binding_ref = f"registry://{self.registry['contract_version']}/{source_key}"
        if free_sql is not None:
            return _block(
                "BLOCK_REGISTERED_SOURCE_FREE_SQL",
                f"free SQL is forbidden for registered source_key={source_key}",
                binding_ref,
            )
        if requested_object is not None and requested_object != binding["object_identity"]:
            return _block(
                "BLOCK_REGISTERED_SOURCE_OBJECT_MISMATCH",
                f"binding object={binding['object_identity']} requested={requested_object}",
                binding_ref,
            )
        vr = self.resolver.validate_receipt(schema_receipt)
        if vr["status"] != PASS:
            return _block(vr["code"], vr.get("detail", ""), binding_ref, *vr.get("evidence_refs", []))
        assert schema_receipt is not None
        receipt_ref = f"schema://{schema_receipt['object_identity']}#{schema_receipt['schema_fingerprint']}"
        if schema_receipt["object_identity"] != binding["object_identity"] or schema_receipt["object_type"] != binding["object_type"]:
            return _block(
                "BLOCK_REGISTERED_SOURCE_RECEIPT_MISMATCH",
                "schema receipt does not match registered object identity/type",
                binding_ref,
                receipt_ref,
            )
        if schema_receipt["schema_fingerprint"] != binding["schema_fingerprint"]:
            return _block(
                "BLOCK_SCHEMA_FINGERPRINT_STALE",
                f"binding={binding['schema_fingerprint']} live={schema_receipt['schema_fingerprint']}",
                binding_ref,
                receipt_ref,
            )
        requested_fields = list(fields or binding["fields"])
        allowed_fields = set(binding["fields"])
        live_fields = set(exact_column_names(schema_receipt))
        bad = sorted(set(requested_fields) - allowed_fields)
        if bad:
            return _block("BLOCK_FIELD_NOT_IN_BINDING", f"fields not registered: {bad}", binding_ref, receipt_ref)
        live_bad = sorted(set(requested_fields) - live_fields)
        if live_bad:
            return _block("BLOCK_FIELD_NOT_IN_SCHEMA_RECEIPT", f"fields not in current schema: {live_bad}", binding_ref, receipt_ref)
        filters = dict(filters or {})
        bad_filters = sorted(set(filters) - set(binding["allowed_filters"]))
        if bad_filters:
            return _block("BLOCK_FILTER_NOT_IN_BINDING", f"filters not registered: {bad_filters}", binding_ref, receipt_ref)
        live_filter_bad = sorted(set(filters) - live_fields)
        if live_filter_bad:
            return _block("BLOCK_FILTER_NOT_IN_SCHEMA_RECEIPT", f"filters not in current schema: {live_filter_bad}", binding_ref, receipt_ref)
        plan = {
            "kind": "TYPED_READ",
            "source_key": source_key,
            "reader": binding["reader"],
            "object_identity": binding["object_identity"],
            "fields": requested_fields,
            "filters": filters,
            "key_fields": binding["key_fields"],
            "schema_fingerprint": binding["schema_fingerprint"],
        }
        return _pass("REGISTERED_TYPED_READER_READY", plan, binding_ref, receipt_ref)


def execute_prepared(preexecution_result: Mapping[str, Any], backend: Callable[[Mapping[str, Any]], Any]) -> dict:
    if preexecution_result.get("interface") != INTERFACE:
        return _block("BLOCK_INVALID_PREEXECUTION_INTERFACE", "expected PREEXECUTION_DATA_ACCESS_RESULT")
    if preexecution_result.get("status") != PASS:
        return dict(preexecution_result)
    value = backend(preexecution_result["plan"])
    out = dict(preexecution_result)
    out["backend_executed"] = True
    out["readback"] = value
    return out


@dataclass(frozen=True)
class LFDataAccess:
    """Explicit typed-reader surface for registered LF sources."""

    typed: TypedReader

    @classmethod
    def from_registry(cls, registry: Mapping[str, Any]) -> "LFDataAccess":
        return cls(typed=TypedReader(registry=registry, resolver=SchemaContractResolver()))

    def _read(self, source_key: str, *, fields=None, filters=None, schema_receipt=None, requested_object=None, free_sql=None) -> dict:
        return self.typed.prepare(
            source_key=source_key,
            fields=fields,
            filters=filters,
            schema_receipt=schema_receipt,
            requested_object=requested_object,
            free_sql=free_sql,
        )

    def read_router_source(self, **kwargs) -> dict:
        return self._read("ROUTER_SOURCE", **kwargs)

    def read_ekb(self, **kwargs) -> dict:
        return self._read("EKB", **kwargs)

    def read_operation_registry(self, **kwargs) -> dict:
        return self._read("OPERATION_REGISTRY", **kwargs)

    def read_operation_contracts(self, **kwargs) -> dict:
        return self._read("OPERATION_CONTRACTS", **kwargs)

    def read_operation_steps(self, **kwargs) -> dict:
        return self._read("OPERATION_STEPS", **kwargs)

    def read_operation_step_contracts(self, **kwargs) -> dict:
        return self._read("OPERATION_STEP_CONTRACTS", **kwargs)

    def read_operation_judges(self, **kwargs) -> dict:
        return self._read("OPERATION_JUDGES", **kwargs)

    def read_operation_step_judge_bindings(self, **kwargs) -> dict:
        return self._read("OPERATION_STEP_JUDGE_BINDINGS", **kwargs)

    def read_operation_policy_bindings(self, **kwargs) -> dict:
        return self._read("OPERATION_POLICY_BINDINGS", **kwargs)

    def read_strategy_snapshots(self, **kwargs) -> dict:
        return self._read("STRATEGY_SNAPSHOTS", **kwargs)

    def read_assets_profiles(self, **kwargs) -> dict:
        return self._read("ASSETS_PROFILES", **kwargs)

    def read_events(self, **kwargs) -> dict:
        return self._read("EVENTS", **kwargs)

    def read_input_governance(self, **kwargs) -> dict:
        return self._read("INPUT_GOVERNANCE", **kwargs)

    def read_adapter_bindings(self, **kwargs) -> dict:
        return self._read("ADAPTER_BINDINGS", **kwargs)

    def read_migration_ledger(self, **kwargs) -> dict:
        return self._read("MIGRATION_LEDGER", **kwargs)
