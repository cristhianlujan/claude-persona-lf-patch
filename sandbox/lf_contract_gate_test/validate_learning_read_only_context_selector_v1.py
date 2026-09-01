#!/usr/bin/env python3
from __future__ import annotations

from learning_read_only_context_selector_v1 import BindingSpec, LearningSelectionError, select_read_only_context


def must_fail(fn):
    try:
        fn()
    except LearningSelectionError:
        return
    raise SystemExit("FAIL expected LearningSelectionError")


def row(kb_id: str, *, grounded: str = "GROUNDED", ready: bool = True):
    return {
        "kb_id": kb_id,
        "grounding_status": grounded,
        "consumer_ready": ready,
        "topic": f"topic-{kb_id}",
        "summary": f"summary-{kb_id}",
        "source_url": f"https://example.test/{kb_id}",
        "competitor": "fixture",
        "quality_score": 0.9,
    }


def main() -> int:
    binding = BindingSpec(
        consumer_id="PERFIL-PRODUCT-DIRECTOR-LF",
        capability_id="NEGOCIACION_DEUDA",
        source_learning_ids=("kb-1", "kb-2", "kb-3", "kb-4", "kb-5", "kb-6"),
        max_evidence_refs=5,
    )
    rows = [
        row("kb-1"), row("kb-2"), row("kb-3"), row("kb-4"), row("kb-5"), row("kb-6"),
        row("kb-not-bound"), row("kb-stale", grounded="STALE"), row("kb-not-ready", ready=False),
    ]
    out = select_read_only_context(rows, binding=binding)
    assert out["mode"] == "READ_ONLY"
    assert out["selector"] == "DETERMINISTIC_EXACT_ID"
    assert out["llm_calls"] == 0
    assert out["round_trips"] == 0
    assert out["selected_count"] == 5
    assert [x["kb_id"] for x in out["selected"]] == ["kb-1", "kb-2", "kb-3", "kb-4", "kb-5"]
    assert all(x["kb_id"] != "kb-not-bound" for x in out["selected"])

    empty = select_read_only_context([row("other")], binding=binding)
    assert empty["selected_count"] == 0
    assert empty["fallback"] == "NO_COMPETITIVE_CONTEXT"

    must_fail(lambda: select_read_only_context(rows, binding=BindingSpec("", "NEGOCIACION_DEUDA", ("kb-1",))))
    must_fail(lambda: select_read_only_context(rows, binding=BindingSpec("PD", "", ("kb-1",))))
    must_fail(lambda: select_read_only_context(rows, binding=BindingSpec("PD", "NEGOCIACION_DEUDA", ())))
    must_fail(lambda: select_read_only_context(rows, binding=BindingSpec("PD", "NEGOCIACION_DEUDA", ("kb-1",), 6)))

    print("LEARNING_READ_ONLY_CONTEXT_SELECTOR=PASS")
    print("positive=1 bounded=1 fallback=1 negative=4 llm_calls=0 round_trips=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
