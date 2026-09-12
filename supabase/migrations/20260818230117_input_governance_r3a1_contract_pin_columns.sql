alter table programacion.input_readiness_runs
  add column if not exists contract_revision text,
  add column if not exists contract_snapshot_sha256 text,
  add column if not exists invalidated_at timestamptz,
  add column if not exists invalidated_reason text,
  add column if not exists invalidated_by_run_id bigint;

alter table programacion.input_readiness_runs
  add constraint input_readiness_runs_invalidation_shape check (
    (invalidated_at is null and invalidated_reason is null and invalidated_by_run_id is null)
    or (invalidated_at is not null and invalidated_reason='TERMINAL_SUCCESSOR' and invalidated_by_run_id is not null)
  );

alter table programacion.input_readiness_runs
  add constraint input_readiness_runs_invalidated_by_run_fk
  foreign key (invalidated_by_run_id) references programacion.input_readiness_runs(id) on delete restrict;

alter table programacion.input_readiness_runs disable trigger trg_input_readiness_run_update;
do $$
declare
  v_contract jsonb;
  v_contract_sha text;
  v_contract_revision text;
begin
  select jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion),
         c.especificacion->>'contract_revision'
    into v_contract,v_contract_revision
  from programacion.contratos c
  where c.version_id=19 and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

  update programacion.input_readiness_runs r
  set contract_revision=x.rev,
      contract_snapshot_sha256=case when x.rev=v_contract_revision then v_contract_sha else null end
  from (
    select a.run_id,
           case when min(a.curator_evidence->>'contract_revision')=max(a.curator_evidence->>'contract_revision')
                then min(a.curator_evidence->>'contract_revision') end rev
    from programacion.input_family_assessments a
    group by a.run_id
  ) x
  where x.run_id=r.id and r.contract_revision is null;
end $$;
alter table programacion.input_readiness_runs enable trigger trg_input_readiness_run_update;