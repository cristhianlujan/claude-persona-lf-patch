#!/usr/bin/env python3
from __future__ import annotations
import math,time
from statistics import median
from typing import Any,Callable,Mapping
SCHEMA_VERSION="lf-performance-exact-source-benchmark-receipt/v1"
class BenchmarkError(ValueError): pass
def _percentile(values,q):
    if not values: raise BenchmarkError("NO_SAMPLES")
    ordered=sorted(values)
    if len(ordered)==1:return ordered[0]
    rank=(len(ordered)-1)*q;lo=math.floor(rank);hi=math.ceil(rank)
    if lo==hi:return ordered[lo]
    fraction=rank-lo;return ordered[lo]+(ordered[hi]-ordered[lo])*fraction
def benchmark_exact_source(*,exact_source_sha256,phases,sample_count=5,warmup_count=1,source_ref):
    if not isinstance(exact_source_sha256,str) or len(exact_source_sha256)!=64:raise BenchmarkError("INVALID_EXACT_SOURCE_SHA256")
    if not isinstance(source_ref,str) or not source_ref.strip():raise BenchmarkError("MISSING_SOURCE_REF")
    if isinstance(sample_count,bool) or not isinstance(sample_count,int) or sample_count<3:raise BenchmarkError("SAMPLE_COUNT_LT_3")
    if isinstance(warmup_count,bool) or not isinstance(warmup_count,int) or warmup_count<0:raise BenchmarkError("INVALID_WARMUP_COUNT")
    if not isinstance(phases,Mapping) or not phases:raise BenchmarkError("MISSING_PHASES")
    normalized={}
    for phase,fn in phases.items():
        if not isinstance(phase,str) or not phase.strip() or not callable(fn):raise BenchmarkError("INVALID_PHASE_CALLABLE")
        normalized[phase.strip().upper()]=fn
    results={}
    for phase in sorted(normalized):
        fn=normalized[phase]
        for _ in range(warmup_count):fn()
        samples=[]
        for _ in range(sample_count):
            started=time.perf_counter_ns();fn();samples.append((time.perf_counter_ns()-started)/1_000_000.0)
        results[phase]={"sample_count":sample_count,"call_count":sample_count,"warmup_count":warmup_count,"p50_ms":round(median(samples),6),"p95_ms":round(_percentile(samples,.95),6),"p99_ms":round(_percentile(samples,.99),6),"max_ms":round(max(samples),6)}
    return {"schema_version":SCHEMA_VERSION,"exact_source_sha256":exact_source_sha256,"source_ref":source_ref.strip(),"measurement_clock":"time.perf_counter_ns","one_call_per_sample":True,"phases":results}
def validate_exact_source_receipt(receipt,*,exact_source_sha256,required_phases,min_samples=3):
    if not isinstance(receipt,Mapping) or receipt.get("schema_version")!=SCHEMA_VERSION:return False,"BENCHMARK_RECEIPT_SCHEMA_INVALID"
    if receipt.get("exact_source_sha256")!=exact_source_sha256:return False,"BENCHMARK_SOURCE_MISMATCH"
    if receipt.get("one_call_per_sample") is not True:return False,"BENCHMARK_CALL_COUNT_CONTRACT_MISSING"
    phases=receipt.get("phases")
    if not isinstance(phases,Mapping):return False,"BENCHMARK_PHASES_INVALID"
    for phase in required_phases:
        item=phases.get(phase.upper())
        if not isinstance(item,Mapping):return False,f"BENCHMARK_REQUIRED_PHASE_MISSING:{phase.upper()}"
        count=item.get("sample_count")
        if isinstance(count,bool) or not isinstance(count,int) or count<min_samples:return False,f"BENCHMARK_SAMPLE_COUNT_INSUFFICIENT:{phase.upper()}"
        if item.get("call_count")!=count:return False,f"BENCHMARK_CALL_COUNT_MISMATCH:{phase.upper()}"
        for key in ("p50_ms","p95_ms","p99_ms"):
            value=item.get(key)
            if isinstance(value,bool) or not isinstance(value,(int,float)) or value<0:return False,f"BENCHMARK_PERCENTILE_INVALID:{phase.upper()}:{key}"
    return True,"BENCHMARK_EXACT_SOURCE_VALID"
