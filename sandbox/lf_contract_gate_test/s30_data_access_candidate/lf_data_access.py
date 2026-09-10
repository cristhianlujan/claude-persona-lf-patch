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


def _result(status: str, *, code: str, evidence_refs: Sequence[str] = (), detail: str = "", plan: Optional[dict] = None, **extra: Any) -> dict:
    out = {
        "interface": INTERFACE,
        "status": status,
        "code": code,
        "evidence_refs": list(evidence_refs),
        "detail": detail,
    }
    if plan is not None:
        out["plan"] = plan
    out.update(extra)
    return out


def _block(code: str, detail: str, *refs: str, **extra: Any) -> dict:
    return _result(BLOCKED, code=code, detail=detail, evidence_refs=refs, **extra)


def _pass(code: str, plan: dict, *refs: str, **extra: Any) -> dict:
    return _result(PASS, code=code, evidence_refs=refs, plan=plan, **extra)


def load_registry(path: str | Path) -> dict:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {
        "contract_version",
        "base_main_sha",
        "canonical_fingerprint_provider",
        "fallback_fingerprint_method",
        "free_sql_policy",
        "stale_policy",
        "unknown_source_policy",
        "schema_resolution_call_policy",
        "sources",
    }
    missing = sorted(required - set(payload))
    if missing:
        raise ValueError(f"registry missing keys: {missing}")
    if not isinstance(payload["sources"], dict) or not payload["sources"]:
        raise ValueError("registry sources must be a non-empty object")

    binding_required = {
        "object_identity",
        "object_type",
        "reader",
        "fields",
        "key_fields",
        "allowed_filters",
        "schema_fingerprint",
        "fingerprint_provider",
    }
    for source_key, binding in payload["sources"].items():
        if not isinstance(binding, Mapping):
            raise ValueError(f"{source_key} binding must be an object")
        b_missing = sorted(binding_required - set(binding))
        if b_missing:
            raise ValueError(f"{source_key} binding missing keys: {b_missing}")
        if binding["object_type"] not in {"TABLE", "VIEW"}:
            raise ValueError(f"{source_key} unsupported registered object_type")
        fields = binding["fields"]
        if not isinstance(fields, list) or not fields or len(fields) != len(set(fields)):
            raise ValueError(f"{source_key} fields must be a non-empty unique list")
        if not set(binding["key_fields"]).issubset(set(fields)):
            raise ValueError(f"{source_key} key_fields must be registered fields")
        if not set(binding["allowed_filters"]).issubset(set(fields)):
            raise ValueError(f"{source_key} allowed_filters must be registered fields")
        if not isinstance(binding["schema_fingerprint"], str) or not _SHA256_RE.fullmatch(binding["schema_fingerprint"]):
            raise ValueError(f"{source_key} schema_fingerprint must be lowercase sha256")
    return payload


def exact_column_names(receipt: Mapping[str, Any]) -> tuple[str, ...]:
    cols = receipt.get("exact_columns")
    if not isinstance(cols, list):
        return ()
    names: list[str] = []
    for col in cols:
        if isinstance(col, str):
            names.append(col)
        elif isinstance(col, Mapping) and isinstance(col.get("name"), str):
            names.append(col["name"])
    return tuple(names)


def _schema_prefix(object_identity: str) -> str:
    return object_identity.split(".", 1)[0] if "." in object_identity else ""


class SchemaContractResolver:
    """Fail-closed schema resolver/binder.

    A dependent read/call is not built until a separate schema backend has returned
    a current, complete receipt. The adapter is responsible for information_schema
    or catalog lookup; the contract layer makes ordering mechanically testable.
    """

    _TABLE_REQUIRED = {
        "object_identity",
        "schema",
        "object_type",
        "exact_columns",
        "data_types",
        "nullability",
        "defaults",
        "is_identity",
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

    def schema_resolution_request(self, *, object_identity: str, expected_object_type: Optional[str] = None) -> dict:
        return {
            "kind": "SCHEMA_CONTRACT_RESOLUTION",
            "call_policy": "SEPARATE_INFORMATION_SCHEMA_CALL_BEFORE_DEPENDENT_BACKEND",
            "object_identity": object_identity,
            "expected_object_type": expected_object_type,
            "required_table_metadata": [
                "exact_columns",
                "data_types",
                "nullability",
                "defaults",
                "is_identity",
                "identity_generation",
                "constraints",
                "indexes",
                "key_fields",
                "allowed_filters",
                "schema_fingerprint",
                "freshness",
            ],
            "required_function_metadata": [
                "exact_signature",
                "arguments(name,order,type,has_default)",
                "return_contract",
                "relevant_permissions",
                "schema_fingerprint",
                "freshness",
            ],
        }

    def validate_receipt(self, receipt: Optional[Mapping[str, Any]]) -> dict:
        if receipt is None:
            return _block("BLOCK_SCHEMA_RECEIPT_REQUIRED", "dependent access requires a prior schema receipt")
        if not isinstance(receipt, Mapping):
            return _block("BLOCK_SCHEMA_RECEIPT_INVALID", "schema receipt must be a mapping")

        object_type = receipt.get("object_type")
        if object_type not in {"TABLE", "VIEW", "FUNCTION"}:
            return _block("BLOCK_SCHEMA_OBJECT_TYPE_UNSUPPORTED", f"unsupported object_type={object_type}")
        required = self._FUNCTION_REQUIRED if object_type == "FUNCTION" else self._TABLE_REQUIRED
        missing = sorted(k for k in required if k not in receipt)
        if missing:
            return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"missing receipt fields: {missing}")

        object_identity = receipt.get("object_identity")
        schema = receipt.get("schema")
        if not isinstance(object_identity, str) or not object_identity or not isinstance(schema, str) or not schema:
            return _block("BLOCK_SCHEMA_RECEIPT_IDENTITY_INVALID", "object_identity and schema must be non-empty strings")
        if _schema_prefix(object_identity) != schema:
            return _block("BLOCK_SCHEMA_RECEIPT_SCHEMA_MISMATCH", f"receipt schema={schema} does not match object_identity={object_identity}")

        fp = receipt.get("schema_fingerprint")
        if not isinstance(fp, str) or not _SHA256_RE.fullmatch(fp):
            return _block("BLOCK_SCHEMA_FINGERPRINT_INVALID", "schema_fingerprint must be lowercase sha256")

        freshness = receipt.get("freshness")
        if not isinstance(freshness, Mapping):
            return _block("BLOCK_SCHEMA_FRESHNESS_INVALID", "freshness must be a mapping")
        if freshness.get("state") != "CURRENT":
            return _block("BLOCK_SCHEMA_RECEIPT_STALE", f"schema receipt freshness state must be CURRENT, got {freshness.get('state')}", f"schema://{object_identity}#{fp}")
        if not isinstance(freshness.get("source"), str) or not freshness.get("source"):
            return _block("BLOCK_SCHEMA_FRESHNESS_SOURCE_MISSING", "freshness.source is required")

        if object_type in {"TABLE", "VIEW"}:
            names = exact_column_names(receipt)
            if not names:
                return _block("BLOCK_SCHEMA_RECEIPT_NO_COLUMNS", "table/view receipt has no exact columns")
            if len(names) != len(set(names)):
                return _block("BLOCK_SCHEMA_RECEIPT_DUPLICATE_COLUMN", "duplicate exact column names")
            name_set = set(names)
            for field_name in ("data_types", "nullability", "defaults", "is_identity", "identity_generation"):
                mapping = receipt.get(field_name)
                if not isinstance(mapping, Mapping):
                    return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"{field_name} must be a mapping")
                missing_names = sorted(name_set - set(mapping))
                if missing_names:
                    return _block("BLOCK_SCHEMA_RECEIPT_COLUMN_METADATA_GAP", f"{field_name} missing {missing_names}")

            is_identity = receipt["is_identity"]
            identity_generation = receipt["identity_generation"]
            for name in names:
                flag = is_identity[name]
                is_id = flag is True or (isinstance(flag, str) and flag.upper() == "YES")
                is_not_id = flag is False or (isinstance(flag, str) and flag.upper() == "NO")
                if not (is_id or is_not_id):
                    return _block("BLOCK_IDENTITY_FLAG_INVALID", f"is_identity[{name}] must be boolean or YES/NO")
                generation = identity_generation[name]
                if is_id and generation not in {"ALWAYS", "BY DEFAULT"}:
                    return _block("BLOCK_IDENTITY_GENERATION_UNRESOLVED", f"identity column {name} requires ALWAYS or BY DEFAULT generation")
                if is_not_id and generation not in {None, ""}:
                    return _block("BLOCK_IDENTITY_GENERATION_INCONSISTENT", f"non-identity column {name} cannot declare identity_generation={generation}")

            for list_name in ("constraints", "indexes", "key_fields", "allowed_filters"):
                if not isinstance(receipt.get(list_name), list):
                    return _block("BLOCK_SCHEMA_RECEIPT_INCOMPLETE", f"{list_name} must be a list")
            if not set(receipt["key_fields"]).issubset(name_set):
                return _block("BLOCK_SCHEMA_KEY_FIELD_UNKNOWN", "key_fields must exist in exact_columns")
            if not set(receipt["allowed_filters"]).issubset(name_set):
                return _block("BLOCK_SCHEMA_FILTER_FIELD_UNKNOWN", "allowed_filters must exist in exact_columns")
        else:
            function_identity = receipt.get("function_identity")
            if function_identity != object_identity:
                return _block("BLOCK_FUNCTION_IDENTITY_INCONSISTENT", "function_identity must equal object_identity")
            signature = receipt.get("exact_signature")
            if not isinstance(signature, str) or not signature.startswith(f"{function_identity}("):
                return _block("BLOCK_FUNCTION_SIGNATURE_INVALID", "exact_signature must be explicit and identity-qualified")
            if not isinstance(receipt.get("return_contract"), str) or not receipt["return_contract"]:
                return _block("BLOCK_FUNCTION_RETURN_CONTRACT_INVALID", "return_contract must be non-empty")
            if not isinstance(receipt.get("relevant_permissions"), list):
                return _block("BLOCK_FUNCTION_PERMISSIONS_INVALID", "relevant_permissions must be an explicit list")
            args = receipt.get("arguments")
            if not isinstance(args, list):
                return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "arguments must be an ordered list")
            names: list[str] = []
            orders: list[int] = []
            for arg in args:
                if not isinstance(arg, Mapping):
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "every function argument must be a mapping")
                missing_arg = sorted({"order", "name", "type", "has_default"} - set(arg))
                if missing_arg:
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", f"argument missing {missing_arg}")
                if not isinstance(arg["name"], str) or not arg["name"] or not isinstance(arg["type"], str) or not arg["type"]:
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "argument name/type must be non-empty strings")
                if not isinstance(arg["order"], int) or not isinstance(arg["has_default"], bool):
                    return _block("BLOCK_FUNCTION_ARGUMENT_CONTRACT_INVALID", "argument order must be int and has_default bool")
                names.append(arg["name"])
                orders.append(arg["order"])
            if orders != list(range(1, len(args) + 1)):
                return _block("BLOCK_FUNCTION_ARGUMENT_ORDER_INVALID", "function arguments must be explicitly ordered from 1")
            if len(names) != len(set(names)):
                return _block("BLOCK_FUNCTION_ARGUMENT_DUPLICATE", "function argument names must be unique")

        ref = f"schema://{object_identity}#{fp}"
        return _pass("SCHEMA_RECEIPT_VALID", {"kind": "SCHEMA_RECEIPT"}, ref)

    def resolve_receipt(self, *, object_identity: str, expected_object_type: Optional[str], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]]) -> dict:
        request = self.schema_resolution_request(object_identity=object_identity, expected_object_type=expected_object_type)
        receipt = schema_backend(request)
        validated = self.validate_receipt(receipt)
        if validated["status"] != PASS:
            return validated
        if receipt["object_identity"] != object_identity:
            return _block("BLOCK_SCHEMA_RECEIPT_IDENTITY_MISMATCH", f"receipt is for {receipt['object_identity']}, requested {object_identity}")
        if expected_object_type is not None and receipt["object_type"] != expected_object_type:
            return _block("BLOCK_SCHEMA_RECEIPT_OBJECT_TYPE_MISMATCH", f"receipt type={receipt['object_type']} expected={expected_object_type}")
        return _pass("SCHEMA_RESOLUTION_COMPLETE", {"kind": "SCHEMA_RESOLUTION_COMPLETE", "receipt": dict(receipt)}, *validated.get("evidence_refs", []), schema_backend_executed=True)

    def prepare_unknown_read(self, *, object_identity: str, fields: Sequence[str], filters: Optional[Mapping[str, Any]], schema_receipt: Optional[Mapping[str, Any]]) -> dict:
        vr = self.validate_receipt(schema_receipt)
        if vr["status"] != PASS:
            return vr
        assert schema_receipt is not None
        if schema_receipt["object_type"] not in {"TABLE", "VIEW"}:
            return _block("BLOCK_OBJECT_KIND_MISMATCH", "read requires TABLE or VIEW receipt")
        if schema_receipt["object_identity"] != object_identity:
            return _block("BLOCK_SCHEMA_RECEIPT_IDENTITY_MISMATCH", f"receipt is for {schema_receipt['object_identity']}, requested {object_identity}")
        if not fields:
            return _block("BLOCK_EMPTY_FIELD_SET", "at least one exact field must be requested")
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

    def resolve_bind_execute_unknown_read(self, *, object_identity: str, fields: Sequence[str], filters: Optional[Mapping[str, Any]], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]], dependent_backend: Callable[[Mapping[str, Any]], Any], expected_object_type: Optional[str] = None) -> dict:
        resolved = self.resolve_receipt(object_identity=object_identity, expected_object_type=expected_object_type, schema_backend=schema_backend)
        if resolved["status"] != PASS:
            out = dict(resolved)
            out["backend_executed"] = False
            return out
        prepared = self.prepare_unknown_read(object_identity=object_identity, fields=fields, filters=filters, schema_receipt=resolved["plan"]["receipt"])
        return execute_prepared(prepared, dependent_backend)

    def prepare_function_call(self, *, function_identity: str, arguments: Mapping[str, Any], schema_receipt: Optional[Mapping[str, Any]]) -> dict:
        vr = self.validate_receipt(schema_receipt)
        if vr["status"] != PASS:
            return vr
        assert schema_receipt is not None
        if schema_receipt["object_type"] != "FUNCTION":
            return _block("BLOCK_OBJECT_KIND_MISMATCH", "function call requires FUNCTION receipt")
        if schema_receipt["function_identity"] != function_identity or schema_receipt["object_identity"] != function_identity:
            return _block("BLOCK_FUNCTION_SCHEMA_OR_IDENTITY_MISMATCH", f"receipt identity={schema_receipt['function_identity']} requested={function_identity}")
        arg_contract = schema_receipt["arguments"]
        contract_names = [a["name"] for a in arg_contract]
        unknown = sorted(set(arguments) - set(contract_names))
        if unknown:
            return _block("BLOCK_FUNCTION_ARGUMENT_NOT_IN_RECEIPT", f"unknown arguments: {unknown}")
        required = [a["name"] for a in arg_contract if not a["has_default"]]
        missing = [name for name in required if name not in arguments]
        if missing:
            return _block("BLOCK_FUNCTION_REQUIRED_ARGUMENT_MISSING", f"missing arguments: {missing}")
        ordered_args = [
            {"name": arg["name"], "declared_type": arg["type"], "value": arguments[arg["name"]]}
            for arg in arg_contract
            if arg["name"] in arguments
        ]
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

    def resolve_bind_execute_function_call(self, *, function_identity: str, arguments: Mapping[str, Any], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]], dependent_backend: Callable[[Mapping[str, Any]], Any]) -> dict:
        resolved = self.resolve_receipt(object_identity=function_identity, expected_object_type="FUNCTION", schema_backend=schema_backend)
        if resolved["status"] != PASS:
            out = dict(resolved)
            out["backend_executed"] = False
            return out
        prepared = self.prepare_function_call(function_identity=function_identity, arguments=arguments, schema_receipt=resolved["plan"]["receipt"])
        return execute_prepared(prepared, dependent_backend)


@dataclass(frozen=True)
class TypedReader:
    registry: Mapping[str, Any]
    resolver: SchemaContractResolver

    def prepare(self, *, source_key: str, fields: Optional[Sequence[str]] = None, filters: Optional[Mapping[str, Any]] = None, schema_receipt: Optional[Mapping[str, Any]] = None, requested_object: Optional[str] = None, free_sql: Optional[str] = None) -> dict:
        binding = self.registry["sources"].get(source_key)
        if binding is None:
            return _block("BLOCK_SOURCE_NOT_REGISTERED_USE_SCHEMA_RESOLVER", f"{source_key} has no canonical reader; resolve schema first")
        binding_ref = f"registry://{self.registry['contract_version']}/{source_key}"
        if free_sql is not None:
            return _block("BLOCK_REGISTERED_SOURCE_FREE_SQL", f"free SQL is forbidden for registered source_key={source_key}", binding_ref)
        if requested_object is not None and requested_object != binding["object_identity"]:
            return _block("BLOCK_REGISTERED_SOURCE_OBJECT_MISMATCH", f"binding object={binding['object_identity']} requested={requested_object}", binding_ref)
        vr = self.resolver.validate_receipt(schema_receipt)
        if vr["status"] != PASS:
            return _block(vr["code"], vr.get("detail", ""), binding_ref, *vr.get("evidence_refs", []))
        assert schema_receipt is not None
        receipt_ref = f"schema://{schema_receipt['object_identity']}#{schema_receipt['schema_fingerprint']}"
        if schema_receipt["object_identity"] != binding["object_identity"] or schema_receipt["object_type"] != binding["object_type"]:
            return _block("BLOCK_REGISTERED_SOURCE_RECEIPT_MISMATCH", "schema receipt does not match registered object identity/type", binding_ref, receipt_ref)
        if schema_receipt["schema_fingerprint"] != binding["schema_fingerprint"]:
            return _block("BLOCK_SCHEMA_FINGERPRINT_STALE", f"binding={binding['schema_fingerprint']} live={schema_receipt['schema_fingerprint']}", binding_ref, receipt_ref)
        receipt_provider = schema_receipt.get("fingerprint_provider")
        if receipt_provider is not None and receipt_provider != binding["fingerprint_provider"]:
            return _block("BLOCK_SCHEMA_FINGERPRINT_PROVIDER_MISMATCH", f"binding provider={binding['fingerprint_provider']} receipt provider={receipt_provider}", binding_ref, receipt_ref)
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
            "fingerprint_provider": binding["fingerprint_provider"],
        }
        return _pass("REGISTERED_TYPED_READER_READY", plan, binding_ref, receipt_ref)


def execute_prepared(preexecution_result: Mapping[str, Any], backend: Callable[[Mapping[str, Any]], Any]) -> dict:
    if preexecution_result.get("interface") != INTERFACE:
        return _block("BLOCK_INVALID_PREEXECUTION_INTERFACE", "expected PREEXECUTION_DATA_ACCESS_RESULT", backend_executed=False)
    if preexecution_result.get("status") != PASS:
        out = dict(preexecution_result)
        out["backend_executed"] = False
        return out
    plan = preexecution_result.get("plan")
    if not isinstance(plan, Mapping):
        return _block("BLOCK_PASS_WITHOUT_BOUND_PLAN", "PASS cannot reach backend without a bound plan", backend_executed=False)
    value = backend(plan)
    out = dict(preexecution_result)
    out["backend_executed"] = True
    out["readback"] = value
    return out


@dataclass(frozen=True)
class LFDataAccess:
    typed: TypedReader

    @classmethod
    def from_registry(cls, registry: Mapping[str, Any]) -> "LFDataAccess":
        return cls(typed=TypedReader(registry=registry, resolver=SchemaContractResolver()))

    def _read(self, source_key: str, *, fields=None, filters=None, schema_receipt=None, requested_object=None, free_sql=None) -> dict:
        return self.typed.prepare(source_key=source_key, fields=fields, filters=filters, schema_receipt=schema_receipt, requested_object=requested_object, free_sql=free_sql)

    def resolve_bind_execute_registered_read(self, *, source_key: str, fields: Optional[Sequence[str]], filters: Optional[Mapping[str, Any]], schema_backend: Callable[[Mapping[str, Any]], Mapping[str, Any]], dependent_backend: Callable[[Mapping[str, Any]], Any]) -> dict:
        binding = self.typed.registry["sources"].get(source_key)
        if binding is None:
            return _block("BLOCK_SOURCE_NOT_REGISTERED_USE_SCHEMA_RESOLVER", f"{source_key} has no canonical reader", backend_executed=False)
        resolved = self.typed.resolver.resolve_receipt(object_identity=binding["object_identity"], expected_object_type=binding["object_type"], schema_backend=schema_backend)
        if resolved["status"] != PASS:
            out = dict(resolved)
            out["backend_executed"] = False
            return out
        prepared = self.typed.prepare(source_key=source_key, fields=fields, filters=filters, schema_receipt=resolved["plan"]["receipt"])
        return execute_prepared(prepared, dependent_backend)

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
