-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M4.10 / PAULO-137
-- Checkpoint: ADJUDICATE_DIVERGENCES
-- Authority: DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001
-- No local override is created. In absence of exact PLAN_AUTHORITY/WAIVER_AUTHORITY,
-- each observed divergence is adjudicated HOLD_BLOCK.

do $m410$
declare
  v_adr constant text := 'DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001';
  v_suite constant text := '7469c5cb-745b-41aa-80d0-638c32965fa9';
  v_screen constant integer := 58;
  v_before_human bigint;
  v_after_human bigint;
  v_inserted integer;
begin
  if not exists (
    select 1
    from transversal.decision_log
    where adr=v_adr and estado='VIGENTE'
      and decision ilike '%Sin autoridad válida, el efecto dependiente queda HOLD/BLOCK%'
  ) then
    raise exception 'BLOCK_M410_M1_7_ADJUDICATION_AUTHORITY_MISSING';
  end if;

  if exists (
    select 1
    from private.lf_post_pase_waivers
    where active
      and expires_at > now()
      and uses_count < max_uses
      and (
        subject_ref ilike '%M4.10%'
        or subject_ref ilike '%AUDIT%'
        or subject_ref ilike '%RATE_LIMIT%'
        or subject_ref ilike '%VISUAL_EVIDENCE%'
      )
  ) then
    raise exception 'BLOCK_M410_EXACT_WAIVER_PRESENT_REQUIRES_WAIVER_EVALUATION';
  end if;

  select count(*) into v_before_human from programacion.human_decisions;

  insert into transversal.decision_log(adr,titulo,decision,razon,impacto,estado)
  values
  (
    'DEC-IG-M4.10-ADJ-AUDIT-20261007',
    'M4.10 adjudicación shadow — AUDIT',
    'HOLD_BLOCK. Divergencia screen=58 family=AUDIT current_coverage=MISSING oracle_classification=PARTIAL. No PLAN_AUTHORITY/WAIVER_AUTHORITY exacta válida observada; se aplica DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001. No cambia readiness ni autoriza promoción.',
    'Oracle: AUDIT_STORAGE_EXISTS_BUT_REFERENCED_AUDIT_RULE_REMAINS_NONFINAL_OR_PARTIAL. Fuentes: lf_client.security_events EXISTS; REG_AUD_004 CANDIDATO.',
    'Divergencia adjudicada como HOLD/BLOCK; consumidor no se autoautoriza.',
    'VIGENTE'
  ),
  (
    'DEC-IG-M4.10-ADJ-RATE-LIMIT-20261007',
    'M4.10 adjudicación shadow — RATE_LIMIT',
    'HOLD_BLOCK. Divergencia screen=58 family=RATE_LIMIT current_coverage=MISSING oracle_classification=PARTIAL. No PLAN_AUTHORITY/WAIVER_AUTHORITY exacta válida observada; se aplica DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001. No cambia readiness ni autoriza promoción.',
    'Oracle: CANONICAL_CLIENT_OTP_RATE_POLICY_RESOLVED_BUT_MULTI_DNI_BASELINE_PENDING. Fuentes: REG_RATE_003; RATE-CLIENT-OTP-PHONE-CROSSSESSION; REG_RISK_PHONE_MULTI_DNI_001 PENDING_BASELINE.',
    'Divergencia adjudicada como HOLD/BLOCK; consumidor no se autoautoriza.',
    'VIGENTE'
  ),
  (
    'DEC-IG-M4.10-ADJ-VISUAL-EVIDENCE-20261007',
    'M4.10 adjudicación shadow — VISUAL_EVIDENCE',
    'HOLD_BLOCK. Divergencia screen=58 family=VISUAL_EVIDENCE current_coverage=MISSING oracle_classification=PARTIAL. No PLAN_AUTHORITY/WAIVER_AUTHORITY exacta válida observada; se aplica DEC-INPUT-GOV-M1.7-DIVERGENCE-ADJUDICATION-001. No cambia readiness ni autoriza promoción.',
    'Oracle: VISUAL_DECISIONS_EXIST_BUT_CURRENT_SCREEN_ARTIFACT_IS_UNRESOLVED. Fuentes: VD_CLIENT_AUTH_FULL_CANVAS_SURFACE_20260820; VD_CLIENT_AUTH_MOCKUP_FRAME_20260819; VD_CLIENT_AUTH_WATERMARK_20260819.',
    'Divergencia adjudicada como HOLD/BLOCK; consumidor no se autoautoriza.',
    'VIGENTE'
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;

  select count(*) into v_after_human from programacion.human_decisions;
  if v_after_human is distinct from v_before_human then
    raise exception 'BLOCK_M410_HUMAN_DECISION_FABRICATION';
  end if;

  if (
    select count(*)
    from transversal.decision_log
    where adr in (
      'DEC-IG-M4.10-ADJ-AUDIT-20261007',
      'DEC-IG-M4.10-ADJ-RATE-LIMIT-20261007',
      'DEC-IG-M4.10-ADJ-VISUAL-EVIDENCE-20261007'
    )
      and estado='VIGENTE'
      and decision like 'HOLD_BLOCK.%'
  ) <> 3 then
    raise exception 'BLOCK_M410_ADJUDICATION_READBACK';
  end if;

  if exists (
    select 1
    from transversal.decision_log
    where adr in (
      'DEC-IG-M4.10-ADJ-AUDIT-20261007',
      'DEC-IG-M4.10-ADJ-RATE-LIMIT-20261007',
      'DEC-IG-M4.10-ADJ-VISUAL-EVIDENCE-20261007'
    )
      and (
        decision ilike '%authorize promotion%'
        or decision ilike '%promotion_authorized=true%'
      )
  ) then
    raise exception 'BLOCK_M410_ADJUDICATION_PROMOTION_SIDE_EFFECT';
  end if;
end
$m410$;
