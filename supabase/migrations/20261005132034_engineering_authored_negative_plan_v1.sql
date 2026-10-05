-- Los checkpoints de verificacion negativa sin consultas declaradas (porque prueban un objeto que crea un
-- checkpoint anterior de la misma unidad) quedaban bloqueados y obligaban a intervencion manual.
-- Cambio transversal en execution_packet_from_spec_v1: si el checkpoint es VERIFY_QUERY_ONCE, no tiene consultas y
-- tiene predecesores en la unidad, el packet es READY con plan EXECUTE_AUTHORED_NEGATIVE_CASES: un solo DO con
-- ROLLBACK forzado, un control positivo que debe ser aceptado y al menos un negativo rechazado por clausula.
-- Si el control es rechazado -> CONTRADICTION (el entregable no funciona). Sin predecesores sigue bloqueado.
-- Probado con rollback sobre 388 checkpoints pendientes: solo cambian 6 negativos (BLOCK -> READY con plan autorado).
-- Guarda: aborta si la funcion cambio respecto a la version probada, o si un ancla no es unica.
DO $mig$
DECLARE
  d text;
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1')
     IS DISTINCT FROM '8951181d1861b0677e78b6d7cf191e99' THEN
    RAISE EXCEPTION 'execution_packet_from_spec_v1 cambio desde la version probada; reprobar antes de aplicar';
  END IF;

  CREATE FUNCTION pg_temp.rep(src text, o text, n text) RETURNS text LANGUAGE plpgsql AS $r$
  BEGIN
    IF (length(src)-length(replace(src,o,'')))/greatest(length(o),1) <> 1 THEN
      RAISE EXCEPTION 'ancla no unica o ausente: %', left(o,70);
    END IF;
    RETURN replace(src,o,n);
  END $r$;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname='fn_engineering_execution_packet_from_spec_v1';
  d := pg_temp.rep(d, $o$lower(coalesce(p_action_spec->>'checkpoint_title','')) title_l,$o$,
$n$lower(coalesce(p_action_spec->>'checkpoint_title','')) title_l,
    exists(
      select 1
      from programacion.engineering_plan_units pu
      join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
      join programacion.engineering_work_checkpoints cur on cur.work_item_id=pu.work_item_id and cur.checkpoint_code=p_checkpoint_code
      where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and c.sequence_no<cur.sequence_no
    ) has_predecessor,$n$);
  d := pg_temp.rep(d, $o$when action_kind='VERIFY_QUERY_ONCE' and not has_verification then 'BLOCK_SPEC_INCOMPLETE'$o$,
$n$when action_kind='VERIFY_QUERY_ONCE' and not has_verification and not has_predecessor then 'BLOCK_SPEC_INCOMPLETE'$n$);
  d := pg_temp.rep(d, $o$(action_kind='VERIFY_QUERY_ONCE' and not effective_material)) and not has_verification$o$,
$n$(action_kind='VERIFY_QUERY_ONCE' and not effective_material and not has_predecessor)) and not has_verification$n$);
  d := pg_temp.rep(d, $o$when has_verification then 'DECLARED_QUERY_READBACK'$o$,
$n$when has_verification then 'DECLARED_QUERY_READBACK'
    when action_kind='VERIFY_QUERY_ONCE' and has_predecessor then 'AUTHORED_NEGATIVE_WITH_POSITIVE_CONTROL'$n$);
  d := pg_temp.rep(d, $o$when not effective_material then coalesce((select jsonb_agg($o$,
$n$when action_kind='VERIFY_QUERY_ONCE' and not has_verification and has_predecessor then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation','EXECUTE_AUTHORED_NEGATIVE_CASES',
        'transaction','SINGLE_STATEMENT_DO_BLOCK_WITH_FORCED_ROLLBACK',
        'requires',jsonb_build_array('ONE_POSITIVE_CONTROL_MUST_BE_ACCEPTED','AT_LEAST_ONE_NEGATIVE_REJECTED_PER_CLAUSE_OF_CHECKPOINT_TITLE','TARGETS_ARE_OBJECTS_CREATED_BY_PRECEDING_CHECKPOINTS_OF_THE_SAME_UNIT','NO_PERSISTENT_MUTATION'),
        'on_control_rejected','CONTRADICTION_DELIVERABLE_NOT_FUNCTIONAL',
        'on_missing_target','MISSING_CANONICAL_OBJECT',
        'evidence_must_include',jsonb_build_array('control_result','negative_results','statement_sha256')),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when not effective_material then coalesce((select jsonb_agg($n$);
  EXECUTE d;
END
$mig$;
