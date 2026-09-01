#!/usr/bin/env python3
from __future__ import annotations
from learning_read_only_context_selector_v1 import BindingSpec, LearningSelectionError, select_read_only_context

NEG_IDS=(
 "f67ffccd-e710-41f4-ae8c-eb5579227fc7",
 "8b744f07-75f6-4332-9df5-12e7c6914bf1",
 "02bcfdd4-6859-4d56-9fbc-02af0ddf65b5",
 "a789f419-b05f-4eba-af99-015bd56d24d5",
 "5500178a-d503-476c-be77-c99223b4d90c",
)

def must_fail(fn,contains=None):
    try: fn()
    except LearningSelectionError as exc:
        if contains and contains not in str(exc): raise SystemExit(f"FAIL wrong error {exc}")
        return
    raise SystemExit("FAIL expected LearningSelectionError")

def row(kb_id: str, *, category: str = "COMPETENCIA", grounded: str = "GROUNDED", ready: bool = True, summary: str | None = None):
    return {"kb_id":kb_id,"kb_category":category,"grounding_status":grounded,"consumer_ready":ready,"topic":f"topic-{kb_id}","summary":(f"summary-{kb_id}" if summary is None else summary),"source_url":f"https://example.test/{kb_id}","competitor":"fixture","quality_score":0.9}

def main() -> int:
    binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",NEG_IDS,5,6000)
    rows=[row(k) for k in NEG_IDS]+[row("kb-not-bound"),row("kb-stale",grounded="STALE"),row("kb-not-ready",ready=False)]
    out=select_read_only_context(rows,binding=binding)
    assert out["mode"]=="READ_ONLY" and out["selector"]=="DETERMINISTIC_EXACT_ID" and out["required_kb_category"]=="COMPETENCIA"
    assert out["llm_calls"]==0 and out["round_trips"]==0 and out["selected_count"]==5
    assert out["context_budget_pass"] is True and out["context_bytes"]<=out["context_budget_bytes"]
    assert [x["kb_id"] for x in out["selected"]]==list(NEG_IDS)
    assert all(x["kb_category"]=="COMPETENCIA" for x in out["selected"])
    category_rows=[row(k,category=("EDUCACION_FINANCIERA" if i==0 else "COMPETENCIA")) for i,k in enumerate(NEG_IDS)]
    wrong=select_read_only_context(category_rows,binding=binding)
    assert wrong["selected_count"]==4 and NEG_IDS[0] not in [x["kb_id"] for x in wrong["selected"]]
    empty=select_read_only_context([row("other")],binding=binding); assert empty["selected_count"]==0 and empty["fallback"]=="NO_COMPETITIVE_CONTEXT"
    big=select_read_only_context([row(k,summary="X"*2500) for k in NEG_IDS],binding=binding)
    assert big["selected_count"]==2 and big["skipped_oversize_count"]>=1 and big["context_budget_pass"] is True
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("","NEGOCIACION_DEUDA",NEG_IDS)),"EXACT_CONSUMER_BINDING_REQUIRED")
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","",NEG_IDS)),"EXACT_CONSUMER_BINDING_REQUIRED")
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",())),"SOURCE_LEARNING_IDS_REQUIRED")
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",NEG_IDS,6)),"MAX_EVIDENCE_REFS_OUT_OF_BOUNDS")
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",NEG_IDS,5,100)),"CONTEXT_BUDGET_BYTES_OUT_OF_BOUNDS")
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-UNBOUND-LF","NEGOCIACION_DEUDA",NEG_IDS)),"EXACT_GOVERNED_CONSUMER_BINDING_REQUIRED")
    mutated=("00000000-0000-0000-0000-000000000000",)+NEG_IDS[1:]
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",mutated)),"SOURCE_LEARNING_IDS_NOT_EXACT_GOVERNED_BINDING")
    must_fail(lambda:select_read_only_context(rows,binding=BindingSpec("PERFIL-PRODUCT-DIRECTOR-LF","NEGOCIACION_DEUDA",NEG_IDS,5,5000)),"BINDING_CONTEXT_BUDGET_MISMATCH")
    print("LEARNING_READ_ONLY_CONTEXT_SELECTOR=PASS")
    print("positive=1 bounded_count=1 bounded_bytes=1 exact_binding=1 category_guard=1 fallback=1 negative=8 llm_calls=0 round_trips=0")
    return 0
if __name__=="__main__": raise SystemExit(main())
