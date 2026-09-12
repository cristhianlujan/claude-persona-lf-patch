from __future__ import annotations

import hashlib
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Optional, Sequence

from lf_data_access import BLOCKED, INTERFACE, PASS, LFDataAccess

EXECUTION_AUTHORITY_CONTRACT = "S30_EXECUTION_AUTHORITY_V1"

_ALLOWED_SCOPES = {"FOCAL", "BOUNDED", "BROAD", "SCHEMA_ONLY", "NON_DATA_TOOL"}
_ALLOWED_DIRECTIONS = {"ASC", "DESC"}


def _result(status: str, code: str, detail: str = "", *, plan: Optional[dict] = None, **extra: Any) -> dict:
    out: dict[str, Any] = {
        "interface": INTERFACE,
        "status": status,
        "code": code,
        "detail": detail,
        "evidence_refs": [],
    }
    if plan is not None:
        out["plan"] = plan
    out.update(extra)
    return out


def _block(code: str, detail: str, **extra: Any) -> dict:
    return _result(BLOCKED, code, detail, **extra)


def _pass(code: str, plan: dict, **extra: Any) -> dict:
    return _result(PASS, code, plan=plan, **extra)


def _stable_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str)


def _sha256(value: Any) -> str:
    return hashlib.sha256(_stable_json(value).encode("utf-8")).hexdigest()


def load_budget_profiles(path: str | Path) -> dict:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    required = {"contract_version", "base_registry_contract", "policy", "sources"}
    missing = sorted(required - set(payload))
    if missing:
        raise ValueError(f"budget policy missing keys: {missing}")
    if payload["contract_version"] != "LF_DATA_ACCESS_BUDGET_V1":
        raise ValueError("unsupported budget contract")
    if not isinstance(payload["sources"], dict) or not payload["sources"]:
        raise ValueError("budget sources must be non-empty")
    for source_key, source_policy in payload["sources"].items():
        if not isinstance(source_policy, Mapping):
            raise ValueError(f"{source_key} budget policy must be an object")
        default_profile = source_policy.get("default_profile")
        profiles = source_policy.get("profiles")
        if not isinstance(default_profile, str) or not default_profile:
            raise ValueError(f"{source_key} default_profile required")
        if not isinstance(profiles, Mapping) or default_profile not in profiles:
            raise ValueError(f"{source_key} profiles/default_profile inconsistent")
        for profile_name, profile in profiles.items():
            if not isinstance(profile, Mapping):
                raise ValueError(f"{source_key}/{profile_name} profile must be an object")
            fields = profile.get("fields")
            if not isinstance(fields, list) or not fields or len(fields) != len(set(fields)):
                raise ValueError(f"{source_key}/{profile_name} fields invalid")
            default_max_rows = profile.get("default_max_rows")
            ceiling = profile.get("max_rows_ceiling")
            byte_budget = profile.get("byte_budget")
            if not isinstance(default_max_rows, int) or default_max_rows < 1:
                raise ValueError(f"{source_key}/{profile_name} default_max_rows invalid")
            if not isinstance(ceiling, int) or ceiling < default_max_rows:
                raise ValueError(f"{source_key}/{profile_name} max_rows_ceiling invalid")
            if not isinstance(byte_budget, int) or byte_budget < 1:
                raise ValueError(f"{source_key}/{profile_name} byte_budget invalid")
            if profile.get("read_scope") not in _ALLOWED_SCOPES:
                raise ValueError(f"{source_key}/{profile_name} read_scope invalid")
    return payload


def _validate_order(order_by: Optional[Sequence[Mapping[str, Any]]], allowed_fields: set[str], key_fields: Sequence[str]) -> tuple[Optional[list[dict]], Optional[dict]]:
    if order_by is None:
        if not key_fields:
            return None, _block("BLOCK_DETERMINISTIC_ORDER_REQUIRED", "bounded read requires at least one deterministic key")
        return [{"field": key_fields[0], "direction": "ASC"}], None
    normalized: list[dict] = []
    if not order_by:
        return None, _block("BLOCK_DETERMINISTIC_ORDER_REQUIRED", "order_by cannot be empty")
    for item in order_by:
        if not isinstance(item, Mapping):
            return None, _block("BLOCK_ORDER_BY_INVALID", "order_by entries must be mappings")
        field = item.get("field")
        direction = str(item.get("direction", "ASC")).upper()
        if field not in allowed_fields:
            return None, _block("BLOCK_ORDER_FIELD_NOT_IN_BINDING", f"order field not registered: {field}")
        if direction not in _ALLOWED_DIRECTIONS:
            return None, _block("BLOCK_ORDER_DIRECTION_INVALID", f"direction={direction}")
        normalized.append({"field": field, "direction": direction})
    return normalized, None


def _row_count(value: Any) -> Optional[int]:
    if isinstance(value, (list, tuple)):
        return len(value)
    if isinstance(value, Mapping):
        for key in ("rows_returned", "row_count"):
            candidate = value.get(key)
            if isinstance(candidate, int) and candidate >= 0:
                return candidate
        rows = value.get("rows")
        if isinstance(rows, (list, tuple)):
            return len(rows)
        if isinstance(rows, int) and rows >= 0:
            return rows
        data = value.get("data")
        if isinstance(data, (list, tuple)):
            return len(data)
    return None


@dataclass(frozen=True)
class BudgetedLFDataAccess:
    base: LFDataAccess
    budget_policy: Mapping[str, Any]

    @classmethod
    def from_contracts(cls, registry: Mapping[str, Any], budget_policy: Mapping[str, Any]) -> "BudgetedLFDataAccess":
        if budget_policy.get("base_registry_contract") != registry.get("contract_version"):
            raise ValueError("budget policy is not bound to current data access registry contract")
        registry_sources = set((registry.get("sources") or {}).keys())
        policy_sources = set((budget_policy.get("sources") or {}).keys())
        if registry_sources != policy_sources:
            missing = sorted(registry_sources - policy_sources)
            extra = sorted(policy_sources - registry_sources)
            raise ValueError(f"budget source coverage mismatch missing={missing} extra={extra}")
        for source_key, source_policy in budget_policy["sources"].items():
            allowed = set(registry["sources"][source_key]["fields"])
            for profile_name, profile in source_policy["profiles"].items():
                unknown = sorted(set(profile["fields"]) - allowed)
                if unknown:
                    raise ValueError(f"{source_key}/{profile_name} fields absent from registry: {unknown}")
        return cls(LFDataAccess.from_registry(registry), budget_policy)

    def prepare_registered_read(
        self,
        *,
        source_key: str,
        field_profile: Optional[str] = None,
        fields: Optional[Sequence[str]] = None,
        filters: Optional[Mapping[str, Any]] = None,
        max_rows: Optional[int] = None,
        byte_budget: Optional[int] = None,
        order_by: Optional[Sequence[Mapping[str, Any]]] = None,
        page_cursor: Any = None,
        schema_receipt: Optional[Mapping[str, Any]] = None,
        requested_object: Optional[str] = None,
        free_sql: Optional[str] = None,
    ) -> dict:
        source_policy = self.budget_policy["sources"].get(source_key)
        if source_policy is None:
            return _block("BLOCK_BUDGET_PROFILE_SOURCE_UNKNOWN", f"source_key={source_key}")
        profile_name = (field_profile or source_policy["default_profile"]).upper()
        profile = source_policy["profiles"].get(profile_name)
        if profile is None:
            return _block("BLOCK_DATA_ACCESS_PROFILE_UNKNOWN", f"source_key={source_key} profile={profile_name}")

        profile_fields = list(profile["fields"])
        requested_fields = list(fields) if fields is not None else profile_fields
        if not requested_fields:
            return _block("BLOCK_EMPTY_FIELD_SET", "budgeted read requires fields")
        outside_profile = sorted(set(requested_fields) - set(profile_fields))
        if outside_profile:
            return _block(
                "BLOCK_FIELD_NOT_IN_ACCESS_PROFILE",
                f"fields outside {source_key}/{profile_name}: {outside_profile}",
            )

        chosen_max_rows = profile["default_max_rows"] if max_rows is None else max_rows
        if not isinstance(chosen_max_rows, int) or chosen_max_rows < 1:
            return _block("BLOCK_ROW_BUDGET_INVALID", f"max_rows={chosen_max_rows}")
        if chosen_max_rows > profile["max_rows_ceiling"]:
            return _block(
                "BLOCK_ROW_BUDGET_EXCEEDS_PROFILE",
                f"max_rows={chosen_max_rows} ceiling={profile['max_rows_ceiling']}",
            )

        chosen_byte_budget = profile["byte_budget"] if byte_budget is None else byte_budget
        if not isinstance(chosen_byte_budget, int) or chosen_byte_budget < 1:
            return _block("BLOCK_BYTE_BUDGET_INVALID", f"byte_budget={chosen_byte_budget}")
        if chosen_byte_budget > profile["byte_budget"]:
            return _block(
                "BLOCK_BYTE_BUDGET_EXCEEDS_PROFILE",
                f"byte_budget={chosen_byte_budget} ceiling={profile['byte_budget']}",
            )

        normalized_filters = dict(filters or {})
        if profile.get("require_filter") is True and not normalized_filters:
            return _block("BLOCK_DETAIL_FILTER_REQUIRED", f"{source_key}/{profile_name} requires a focal filter")

        binding = self.base.typed.registry["sources"].get(source_key)
        if binding is None:
            return _block("BLOCK_SOURCE_NOT_REGISTERED_USE_SCHEMA_RESOLVER", f"source_key={source_key}")
        normalized_order, order_error = _validate_order(order_by, set(binding["fields"]), binding["key_fields"])
        if order_error is not None:
            return order_error

        base_result = self.base.typed.prepare(
            source_key=source_key,
            fields=requested_fields,
            filters=normalized_filters,
            schema_receipt=schema_receipt,
            requested_object=requested_object,
            free_sql=free_sql,
        )
        if base_result.get("status") != PASS:
            return base_result

        plan = dict(base_result["plan"])
        plan.update(
            execution_authority="DETERMINISTIC",
            model_call_required=False,
            execution_authority_contract=EXECUTION_AUTHORITY_CONTRACT,
            access_profile=profile_name,
            read_scope=profile["read_scope"],
            max_rows=chosen_max_rows,
            byte_budget=chosen_byte_budget,
            order_by=normalized_order,
            page_cursor=page_cursor,
            budget_contract=self.budget_policy["contract_version"],
        )
        return _pass(
            "REGISTERED_BOUNDED_TYPED_READER_READY",
            plan,
            inherited_code=base_result.get("code"),
            evidence_refs=base_result.get("evidence_refs", []),
        )

    def _validate_bound_plan(self, plan: Mapping[str, Any]) -> Optional[dict]:
        required = {
            "kind", "source_key", "reader", "object_identity", "fields", "filters",
            "schema_fingerprint", "fingerprint_provider", "max_rows", "byte_budget",
            "order_by", "access_profile", "read_scope", "budget_contract",
            "execution_authority", "model_call_required", "execution_authority_contract",
        }
        missing = sorted(required - set(plan))
        if missing:
            return _block("BLOCK_BUDGETED_PLAN_INCOMPLETE", f"missing plan fields={missing}", backend_executed=False)
        if plan.get("kind") != "TYPED_READ":
            return _block("BLOCK_BUDGETED_PLAN_KIND_INVALID", f"kind={plan.get('kind')}", backend_executed=False)
        if plan.get("budget_contract") != self.budget_policy.get("contract_version"):
            return _block("BLOCK_BUDGET_CONTRACT_MISMATCH", "plan budget contract is not current", backend_executed=False)
        if plan.get("execution_authority") != "DETERMINISTIC" or plan.get("model_call_required") is not False:
            return _block("BLOCK_REGISTERED_READ_NONDETERMINISTIC_AUTHORITY", "registered read planning must remain deterministic", backend_executed=False)
        if plan.get("execution_authority_contract") != self.budget_policy.get("execution_authority_contract"):
            return _block("BLOCK_EXECUTION_AUTHORITY_CONTRACT_MISMATCH", "registered read authority contract mismatch", backend_executed=False)

        source_key = plan.get("source_key")
        binding = self.base.typed.registry["sources"].get(source_key)
        source_policy = self.budget_policy["sources"].get(source_key)
        if binding is None or source_policy is None:
            return _block("BLOCK_BUDGET_PROFILE_SOURCE_UNKNOWN", f"source_key={source_key}", backend_executed=False)
        profile_name = plan.get("access_profile")
        profile = source_policy["profiles"].get(profile_name)
        if profile is None:
            return _block("BLOCK_DATA_ACCESS_PROFILE_UNKNOWN", f"source_key={source_key} profile={profile_name}", backend_executed=False)

        exact_binding = {
            "reader": binding["reader"],
            "object_identity": binding["object_identity"],
            "schema_fingerprint": binding["schema_fingerprint"],
            "fingerprint_provider": binding["fingerprint_provider"],
        }
        mismatched = sorted(k for k, v in exact_binding.items() if plan.get(k) != v)
        if mismatched:
            return _block("BLOCK_BUDGETED_PLAN_BINDING_MISMATCH", f"binding fields mismatched={mismatched}", backend_executed=False)

        fields = plan.get("fields")
        if not isinstance(fields, list) or not fields or len(fields) != len(set(fields)):
            return _block("BLOCK_BUDGETED_PLAN_FIELDS_INVALID", "fields must be a non-empty unique list", backend_executed=False)
        outside_profile = sorted(set(fields) - set(profile["fields"]))
        if outside_profile:
            return _block("BLOCK_FIELD_NOT_IN_ACCESS_PROFILE", f"fields outside {source_key}/{profile_name}: {outside_profile}", backend_executed=False)

        filters = plan.get("filters")
        if not isinstance(filters, Mapping):
            return _block("BLOCK_BUDGETED_PLAN_FILTERS_INVALID", "filters must be a mapping", backend_executed=False)
        bad_filters = sorted(set(filters) - set(binding["allowed_filters"]))
        if bad_filters:
            return _block("BLOCK_FILTER_NOT_IN_BINDING", f"filters not registered: {bad_filters}", backend_executed=False)
        if profile.get("require_filter") is True and not filters:
            return _block("BLOCK_DETAIL_FILTER_REQUIRED", f"{source_key}/{profile_name} requires a focal filter", backend_executed=False)

        max_rows = plan.get("max_rows")
        if not isinstance(max_rows, int) or isinstance(max_rows, bool) or max_rows < 1 or max_rows > profile["max_rows_ceiling"]:
            return _block("BLOCK_ROW_BUDGET_INVALID_AT_EXECUTION", f"max_rows={max_rows}", backend_executed=False)
        byte_budget = plan.get("byte_budget")
        if not isinstance(byte_budget, int) or isinstance(byte_budget, bool) or byte_budget < 1 or byte_budget > profile["byte_budget"]:
            return _block("BLOCK_BYTE_BUDGET_INVALID_AT_EXECUTION", f"byte_budget={byte_budget}", backend_executed=False)
        if plan.get("read_scope") != profile["read_scope"]:
            return _block("BLOCK_READ_SCOPE_MISMATCH", f"read_scope={plan.get('read_scope')}", backend_executed=False)

        normalized_order, order_error = _validate_order(plan.get("order_by"), set(binding["fields"]), binding["key_fields"])
        if order_error is not None:
            return {**order_error, "backend_executed": False}
        if normalized_order != list(plan.get("order_by") or []):
            return _block("BLOCK_ORDER_BY_NOT_NORMALIZED", "order_by differs from canonical normalized form", backend_executed=False)
        if not any(item["field"] in set(binding["key_fields"]) for item in normalized_order or []):
            return _block("BLOCK_DETERMINISTIC_KEY_ORDER_REQUIRED", "order_by must include at least one registered key field", backend_executed=False)
        return None

    def execute_registered_read(self, *, prepared: Mapping[str, Any], backend: Callable[[Mapping[str, Any]], Any]) -> dict:
        if prepared.get("interface") != INTERFACE:
            return _block("BLOCK_INVALID_PREEXECUTION_INTERFACE", "invalid preexecution interface", backend_executed=False)
        if prepared.get("status") != PASS:
            return {**dict(prepared), "backend_executed": False}
        plan = prepared.get("plan")
        if not isinstance(plan, Mapping):
            return _block("BLOCK_PASS_WITHOUT_BOUND_PLAN", "PASS requires bound plan", backend_executed=False)
        plan_error = self._validate_bound_plan(plan)
        if plan_error is not None:
            return plan_error

        started = time.perf_counter()
        readback = backend(plan)
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        serialized = _stable_json(readback).encode("utf-8")
        result_bytes = len(serialized)
        result_sha = hashlib.sha256(serialized).hexdigest()
        rows = _row_count(readback)

        common = {
            "backend_executed": True,
            "result_sha256": result_sha,
            "rows_returned": rows if rows is not None else "NOT_OBSERVED",
            "result_bytes": result_bytes,
            "client_elapsed_ms": round(elapsed_ms, 3),
        }
        if rows is not None and rows > int(plan["max_rows"]):
            return _block(
                "BLOCK_RESULT_ROW_BUDGET_EXCEEDED",
                f"rows={rows} max_rows={plan['max_rows']}",
                **common,
            )
        if result_bytes > int(plan["byte_budget"]):
            return _block(
                "BLOCK_RESULT_BYTE_BUDGET_EXCEEDED",
                f"bytes={result_bytes} byte_budget={plan['byte_budget']}",
                **common,
            )

        trace = {
            "tool_name": "S30_B_BUDGETED_TYPED_READER",
            "purpose": f"bounded read {plan['source_key']}/{plan['access_profile']}",
            "source_object": plan["object_identity"],
            "operation_kind": "TYPED_READ",
            "execution_authority": "DETERMINISTIC",
            "model_call_required": False,
            "query_or_request_digest": _sha256(plan),
            "exact_columns_or_fields": list(plan["fields"]),
            "filters": dict(plan["filters"]),
            "limit_or_range": {"max_rows": plan["max_rows"], "page_cursor": plan.get("page_cursor")},
            "rows_returned": rows if rows is not None else "NOT_OBSERVED",
            "result_bytes_if_observed": result_bytes,
            "server_elapsed_ms_if_observed": "NOT_OBSERVED",
            "client_elapsed_ms_if_observed": round(elapsed_ms, 3),
            "round_trip_index": 1,
            "retry_count": 0,
            "error_code_if_any": None,
            "cache_or_reuse": False,
            "read_scope": plan["read_scope"],
            "output_digest": result_sha,
        }
        return {
            **dict(prepared),
            **common,
            "readback": readback,
            "tool_trace": trace,
        }
