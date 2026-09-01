#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
if str(HERE) not in sys.path: sys.path.insert(0,str(HERE))

from learning_profile_request_builder_v1 import GovernanceReceipt, LearningRequestBuildError, build_profile_request
from learning_read_only_context_selector_v1 import BindingSpec

PD="PERFIL-PRODUCT-DIRECTOR-LF"
CAP="PAYMENT_NO_ADEUDO"
IDS=("f67ffccd-e710-41f4-ae8c-eb5579227fc7","8b744f07-75f6-4332-9df5-12e7c6914bf1","02bcfdd4-6859-4d56-9fbc-02af0ddf65b5")


def row(kb_id: str, *, ready=True, grounded="GROUNDED", category="COMPETENCIA"):
    return {"kb_id":kb_id,"kb_category":category,"consumer_ready":ready,"grounding_status":grounded,"topic":"constancia","summary":"evidencia acotada","source_url":"https://example.invalid/evidence","competitor":"COMPETITOR","quality_score":9.0}


def governed_binding():
    return BindingSpec(consumer_id=PD,capability_id=CAP,source_learning_ids=IDS,max_evidence_refs=3,context_budget_bytes=6000)


def current_receipt():
    return GovernanceReceipt(current_run_id=212,pantalla_id=2,screen_code="ONB_002",contract_revision="5.12",current=True)


def expect_fail(code: str, fn):
    try: fn()
    except LearningRequestBuildError as exc:
        if code not in str(exc): raise AssertionError(f"expected {code}, got {exc}")
        return
    raise AssertionError(f"expected failure {code}")


def main():
    rows=[row(x) for x in IDS]+[row("00000000-0000-0000-0000-000000000000")]
    result=build_profile_request(rows,profile_code=PD,task_intent="Definir dirección de producto usando solo evidencia autorizada",explicit_constraints=["No inventar claims","No dar asesoría financiera individual"],binding=governed_binding(),governance=current_receipt(),provenance={"router":"ACT-0001","adapter":"ADAPTER_LF_SHELL_PROFILE"})
    assert result["mode"]=="READ_ONLY"
    assert result["profile_code"]==PD
    assert result["context_selected_count"]==3
    assert result["context_bytes"]<=result["context_budget_bytes"]
    assert result["input_budget_pass"] is True
    assert result["llm_calls_for_materialization"]==0 and result["round_trips_for_materialization"]==0
    assert result["enqueue_performed"] is False and result["writes_performed"] is False
    payload=json.loads(result["input_literal"])
    assert payload["input_governance"]["current"] is True
    assert payload["input_governance"]["current_run_id"]==212
    assert payload["input_governance"]["governance_consumer"]=="CONTEXT_PACK"
    assert payload["learning_context"]["selected_count"]==3
    assert all(x["kb_id"] in IDS for x in payload["learning_context"]["selected"])
    assert payload["learning_selection"]["automatic_impact"] is False
    expect_fail("PROFILE_CONSUMER_EXACT_BINDING_REQUIRED",lambda:build_profile_request(rows,profile_code="PERFIL-UI-ARCHITECT",task_intent="x",explicit_constraints=[],binding=governed_binding(),governance=current_receipt()))
    expect_fail("INPUT_GOVERNANCE_RECEIPT_NOT_CURRENT",lambda:build_profile_request(rows,profile_code=PD,task_intent="x",explicit_constraints=[],binding=governed_binding(),governance=GovernanceReceipt(current_run_id=212,pantalla_id=2,screen_code="ONB_002",contract_revision="5.12",current=False)))
    expect_fail("CURRENT_INPUT_GOVERNANCE_RUN_REQUIRED",lambda:build_profile_request(rows,profile_code=PD,task_intent="x",explicit_constraints=[],binding=governed_binding(),governance=GovernanceReceipt(current_run_id=0,pantalla_id=2,screen_code="ONB_002",contract_revision="5.12",current=True)))
    expect_fail("INPUT_GOVERNANCE_CONSUMER_MISMATCH",lambda:build_profile_request(rows,profile_code=PD,task_intent="x",explicit_constraints=[],binding=governed_binding(),governance=GovernanceReceipt(current_run_id=212,pantalla_id=2,screen_code="ONB_002",contract_revision="5.12",current=True,governance_consumer="PROFILE")))
    fallback=build_profile_request([row(x,ready=False) for x in IDS],profile_code=PD,task_intent="x",explicit_constraints=[],binding=governed_binding(),governance=current_receipt())
    fp=json.loads(fallback["input_literal"])
    assert fallback["context_selected_count"]==0
    assert fp["fallback"]=="RUN_PROFILE_WITHOUT_COMPETITIVE_CONTEXT"
    assert fp["learning_context"]["fallback"]=="NO_COMPETITIVE_CONTEXT"
    print("LEARNING_PROFILE_REQUEST_BUILDER=PASS")
    print("positive=1 negative=4 fallback=1 llm_calls=0 round_trips=0 writes=0 enqueue=0")
    return 0

if __name__=="__main__": raise SystemExit(main())
