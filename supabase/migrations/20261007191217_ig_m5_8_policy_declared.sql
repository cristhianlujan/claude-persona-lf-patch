-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M5.8 / PAULO-073
-- POLICY_DECLARED: versioned gap policy for create / inherit / close.
-- Scope: programacion.contratos + transversal.decision_log only.
-- No runtime activation, no production authorization, no proposal canonicalization.

do $$
declare
  v_contract_id bigint;
  v_version_id bigint;
begin
  select c.id, c.version_id
    into v_contract_id, v_version_id
  from programacion.contratos c
  where c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined'
    and c.fail_closed
  order by c.version_id desc, c.id desc
  limit 1
  for update;

  if v_contract_id is null then
    raise exception 'BLOCK_M58_EXECUTION_CONTRACT_NOT_FOUND';
  end if;

  if (select especificacion->>'contract_revision'
      from programacion.contratos
      where id=v_contract_id) <> '1.6' then
    raise exception 'BLOCK_M58_EXECUTION_CONTRACT_PRECONDITION_DRIFT';
  end if;

  if exists (
    select 1
    from transversal.decision_log
    where adr='DEC-INPUT-GOV-GAP-POLICY-001'
  ) then
    raise exception 'BLOCK_M58_GAP_POLICY_ADR_ALREADY_EXISTS_REVALIDATE';
  end if;

  insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  values(
    'DEC-INPUT-GOV-GAP-POLICY-001',
    'Política determinística para crear, heredar y cerrar gaps de Input Governance',
    'M5.8 establece una política única para gap proposals. CREATE materializa una propuesta no canónica solo cuando el gap sigue abierto y no existe equivalente vigente. INHERIT reutiliza evidencia/propuesta vigente sin duplicarla cuando identidad, currentness y fingerprint permanecen compatibles. CLOSE conserva historial y solo cierra tras evidencia suficiente y validación independiente. La síntesis selecciona SINGLE_EXACT, BOUNDED_ALTERNATIVES o HOLD_FOR_EVIDENCE según la evidencia disponible. Antes de escalar se usa TARGETED_EVIDENCE_ACQUISITION; toda mutación canónica exige SAFE_CHANGE_ADMISSION. Si no corresponde cambio efectivo, el resultado es VERIFY_NO_CHANGE. Resultados permitidos: AUTOMATIZABLE, RECOMENDADA, REQUIERE_DECISION, UNKNOWN y VERIFY_NO_CHANGE.',
    'Evita gaps perdidos o duplicados, evita escalamiento humano prematuro y separa propuesta, evidencia, decisión y admisión de cambio.',
    'La política queda versionada en INPUT_GOVERNANCE_EXECUTION_CONTRACT. No autoriza promoción ni producción, no convierte propuestas en fuente canónica y no amplía la allowlist de escritura automática.',
    'vigente'
  );

  update programacion.contratos
  set especificacion = especificacion || jsonb_build_object(
        'contract_revision','1.7',
        'gap_policy_decision','DEC-INPUT-GOV-GAP-POLICY-001',
        'gap_policy_contract',jsonb_build_object(
          'schema_version','INPUT_GAP_POLICY_V1',
          'strategy_actions',jsonb_build_object(
            'CREATE',jsonb_build_object(
              'condition','OPEN_GAP_AND_NO_CURRENT_EQUIVALENT',
              'output','NON_CANONICAL_GAP_PROPOSAL',
              'duplicate_policy','DENY'
            ),
            'INHERIT',jsonb_build_object(
              'condition','CURRENT_EQUIVALENT_AND_IDENTITY_CURRENTNESS_FINGERPRINT_COMPATIBLE',
              'output','REUSE_CURRENT_EVIDENCE_OR_PROPOSAL',
              'duplicate_policy','DENY'
            ),
            'CLOSE',jsonb_build_object(
              'condition','SUFFICIENT_EVIDENCE_AND_INDEPENDENT_VALIDATION',
              'output','CLOSE_WITH_HISTORY_RETAINED',
              'delete_history',false
            )
          ),
          'dynamic_synthesis_modes',jsonb_build_array(
            'SINGLE_EXACT','BOUNDED_ALTERNATIVES','HOLD_FOR_EVIDENCE'
          ),
          'result_states',jsonb_build_array(
            'AUTOMATIZABLE','RECOMENDADA','REQUIERE_DECISION','UNKNOWN','VERIFY_NO_CHANGE'
          ),
          'targeted_evidence_before_escalation','TARGETED_EVIDENCE_ACQUISITION',
          'canonical_change_admission','SAFE_CHANGE_ADMISSION',
          'no_effective_change_result','VERIFY_NO_CHANGE',
          'owner_escalation','POSITIVE_OWNER_AUTHORITY_ONLY',
          'proposal_is_canonical_source',false,
          'automatic_canonicalization','DENY_BY_DEFAULT_EXPLICIT_SAFE_ALLOWLIST',
          'invariants',jsonb_build_array(
            'NO_GAP_LOSS',
            'NO_DUPLICATE_GAP_PROPOSALS',
            'HISTORY_RETAINED',
            'UNKNOWN_IS_EXPLICIT',
            'NO_OWNER_ESCALATION_BEFORE_TARGETED_EVIDENCE_UNLESS_OWNER_DECISION_IS_INTRINSICALLY_REQUIRED',
            'CANONICAL_WRITE_REQUIRES_SAFE_CHANGE_ADMISSION'
          )
        )
      )
  where id=v_contract_id
    and version_id=v_version_id
    and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and estado='defined'
    and fail_closed
    and especificacion->>'contract_revision'='1.6';

  if not found then
    raise exception 'BLOCK_M58_EXECUTION_CONTRACT_UPDATE_MISSED';
  end if;

  if (select especificacion->>'contract_revision'
      from programacion.contratos
      where id=v_contract_id) <> '1.7' then
    raise exception 'BLOCK_M58_REVISION_READBACK';
  end if;

  if (select especificacion#>>'{gap_policy_contract,schema_version}'
      from programacion.contratos
      where id=v_contract_id) <> 'INPUT_GAP_POLICY_V1' then
    raise exception 'BLOCK_M58_POLICY_SCHEMA_READBACK';
  end if;

  if (select especificacion#>>'{gap_policy_contract,targeted_evidence_before_escalation}'
      from programacion.contratos
      where id=v_contract_id) <> 'TARGETED_EVIDENCE_ACQUISITION' then
    raise exception 'BLOCK_M58_TARGETED_EVIDENCE_READBACK';
  end if;

  if (select especificacion#>>'{gap_policy_contract,canonical_change_admission}'
      from programacion.contratos
      where id=v_contract_id) <> 'SAFE_CHANGE_ADMISSION' then
    raise exception 'BLOCK_M58_SAFE_CHANGE_ADMISSION_READBACK';
  end if;

  if (select count(*)
      from transversal.decision_log
      where adr='DEC-INPUT-GOV-GAP-POLICY-001'
        and upper(coalesce(estado,'')) in ('VIGENTE','ACTIVE','ACTIVO')) <> 1 then
    raise exception 'BLOCK_M58_GAP_POLICY_ADR_READBACK';
  end if;
end $$;
