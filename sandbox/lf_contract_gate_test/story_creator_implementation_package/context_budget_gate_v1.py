#!/usr/bin/env python3
from __future__ import annotations

import json
from typing import Any

CAPABILITY_CODE = "CONTEXT_BUDGET_GOVERNANCE"
BENCHMARK_PATTERN = "PERFORMANCE_EXACT_SOURCE_BENCHMARK"


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def build_task_view(pkg: dict[str, Any], task_view: dict[str, Any]) -> dict[str, Any]:
    selected = task_view.get("selected_sections", [])
    return {name: pkg[name] for name in selected if name in pkg}


def evaluate_context_budget(pkg: dict[str, Any], task_view: dict[str, Any]) -> dict[str, Any]:
    view = build_task_view(pkg, task_view)
    measured = len(canonical_bytes(view))
    view_limit = int(task_view["max_context_bytes"])
    transport_limit = int(pkg["context_transport"]["max_context_bytes"])
    effective_limit = min(view_limit, transport_limit)
    return {
        "schema": "STORY_IMPLEMENTATION_CONTEXT_BUDGET_RESULT_V1",
        "capability_code": CAPABILITY_CODE,
        "benchmark_pattern": BENCHMARK_PATTERN,
        "task_code": task_view["task_code"],
        "measured_context_bytes": measured,
        "view_limit_bytes": view_limit,
        "transport_limit_bytes": transport_limit,
        "effective_limit_bytes": effective_limit,
        "result": "PASS" if measured <= effective_limit else "BLOCK_CONTEXT_BUDGET_EXCEEDED",
    }
