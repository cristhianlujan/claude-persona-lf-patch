-- Documentation-only adjustment approved for EJECUCION_ROUTER_LF step 4.
-- Preserve execution order, resolver, evidence, transitions and runtime behavior.
BEGIN;

DO $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.lf_operation_step_contracts
     SET purpose = 'Control de transición de ruta: valida determinísticamente el resultado sellado de Stage 2 y determina únicamente la siguiente transición autorizada.',
         notes = 'Nombre funcional: Control de transición de ruta. Este paso no vuelve a buscar, clasificar ni seleccionar rutas o perfiles. Verifica que la salida sellada de Stage 2 tenga una transición reconocida y permite continuar solo al siguiente paso autorizado, evitando saltos, omisiones o llamadas incorrectas. Si Stage 2 no devuelve una ruta válida/reconocida, bloquea la continuación. Si posteriormente ningún perfil cumple las condiciones, lo resuelve el selector semántico y sus validadores, no este paso. El invocador no puede suministrar route_result ni next_step: ambos se recuperan y resuelven en el servidor.',
         updated_at = now()
   WHERE operation_code = 'EJECUCION_ROUTER_LF'
     AND step_id = 'resolve_next_transition'
     AND step_order = 40
     AND contract_code = 'CONTRACT-EJECUCION-ROUTER-LF-v0.4'
     AND resolver_ref = 'public.lf_router_route_transition_resolve_v1'
     AND status = 'ACTIVE_ENFORCEMENT'
     AND purpose = 'Resolve the next governed Router state deterministically from the sealed Stage2 route result.'
     AND notes = 'The caller cannot supply route_result or next_step. Both are recovered and resolved server-side from this execution.';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RAISE EXCEPTION 'ROUTER_STEP4_DESCRIPTION_PRECONDITION_FAILED: expected one unchanged contract row, got %', v_updated;
  END IF;
END;
$$;

-- Ensure identity and runtime sequence remain unchanged.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_step_contracts
    WHERE operation_code = 'EJECUCION_ROUTER_LF'
      AND step_id = 'resolve_next_transition'
      AND step_order = 40
      AND execution_order = 40
      AND resolver_ref = 'public.lf_router_route_transition_resolve_v1'
      AND next_if_pass = 'DYNAMIC_FROM_TRANSITION_RESULT'
      AND next_if_blocked = 'RETURN_TO_ORCHESTRATOR'
      AND status = 'ACTIVE_ENFORCEMENT'
      AND notes LIKE 'Nombre funcional: Control de transición de ruta.%'
  ) THEN
    RAISE EXCEPTION 'ROUTER_STEP4_DESCRIPTION_POSTCHECK_FAILED';
  END IF;
END;
$$;

COMMIT;
