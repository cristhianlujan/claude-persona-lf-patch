-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L0 · M1.A5 (PAULO-009)
-- Inconsistencia: INPUT_GOVERNANCE_EXECUTION_CONTRACT (version_id 19) declara la allowlist
-- de escritura canónica segura dos veces y con valores contradictorios:
--   especificacion.safe_canonical_write_allowlist                 = ["BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN"]  (la que lee el runtime: worker_spec*)
--   especificacion.remediation_loop.safe_canonical_write_allowlist = []                                        (nadie la lee)
--   especificacion.auto_canonicalization                           = DENY_BY_DEFAULT_EXPLICIT_SAFE_ALLOWLIST
--   especificacion.remediation_loop.automatic_canonicalization     = DENY
-- Autoridad: transversal.decision_log DEC-INPUT-GOV-SAFE-AUTOFIX-001 (vigente, posterior a
-- DEC-INPUT-GOV-SELF-REMEDIATE-001): DENY por defecto, solo allowlist explícita,
-- V1 autoriza únicamente BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN.
-- Corrección: una sola allowlist (top-level) y el mismo modo de auto-canonicalización.
-- Prueba con ROLLBACK (2026-09-30): worker_spec(51/58,'MANUAL') idéntico antes/después;
-- fn_input_readiness_run_is_current(266) sin cambio; 1 sola ocurrencia de la allowlist.
begin;

update programacion.contratos
   set especificacion = jsonb_set(
         especificacion #- '{remediation_loop,safe_canonical_write_allowlist}',
         '{remediation_loop,automatic_canonicalization}',
         '"DENY_BY_DEFAULT_EXPLICIT_SAFE_ALLOWLIST"')
 where contrato_codigo = 'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   and version_id = 19
   and especificacion->'remediation_loop' ? 'safe_canonical_write_allowlist';

do $conditions$
declare v jsonb;
begin
  select especificacion into v from programacion.contratos
   where contrato_codigo = 'INPUT_GOVERNANCE_EXECUTION_CONTRACT' and version_id = 19;
  if jsonb_array_length(jsonb_path_query_array(v, 'strict $.**.safe_canonical_write_allowlist')) <> 1 then
    raise exception 'M1A5_ALLOWLIST_NOT_SINGLE';
  end if;
  if v->'safe_canonical_write_allowlist' <> '["BIND_EXISTING_COMPONENT_EXPLICIT_TOKEN"]'::jsonb then
    raise exception 'M1A5_ALLOWLIST_VALUE_CHANGED';
  end if;
  if v->'remediation_loop'->>'automatic_canonicalization' is distinct from v->>'auto_canonicalization' then
    raise exception 'M1A5_AUTO_CANONICALIZATION_MISMATCH';
  end if;
end
$conditions$;

commit;
