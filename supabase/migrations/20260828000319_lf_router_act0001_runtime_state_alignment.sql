update public.lf_activos
set runtime_estado='RUNTIME_OPERATIVO',
    updated_by_execution_id='EXEC-GOV-ROUTER-ACT0001-20260827-001',
    updated_at=now(),
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'runtime_state_evidence','public.lf_router_resolve_v1 exists and passed canonical E2E routing cases on 2026-08-27',
      'runtime_scope','ROUTER_RESOLUTION_ONLY; downstream operation executors remain governed by their own contracts'
    )
where codigo_activo='ACT-0001';
