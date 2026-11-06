-- lf_selector_descriptor_resync_ui_architect_v1
-- Re-syncs the selector descriptor of PERFIL-UI-ARCHITECT, marked STALE_SOURCE_CHANGED after its governed
-- update (ACTUALIZACION_PERFIL_LF, PR #3650). A stale canonical descriptor makes the whole Router catalog
-- not ready (LF_PROFILE_SELECTOR_CATALOG_NOT_READY). Descriptor evidence was verified as literal text of the
-- current SKILL.md (blob eddf372e, last changed at commit f09b2399). No runtime, SKILL or contract change.
DO $resync$
DECLARE
  n integer;
  v jsonb;
BEGIN
  SELECT count(*) INTO n FROM public.lf_profile_selection_registry_v1 WHERE profile_code='PERFIL-UI-ARCHITECT' AND descriptor_status='STALE_SOURCE_CHANGED';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_PRESTATE_DRIFT:PERFIL-UI-ARCHITECT:%', n; END IF;
  SELECT count(*) INTO n FROM public.lf_activos WHERE codigo_activo='PERFIL-UI-ARCHITECT' AND tipo_activo='PERFIL' AND archived_at IS NULL AND raw_payload->>'skill_sha'='eddf372e2bb8c1f7dd8cc7dd7b1b0cb007024da8' AND metadata->>'entrypoint_sha'='eddf372e2bb8c1f7dd8cc7dd7b1b0cb007024da8';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_SOURCE_SHA_MISMATCH:PERFIL-UI-ARCHITECT:%', n; END IF;
  v := public.lf_profile_selector_descriptor_sync_v1(
    'PERFIL-UI-ARCHITECT',
    '{"schema_version": "LF_PROFILE_SELECTION_DESCRIPTOR_V1", "description": "Convert product and UX decisions into executable UI specifications. Existing-screen findings become concrete remediation actions. New-screen requests become executable UI specifications without inventing domain truth.", "selection_evidence": [{"kind": "PURPOSE", "source_section": "Purpose", "value": "Convert product and UX decisions into executable UI specifications. Existing-screen findings become concrete remediation actions. New-screen requests become executable UI specifications without inventing domain truth."}, {"kind": "OWNERSHIP", "source_section": "New-screen invariants", "value": "Keep domain truth from upstream profiles intact; UI owns presentation, hierarchy, components, states, tokens and responsive behavior, not financial/legal/privacy truth."}, {"kind": "BOUNDARY", "source_section": "Traceability and lifecycle", "value": "Candidate remediation evidence lives under `profiles/ui_architect/evals/<remediation_lot>/`.\nFuture profile writes require `ACTUALIZACION_PERFIL_LF` bound to `PERFIL-UI-ARCHITECT` before the first GitHub write.\nRuntime enablement, `VALIDATED`, production promotion, and automatic promotion remain blocked unless separately governed and authorized."}]}'::jsonb,
    'GITHUB_SKILL',
    'github://cristhianlujan/claude-persona-lf-patch@f09b239941ecd91a65bef198b8041790c9997213/profiles/ui_architect/SKILL.md',
    'eddf372e2bb8c1f7dd8cc7dd7b1b0cb007024da8',
    'SELECTOR-DESCRIPTOR-RESYNC-20261105');
  IF v->>'outcome' <> 'SYNCED' THEN RAISE EXCEPTION 'SELECTOR_RESYNC_FAILED:%', v; END IF;

  v := public.lf_profile_selector_catalog_v1();
  IF coalesce((v->>'all_canonical_descriptors_complete')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'SELECTOR_RESYNC_CATALOG_STILL_INCOMPLETE:%', left(v::text,500);
  END IF;
END
$resync$;
