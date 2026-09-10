from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Optional, Sequence

PASS, BLOCKED = "PASS", "BLOCKED"
INTERFACE = "PREEXECUTION_DATA_ACCESS_RESULT"
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _result(status: str, code: str, detail: str = "", refs: Sequence[str] = (), plan: Optional[dict] = None, **extra: Any) -> dict:
    out = {"interface": INTERFACE, "status": status, "code": code, "detail": detail, "evidence_refs": list(refs)}
    if plan is not None:
        out["plan"] = plan
    out.update(extra)
    return out


def _block(code: str, detail: str, *refs: str, **extra: Any) -> dict:
    return _result(BLOCKED, code, detail, refs, **extra)


def _pass(code: str, plan: dict, *refs: str, **extra: Any) -> dict:
    return _result(PASS, code, refs=refs, plan=plan, **extra)


def load_registry(path: str | Path) -> dict:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {"contract_version", "base_main_sha", "canonical_fingerprint_provider", "fallback_fingerprint_method",
                "free_sql_policy", "stale_policy", "unknown_source_policy", "schema_resolution_call_policy", "sources"}
    missing = sorted(required - set(payload))
    if missing:
        raise ValueError(f"registry missing keys: {missing}")
    if not isinstance(payload["sources"], dict) or not payload["sources"]:
        raise ValueError("registry sources must be non-empty")
    binding_required = {"object_identity", "object_type", "reader", "fields", "key_fields", "allowed_filters",
                        "schema_fingerprint", "fingerprint_provider"}
    for key, b in payload["sources"].items():
        if not isinstance(b, Mapping):
            raise ValueError(f"{key} binding must be an object")
        missing = sorted(binding_required - set(b))
        if missing:
            raise ValueError(f"{key} binding missing keys: {missing}")
        if b["object_type"] not in {"TABLE", "VIEW"}:
            raise ValueError(f"{key} invalid object_type")
        if not isinstance(b["fields"], list) or not b["fields"] or len(b["fields"]) != len(set(b["fields"])):
            raise ValueError(f"{key} fields invalid")
        field_set = set(b["fields"])
        if not set(b["key_fields"]).issubset(field_set) or not set(b["allowed_filters"]).issubset(field_set):
            raise ValueError(f"{key} keys/filters must be registered fields")
        if not isinstance(b["schema_fingerprint"], str) or not _SHA256.fullmatch(b["schema_fingerprint"]):
            raise ValueError(f"{key} fingerprint invalid")
    return payload


def exact_column_names(receipt: Mapping[str, Any]) -> tuple[str, ...]:
    cols = receipt.get("exact_columns")
    if not isinstance(cols, list):
        return ()
    names = []
    for col in cols:
        name = col if isinstance(col, str) else col.get("name") if isinstance(col, Mapping) else None
        if isinstance(name, str) and name:
            names.append(name)
    return tuple(names)


def _schema(identity: str) -> str:
    return identity.split(".", 1)[0] if "." in identity else ""


class SchemaContractResolver:
    _TABLE_REQUIRED = {"object_identity", "schema", "object_type", "exact_columns", "data_types", "nullability",
                       "defaults", "is_identity", "identity_generation", "constraints", "indexes", "key_fields",
                       "allowed_filters", "schema_fingerprint", "freshness"}
    _FUNCTION_REQUIRED = {"object_identity", "schema", "object_type", "function_identity", "exact_signature",
                          "arguments", "return_contract", "relevant_permissions", "schema_fingerprint", "freshness"}

    def schema_resolution_request(self, *, object_identity: str, expected_object_type: Optional[str] = None) -> dict:
        return {
            "kind": "SCHEMA_CONTRACT_RESOLUTION",
            "call_policy": "SEPARATE_INFORMATION_SCHEMA_CALL_BEFORE_DEPENDENT_BACKEND",
            "object_identity": object_identity,
            "expected_object_type": expected_object_type,
            "required_table_metadata": ["exact_columns", "data_types", "nullability", "defaults", "is_identity",
                                        "identity_generation", "constraints", "indexes", "key_fields", "allowed_filters",
                                        "schema_fingerprint", "freshness"],
            "required_function_metadata": ["exact_signature", "arguments(name,order,type,has_default)", "return_contract",
                                           "relevant_permissions", "schema_fingerprint", "freshness"],
        }

    def validate_receipt(self, receipt: Optional[Mapping[str, Any]]) -> dict:
        if receipt is None:
            return _block("BLOCK_SCHEMA_RECEIPT_REQUIRED", "dependent access requires prior schema receipt")
        if not isinstance(receipt, Mapping):
            return _block("BLOCK_SCHEMA_RECEIPT_INVALID", "receipt must be a mapping")
        kind = receipt.get("object_type")
        if kind not in {"TABLE", "VIEW", "FUNCTION"}:
            return _block("BLOCK_SCHEMA_OBJECT_TYPE_UNSUPPORTED", f"unsupported object_type={kind}")
        required = self._FUNCTION_REQUIRED if kind == "FUNCTION" else self._TABLE_REQUIRED
        missing = sorted(required - set(receipt))
        if missing:
            return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"missing receipt fields: {missing}")
        identity, schema = receipt.get("object_identity"), receipt.get("schema")
        if not isinstance(identity, str) or not identity or not isinstance(schema, str) or not schema:
            return _block("BLOCK_SCHEMA_RECEIPT_IDENTITY_INVALID", "object_identity/schema must be non-empty")
        if _schema(identity) != schema:
            return _block("BLOCK_SCHEMA_RECEIPT_SCHEMA_MISMATCH", f"schema={schema} identity={identity}")
        fp = receipt.get("schema_fingerprint")
        if not isinstance(fp, str) or not _SHA256.fullmatch(fp):
            return _block("BLOCK_SCHEMA_FINGERPRINT_INVALID", "schema_fingerprint must be lowercase sha256")
        freshness = receipt.get("freshness")
        if not isinstance(freshness, Mapping):
            return _block("BLOCK_SCHEMA_FRESHNESS_INVALID", "freshness must be a mapping")
        if freshness.get("state") != "CURRENT":
            return _block("BLOCK_SCHEMA_RECEIPT_STALE", f"freshness={freshness.get('state')}", f"schema://{identity}#{fp}")
        if not isinstance(freshness.get("source"), str) or not freshness.get("source"):
            return _block("BLOCK_SCHEMA_FRESHNESS_SOURCE_MISSING", "freshness.source required")
        if not isinstance(freshness.get("observed_at"), str) or not freshness.get("observed_at"):
            return _block("BLOCK_SCHEMA_FRESHNESS_OBSERVED_AT_MISSING", "freshness.observed_at required")

        if kind in {"TABLE", "VIEW"}:
            names = exact_column_names(receipt)
            if not names:
                return _block("BLOCK_SCHEMA_RECEIPT_NO_COLUMNS", "exact_columns empty")
            if len(names) != len(set(names)):
                return _block("BLOCK_SCHEMA_RECEIPT_DUPLICATE_COLUMN", "duplicate exact columns")
            name_set = set(names)
            for field in ("data_types", "nullability", "defaults", "is_identity", "identity_generation"):
                mapping = receipt.get(field)
                if not isinstance(mapping, Mapping):
                    return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"{field} must be mapping")
                gaps = sorted(name_set - set(mapping))
                if gaps:
                    return _block("BLOCK_SCHEMA_RECEIPT_COLUMN_METADATA_GAP", f"{field} missing {gaps}")
            for name in names:
                if not isinstance(receipt["data_types"][name], str) or not receipt["data_types"][name]:
                    return _block("BLOCK_SCHEMA_DATA_TYPE_UNRESOLVED", f"data_types[{name}] unresolved")
                if receipt["nullability"][name] not in {True, False, "YES", "NO"}:
                    return _block("BLOCK_SCHEMA_NULLABILITY_INVALID", f"nullability[{name}] invalid")
                identity_flag = receipt["is_identity"][name]
                is_id = identity_flag is True or (isinstance(identity_flag, str) and identity_flag.upper() == "YES")
                not_id = identity_flag is False or (isinstance(identity_flag, str) and identity_flag.upper() == "NO")
                if not (is_id or not_id):
                    return _block("BLOCK_IDENTITY_FLAG_INVALID", f"is_identity[{name}] invalid")
                generation = receipt["identity_generation"][name]
                if is_id and generation not in {"ALWAYS", "BY DEFAULT"}:
                    return _block("BLOCK_IDENTITY_GENERATION_UNRESOLVED", f"identity_generation[{name}] unresolved")
                if not_id and generation not in {None, ""}:
                    return _block("BLOCK_IDENTITY_GENERATION_INCONSISTENT", f"identity_generation[{name}] inconsistent")
            for field in ("constraints", "indexes", "key_fields", "allowed_filters"):
                if not isinstance(receipt.get(field), list):
                    return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"{field} must be list")
            if not set(receipt["key_fields"]).issubset(name_set):
                return _block("BLOCK_SCHEMA_KEY_FIELD_UNKNOWN", "key field absent from exact_columns")
            if not set(receipt["allowed_filters"]).issubset(name_set):
                return _block("BLOCK_SCHEMA_FILTER_FIELD_UNKNOWN", "allowed filter absent from exact_columns")
        else:
            fn = receipt.get("function_identity")
            if fn != identity:
                return _block("BLOCK_FUNCTION_IDENTITY_INCONSISTENT", "function_identity != object_identity")
            signature = receipt.get("exact_signature")
            if not isinstance(signature, str) or not signature.startswith(f"{fn}(") or not signature.endswith(")"):
                return _block("BLOCK_FUNCTION_SIGNATURE_INVALID", "exact_signature must be identity-qualified")
            if not isinstance(receipt.get("return_contract"), str) or not receipt["return_contract"]:
                return _block("BLOCK_FUNCTION_RETURN_CONTRACT_INVALID", "return_contract required")
            if not isinstance(receipt.get("relevant_permissions"), list):
                return _block("BLOCK_FUNCTION_PERMISSIONS_INVALID", "relevant_permissions must be list")
            args = receipt.get("arguments")
            if not isinstance(args, list):
                return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "arguments must be ordered list")
            names, orders = [], []
            for arg in args:
                if not isinstance(arg, Mapping) or not {"order", "name", "type", "has_default"}.issubset(arg):
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "argument metadata incomplete")
                if not isinstance(arg["name"], str) or not arg["name"] or not isinstance(arg["type"], str) or not arg["type"]:
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "argument name/type unresolved")
                if not isinstance(arg["order"], int) or not isinstance(arg["has_default"], bool):
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "argument order/default invalid")
                names.append(arg["name"]); orders.append(arg["order"])
            if orders != list(range(1, len(args) + 1)):
                return _block("BLOCK_FUNCTION_ARGUMENT_ORDER_INVALID", "argument order must start at 1 and be contiguous")
            if len(names) != len(set(names)):
                return _block("BLOCK_FUNCTION_ARGUMENT_DUPLICATE", "argument names duplicate")
            body, cursor = signature[len(fn) + 1:-1].casefold(), 0
            for arg in args:
                for token in (arg["name"], arg["type"]):
                    pos = body.find(str(token).casefold(), cursor)
                    if pos < 0:
                        return _block("BLOCK_FUNCTION_SIGNATURE_ARGUMENT_MISMATCH", f"signature missing ordered token {token}")
                    cursor = pos + len(str(token))
        return _pass("SCHEMA_RECEIPT_VALID", {"kind": "SCHEMA_RECEIPT"}, f"schema://{identity}#{fp}")

    def resolve_receipt(self, *, object_identity: str, expected_object_type: Optional[str], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]]) -> dict:
        receipt = schema_backend(self.schema_resolution_request(object_identity=object_identity, expected_object_type=expected_object_type))
        checked = self.validate_receipt(receipt)
        if checked["status"] != PASS:
            return checked
        if receipt["object_identity"] != object_identity:
            return _block("BLOCK_SCHEMA_RECEIPT_IDENTITY_MISMATCH", f"receipt={receipt['object_identity']} requested={object_identity}")
        if expected_object_type is not None and receipt["object_type"] != expected_object_type:
            return _block("BLOCK_SCHEMA_RECEIPT_OBJECT_TYPE_MISMATCH", f"receipt={receipt['object_type']} expected={expected_object_type}")
        return _pass("SCHEMA_RESOLUTION_COMPLETE", {"kind": "SCHEMA_RESOLUTION_COMPLETE", "receipt": dict(receipt)}, *checked["evidence_refs"], schema_backend_executed=True)

    def prepare_unknown_read(self, *, object_identity: str, fields: Sequence[str], filters: Optional[Mapping[str, Any]], schema_receipt: Optional[Mapping[str, Any]]) -> dict:
        checked = self.validate_receipt(schema_receipt)
        if checked["status"] != PASS:
            return checked
        assert schema_receipt is not None
        if schema_receipt["object_type"] not in {"TABLE", "VIEW"}:
            return _block("BLOCK_OBJECT_KIND_MISMATCH", "read requires TABLE/VIEW")
        if schema_receipt["object_identity"] != object_identity:
            return _block("BLOCK_SCHEMA_RECEIPT_IDENTITY_MISMATCH", "receipt identity mismatch")
        if not fields:
            return _block("BLOCK_EMPTY_FIELD_SET", "at least one exact field required")
        live = set(exact_column_names(schema_receipt))
        bad = sorted(set(fields) - live)
        if bad:
            return _block("BLOCK_FIELD_NOT_IN_SCHEMA_RECEIPT", f"unresolved fields: {bad}")
        filters = dict(filters or {})
        bad_filters = sorted(set(filters) - set(schema_receipt["allowed_filters"]))
        if bad_filters:
            return _block("BLOCK_FILTER_NOT_ALLOWED_BY_SCHEMA_RECEIPT", f"unresolved filters: {bad_filters}")
        plan = {"kind": "SCHEMA_BOUND_READ", "object_identity": object_identity, "fields": list(fields), "filters": filters,
                "schema_fingerprint": schema_receipt["schema_fingerprint"]}
        return _pass("UNKNOWN_SOURCE_BOUND_TO_SCHEMA_RECEIPT", plan, f"schema://{object_identity}#{schema_receipt['schema_fingerprint']}")

    def resolve_bind_execute_unknown_read(self, *, object_identity: str, fields: Sequence[str], filters: Optional[Mapping[str, Any]], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]], dependent_backend: Callable[[Mapping[str, Any]], Any], expected_object_type: Optional[str] = None) -> dict:
        resolved = self.resolve_receipt(object_identity=object_identity, expected_object_type=expected_object_type, schema_backend=schema_backend)
        if resolved["status"] != PASS:
            return {**resolved, "backend_executed": False}
        prepared = self.prepare_unknown_read(object_identity=object_identity, fields=fields, filters=filters, schema_receipt=resolved["plan"]["receipt"])
        return execute_prepared(prepared, dependent_backend)

    def prepare_function_call(self, *, function_identity: str, arguments: Mapping[str, Any], schema_receipt: Optional[Mapping[str, Any]]) -> dict:
        checked = self.validate_receipt(schema_receipt)
        if checked["status"] != PASS:
            return checked
        assert schema_receipt is not None
        if schema_receipt["object_type"] != "FUNCTION":
            return _block("BLOCK_OBJECT_KIND_MISMATCH", "function call requires FUNCTION")
        if schema_receipt["function_identity"] != function_identity or schema_receipt["object_identity"] != function_identity:
            return _block("BLOCK_FUNCTION_SCHEMA_OR_IDENTITY_MISMATCH", "function identity mismatch")
        contract = schema_receipt["arguments"]
        names = [a["name"] for a in contract]
        unknown = sorted(set(arguments) - set(names))
        if unknown:
            return _block("BLOCK_FUNCTION_ARGUMENT_NOT_IN_RECEIPT", f"unknown arguments: {unknown}")
        missing = [a["name"] for a in contract if not a["has_default"] and a["name"] not in arguments]
        if missing:
            return _block("BLOCK_FUNCTION_REQUIRED_ARGUMENT_MISSING", f"missing arguments: {missing}")
        ordered = [{"name": a["name"], "declared_type": a["type"], "value": arguments[a["name"]]} for a in contract if a["name"] in arguments]
        plan = {"kind": "SCHEMA_BOUND_FUNCTION_CALL", "function_identity": function_identity, "arguments": ordered, "exact_signature": schema_receipt["exact_signature"], "return_contract": schema_receipt["return_contract"], "schema_fingerprint": schema_receipt["schema_fingerprint"]}
        return _pass("FUNCTION_BOUND_TO_SCHEMA_RECEIPT", plan, f"schema://{function_identity}#{schema_receipt['schema_fingerprint']}")

    def resolve_bind_execute_function_call(self, *, function_identity: str, arguments: Mapping[str, Any], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]], dependent_backend: Callable[[Mapping[str, Any]], Any]) -> dict:
        resolved = self.resolve_receipt(object_identity=function_identity, expected_object_type="FUNCTION", schema_backend=schema_backend)
        if resolved["status"] != PASS:
            return {**resolved, "backend_executed": False}
        return execute_prepared(self.prepare_function_call(function_identity=function_identity, arguments=arguments, schema_receipt=resolved["plan"]["receipt"]), dependent_backend)


@dataclass(frozen=True)
class TypedReader:
    registry: Mapping[str, Any]
    resolver: SchemaContractResolver

    def prepare(self, *, source_key: str, fields: Optional[Sequence[str]] = None, filters: Optional[Mapping[str, Any]] = None, schema_receipt: Optional[Mapping[str, Any]] = None, requested_object: Optional[str] = None, free_sql: Optional[str] = None) -> dict:
        b = self.registry["sources"].get(source_key)
        if b is None:
            return _block("BLOCK_SOURCE_NOT_REGISTERED_USE_SCHEMA_RESOLVER", f"{source_key} not registered")
        bref = f"registry://{self.registry['contract_version']}/{source_key}"
        if free_sql is not None:
            return _block("BLOCK_REGISTERED_SOURCE_FREE_SQL", "free SQL forbidden", bref)
        if requested_object is not None and requested_object != b["object_identity"]:
            return _block("BLOCK_REGISTERED_SOURCE_OBJECT_MISMATCH", "requested object != binding", bref)
        checked = self.resolver.validate_receipt(schema_receipt)
        if checked["status"] != PASS:
            return _block(checked["code"], checked.get("detail", ""), bref, *checked.get("evidence_refs", []))
        assert schema_receipt is not None
        rref = f"schema://{schema_receipt['object_identity']}#{schema_receipt['schema_fingerprint']}"
        if schema_receipt["object_identity"] != b["object_identity"] or schema_receipt["object_type"] != b["object_type"]:
            return _block("BLOCK_REGISTERED_SOURCE_RECEIPT_MISMATCH", "receipt identity/type mismatch", bref, rref)
        if schema_receipt["schema_fingerprint"] != b["schema_fingerprint"]:
            return _block("BLOCK_SCHEMA_FINGERPRINT_STALE", "registered fingerprint stale", bref, rref)
        if schema_receipt.get("fingerprint_provider") != b["fingerprint_provider"]:
            return _block("BLOCK_SCHEMA_FINGERPRINT_PROVIDER_MISMATCH", "fingerprint provider mismatch", bref, rref)
        requested = list(fields or b["fields"])
        live = set(exact_column_names(schema_receipt))
        bad = sorted(set(requested) - set(b["fields"]))
        if bad:
            return _block("BLOCK_FIELD_NOT_IN_BINDING", f"fields not registered: {bad}", bref, rref)
        live_bad = sorted(set(requested) - live)
        if live_bad:
            return _block("BLOCK_FIELD_NOT_IN_SCHEMA_RECEIPT", f"fields not live: {live_bad}", bref, rref)
        filters = dict(filters or {})
        bad_filters = sorted(set(filters) - set(b["allowed_filters"]))
        if bad_filters:
            return _block("BLOCK_FILTER_NOT_IN_BINDING", f"filters not registered: {bad_filters}", bref, rref)
        if set(filters) - live:
            return _block("BLOCK_FILTER_NOT_IN_SCHEMA_RECEIPT", "filter absent from live schema", bref, rref)
        plan = {"kind": "TYPED_READ", "source_key": source_key, "reader": b["reader"], "object_identity": b["object_identity"], "fields": requested, "filters": filters, "key_fields": b["key_fields"], "schema_fingerprint": b["schema_fingerprint"], "fingerprint_provider": b["fingerprint_provider"]}
        return _pass("REGISTERED_TYPED_READER_READY", plan, bref, rref)


def execute_prepared(preexecution_result: Mapping[str, Any], backend: Callable[[Mapping[str, Any]], Any]) -> dict:
    if preexecution_result.get("interface") != INTERFACE:
        return _block("BLOCK_INVALID_PREEXECUTION_INTERFACE", "invalid preexecution interface", backend_executed=False)
    if preexecution_result.get("status") != PASS:
        return {**preexecution_result, "backend_executed": False}
    plan = preexecution_result.get("plan")
    if not isinstance(plan, Mapping):
        return _block("BLOCK_PASS_WITHOUT_BOUND_PLAN", "PASS requires bound plan", backend_executed=False)
    out = dict(preexecution_result)
    out.update(backend_executed=True, readback=backend(plan))
    return out


@dataclass(frozen=True)
class LFDataAccess:
    typed: TypedReader

    @classmethod
    def from_registry(cls, registry: Mapping[str, Any]) -> "LFDataAccess":
        return cls(TypedReader(registry, SchemaContractResolver()))

    def _read(self, key: str, **kwargs: Any) -> dict:
        return self.typed.prepare(source_key=key, **kwargs)

    def resolve_bind_execute_registered_read(self, *, source_key: str, fields: Optional[Sequence[str]], filters: Optional[Mapping[str, Any]], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]], dependent_backend: Callable[[Mapping[str, Any]], Any]) -> dict:
        b = self.typed.registry["sources"].get(source_key)
        if b is None:
            return _block("BLOCK_SOURCE_NOT_REGISTERED_USE_SCHEMA_RESOLVER", f"{source_key} not registered", backend_executed=False)
        resolved = self.typed.resolver.resolve_receipt(object_identity=b["object_identity"], expected_object_type=b["object_type"], schema_backend=schema_backend)
        if resolved["status"] != PASS:
            return {**resolved, "backend_executed": False}
        return execute_prepared(self.typed.prepare(source_key=source_key, fields=fields, filters=filters, schema_receipt=resolved["plan"]["receipt"]), dependent_backend)

    def read_router_source(self, **kwargs: Any) -> dict: return self._read("ROUTER_SOURCE", **kwargs)
    def read_ekb(self, **kwargs: Any) -> dict: return self._read("EKB", **kwargs)
    def read_operation_registry(self, **kwargs: Any) -> dict: return self._read("OPERATION_REGISTRY", **kwargs)
    def read_operation_contracts(self, **kwargs: Any) -> dict: return self._read("OPERATION_CONTRACTS", **kwargs)
    def read_operation_steps(self, **kwargs: Any) -> dict: return self._read("OPERATION_STEPS", **kwargs)
    def read_operation_step_contracts(self, **kwargs: Any) -> dict: return self._read("OPERATION_STEP_CONTRACTS", **kwargs)
    def read_operation_judges(self, **kwargs: Any) -> dict: return self._read("OPERATION_JUDGES", **kwargs)
    def read_operation_step_judge_bindings(self, **kwargs: Any) -> dict: return self._read("OPERATION_STEP_JUDGE_BINDINGS", **kwargs)
    def read_operation_policy_bindings(self, **kwargs: Any) -> dict: return self._read("OPERATION_POLICY_BINDINGS", **kwargs)
    def read_strategy_snapshots(self, **kwargs: Any) -> dict: return self._read("STRATEGY_SNAPSHOTS", **kwargs)
    def read_assets_profiles(self, **kwargs: Any) -> dict: return self._read("ASSETS_PROFILES", **kwargs)
    def read_events(self, **kwargs: Any) -> dict: return self._read("EVENTS", **kwargs)
    def read_input_governance(self, **kwargs: Any) -> dict: return self._read("INPUT_GOVERNANCE", **kwargs)
    def read_adapter_bindings(self, **kwargs: Any) -> dict: return self._read("ADAPTER_BINDINGS", **kwargs)
    def read_migration_ledger(self, **kwargs: Any) -> dict: return self._read("MIGRATION_LEDGER", **kwargs)
