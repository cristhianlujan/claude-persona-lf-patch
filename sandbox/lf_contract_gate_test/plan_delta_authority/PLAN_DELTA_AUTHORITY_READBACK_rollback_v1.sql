-- Exact rollback for SADM-PP-L6-025 producer materialization.
-- Not executed by the unit; retained as reversible evidence.

begin;

delete from public.lf_activo_relaciones
where fuente='sandbox/lf_contract_gate_test/plan_delta_authority/plan_delta_authority_contract_v1.json'
  and (
    (codigo_activo='PLAN_DELTA_AUTHORITY_READBACK_PRODUCER' and relacionado_codigo='LF_GOVERNANCE')
    or
    (codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD' and relacionado_codigo='PLAN_DELTA_AUTHORITY_READBACK_PRODUCER')
  );

delete from public.lf_activos
where codigo_activo='PLAN_DELTA_AUTHORITY_READBACK_PRODUCER';

drop function if exists public.fn_lf_plan_delta_authority_readback_v1(bigint,text,text,text);

commit;
