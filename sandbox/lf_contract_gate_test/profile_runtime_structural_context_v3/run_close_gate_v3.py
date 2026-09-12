#!/usr/bin/env python3
"""Executable close gate for PROFILE_RUNTIME P0 V3.

A report cannot become final merely because it narrates the anti-close question.
Closing is allowed only after work/report timing telemetry + next-execution readback +
EKB final readback + global remaining-work scan prove that no safe batch remains and
the anti-close answer is NO.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Any

ALLOWED_STOP_REASONS={
    'NO_SAFE_WORK_REMAINING',
    'NONDELEGABLE_AUTHORITY_ONLY',
    'EXECUTION_LIMIT_REACHED',
}

@dataclass(frozen=True)
class CloseDecision:
    can_close: bool
    reasons: tuple[str,...]
    required_action: str
    def to_dict(self): return asdict(self)

def _nonempty(value: Any) -> bool:
    return value is not None and str(value).strip() not in {'','NOT_OBSERVED','UNKNOWN'}

def _clock(value: Any):
    if not _nonempty(value): return None
    try: return datetime.strptime(str(value).strip(), '%H:%M:%S')
    except ValueError: return None

def evaluate_close_gate(report: dict) -> CloseDecision:
    reasons=[]
    telemetry=(
        'inicio_lima','work_end_at_lima','report_started_at_lima','fin_lima',
        'duracion_real','trabajo_activo','espera_neta','report_duration','asked_at_lima',
    )
    for field in telemetry:
        if not _nonempty(report.get(field)):
            reasons.append(f'MISSING_TELEMETRY:{field}')

    work_end=_clock(report.get('work_end_at_lima'))
    report_started=_clock(report.get('report_started_at_lima'))
    if work_end is None and _nonempty(report.get('work_end_at_lima')):
        reasons.append('INVALID_CLOCK:work_end_at_lima')
    if report_started is None and _nonempty(report.get('report_started_at_lima')):
        reasons.append('INVALID_CLOCK:report_started_at_lima')
    if work_end is not None and report_started is not None and report_started < work_end:
        reasons.append('REPORT_STARTED_BEFORE_WORK_END')

    if report.get('next_execution_readback_verified') is not True:
        reasons.append('NEXT_EXECUTION_READBACK_NOT_VERIFIED')
    if report.get('ekb_final_enrichment') != 'PASS':
        reasons.append('EKB_FINAL_ENRICHMENT_NOT_PASS')
    if report.get('ekb_readback_verified') is not True:
        reasons.append('EKB_FINAL_READBACK_NOT_VERIFIED')
    if report.get('global_remaining_work_scan') != 'PASS':
        reasons.append('GLOBAL_REMAINING_WORK_SCAN_NOT_PASS')

    answer=str(report.get('anti_close_answer','')).strip().upper()
    if answer in {'SI','SÍ','YES'}:
        reasons.append('ANTI_CLOSE_ANSWER_YES')
    elif answer not in {'NO'}:
        reasons.append('ANTI_CLOSE_ANSWER_INVALID')

    remaining=report.get('safe_work_remaining_count')
    if remaining != 0:
        reasons.append('SAFE_WORK_REMAINING_NONZERO_OR_UNKNOWN')

    next_batch=str(report.get('next_safe_batch','')).strip().upper()
    if next_batch not in {'NONE','N/A'}:
        reasons.append('NEXT_SAFE_BATCH_PRESENT')

    stop_reason=str(report.get('why_run_stopped','')).strip().upper()
    if stop_reason not in ALLOWED_STOP_REASONS:
        reasons.append('STOP_REASON_NOT_ALLOWED')
    if stop_reason=='EXECUTION_LIMIT_REACHED' and not _nonempty(report.get('execution_limit_evidence')):
        reasons.append('EXECUTION_LIMIT_EVIDENCE_MISSING')

    if reasons:
        action='EXECUTE_NEXT_SAFE_BATCH' if any(x in reasons for x in ('ANTI_CLOSE_ANSWER_YES','NEXT_SAFE_BATCH_PRESENT','SAFE_WORK_REMAINING_NONZERO_OR_UNKNOWN')) else 'REPAIR_CLOSE_EVIDENCE'
        return CloseDecision(False,tuple(reasons),action)
    return CloseDecision(True,(), 'FINAL_REPORT_ALLOWED')
