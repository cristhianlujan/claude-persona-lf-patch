do $reconcile$
declare
  v_105 public.lf_operation_step_contracts%rowtype;
  v_110 public.lf_operation_step_contracts%rowtype;
begin
  select * into v_105
  from public.lf_operation_step_contracts
  where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=105 and step_id='restock_queue' and status='ACTIVO';
  if not found then raise exception 'ACT0058_STEP_105_BASELINE_MISSING'; end if;
  if v_105.mini_judge_code is distinct from 'MINI_JUDGE_ACT0058_RESTOCK'
     or v_105.pass_condition is distinct from '{"estado":"PENDIENTE","urls_insertadas":">=1"}'::jsonb
     or coalesce(v_105.fail_condition,'{}'::jsonb) is distinct from '{"NO_NEW_URLS":{"next_action":"SKIP_RESTOCK","execution_sql":"INSERT INTO lf_eventos (evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, origen) VALUES (''WARN'', ''PIPELINE'', ''ORQUESTACION_PIPELINE_LF'', ''restock_queue: 0 URLs nuevas encontradas'', ''MEDIA'', ''ORQUESTADOR'')"}}'::jsonb
  then raise exception 'ACT0058_STEP_105_BASELINE_DRIFT'; end if;

  select * into v_110
  from public.lf_operation_step_contracts
  where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=110 and step_id='failed_retry' and status='ACTIVO';
  if not found then raise exception 'ACT0058_STEP_110_BASELINE_MISSING'; end if;
  if v_110.mini_judge_code is distinct from 'MINI_JUDGE_ACT0058_RETRY'
     or coalesce(v_110.notes,'') <> 'Politica de reintento: maximo 3 intentos. Superado ese umbral, requiere intervencion manual.'
     or position('retry_count + 1 >= 3' in coalesce(v_110.execution_sql,''))=0
  then raise exception 'ACT0058_STEP_110_BASELINE_DRIFT'; end if;

  update public.lf_operation_step_contracts
  set pass_condition=jsonb_build_object(
        'RESTOCK_COMPLETED',jsonb_build_object('restock_attempted',true,'dedup_verified',true,'urls_insertadas','>=1'),
        'RESTOCK_NOOP_WARN',jsonb_build_object('restock_attempted',true,'dedup_verified',true,'urls_insertadas',0,'warn_recorded',true)
      ),
      fail_condition=jsonb_build_object('RESTOCK_EVIDENCE_MISSING',jsonb_build_object('restock_attempted',false,'or_dedup_unverified',true)),
      block_condition=jsonb_build_object('RESTOCK_EVIDENCE_MISSING',true),
      blocking_code='RESTOCK_GOVERNANCE_EVIDENCE_MISSING',
      notes='Canonical ACT-0058: fewer than 5 new URLs is WARN/no-op, not batch failure. Zero new URLs is valid only after governed restock attempt + dedup + WARN evidence.',
      updated_at=now()
  where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=105 and step_id='restock_queue' and status='ACTIVO';

  update public.lf_operation_step_contracts
  set purpose='Reintentar solo mientras retry_count < 3. Al alcanzar 3 intentos, marcar FAILED definitivo y continuar con la siguiente URL.',
      pass_condition=jsonb_build_object('RETRY_ALLOWED',jsonb_build_object('retry_count','<3','next_action','RETRY')),
      fail_condition=jsonb_build_object('RETRY_TERMINAL_FAILED',jsonb_build_object('retry_count','>=3','next_action','FAILED_CONTINUE_NEXT_URL')),
      block_condition=jsonb_build_object('RETRY_INVALID_AFTER_TERMINAL',jsonb_build_object('retry_count','>=3','next_action','RETRY')),
      blocking_code='MAX_RETRY_EXCEEDED',
      notes='Canonical ACT-0058: maximum 3 attempts. At retry_count >= 3 the URL is terminal FAILED and orchestration continues with the next URL; no fourth retry and no batch stop.',
      updated_at=now()
  where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=110 and step_id='failed_retry' and status='ACTIVO';

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=105
      and pass_condition ? 'RESTOCK_NOOP_WARN'
      and blocking_code='RESTOCK_GOVERNANCE_EVIDENCE_MISSING'
  ) then raise exception 'ACT0058_STEP_105_RECONCILIATION_FAILED'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='ORQUESTACION_PIPELINE_LF' and step_order=110
      and fail_condition ? 'RETRY_TERMINAL_FAILED'
      and block_condition ? 'RETRY_INVALID_AFTER_TERMINAL'
  ) then raise exception 'ACT0058_STEP_110_RECONCILIATION_FAILED'; end if;
end
$reconcile$;
