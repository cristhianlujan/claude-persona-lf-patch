-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · corrección de rendimiento de vigencia (source pack M8.1, evento #19618)
-- programacion.fn_input_readiness_run_is_current recalculaba el clasificador completo por familia
-- (fn_input_governance_bootstrap_classify_v2, que reconstruye el grafo canónico de la pantalla en cada llamada).
-- La corrige para construir el grafo una sola vez y usar fn_input_governance_bootstrap_classify_v2_cached_v2,
-- igual que fn_input_readiness_run_is_current_cached_v2. Nombre, firma, autoridad y semántica no cambian;
-- los 9 llamadores (Router, worker_spec, stage gate, context manifest, etc.) quedan corregidos sin tocarlos.
-- Prueba con ROLLBACK (2026-09-30): 13 pantallas, 611 familias, 0 diferencias de classifier_sha256 entre
-- classify_v2 y classify_v2_cached_v2; tiempo 100.4 s -> 3.5 s.
-- Método: reescritura determinista fijada por md5. Si la función cambió, falla sin tocar nada.
begin;

do $cur$
declare
  d text;
  expected_md5 constant text := 'b35220735b368e3b44e197d911cfff4f';
  old_decl constant text := '  v_expected_classifier jsonb;
begin';
  new_decl constant text := '  v_expected_classifier jsonb;
  v_current_graph jsonb;
begin';
  old_loop constant text := '    for v_assessment in';
  new_loop constant text := '    v_current_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_run.version_id);
    for v_assessment in';
  old_call constant text := 'programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,v_assessment.family_code,v_run.version_id)';
  new_call constant text := 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_pantalla_id,v_assessment.family_code,v_run.version_id,v_current_graph)';
  n_decl int; n_loop int; n_call int;
begin
  d := pg_get_functiondef('programacion.fn_input_readiness_run_is_current(bigint)'::regprocedure);
  if md5(d) <> expected_md5 then
    raise exception 'CURRENTNESS_SOURCE_DRIFT:% (esperado %)', md5(d), expected_md5;
  end if;
  n_decl := (length(d) - length(replace(d, old_decl, ''))) / length(old_decl);
  n_loop := (length(d) - length(replace(d, old_loop, ''))) / length(old_loop);
  n_call := (length(d) - length(replace(d, old_call, ''))) / length(old_call);
  if n_decl <> 1 or n_loop <> 1 or n_call <> 1 then
    raise exception 'CURRENTNESS_UNEXPECTED_OCCURRENCES:decl=%:loop=%:call=%', n_decl, n_loop, n_call;
  end if;
  d := replace(replace(replace(d, old_decl, new_decl), old_loop, new_loop), old_call, new_call);
  execute d;
  d := pg_get_functiondef('programacion.fn_input_readiness_run_is_current(bigint)'::regprocedure);
  if position(old_call in d) > 0 then raise exception 'CURRENTNESS_OLD_CALL_REMAINS'; end if;
  if position(new_call in d) = 0 then raise exception 'CURRENTNESS_NEW_CALL_MISSING'; end if;
end
$cur$;

commit;
