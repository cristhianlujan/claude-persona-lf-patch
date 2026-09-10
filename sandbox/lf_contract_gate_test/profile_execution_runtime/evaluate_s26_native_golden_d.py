#!/usr/bin/env python3
"""Evaluate fresh S26 Native Golden Run D up to the independent-quality boundary."""
from __future__ import annotations
import contextlib, io, json
from pathlib import Path
import evaluate_s26_native_golden_c as base
from profile_runtime_runner import _build_lf_adapter_invocations
ROOT=Path(__file__).resolve().parents[3]
EVIDENCE=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_004'
MATERIALIZATION_COMMIT='563f0b2a93d577884eb5dab689b98f9fc732baa7'
MATERIALIZATION_COMMIT_AT='2026-09-08T22:13:58+00:00'
PRODUCER_RUN_ID='CHATGPT-NATIVE-S26-N08D-GOLDEN-D-001'
def build_adapter_invocations(preflight):
    binding=json.loads((EVIDENCE/'router_adapter_binding_snapshot.json').read_text(encoding='utf-8'))
    capsule_path=ROOT/'adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml'; content=capsule_path.read_text(encoding='utf-8')
    request_stub={'execution_id':preflight['execution_id'],'profile_code':'PERFIL-UI-ARCHITECT','lf_adapter_sources':[{'adapter_code':binding['adapter_code'],'assurance_revision':binding['assurance_revision'],'binding_ref':'sandbox/lf_contract_gate_test/profile_execution_runtime/evidence/s26_native_golden_004/router_adapter_binding_snapshot.json','target_ref':binding['target_asset_code'],'ref':'adapters/lf_shell_profile_adapter/runtime/runtime_capsule.yaml','content':content,'capsule_char_count':len(content)}]}
    return _build_lf_adapter_invocations(request_stub)
def main():
    base.EVIDENCE=EVIDENCE; base.RAW_PATH=EVIDENCE/'raw_output.json'; base.INPUT_PATH=EVIDENCE/'input.txt'; base.GOVERNED_CONTEXT_PATH=EVIDENCE/'governed_context_receipt.json'; base.METRICS_PATH=EVIDENCE/'metrics_plan.json'; base.PREPARE=ROOT/'sandbox/lf_contract_gate_test/profile_execution_runtime/prepare_s26_native_golden_d.py'; base.MATERIALIZATION_COMMIT=MATERIALIZATION_COMMIT; base.MATERIALIZATION_COMMIT_AT=MATERIALIZATION_COMMIT_AT; base.PRODUCER_RUN_ID=PRODUCER_RUN_ID; base.build_adapter_invocations=build_adapter_invocations
    buf=io.StringIO()
    with contextlib.redirect_stdout(buf): rc=base.main()
    text=buf.getvalue()
    if rc!=0: print(text,end=''); return rc
    result=json.loads(text); result['schema']='S26_NATIVE_GOLDEN_D_EVALUATION_V1'; result['run_revision']='D'; result['producer_run_id']=PRODUCER_RUN_ID; result['materialization_commit_sha']=MATERIALIZATION_COMMIT; result['golden_eligible']=False; result['golden_declared']=False; result['next_gate']='INDEPENDENT_CHAT_CONTEXT'; result['blocking_codes']=['INDEPENDENT_QUALITY_REVIEW_NOT_EXECUTED']
    (EVIDENCE/'evaluation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8'); (EVIDENCE/'execution_receipt.json').write_text(json.dumps(result['execution_receipt'],ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8'); (EVIDENCE/'semantic_check_bundle.json').write_text(json.dumps(result['check_bundle'],ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(json.dumps({'status':result['status'],'execution_id':result['execution_id'],'run_revision':'D','ui_architect_validator':result['ui_architect_validator'],'depth_gate':result['depth_gate'],'semantic_checks_pending':result['semantic_checks_pending'],'execution_receipt_sha256':result['execution_receipt_sha256'],'check_bundle_sha256':result['check_bundle_sha256'],'context_fingerprint':result['context_fingerprint'],'next_gate':result['next_gate'],'golden_declared':False},ensure_ascii=False,indent=2,sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
