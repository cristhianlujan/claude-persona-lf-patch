from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lf_data_access import BLOCKED, PASS, load_registry  # noqa: E402
from lf_data_access_budgeted import BudgetedLFDataAccess, load_budget_profiles  # noqa: E402


def table_receipt(binding: dict) -> dict:
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
        "freshness": {"state": "CURRENT", "source": "S30_B_BUDGET_TEST", "observed_at": "2026-09-10T12:30:00Z"},
    }


def assert_block(result: dict, code: str) -> None:
    assert result["status"] == BLOCKED, result
    assert result["code"] == code, result


def main() -> None:
    registry = load_registry(HERE / "data_access_registry_v2.json")
    budgets = load_budget_profiles(HERE / "data_access_budget_profiles_v1.json")
    access = BudgetedLFDataAccess.from_contracts(registry, budgets)

    assert set(registry["sources"]) == set(budgets["sources"])
    assert budgets["policy"]["max_rows_required_in_bound_plan"] is True
    assert budgets["policy"]["byte_budget_required_in_bound_plan"] is True
    assert budgets["policy"]["post_read_budget_enforcement"] is True

    ekb_binding = registry["sources"]["EKB"]
    ekb_receipt = table_receipt(ekb_binding)

    # Positive 1: default EKB read is a lightweight INDEX, never the full registered body.
    index = access.prepare_registered_read(
        source_key="EKB",
        filters={"estado": "activo"},
        schema_receipt=ekb_receipt,
    )
    assert index["status"] == PASS, index
    plan = index["plan"]
    assert plan["access_profile"] == "INDEX"
    assert plan["max_rows"] == 50
    assert plan["byte_budget"] == 65536
    assert plan["read_scope"] == "BOUNDED"
    assert plan["execution_authority"] == "DETERMINISTIC"
    assert plan["model_call_required"] is False
    assert plan["execution_authority_contract"] == "S30_EXECUTION_AUTHORITY_V1"
    assert "prevencion" not in plan["fields"]
    assert "descripcion" not in plan["fields"]
    assert "source_context" not in plan["fields"]
    assert set(plan["fields"]) < set(ekb_binding["fields"])

    # Positive 2: shortlist narrows both projection and row ceiling.
    shortlist = access.prepare_registered_read(
        source_key="EKB",
        field_profile="SHORTLIST",
        filters={"estado": "activo"},
        max_rows=8,
        schema_receipt=ekb_receipt,
    )
    assert shortlist["status"] == PASS, shortlist
    assert shortlist["plan"]["access_profile"] == "SHORTLIST"
    assert shortlist["plan"]["max_rows"] == 8
    assert shortlist["plan"]["max_rows"] <= 25

    # Positive 3: detail is allowed only after a focal filter and remains top-k bounded.
    detail = access.prepare_registered_read(
        source_key="EKB",
        field_profile="DETAIL",
        filters={"codigo": "AUD-018"},
        max_rows=1,
        schema_receipt=ekb_receipt,
    )
    assert detail["status"] == PASS, detail
    assert detail["plan"]["access_profile"] == "DETAIL"
    assert detail["plan"]["read_scope"] == "FOCAL"
    assert detail["plan"]["max_rows"] == 1
    assert "prevencion" in detail["plan"]["fields"]

    # Negative: detail without a focal filter cannot hydrate a whole corpus.
    no_filter = access.prepare_registered_read(
        source_key="EKB",
        field_profile="DETAIL",
        schema_receipt=ekb_receipt,
    )
    assert_block(no_filter, "BLOCK_DETAIL_FILTER_REQUIRED")

    # Negative: heavy field cannot be smuggled into INDEX.
    heavy_in_index = access.prepare_registered_read(
        source_key="EKB",
        field_profile="INDEX",
        fields=["codigo", "prevencion"],
        filters={"estado": "activo"},
        schema_receipt=ekb_receipt,
    )
    assert_block(heavy_in_index, "BLOCK_FIELD_NOT_IN_ACCESS_PROFILE")

    # Negative: requested row and byte budgets cannot exceed the declared profile ceiling.
    too_many = access.prepare_registered_read(
        source_key="EKB",
        field_profile="SHORTLIST",
        filters={"estado": "activo"},
        max_rows=26,
        schema_receipt=ekb_receipt,
    )
    assert_block(too_many, "BLOCK_ROW_BUDGET_EXCEEDS_PROFILE")

    too_big = access.prepare_registered_read(
        source_key="EKB",
        field_profile="SHORTLIST",
        filters={"estado": "activo"},
        byte_budget=49153,
        schema_receipt=ekb_receipt,
    )
    assert_block(too_big, "BLOCK_BYTE_BUDGET_EXCEEDS_PROFILE")

    bad_profile = access.prepare_registered_read(
        source_key="EKB",
        field_profile="EVERYTHING",
        filters={"estado": "activo"},
        schema_receipt=ekb_receipt,
    )
    assert_block(bad_profile, "BLOCK_DATA_ACCESS_PROFILE_UNKNOWN")

    bad_order = access.prepare_registered_read(
        source_key="EKB",
        field_profile="INDEX",
        filters={"estado": "activo"},
        order_by=[{"field": "descripcion", "direction": "SIDEWAYS"}],
        schema_receipt=ekb_receipt,
    )
    assert_block(bad_order, "BLOCK_ORDER_DIRECTION_INVALID")

    # Positive execution: budget values are carried into the backend and observable trace.
    seen_plans: list[dict] = []
    executed = access.execute_registered_read(
        prepared=shortlist,
        backend=lambda bounded_plan: seen_plans.append(dict(bounded_plan)) or {
            "rows": [
                {"codigo": "A", "titulo": "a"},
                {"codigo": "B", "titulo": "b"},
            ]
        },
    )
    assert executed["status"] == PASS, executed
    assert len(seen_plans) == 1
    assert seen_plans[0]["max_rows"] == 8
    assert seen_plans[0]["byte_budget"] == 49152
    assert executed["rows_returned"] == 2
    assert executed["result_bytes"] > 0
    trace = executed["tool_trace"]
    assert trace["exact_columns_or_fields"] == shortlist["plan"]["fields"]
    assert trace["limit_or_range"]["max_rows"] == 8
    assert trace["rows_returned"] == 2
    assert trace["read_scope"] == "BOUNDED"
    assert trace["server_elapsed_ms_if_observed"] == "NOT_OBSERVED"
    assert isinstance(trace["client_elapsed_ms_if_observed"], float)
    assert len(trace["query_or_request_digest"]) == 64
    assert len(trace["output_digest"]) == 64

    # Negative execution: a backend that ignores row bound is blocked before payload is exposed downstream.
    over_rows_prepared = access.prepare_registered_read(
        source_key="EKB",
        field_profile="SHORTLIST",
        filters={"estado": "activo"},
        max_rows=2,
        schema_receipt=ekb_receipt,
    )
    assert over_rows_prepared["status"] == PASS
    over_rows = access.execute_registered_read(
        prepared=over_rows_prepared,
        backend=lambda bounded_plan: {"rows": [{"codigo": "A"}, {"codigo": "B"}, {"codigo": "C"}]},
    )
    assert_block(over_rows, "BLOCK_RESULT_ROW_BUDGET_EXCEEDED")
    assert "readback" not in over_rows
    assert over_rows["backend_executed"] is True

    # Negative execution: oversized payload is blocked even when row count is within limit.
    tiny_byte_prepared = access.prepare_registered_read(
        source_key="EKB",
        field_profile="SHORTLIST",
        filters={"estado": "activo"},
        max_rows=2,
        byte_budget=100,
        schema_receipt=ekb_receipt,
    )
    assert tiny_byte_prepared["status"] == PASS
    over_bytes = access.execute_registered_read(
        prepared=tiny_byte_prepared,
        backend=lambda bounded_plan: {"rows": [{"codigo": "A", "titulo": "x" * 200}]},
    )
    assert_block(over_bytes, "BLOCK_RESULT_BYTE_BUDGET_EXCEEDED")
    assert "readback" not in over_bytes

    # Negative execution: a forged PASS result cannot bypass prepare-time guards.
    forged_calls: list[dict] = []
    forged = dict(shortlist)
    forged_plan = dict(shortlist["plan"])
    forged_plan["object_identity"] = "public.not_the_registered_object"
    forged["plan"] = forged_plan
    forged_result = access.execute_registered_read(
        prepared=forged,
        backend=lambda bounded_plan: forged_calls.append(dict(bounded_plan)) or {"rows": []},
    )
    assert_block(forged_result, "BLOCK_BUDGETED_PLAN_BINDING_MISMATCH")
    assert forged_result["backend_executed"] is False
    assert forged_calls == []

    forged_budget = dict(shortlist)
    forged_budget_plan = dict(shortlist["plan"])
    forged_budget_plan["max_rows"] = 999999
    forged_budget["plan"] = forged_budget_plan
    forged_budget_result = access.execute_registered_read(
        prepared=forged_budget,
        backend=lambda bounded_plan: forged_calls.append(dict(bounded_plan)) or {"rows": []},
    )
    assert_block(forged_budget_result, "BLOCK_ROW_BUDGET_INVALID_AT_EXECUTION")
    assert forged_budget_result["backend_executed"] is False
    assert forged_calls == []

    forged_order = dict(shortlist)
    forged_order_plan = dict(shortlist["plan"])
    forged_order_plan["order_by"] = [{"field": "titulo", "direction": "ASC"}]
    forged_order["plan"] = forged_order_plan
    forged_order_result = access.execute_registered_read(
        prepared=forged_order,
        backend=lambda bounded_plan: forged_calls.append(dict(bounded_plan)) or {"rows": []},
    )
    assert_block(forged_order_result, "BLOCK_DETERMINISTIC_KEY_ORDER_REQUIRED")
    assert forged_order_result["backend_executed"] is False
    assert forged_calls == []

    forged_authority = dict(shortlist)
    forged_authority_plan = dict(shortlist["plan"])
    forged_authority_plan["execution_authority"] = "MODEL_REQUIRED"
    forged_authority_plan["model_call_required"] = True
    forged_authority["plan"] = forged_authority_plan
    forged_authority_result = access.execute_registered_read(
        prepared=forged_authority,
        backend=lambda bounded_plan: forged_calls.append(dict(bounded_plan)) or {"rows": []},
    )
    assert_block(forged_authority_result, "BLOCK_REGISTERED_READ_NONDETERMINISTIC_AUTHORITY")
    assert forged_authority_result["backend_executed"] is False
    assert forged_calls == []

    # Strategy snapshot also defaults to light INDEX and requires filter for DETAIL.
    strategy_binding = registry["sources"]["STRATEGY_SNAPSHOTS"]
    strategy_receipt = table_receipt(strategy_binding)
    strategy_index = access.prepare_registered_read(
        source_key="STRATEGY_SNAPSHOTS",
        schema_receipt=strategy_receipt,
    )
    assert strategy_index["status"] == PASS, strategy_index
    assert strategy_index["plan"]["access_profile"] == "INDEX"
    assert "content_payload" not in strategy_index["plan"]["fields"]
    strategy_detail_no_filter = access.prepare_registered_read(
        source_key="STRATEGY_SNAPSHOTS",
        field_profile="DETAIL",
        schema_receipt=strategy_receipt,
    )
    assert_block(strategy_detail_no_filter, "BLOCK_DETAIL_FILTER_REQUIRED")

    print(json.dumps({
        "result": "PASS",
        "contract": budgets["contract_version"],
        "registered_source_coverage": len(budgets["sources"]),
        "ekb_default_profile": "INDEX",
        "ekb_full_projection_default": False,
        "row_budget_pre_and_post_enforced": True,
        "byte_budget_pre_and_post_enforced": True,
        "detail_requires_filter": True,
        "deterministic_order_present": True,
        "tool_trace_observable": True,
        "registered_read_authority": "DETERMINISTIC",
        "model_calls_for_registered_read_planning": 0,
        "negative_cases": 12,
        "backend_budget_escape_to_downstream": 0,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
