#!/usr/bin/env python3
from __future__ import annotations
from learning_read_only_context_selector_v1 import BindingSpec, LearningSelectionError, select_read_only_context

def must_fail(fn):
    try: fn()
    except LearningSelectionError: return
    raise SystemExit("FAIL expected LearningSelectionError")

def row(kb_id: str, *, category: str = "COMPETENCIA", grounded: str = "GROUNDED", ready: bool = True):
    return {"kb_id":kb_id,"kb_category":category,"grounding_status":grounded,"consumer_ready":ready,"topic":f"topic-{kb_id}","summary":f"summary-{kb_id}","source_url":f"https://example.test/{kb_id}","competitor":"fixture","quality_score":0.9}

def main() -> int:
    binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",("kb-1","kb-2","kb-3","kb-4","kb-5","kb-6","kb-wrong-category"),5)
    rows=[row("kb-1"),row("kb-2"),row("kb-3"),row("kb-4"),row("kb-5"),row("kb-6"),row("kb-wrong-category",category="EDUCACION_FINANCIERA"),row("kb-not-bound"),row("kb-stale",grounded="STALE"),row("kb-not-ready",ready=False)]
    out=select_read_only_context(rows,binding=binding)
    assert out["mode"]=="READ_ONLY" and out["selector"]=="DETERMINISTIC_EXACT_ID" and out["required_kb_category"]=="COMPETENCIA"
    assert out["llm_calls"]==0 and out["round_trips"]==0 and out["selected_count"]==5
    assert [x["kb_id"] for x in out["selected"]]==["kb-1","kb-2","kb-3","kb-4","kb-5"]
    assert all(x["kb_category"]=="COMPETENCIA" for x in out["selected"])
    wrong=select_read_only_context([row("kb-wrong-category",category="EDUCACION_FINANCIERA")],binding=BindingSpec("PD","NEGOCIACION_DEUDA",("kb-wrong-category",)))
    assert wrong["selected_count"]==0 and wrong["fallback"]=="NO_COMPETITIVE_CONTEXT"
    empty=select_read_only_context([row("other")],binding=binding); assert empty["selected_count"]==0
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("","NEGOCIACION_DEUDA",("kb-1",))))
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PD","",("kb-1",))))
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PD","NEGOCIACION_DEUDA",())))
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PD","NEGOCIACION_DEUDA",("kb-1",),6)))
    print("LEARNING_READ_ONLY_CONTEXT_SELECTOR=PASS")
    print("positive=1 bounded=1 category_guard=1 fallback=2 negative=4 llm_calls=0 round_trips=0")
    return 0
if __name__=="__main__": raise SystemExit(main())
