-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M1.A3 / PAULO-123
-- R16 Git-first candidate.
-- Registers the three owner-approved Input Governance 5.12 decisions in the
-- canonical decision registry and corrects only their normalized source state.
-- Historical decision/context/impact text is not rewritten.
-- No runtime/deploy/production activation.

do $$
declare
  v_execution_id constant text := 'CHATGPT-IG-CV-M1A3-R16-20261002';
  v_count integer;
begin
  -- Fail closed if the exact three source decisions are not in the expected prestate.
  select count(*) into v_count
  from public.lf_decisiones_gov
  where (
      (id_decision='DEC-INPUT-GOV-512-HUMAN-001' and decision_number=123 and estado_original='APROBADO_POR_OWNER')
      or (id_decision='DEC-INPUT-GOV-512-API-STAGE-HUMAN-001' and decision_number=127 and estado_original='OWNER_APPROVED')
      or (id_decision='DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001' and decision_number=128 and estado_original='OWNER_APPROVED')
    )
    and estado_normalizado='CANDIDATO_CONTROLADO';
  if v_count <> 3 then
    raise exception 'BLOCK_M1A3_SOURCE_PRESTATE_COUNT:%', v_count;
  end if;

  -- D-M1.3 requires all three to be absent from the canonical registry before migration.
  select count(*) into v_count
  from transversal.decision_log
  where adr in (
    'DEC-INPUT-GOV-512-HUMAN-001',
    'DEC-INPUT-GOV-512-API-STAGE-HUMAN-001',
    'DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001'
  );
  if v_count <> 0 then
    raise exception 'BLOCK_M1A3_CANONICAL_PREEXISTING_COUNT:%', v_count;
  end if;

  insert into transversal.decision_log(
    adr,
    titulo,
    decision,
    razon,
    impacto,
    estado
  )
  select
    g.id_decision,
    g.id_decision,
    g.decision,
    g.contexto,
    g.impacto,
    'VIGENTE'
  from public.lf_decisiones_gov g
  where g.id_decision in (
    'DEC-INPUT-GOV-512-HUMAN-001',
    'DEC-INPUT-GOV-512-API-STAGE-HUMAN-001',
    'DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001'
  )
  order by g.decision_number;

  get diagnostics v_count = row_count;
  if v_count <> 3 then
    raise exception 'BLOCK_M1A3_CANONICAL_INSERT_COUNT:%', v_count;
  end if;

  update public.lf_decisiones_gov
  set estado_normalizado='CANDIDATO_APROBADO_POR_OWNER',
      updated_by_execution_id=v_execution_id
  where id_decision in (
    'DEC-INPUT-GOV-512-HUMAN-001',
    'DEC-INPUT-GOV-512-API-STAGE-HUMAN-001',
    'DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001'
  )
    and estado_normalizado='CANDIDATO_CONTROLADO';

  get diagnostics v_count = row_count;
  if v_count <> 3 then
    raise exception 'BLOCK_M1A3_NORMALIZATION_UPDATE_COUNT:%', v_count;
  end if;

  -- Canonical registry must preserve the source decision/context/impact byte-for-byte.
  select count(*) into v_count
  from transversal.decision_log d
  join public.lf_decisiones_gov g on g.id_decision=d.adr
  where g.id_decision in (
    'DEC-INPUT-GOV-512-HUMAN-001',
    'DEC-INPUT-GOV-512-API-STAGE-HUMAN-001',
    'DEC-INPUT-GOV-512-STAGE-PARAM-AUTH-HUMAN-001'
  )
    and d.decision is not distinct from g.decision
    and d.razon is not distinct from g.contexto
    and d.impacto is not distinct from g.impacto
    and d.estado='VIGENTE'
    and g.estado_normalizado='CANDIDATO_APROBADO_POR_OWNER';
  if v_count <> 3 then
    raise exception 'BLOCK_M1A3_POST_READBACK_COUNT:%', v_count;
  end if;
end $$;
