-- LF Router ACT-0001: aliases en español para activos clave del inventario (v1).
-- Aditivo y reversible: solo agrega entradas a lf_activos.metadata->'aliases' (union, sin quitar nada).
-- No cambia funciones, permisos ni estados. Los aliases son pistas de busqueda, no autorizan nada.
-- El ensayo al final aborta la migracion si algun alias no se agrega o la busqueda no los encuentra.

DO $mig$
DECLARE
  v_updated integer;
  v_bad integer;
  v_case record;
  v_res jsonb;
BEGIN
  CREATE TEMP TABLE _alias_nuevos(codigo text PRIMARY KEY, alias text[]) ON COMMIT DROP;
  INSERT INTO _alias_nuevos(codigo, alias) VALUES
    ('SKILL-CREATING-INTEGRAL-USER-STORIES', ARRAY['historias de usuario','user stories','history de usuario','creador de historias']),
    ('ACT-0043', ARRAY['creador de skills','skill creator','crear skills']),
    ('ADAPTER-MARKETPLACE-LF-UX-20260531', ARRAY['adaptador ux marketplace','experiencia de usuario']),
    ('ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531', ARRAY['adaptador marketplace','confianza','experiencia del cliente','cx trust']),
    ('ADAPTER-LF-SHELL-PROFILE-20260827', ARRAY['adaptador shell perfil']),
    ('ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827', ARRAY['adaptador marca mockup render']),
    ('PERFIL-PRODUCT-DIRECTOR-LF', ARRAY['perfil director de producto','product director']),
    ('PERFIL-UI-ARCHITECT', ARRAY['perfil arquitecto de interfaz','ui']),
    ('PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531', ARRAY['perfil arquitecto de experiencia de usuario','ux']),
    ('PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531', ARRAY['perfil arquitecto de confianza','experiencia del cliente','cx']),
    ('PERFIL-QUALITY-PACK', ARRAY['perfil paquete de calidad','quality pack']),
    ('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF', ARRAY['perfil revisor de linaje de evidencia']),
    ('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF', ARRAY['perfil reparacion de causa raiz sistemica']),
    ('PERFIL-GAMIFICATION-SYSTEM-ARCHITECT', ARRAY['perfil gamificacion']),
    ('EDGE_FN_INPUT_GOVERNANCE_AGENT_V1', ARRAY['gobernanza de entrada','gobernanza de input','agente']),
    ('EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1', ARRAY['gobernanza de entrada','curador']),
    ('EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1', ARRAY['gobernanza de entrada','validador']);

  -- Precondiciones: los 17 activos existen, vigentes, y aliases es null o arreglo.
  SELECT count(*) INTO v_bad FROM _alias_nuevos n
   WHERE NOT EXISTS (SELECT 1 FROM public.lf_activos a WHERE a.codigo_activo = n.codigo AND a.archived_at IS NULL);
  IF v_bad <> 0 THEN RAISE EXCEPTION 'ALIASES_ES_V1: % activos no existen o estan archivados', v_bad; END IF;
  SELECT count(*) INTO v_bad FROM public.lf_activos a JOIN _alias_nuevos n ON n.codigo = a.codigo_activo
   WHERE a.metadata ? 'aliases' AND jsonb_typeof(a.metadata->'aliases') <> 'array';
  IF v_bad <> 0 THEN RAISE EXCEPTION 'ALIASES_ES_V1: aliases existente no es arreglo en % activos', v_bad; END IF;

  CREATE TEMP TABLE _alias_pre ON COMMIT DROP AS
    SELECT a.codigo_activo AS codigo, coalesce(a.metadata->'aliases','[]'::jsonb) AS pre
      FROM public.lf_activos a JOIN _alias_nuevos n ON n.codigo = a.codigo_activo WHERE a.archived_at IS NULL;

  UPDATE public.lf_activos a
     SET metadata = jsonb_set(
           coalesce(a.metadata,'{}'::jsonb), '{aliases}',
           (SELECT coalesce(jsonb_agg(s.e), '[]'::jsonb) FROM (
              SELECT e FROM jsonb_array_elements(coalesce(a.metadata->'aliases','[]'::jsonb)) e
              UNION
              SELECT to_jsonb(u) FROM unnest(n.alias) u) s),
           true)
    FROM _alias_nuevos n
   WHERE a.codigo_activo = n.codigo AND a.archived_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 17 THEN RAISE EXCEPTION 'ALIASES_ES_V1: se esperaban 17 filas y se actualizaron %', v_updated; END IF;

  -- Ensayo 1: nada previo se perdio y todo alias nuevo quedo.
  SELECT count(*) INTO v_bad FROM _alias_pre p JOIN public.lf_activos a ON a.codigo_activo = p.codigo
   WHERE NOT (a.metadata->'aliases' @> p.pre);
  IF v_bad <> 0 THEN RAISE EXCEPTION 'ALIASES_ES_V1: se perdieron aliases previos en % activos', v_bad; END IF;
  SELECT count(*) INTO v_bad FROM _alias_nuevos n JOIN public.lf_activos a ON a.codigo_activo = n.codigo
   WHERE NOT (a.metadata->'aliases' @> (SELECT jsonb_agg(to_jsonb(u)) FROM unnest(n.alias) u));
  IF v_bad <> 0 THEN RAISE EXCEPTION 'ALIASES_ES_V1: faltan aliases nuevos en % activos', v_bad; END IF;

  -- Ensayo 2: la busqueda nivel 1 trae el activo esperado entre los candidatos devueltos.
  FOR v_case IN SELECT * FROM (VALUES
      ('crear history de usuario','SKILL-CREATING-INTEGRAL-USER-STORIES'),
      ('crear historias de usuario integrales','SKILL-CREATING-INTEGRAL-USER-STORIES'),
      ('el creador de skills','ACT-0043'),
      ('adaptador de experiencia de usuario del marketplace','ADAPTER-MARKETPLACE-LF-UX-20260531'),
      ('adaptador de confianza del cliente','ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531'),
      ('perfil del arquitecto de interfaz','PERFIL-UI-ARCHITECT'),
      ('el perfil del director de producto','PERFIL-PRODUCT-DIRECTOR-LF'),
      ('perfil paquete de calidad','PERFIL-QUALITY-PACK'),
      ('revisor de linaje de evidencia','PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'),
      ('reparacion de causa raiz','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'),
      ('gobernanza de entrada agente','EDGE_FN_INPUT_GOVERNANCE_AGENT_V1')
    ) t(frase, esperado)
  LOOP
    v_res := public.lf_router_search_v1(v_case.frase, 5);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'candidatos') c WHERE c->>'codigo' = v_case.esperado) THEN
      RAISE EXCEPTION 'ALIASES_ES_V1: la frase "%" no trae %', v_case.frase, v_case.esperado;
    END IF;
  END LOOP;

  -- Ensayo 3: lo que no existe sigue sin candidatos (no se inventa).
  FOR v_case IN SELECT * FROM (VALUES
      ('spec driving'),('qué hora es en Lima'),('quiero tomar un café con mi equipo'),('regla de ajedrez para el enroque')
    ) t(frase)
  LOOP
    v_res := public.lf_router_search_v1(v_case.frase, 5);
    IF v_res->>'resultado' <> 'NO_ENCONTRADO' THEN
      RAISE EXCEPTION 'ALIASES_ES_V1: la frase "%" ya no deberia traer candidatos', v_case.frase;
    END IF;
  END LOOP;
END
$mig$;
