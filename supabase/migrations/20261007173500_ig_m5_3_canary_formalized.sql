-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.3 / CANARY_FORMALIZED
-- Formalizes the historical request-local canary and its mandatory rollback.
-- The historical canary was sandbox/candidate-only; this does not classify it as a functional failure.

do $migration$
declare
  v_event_id bigint;
begin
  if not exists (
    select 1
    from public.lf_eventos
    where entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M5.3.CANARY_FORMALIZED'
      and created_by_execution_id='CHATGPT-IG-M5-3-CANARY-FORMALIZED-20261007'
  ) then
    insert into public.lf_eventos(
      evento_tipo,
      entidad_tipo,
      entidad_codigo,
      descripcion,
      severidad,
      payload,
      origen,
      created_by_execution_id
    )
    values(
      'CONTROL_OPERATIVO',
      'PROGRAM_SOLUTION',
      'IG_CURATOR_VALIDATOR_REFACTOR_V2.M5.3.CANARY_FORMALIZED',
      'M5.3 formaliza el canary request-local histórico IG006/IG007. La reversión histórica fue el rollback obligatorio de un sandbox/candidato; el safety finalizer restauró el baseline. La corrección vigente integra el patrón en el contexto canónico request-local con identidad pantalla/version, SHA fail-closed y una sola construcción directa del grafo en el materializador.',
      'INFO',
      jsonb_build_object(
        'schema_version','IG_M5_3_CANARY_FORMALIZED_V1',
        'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'unit_code','M5.3',
        'checkpoint_code','CANARY_FORMALIZED',
        'historical_canary_forward','git://supabase/migrations/20260907023000_lf_input_governance_ig006_ig007_exact_canary_forward_v1.sql',
        'historical_canary_rollback','git://supabase/migrations/20260907023100_lf_input_governance_ig006_ig007_exact_canary_rollback_v1.sql',
        'historical_forward_commit','bb0b26038379173ad0719d64e5d41d103dccff21',
        'historical_rollback_commit','82f6c5c8cda7223bcbf3aaabec7f89929f414fd5',
        'safety_finalizer_fix_commit','36be112f2b40911c1ddd62a86343f2658972c4f4',
        'rollback_classification','MANDATORY_SANDBOX_ROLLBACK_NOT_FUNCTIONAL_FAILURE',
        'handoff_event_ids',jsonb_build_array(19258,19338),
        'corrected_by_migration','20261007173000_ig_m5_3_context_object',
        'corrected_merge_sha','0a14a71e7cd498cb07cf8b320af4a5f74350ab34',
        'corrected_invariants',jsonb_build_array(
          'REQUEST_LOCAL_CONTEXT',
          'PANTALLA_VERSION_IDENTITY_MATCH',
          'GRAPH_SHA256_FAIL_CLOSED',
          'ONE_DIRECT_GRAPH_BUILD_IN_CURATOR_MATERIALIZER'
        )
      ),
      'CHATGPT:IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'CHATGPT-IG-M5-3-CANARY-FORMALIZED-20261007'
    )
    returning id into v_event_id;
  else
    select id into v_event_id
    from public.lf_eventos
    where entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M5.3.CANARY_FORMALIZED'
      and created_by_execution_id='CHATGPT-IG-M5-3-CANARY-FORMALIZED-20261007'
    order by id desc
    limit 1;
  end if;

  if v_event_id is null then
    raise exception 'M5_3_CANARY_FORMALIZED_EVENT_NOT_MATERIALIZED';
  end if;

  if not exists (
    select 1
    from public.lf_eventos
    where id in (19258,19338)
    group by 1=1
    having count(*)=2
  ) then
    raise exception 'M5_3_CANARY_FORMALIZED_HANDOFF_EVIDENCE_MISSING';
  end if;
end;
$migration$;
