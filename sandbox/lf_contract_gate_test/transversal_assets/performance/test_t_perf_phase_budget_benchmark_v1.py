import asyncio
from performance_exact_source_benchmark_v1 import benchmark_exact_source,validate_exact_source_receipt
from timeout_phase_budget_policy_v1 import evaluate_timeout_request,execute_with_phase_budget
SOURCE_SHA="a"*64
POLICY={"schema_version":"lf-timeout-phase-budget-policy/v1","phase_budgets_ms":{"CONNECT":20,"READ":25,"INFERENCE":30,"JOB":35,"ORCHESTRATION":40},"min_benchmark_samples":3}
def test_policy():
    allowed=evaluate_timeout_request(phase="READ",requested_timeout_ms=25,policy=POLICY,exact_source_sha256=SOURCE_SHA);assert allowed["decision"]=="ALLOWED_WITHIN_BUDGET"
    blind=evaluate_timeout_request(phase="READ",requested_timeout_ms=50,policy=POLICY,exact_source_sha256=SOURCE_SHA);assert blind["decision"]=="BLOCKED_BLIND_TIMEOUT_EXTENSION" and blind["reason_code"]=="BENCHMARK_RECEIPT_MISSING"
    unknown=evaluate_timeout_request(phase="OTHER",requested_timeout_ms=1,policy=POLICY,exact_source_sha256=SOURCE_SHA);assert unknown["decision"]=="BLOCKED" and unknown["reason_code"]=="UNKNOWN_PHASE"
def test_benchmark():
    receipt=benchmark_exact_source(exact_source_sha256=SOURCE_SHA,source_ref="fixture://t-perf-source",phases={"CONNECT":lambda:sum(range(30)),"READ":lambda:sum(range(60)),"INFERENCE":lambda:sum(range(90)),"JOB":lambda:sum(range(120)),"ORCHESTRATION":lambda:sum(range(150))},sample_count=5,warmup_count=1)
    ok,code=validate_exact_source_receipt(receipt,exact_source_sha256=SOURCE_SHA,required_phases={"CONNECT","READ","INFERENCE","JOB","ORCHESTRATION"});assert ok is True and code=="BENCHMARK_EXACT_SOURCE_VALID"
    for phase in receipt["phases"].values(): assert set(("p50_ms","p95_ms","p99_ms")).issubset(phase) and phase["call_count"]==phase["sample_count"]==5
    evidence_bound=evaluate_timeout_request(phase="READ",requested_timeout_ms=max(50,int(receipt["phases"]["READ"]["p99_ms"])+2),policy=POLICY,exact_source_sha256=SOURCE_SHA,benchmark_receipt=receipt)
    assert evidence_bound["decision"]=="EVIDENCE_BOUND_EXTENSION_CANDIDATE" and evidence_bound["approval_required"] is True and evidence_bound["mutates_timeout"] is False
    return receipt
async def test_real_cancellation():
    async def slow_call(): await asyncio.sleep(.08); return "UNEXPECTED"
    cancelled=False
    try: await execute_with_phase_budget(slow_call(),phase="CONNECT",policy=POLICY)
    except asyncio.TimeoutError: cancelled=True
    assert cancelled is True
def main():
    test_policy();test_benchmark();asyncio.run(test_real_cancellation());print("PASS_T_PERF_PHASE_BUDGET_BENCHMARK_V1 checks=7")
if __name__=="__main__": main()
