-- IG_CURATOR_VALIDATOR_REFACTOR_V2 M1.3 / PAULO-118
-- Git-first governance ADR only. No runtime/deploy/production change.

do $$
declare
  v_existing transversal.decision_log%rowtype;
  v_adr constant text := 'DEC-INPUT-GOV-VALIDATOR-CLAIMS-NOT-CONCLUSIONS-001';
  v_title constant text := 'Validator consume claims y referencias del Curator, no conclusiones como autoridad';
  v_decision constant text := 'El Validator puede consumir identidad, referencias, manifests, hashes y claims del Curator únicamente como candidatos, locators o bindings de integridad. MUST NOT usar severity, applicability, coverage, well_defined, readiness, rationale, blockers, semantic depth, proposal payload/confidence/stage impact o cualquier conclusión del Curator como verdad autoritativa o evidencia suficiente de PASS. Source refs, evidence refs y canonical targets deben re-resolverse contra autoridad actual con digest de readback. Un replay del mismo clasificador, resolver o grafo altamente correlacionado es consistency/equivalence check y no satisface independencia. curator_sha256 prueba identidad/integridad del output del Curator, no corrección.';
  v_reason constant text := 'INPUT_READINESS_CONTRACT 5.13 exige validator_independence_required, direct_source_readback_required, validator_re_resolves_source_refs y validator_source_readback_digests_required. M4.1 verificó alta correlación con Curator: validator_rebind_v1 17/17 dependencias programacion compartidas, validate_v2 29/31 y bootstrap_validate_v1 16/17.';
  v_impact constant text := 'Congela la frontera lógica M1.3 sin modificar runtime. Los caminos correlacionados actuales pueden servir para consistencia, rebind o equivalencia, pero no deben acreditarse como oracle semántico independiente. La implementación de oracle/entrypoint independiente queda para M4/M5 y capacidades transversales previstas por el plan.';
begin
  select * into v_existing
  from transversal.decision_log
  where adr=v_adr;

  if found then
    if v_existing.titulo is distinct from v_title
       or v_existing.decision is distinct from v_decision
       or v_existing.razon is distinct from v_reason
       or v_existing.impacto is distinct from v_impact
       or lower(coalesce(v_existing.estado,'')) is distinct from 'vigente'
    then
      raise exception 'INPUT_GOV_M1_3_ADR_DRIFT:%',v_adr;
    end if;
  else
    insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
    values(v_adr,v_title,v_decision,v_reason,v_impact,'vigente');
  end if;
end $$;
