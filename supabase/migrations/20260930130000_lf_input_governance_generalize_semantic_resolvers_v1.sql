-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-3 (PAULO-168) · dirección #19445 · evidencia #19438
-- Generaliza los resolvedores semánticos del Curator: quita las 9 condiciones en duro
-- "v_screen_code like 'B2B-%'" y acepta transiciones gobernadas (con decisión de origen)
-- aunque no exista la regla de registro. Aplica a:
--   programacion.fn_input_governance_semantic_probe_v3            (usada por bootstrap_classify_v2)
--   programacion.fn_input_governance_semantic_probe_v3_cached_v1  (usada por bootstrap_classify_v2_cached_v2)
-- Método: reescritura determinista de la definición vigente, fijada por md5. Si la función
-- cambió desde la prueba, la migración falla sin tocar nada (fail-closed).
-- Prueba con ROLLBACK (2026-09-30, #19438): 13 pantallas x 47 familias; 0 regresiones;
-- 11 familias-pantalla mejoran, todas con fuente canónica verificable.
begin;

do $n3$
declare
  f text;
  expected_md5 jsonb := jsonb_build_object(
    'fn_input_governance_semantic_probe_v3',           '2ef2ab5565fc80a1302762ff3a77f4a5',
    'fn_input_governance_semantic_probe_v3_cached_v1', '98f12c3c4c20e10155945d06dc2848bd');
  old_prefix text := 'v_screen_code like ''B2B-%''';
  old_trans  text := 'if v_story_source_count>0 and v_rule_count>0 and v_unresolved_count_b2b=0';
  new_trans  text := 'if v_story_source_count>0 and (v_rule_count>0 or v_missing_source_count=0) and v_unresolved_count_b2b=0';
  d text;
  n_prefix int;
  n_trans int;
begin
  foreach f in array array['fn_input_governance_semantic_probe_v3','fn_input_governance_semantic_probe_v3_cached_v1'] loop
    d := pg_get_functiondef(('programacion.'||f)::regproc);
    if md5(d) <> expected_md5->>f then
      raise exception 'N3_SOURCE_DRIFT:%:% (esperado %)', f, md5(d), expected_md5->>f;
    end if;
    n_prefix := (length(d) - length(replace(d, old_prefix, ''))) / length(old_prefix);
    n_trans  := (length(d) - length(replace(d, old_trans, ''))) / length(old_trans);
    if n_prefix <> 9 or n_trans <> 1 then
      raise exception 'N3_UNEXPECTED_OCCURRENCES:%:prefix=%:trans=%', f, n_prefix, n_trans;
    end if;
    d := replace(replace(d, old_prefix, 'true'), old_trans, new_trans);
    execute d;
    d := pg_get_functiondef(('programacion.'||f)::regproc);
    if position('like ''B2B-%''' in d) > 0 then
      raise exception 'N3_PREFIX_REMAINS:%', f;
    end if;
    if position(new_trans in d) = 0 then
      raise exception 'N3_TRANSITION_CONDITION_MISSING:%', f;
    end if;
  end loop;
end
$n3$;

commit;
