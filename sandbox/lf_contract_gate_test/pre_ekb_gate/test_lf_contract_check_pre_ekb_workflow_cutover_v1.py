#!/usr/bin/env python3
from pathlib import Path

p = Path(".github/workflows/lf-contract-check.yml")
text = p.read_text(encoding="utf-8")
start_marker = "      - name: Persist failed deterministic LF contract diagnostics through PRE_EKB_GATE\n"
end_marker = "      - name: Capture authenticated E.16 Actions inventory\n"
assert text.count(start_marker) == 1
assert text.count(end_marker) == 1
start = text.index(start_marker)
end = text.index(end_marker, start)
block = text[start:end]
consumer = "sandbox/lf_contract_gate_test/pre_ekb_gate/lf_contract_check_pre_ekb_consumer_v1.py"
assert block.count(consumer) == 1
for forbidden in ("public.lf_record_gate_checks_v1", "public.fn_lf_operation_reserve_execution_v1", "public.lf_pre_ekb_gate_consumer_v1", "LF_PRE_EKB_GATE_AUTOPERSIST_V1", "python3 - <<\'PY\'"):
    assert forbidden not in block, forbidden
for required in ("PGPASSWORD:", "LF_EXACT_SOURCE_SHA:", "LF_WORKFLOW_EVENT:", "LF_REPOSITORY:", "LF_RUN_ID:", "LF_RUN_ATTEMPT:", "LF_JOB_ID:", "--diagnostics-root .lf_gate_diagnostics/lf_contract_check"):
    assert required in block, required
print("PASS_LF_CONTRACT_PRE_EKB_WORKFLOW_CUTOVER checks=13")
