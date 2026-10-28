-- Solo se actualiza descriptor.description del selector semantico del reparador.
-- No modifica SKILL, contratos, selection_evidence, source_revision ni runtime.
BEGIN;
DO $only_description$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.lf_profile_selection_registry_v1
  WHERE profile_code = 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND descriptor_status = 'CURRENT'
    AND source_revision = '35bbadad5c76b7a4b42b695f01beefa30cd8f272'
    AND descriptor->>'description' = 'Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient repair that eliminates the failure class. By default the profile is read-only. When the Router-selected execution carries a valid governed repair authority for an explicitly allowed repair intent, it may implement the minimum sufficient in-scope repair, perform deterministic readback and return control to the Router. It never self-authorizes writes, broadens scope or promotes/activates the repaired asset.';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'SRCR_SELECTOR_DESCRIPTION_PRESTATE_DRIFT: %', v_count;
  END IF;

  UPDATE public.lf_profile_selection_registry_v1
     SET descriptor = jsonb_set(descriptor, '{description}', to_jsonb('Perfil responsable de diagnosticar, reparar, crear, actualizar y mejorar activos y perfiles de LF. Investiga las causas, determina los cambios necesarios y utiliza las operaciones existentes mediante la ruta gobernada del Router ACT-0001. No se autoautoriza escrituras, permisos, promocion ni activacion de runtime.'::text), false)
   WHERE profile_code = 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
     AND descriptor_status = 'CURRENT'
     AND source_revision = '35bbadad5c76b7a4b42b695f01beefa30cd8f272'
     AND descriptor->>'description' = 'Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient repair that eliminates the failure class. By default the profile is read-only. When the Router-selected execution carries a valid governed repair authority for an explicitly allowed repair intent, it may implement the minimum sufficient in-scope repair, perform deterministic readback and return control to the Router. It never self-authorizes writes, broadens scope or promotes/activates the repaired asset.';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'SRCR_SELECTOR_DESCRIPTION_UPDATE_COUNT_INVALID: %', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.lf_profile_selection_registry_v1
  WHERE profile_code = 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND descriptor_status = 'CURRENT'
    AND source_revision = '35bbadad5c76b7a4b42b695f01beefa30cd8f272'
    AND descriptor->>'description' = 'Perfil responsable de diagnosticar, reparar, crear, actualizar y mejorar activos y perfiles de LF. Investiga las causas, determina los cambios necesarios y utiliza las operaciones existentes mediante la ruta gobernada del Router ACT-0001. No se autoautoriza escrituras, permisos, promocion ni activacion de runtime.';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'SRCR_SELECTOR_DESCRIPTION_READBACK_FAILED: %', v_count;
  END IF;
END
$only_description$;
COMMIT;
