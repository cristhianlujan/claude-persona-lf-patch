#!/usr/bin/env python3
from __future__ import annotations

import copy
import json

from context_budget_gate_v1 import evaluate_context_budget
from validate_story_implementation_package_v1 import valid_fixture


def main() -> int:
    base = valid_fixture()
    view = base["task_views"][0]
    positive = evaluate_context_budget(base, view)

    over_view = copy.deepcopy(base)
    over_view["task_views"][0]["max_context_bytes"] = 32
    negative_view = evaluate_context_budget(over_view, over_view["task_views"][0])

    over_transport = copy.deepcopy(base)
    over_transport["context_transport"]["max_context_bytes"] = 32
    negative_transport = evaluate_context_budget(over_transport, over_transport["task_views"][0])

    payload_overload = copy.deepcopy(base)
    payload_overload["outcome"]["oversized_context_probe"] = "x" * 70000
    negative_payload = evaluate_context_budget(payload_overload, payload_overload["task_views"][0])

    cases = [
        {"case":"gold_declared_view","ok":positive["result"] == "PASS","observed":positive},
        {"case":"view_limit_overload","ok":negative_view["result"] == "BLOCK_CONTEXT_BUDGET_EXCEEDED","observed":negative_view},
        {"case":"transport_limit_overload","ok":negative_transport["result"] == "BLOCK_CONTEXT_BUDGET_EXCEEDED","observed":negative_transport},
        {"case":"payload_overload","ok":negative_payload["result"] == "BLOCK_CONTEXT_BUDGET_EXCEEDED","observed":negative_payload},
    ]
    passed = sum(1 for case in cases if case["ok"])
    out = {
        "schema":"SC_M3_5_CONTEXT_BUDGET_SELF_TEST_V1",
        "cases_total":len(cases),
        "cases_passed":passed,
        "result":"PASS" if passed == len(cases) else "FAIL",
        "cases":cases,
    }
    print(json.dumps(out, indent=2, sort_keys=True))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
