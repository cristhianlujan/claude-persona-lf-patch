#!/usr/bin/env python3
"""Resolve fresh S26 Native Golden Run D preflight while preserving Run C evidence."""
from __future__ import annotations
import contextlib, io, json, sys
from pathlib import Path
import prepare_s26_native_golden_c as base
from profile_execution_contract import build_execution_contract
ROOT=Path(__file__).resolve().parents[3]
EVIDENCE=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_004'
TEMPLATE=EVIDENCE/'obligation_template.json'
OUT=EVIDENCE/'preflight_binding.json'
def main():
    template=json.loads(TEMPLATE.read_text(encoding='utf-8'))
    if template.get('run_revision')!='D': raise SystemExit('BLOCK_RUN_REVISION_NOT_D')
    old=sys.argv[:]; buf=io.StringIO()
    try:
        sys.argv=[str(Path(base.__file__)),'--template',str(TEMPLATE),'--output',str(EVIDENCE/'base_preflight.json')]
        with contextlib.redirect_stdout(buf): rc=base.main()
    finally: sys.argv=old
    if rc!=0: return rc
    r=json.loads(buf.getvalue())
    contract=build_execution_contract(run_id=r['execution_id'],profile_code=template['profile_code'],profile_version='resolved:'+r['profile_source_sha256'][:16],objective=template['objective'],authorized_scope=['screen:B2B-CARGA-001','artifact_sha256:'+r['visual_artifact_sha256'],'evidence:s26_native_golden_004'],current_gate=template['current_gate'],allowed_actions=['READ_INPUT','CONSUME_GOVERNED_CONTEXT','EVALUATE_UI','EMIT_FINDINGS','MATERIALIZE_EVIDENCE'],forbidden_actions=['MODIFY_PRODUCTION','MERGE_MAIN','ACQUIRE_MODEL_WEIGHTS','MODIFY_SHELL','SELF_AUTHORIZE_GOLDEN','SECOND_ADAPTER_LLM_CALL'],required_checks=['ROUTER','INPUT_GOVERNANCE','PROFILE_CONTRACT','CARD_RECEIPT_SAME_RUN','ADAPTER_RECEIPT_SAME_RUN','UI_ARCHITECT_VALIDATOR','DEPTH_GATE','SEMANTIC_OBLIGATION_COVERAGE','INDEPENDENT_QUALITY','LATENCY_OBSERVABLE','TOKEN_USAGE_STATUS','TRACEABILITY','NO_MODEL_WEIGHT_ACQUISITION'],required_evidence=['router','input_governance','visual_artifact','governed_context_receipt','card_receipt','adapter_receipt','profile_execution','ui_validator','depth_gate','semantic_manifest','independent_quality','native_metrics','traceability'],closure_conditions=['STRUCTURAL_PASS','GOVERNED_CONTEXT_PASS','DEPTH_PASS','SEMANTIC_OBLIGATIONS_PASS','INDEPENDENT_QUALITY_STRICT_PASS','LATENCY_OBSERVABLE_PASS','TOKEN_USAGE_STATUS_PASS','TRACEABILITY_PASS','NO_MODEL_WEIGHT_ACQUISITION','NO_P0_OPEN','READBACK_PASS'],input_governance_ref=template['input_governance_ref'],card_refs_and_hashes=[{'ref':template['card_ref'],'sha256':r['card_source_sha256']}],adapter_ref=f"{template['adapter_ref']}@sha256:{r['adapter_source_sha256']};binding_sha256:{r['adapter_binding_snapshot_sha256']}",context_fingerprint=r['context_fingerprint'],tool_permissions=['READ_GITHUB','READ_SUPABASE','READ_GOOGLE_DRIVE'],executor_mode='GPT_NATIVE')
    r.update(schema=template['preflight_schema'],run_revision='D',execution_contract=contract,execution_contract_sha256=contract['contract_sha256'],base_resolver='prepare_s26_native_golden_c.py',base_resolver_contract_rebound=True)
    rendered=json.dumps(r,ensure_ascii=False,indent=2,sort_keys=True)+'\n'
    OUT.write_text(rendered,encoding='utf-8')
    (EVIDENCE/'governed_context_receipt.json').write_text(json.dumps(r['governed_context_receipt'],ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    (EVIDENCE/'obligation_manifest.json').write_text(json.dumps(r['obligation_manifest'],ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(rendered,end=''); return 0
if __name__=='__main__': raise SystemExit(main())
