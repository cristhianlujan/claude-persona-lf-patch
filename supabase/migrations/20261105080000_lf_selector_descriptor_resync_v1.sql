-- lf_selector_descriptor_resync_v1
-- Re-syncs the selector descriptors of the two profiles marked STALE_SOURCE_CHANGED after their governed
-- updates (Reparador, Product Director). A stale canonical descriptor makes the whole Router catalog
-- not ready (LF_PROFILE_SELECTOR_CATALOG_NOT_READY), which blocks every profile selection.
-- Descriptor evidence was verified as literal text of the current SKILL.md of each profile.
-- Uses the existing sync function only; no runtime, SKILL or contract change.
DO $resync$
DECLARE
  n integer;
  v jsonb;
BEGIN
  SELECT count(*) INTO n FROM public.lf_profile_selection_registry_v1 WHERE profile_code='PERFIL-PRODUCT-DIRECTOR-LF' AND descriptor_status='STALE_SOURCE_CHANGED';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_PRESTATE_DRIFT:PERFIL-PRODUCT-DIRECTOR-LF:%', n; END IF;
  SELECT count(*) INTO n FROM public.lf_activos WHERE codigo_activo='PERFIL-PRODUCT-DIRECTOR-LF' AND tipo_activo='PERFIL' AND archived_at IS NULL AND raw_payload->>'skill_sha'='c9501679bdcd08d80cebf4a107a6a9a5282084d0' AND metadata->>'entrypoint_sha'='c9501679bdcd08d80cebf4a107a6a9a5282084d0';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_SOURCE_SHA_MISMATCH:PERFIL-PRODUCT-DIRECTOR-LF:%', n; END IF;
  v := public.lf_profile_selector_descriptor_sync_v1(
    'PERFIL-PRODUCT-DIRECTOR-LF',
    '{"schema_version": "LF_PROFILE_SELECTION_DESCRIPTOR_V1", "description": "Define product direction, scope, priority, functional trade-offs, acceptance criteria and handoff for LF deliverables. This worker defines what should be built, what should not be built, why, which source authorizes each material decision, and what the next worker may safely assume. It does not replace UX/UI, Copy, Legal, Tech, Data, QA or human approval.", "selection_evidence": [{"kind": "PURPOSE", "source_section": "Purpose", "value": "Define product direction, scope, priority, functional trade-offs, acceptance criteria and handoff for LF deliverables. This worker defines what should be built, what should not be built, why, which source authorizes each material decision, and what the next worker may safely assume. It does not replace UX/UI, Copy, Legal, Tech, Data, QA or human approval."}, {"kind": "ACTIVATION", "source_section": "Activation triggers", "value": "Use for product scope/priority decisions, MVP vs future scope, product conflicts, acceptance criteria, or translation of business intent into an operational brief."}, {"kind": "EXCLUSION", "source_section": "Do not activate when", "value": "- The task is only visual design, copywriting, legal approval, technical architecture, data modeling, financial advice or document audit.\n- A product decision is already closed and verified.\n- The request needs a specialist first and the product question is not defined."}]}'::jsonb,
    'GITHUB_SKILL',
    'github://cristhianlujan/claude-persona-lf-patch@2384d0f6e077310bdf6d3444f45c4357ee2dcf1c/profiles/product_director_lf/SKILL.md',
    'c9501679bdcd08d80cebf4a107a6a9a5282084d0',
    'SELECTOR-DESCRIPTOR-RESYNC-20261105');
  IF v->>'outcome' <> 'SYNCED' THEN RAISE EXCEPTION 'SELECTOR_RESYNC_FAILED:%', v; END IF;

  SELECT count(*) INTO n FROM public.lf_profile_selection_registry_v1 WHERE profile_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' AND descriptor_status='STALE_SOURCE_CHANGED';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_PRESTATE_DRIFT:PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF:%', n; END IF;
  SELECT count(*) INTO n FROM public.lf_activos WHERE codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' AND tipo_activo='PERFIL' AND archived_at IS NULL AND raw_payload->>'skill_sha'='9d5ee3218da43b8de46bbbd32be065a3f6827c79' AND metadata->>'entrypoint_sha'='9d5ee3218da43b8de46bbbd32be065a3f6827c79';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_SOURCE_SHA_MISMATCH:PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF:%', n; END IF;
  v := public.lf_profile_selector_descriptor_sync_v1(
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
    '{"schema_version": "LF_PROFILE_SELECTION_DESCRIPTOR_V1", "description": "Perfil responsable de diagnosticar, reparar, crear, actualizar y mejorar activos y perfiles de LF. Investiga las causas, determina los cambios necesarios y utiliza las operaciones existentes mediante la ruta gobernada del Router ACT-0001. No se autoautoriza escrituras, permisos, promocion ni activacion de runtime.", "selection_evidence": [{"kind": "PURPOSE", "source_section": "Purpose", "value": "Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient, implementable repair specification that eliminates the failure class rather than the first plausible local fix."}, {"kind": "ACTIVATION", "source_section": "Activation", "value": "Use for recurrent failures, repeated local repairs, cross-run regressions, bypasses, replay/duplicate failures, partial-failure recovery defects, stale-state defects, authority/source contradictions, or incidents whose immediate cause is not sufficient to explain recurrence."}, {"kind": "ACTIVATION", "source_section": "Governed profile update skill invocation", "value": "When ACT-0001 selects this profile for an LF profile update request, the profile MAY select and invoke only `PROFILE_UPDATE_APPLY`, exclusively for operation `ACTUALIZACION_PERFIL_LF`. This is a governed skill invocation, not a direct invocation of another profile and not authorization to write or activate any asset."}, {"kind": "EXCLUSION", "source_section": "Activation", "value": "Do not use for simple deterministic defects whose cause and repair are already classified and covered by an existing EKB rule."}, {"kind": "BOUNDARY", "source_section": "Purpose", "value": "The profile designs and specifies the repair. By default it remains read-only. When the Router-selected execution carries a valid `repair_execution_authority` for an in-scope governed repair, the profile may also implement the minimum sufficient repair, perform required readback, and return control to the Router. It never self-authorizes writes, broadens scope, promotes/activates the repaired asset, or claims verification that was not observed."}]}'::jsonb,
    'GITHUB_SKILL',
    'github://cristhianlujan/claude-persona-lf-patch@36252592d31178984d5351d606b02609f332dbd2/profiles/systemic_root_cause_repair_lf/SKILL.md',
    '9d5ee3218da43b8de46bbbd32be065a3f6827c79',
    'SELECTOR-DESCRIPTOR-RESYNC-20261105');
  IF v->>'outcome' <> 'SYNCED' THEN RAISE EXCEPTION 'SELECTOR_RESYNC_FAILED:%', v; END IF;

  v := public.lf_profile_selector_catalog_v1();
  IF coalesce((v->>'all_canonical_descriptors_complete')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'SELECTOR_RESYNC_CATALOG_STILL_INCOMPLETE:%', left(v::text,500);
  END IF;
END
$resync$;
