-- Lessons from M9.13 contract preflight, recorded without altering completion history.
DO $e$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M913-POSTPASE-SOURCEPACK-LEAK-001','IG-M913-INDEPENDENT-EVENT-SELF-CLAIM-001'))
 THEN RAISE EXCEPTION 'M913_EKB_PRESTATE_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,causa_raiz,prevencion,validacion,estado,evidencia,lote_origen,source_ref)
 VALUES
 ('IG-M913-POSTPASE-SOURCEPACK-LEAK-001','GOVERNANCE',
 'M9.13 SOURCE_PACK de evidencias aún exigía POST_PASE desactivado',
 'Aunque action_spec M9_EVIDENCE_BUNDLE ya usaba ledger IG, SOURCE_PACK y ruta DECLARED_ONLY todavía apuntaban a artefactos FINAL_EVIDENCE externos.',
 'Reconciliar action_spec, SOURCE_PACK, routing y governance simultáneamente; consumir consulta canónica del manifiesto SHA por unidad y retirar el handler externo.',
 'Git exacto BEGIN/ROLLBACK: consulta manifiesto=1; artefactos externos=0; routing externo ausente; bootstrap WAIT_DEPENDENCIES; 0 residuos.',
 'VERIFICADO','supabase://programacion.engineering_plan_units/M9.13; github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261012032000_ig_m913_ledger_independent_contract_v1.sql',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.engineering_plan_units M9.13'),
 ('IG-M913-INDEPENDENT-EVENT-SELF-CLAIM-001','ENGINEERING_VALIDATION',
 'READBACK_VERIFICADO no demuestra ejecutor independiente por autodeclaración',
 'fn_engineering_closure_event_v1 crea evento INDEPENDENT_READBACK con independent_identity=true sin identidad verificable de segundo ejecutor ni comparación del SHA manifest contra HANDOFF. M7.14 y M8.12 usaron ese patrón; su cierre histórico no se modifica aquí.',
 'Para M9.13 exigir artefacto y prueba por actor distinto, recomputación independiente del ledger, comparación SHA y cero divergencias; no aceptar flag self-reported ni cerrar por evento del mismo productor. Auditar patrón transversal en cierres anteriores.',
 'Contrato M9.13 requiere independent_executor_verified=true, manifest_parity_verified=true, discrepancy_count=0 y runner ejecutado; checkpoint queda PENDING hasta prueba real. Riesgo transversal sigue activo.',
 'ACTIVO','supabase://programacion.fn_engineering_closure_event_v1; programacion.engineering_work_checkpoints/M7_INDEPENDENT_READBACK+M8_INDEPENDENT_READBACK',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.fn_engineering_closure_event_v1');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M913-POSTPASE-SOURCEPACK-LEAK-001','IG-M913-INDEPENDENT-EVENT-SELF-CLAIM-001'))<>2
 THEN RAISE EXCEPTION 'M913_EKB_POSTWRITE_FAILED'; END IF;
END $e$;