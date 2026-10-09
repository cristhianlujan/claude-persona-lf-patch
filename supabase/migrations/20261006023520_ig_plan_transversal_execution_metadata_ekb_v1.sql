
update public.lf_error_knowledge
set
  ultima_vez=now(),
  updated_at=now(),
  evidencia=concat_ws(E'\n',nullif(evidencia,''),
    '2026-10-05 plan materialization: IG_CURATOR_VALIDATOR_REFACTOR_V2 now has TRANSVERSAL_EXECUTION_DECLARATION_V1 inherited contract on 187/187 plan units. unit_metadata.transversal_execution_v1 is the per-checkpoint authority; no new column/table created.',
    'Readback: 15 checkpoint declarations total = 1 ACTIVE (M3.9/SHADOW_RUN CONTROL_EQUIVALENCE_JUDGE) + 14 DECLARED_ONLY across M4.4/M4.5/M4.7/M4.10/M8.8/M8.10(2)/M8.11/M9.3/M9.5/M9.7/M10.11/M10.13/N-6. DECLARED_ONLY returns legacy action with transversal_gate=DECLARED_NOT_ACTIVATED and cannot introduce a new block.',
    'Stale plan sanitation: M4.10 SHADOW_BY_MODULE false missing T-EQUIV removed -> missing=[]/missing_typed=[]; M8.8 false TIMEOUT_PHASE_BUDGET_POLICY missing removed while real nonblocking telemetry gap preserved.',
    'M3.9 structural route remains READY/PASS_CURRENT_ITEM with active T_EQUIV_SHADOW. M8.10 has both BENCH_VIA_TPERF and PHASE_BUDGET declarations.'
  ),
  validacion='PASS when 187/187 plan units inherit TRANSVERSAL_EXECUTION_DECLARATION_V1; every activated checkpoint routes from unit_metadata.transversal_execution_v1 rather than title; DECLARED_ONLY metadata does not alter legacy execution or block; M3.9 remains READY; multi-capability sequencing uses ONE_BY_ONE_REBOOTSTRAP; known false stale capability-missing entries are removed without deleting unrelated real gaps.'
where codigo='ENGINEERING-TRANSVERSAL-EXPLICIT-ROUTING-001';
