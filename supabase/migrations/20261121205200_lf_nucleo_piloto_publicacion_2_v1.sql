-- 2026-11-21, decision del dueno 13:55 Lima para publicar solo dos reglas; 14:54 autorizo deprecacion.
-- Ruta unica: PROMOCION v1, DEPRECACION v1 por ensayo de subtransaccion. Sin cortar lectores.
BEGIN;
DO $pilot$
DECLARE
  x record; res jsonb; got jsonb;
  targets CONSTANT text[] := ARRAY['REG_CHK_002','REG_TEC_007'];
  scope_nodes CONSTANT text[] := ARRAY['CLIENT_PAYMENTS','PANTALLA-21','PANTALLA-24','PANTALLA-25','PANTALLA-27','PANTALLA-28','PANTALLA-30','PANTALLA-33','PANTALLA-34','PANTALLA-59'];
  legacy_before jsonb; other_before jsonb; other_versions_before jsonb;
  versions_before jsonb; proofs_before jsonb; judges_before jsonb; applications_before jsonb;
  eval_before jsonb; decisions_before jsonb; history_before jsonb; saly_before jsonb;
  eval_max bigint; old_count bigint; old_core bigint; published_count bigint;
  current_versions jsonb; caught boolean := false;
  published_before_deprecation jsonb;
BEGIN
  -- Exact snapshots of all legacy and all unaffected identities/versions, not just counts.
  SELECT count(*),jsonb_agg(to_jsonb(l) ORDER BY id) INTO old_count,legacy_before FROM lf_ops.reglas l;
  SELECT count(*) INTO old_core FROM lf_ops.nucleo_reglas;
  SELECT count(*) INTO published_count FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA';
  SELECT jsonb_agg(to_jsonb(n) ORDER BY codigo) INTO other_before FROM lf_ops.nucleo_reglas n WHERE codigo<>ALL(targets);
  SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) INTO other_versions_before FROM lf_ops.nucleo_regla_versiones v WHERE regla<>ALL(targets);
  SELECT jsonb_agg(CASE WHEN regla=ANY(targets) AND version=2 THEN to_jsonb(v)-'estado'-'publicada_desde'-'exigible_desde' ELSE to_jsonb(v) END ORDER BY regla,version)
    INTO versions_before FROM lf_ops.nucleo_regla_versiones v;
  SELECT jsonb_agg(to_jsonb(t) ORDER BY regla,version,n) INTO proofs_before FROM lf_ops.nucleo_regla_pruebas t;
  SELECT jsonb_agg(to_jsonb(j) ORDER BY id) INTO judges_before FROM lf_ops.nucleo_juicios j;
  SELECT jsonb_agg(to_jsonb(a) ORDER BY regla,nodo) INTO applications_before FROM lf_ops.nucleo_aplicaciones a;
  SELECT coalesce(max(id),0),jsonb_agg(to_jsonb(e) ORDER BY id) INTO eval_max,eval_before FROM lf_ops.nucleo_evaluaciones e;
  SELECT jsonb_agg(to_jsonb(d) ORDER BY id) INTO decisions_before FROM lf_ops.nucleo_decisiones d;
  SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) INTO history_before FROM lf_ops.nucleo_deprecaciones d;
  SELECT jsonb_build_object('legacy',(SELECT jsonb_agg(to_jsonb(l) ORDER BY codigo) FROM saly.reglas l),
    'core',(SELECT jsonb_agg(to_jsonb(n) ORDER BY codigo) FROM saly.nucleo_reglas n),
    'versions',(SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM saly.nucleo_regla_versiones v),
    'eval',(SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM saly.nucleo_evaluaciones e),
    'history',(SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) FROM saly.nucleo_deprecaciones d)) INTO saly_before;
  IF old_core<>10 OR published_count<>0 OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='CANDIDATA')<>10
    OR (SELECT count(*) FROM saly.nucleo_reglas WHERE estado='CANDIDATA')<>14
    OR (SELECT count(*) FROM saly.nucleo_regla_versiones WHERE estado='PUBLICADA')<>0
    OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
    OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_autoridades WHERE codigo='LEG-DUENO' AND estado='VIGENTE')
    OR EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1)
    OR EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 EXCEPT ALL SELECT * FROM lf_ops.reglas)
    OR EXISTS(SELECT 1 FROM lf_ops.nucleo_relaciones WHERE origen=ANY(targets) OR destino=ANY(targets))
    OR (SELECT count(*) FROM lf_ops.nucleo_aplicaciones WHERE regla=ANY(targets))<>2
    OR (SELECT count(*) FROM lf_ops.nucleo_aplicaciones WHERE regla=ANY(targets) AND nodo='CLIENT_PAYMENTS' AND modo='HEREDA')<>2
  THEN RAISE EXCEPTION 'PILOTO_PREFLIGHT_INVARIANT'; END IF;
  IF (SELECT array_agg(codigo ORDER BY codigo) FROM lf_ops.nucleo_nodos WHERE codigo='CLIENT_PAYMENTS' OR padre='CLIENT_PAYMENTS')
    IS DISTINCT FROM scope_nodes THEN RAISE EXCEPTION 'PILOTO_SCOPE_DRIFT'; END IF;
  RAISE NOTICE 'PILOT_PASS 01 preflight: % legadas, % identidades, 0 publicadas',old_count,old_core;
  FOR x IN SELECT * FROM (VALUES
    ('REG_CHK_002','0d08e6f13b1eefb6188c4a06098ddac4a4641f149f9baa486cb7bfd74498cb19','7d796a48bd4576f53ace8cf27718cab2cf9bb5bdda0b9ebb716603c2f274cd67'),
    ('REG_TEC_007','9ea2a6c14b2b816ae0d0fb599f629d0ed23775bfb293d5cca0d59916314262e5','e07786dcea25d66456ff270fc9a6880fd2c0849a16884bd7773b2fa23e1be1a3')
  ) AS t(codigo,hash_version,hash_paquete) LOOP
    IF NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_reglas n JOIN lf_ops.nucleo_regla_versiones v ON v.regla=n.codigo
      WHERE n.codigo=x.codigo AND n.estado='CANDIDATA' AND v.version=2 AND v.estado='CANDIDATA' AND v.hash=x.hash_version)
       OR lf_ops.nucleo_hash_paquete_v1(x.codigo,2) IS DISTINCT FROM x.hash_paquete
    THEN RAISE EXCEPTION 'PILOTO_TARGET_HASH_DRIFT %',x.codigo; END IF;
    res:=lf_ops.nucleo_regla_evaluar_v1(x.codigo,false);
    IF res->>'decision' IS DISTINCT FROM 'AUTO' OR res->>'nota' IS DISTINCT FROM '100'
      OR res->>'hash_paquete' IS DISTINCT FROM x.hash_paquete OR res->>'version' IS DISTINCT FROM '2'
    THEN RAISE EXCEPTION 'PILOTO_REEVALUACION_REJECTED % %',x.codigo,res; END IF;
    res:=lf_ops.nucleo_regla_promover_v1(x.codigo);
    IF res->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR res->>'decision' IS DISTINCT FROM 'AUTO'
      OR res->>'nota' IS DISTINCT FROM '100' OR res->>'version' IS DISTINCT FROM '2'
      OR res->>'hash_paquete' IS DISTINCT FROM x.hash_paquete
    THEN RAISE EXCEPTION 'PILOTO_PROMOCION_REJECTED % %',x.codigo,res; END IF;
    RAISE NOTICE 'PILOT_PUBLISHED % V2 AUTO 100 hash_paquete=% evaluacion_id=%',x.codigo,x.hash_paquete,res->>'evaluacion_id';
  END LOOP;
  IF (SELECT count(*) FROM lf_ops.nucleo_reglas)<>old_core OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='CANDIDATA')<>8
    OR (SELECT array_agg(codigo ORDER BY codigo) FROM lf_ops.nucleo_reglas WHERE estado='VIGENTE') IS DISTINCT FROM targets
    OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>2
    OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE regla=ANY(targets) AND version=2 AND estado='PUBLICADA'
      AND publicada_desde=now() AND exigible_desde>=publicada_desde AND vigente_hasta IS NULL)<>2
  THEN RAISE EXCEPTION 'PILOTO_PUBLICACION_EXACTA'; END IF;
  RAISE NOTICE 'PILOT_PASS 02 solo dos publicaciones';
  -- Probar el resolvedor de cada nodo de la instancia, incluidos los limites del alcance.
  SELECT jsonb_agg(jsonb_build_object('nodo',n.codigo,'regla',e.regla,'version',e.version,'origen',e.nodo_origen,'modo',e.modo) ORDER BY n.codigo,e.regla)
  INTO got FROM lf_ops.nucleo_nodos n CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(n.codigo,now()) e;
  SELECT jsonb_agg(jsonb_build_object('nodo',n,'regla',r,'version',2,'origen','CLIENT_PAYMENTS','modo','HEREDA') ORDER BY n,r)
  INTO current_versions FROM unnest(scope_nodes) n CROSS JOIN unnest(targets) r;
  IF got IS DISTINCT FROM current_versions OR EXISTS(SELECT 1 FROM lf_ops.nucleo_nodos n CROSS JOIN LATERAL
    lf_ops.nucleo_reglas_efectivas_v1(n.codigo,now()) e WHERE e.conflicto IS NOT NULL)
  THEN RAISE EXCEPTION 'PILOTO_RESOLVEDOR_DRIFT %',got; END IF;
  RAISE NOTICE 'PILOT_PASS 03 20 resoluciones en modulo y nueve pantallas, cero fuera';
  IF (SELECT count(*) FROM lf_ops.reglas)<>old_count OR
    (SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM lf_ops.reglas l) IS DISTINCT FROM legacy_before
    OR EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1)
    OR EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 EXCEPT ALL SELECT * FROM lf_ops.reglas)
  THEN RAISE EXCEPTION 'PILOTO_COMPAT_DRIFT'; END IF;
  RAISE NOTICE 'PILOT_PASS 04 % legadas y compat exactas',old_count;
  -- No cutover: the diagnostic adapter must not certify a mixed native/legacy set.
  -- All actual checkout screens have legacy rows; fixture has link at screen 59.
  got:=lf_ops.lf_nucleo_lectura_transicion_v1(59,'INPUT_GOVERNANCE','DIRECTAS');
  IF jsonb_array_length(got->'nativas')<>2 OR got->>'estado' IS DISTINCT FROM 'PARIDAD_MIXTA_PENDIENTE'
     OR got->'reglas' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'PILOTO_MIXED_NOT_GUARDED %',got; END IF;
  RAISE NOTICE 'PILOT_PASS 05 mixto diagnostico separado, sin redireccion';
  SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) INTO published_before_deprecation
  FROM lf_ops.nucleo_regla_versiones v WHERE regla=ANY(targets) AND version=2;
  -- Atomic nested rehearsal on the actual same two publications. Deliberate sentinel
  -- rolls back all deprecation writes (including history) before final commit.
  BEGIN
    FOR x IN SELECT regla,version,hash FROM lf_ops.nucleo_regla_versiones WHERE regla=ANY(targets) AND version=2 ORDER BY regla LOOP
      res:=lf_ops.nucleo_regla_deprecar_v1(x.regla,x.version,x.hash,'LEG-DUENO',
        'Ensayo transaccional de retorno autorizado 2026-11-21 14:54 Lima; se revierte antes del commit.');
      IF res->>'estado' IS DISTINCT FROM 'DEPRECADA' OR res->>'regla' IS DISTINCT FROM x.regla
        OR res->>'hash_version' IS DISTINCT FROM x.hash THEN RAISE EXCEPTION 'PILOTO_DEPRECACION_REJECTED %',res; END IF;
      caught:=false;
      BEGIN
        PERFORM lf_ops.nucleo_regla_deprecar_v1(x.regla,x.version,x.hash,'LEG-DUENO','Prueba negativa: una regla no vigente no se puede deprecar.');
      EXCEPTION WHEN others THEN IF SQLERRM LIKE 'NUCLEO_DEPRECAR_NO_VIGENTE:%' THEN caught:=true; ELSE RAISE; END IF; END;
      IF NOT caught THEN RAISE EXCEPTION 'PILOTO_NEGATIVE_NOT_REJECTED %',x.regla; END IF;
      RAISE NOTICE 'PILOT_DEPRECATED_TEST % V2 negative rejected',x.regla;
    END LOOP;
    IF (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='DEPRECADA' AND codigo=ANY(targets))<>2
      OR (SELECT count(*) FROM lf_ops.nucleo_reglas)<>old_core
      OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE regla=ANY(targets) AND version=2 AND estado='PUBLICADA' AND vigente_hasta=now())<>2
      OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones WHERE regla=ANY(targets) AND version=2 AND autoridad='LEG-DUENO' AND vigente_hasta=now())<>2
      OR EXISTS(SELECT 1 FROM lf_ops.nucleo_nodos n CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(n.codigo,now()) e)
      OR (SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM lf_ops.reglas l) IS DISTINCT FROM legacy_before
      OR EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1)
      OR EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 EXCEPT ALL SELECT * FROM lf_ops.reglas)
      OR (SELECT jsonb_agg(to_jsonb(v)-'vigente_hasta' ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v WHERE regla=ANY(targets) AND version=2)
        IS DISTINCT FROM (SELECT jsonb_agg(v-'vigente_hasta' ORDER BY v->>'regla',v->>'version') FROM jsonb_array_elements(published_before_deprecation) v)
    THEN RAISE EXCEPTION 'PILOTO_DEPRECATION_INVARIANT'; END IF;
    RAISE NOTICE 'PILOT_PASS 06 dos deprecaciones, historial exacto, cero efectivas, % legadas intactas',old_count;
    RAISE EXCEPTION 'PILOTO_REHEARSAL_ROLLBACK_SENTINEL';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'PILOTO_REHEARSAL_ROLLBACK_SENTINEL' THEN RAISE; END IF;
  END;
  IF (SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v WHERE regla=ANY(targets) AND version=2) IS DISTINCT FROM published_before_deprecation
    OR (SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones d) IS DISTINCT FROM history_before
    OR (SELECT array_agg(codigo ORDER BY codigo) FROM lf_ops.nucleo_reglas WHERE estado='VIGENTE') IS DISTINCT FROM targets
    OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado IN ('DEPRECADA','RETIRADA'))<>0
  THEN RAISE EXCEPTION 'PILOTO_REHEARSAL_ROLLBACK_FAILED'; END IF;
  RAISE NOTICE 'PILOT_PASS 07 ensayo deprecacion ROLLBACK, ambas publicadas abiertas';
  IF (SELECT jsonb_agg(to_jsonb(n) ORDER BY codigo) FROM lf_ops.nucleo_reglas n WHERE codigo<>ALL(targets)) IS DISTINCT FROM other_before
    OR (SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v WHERE regla<>ALL(targets)) IS DISTINCT FROM other_versions_before
    OR (SELECT jsonb_agg(CASE WHEN regla=ANY(targets) AND version=2 THEN to_jsonb(v)-'estado'-'publicada_desde'-'exigible_desde' ELSE to_jsonb(v) END ORDER BY regla,version)
        FROM lf_ops.nucleo_regla_versiones v) IS DISTINCT FROM versions_before
    OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas t) IS DISTINCT FROM proofs_before
    OR (SELECT jsonb_agg(to_jsonb(j) ORDER BY id) FROM lf_ops.nucleo_juicios j) IS DISTINCT FROM judges_before
    OR (SELECT jsonb_agg(to_jsonb(a) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones a) IS DISTINCT FROM applications_before
    OR (SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM lf_ops.nucleo_evaluaciones e WHERE id<=eval_max) IS DISTINCT FROM eval_before
    OR (SELECT count(*) FROM lf_ops.nucleo_evaluaciones WHERE id>eval_max)<>2
    OR (SELECT count(*) FROM lf_ops.nucleo_evaluaciones WHERE id>eval_max AND regla=ANY(targets) AND version=2 AND nota=100 AND decision='AUTO')<>2
    OR (SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM lf_ops.nucleo_decisiones d) IS DISTINCT FROM decisions_before
  THEN RAISE EXCEPTION 'PILOTO_UNAUTHORIZED_DRIFT'; END IF;
  RAISE NOTICE 'PILOT_PASS 08 ocho identidades ajenas, historial, pruebas, juicios y alcance intactos';
  IF (SELECT jsonb_build_object('legacy',(SELECT jsonb_agg(to_jsonb(l) ORDER BY codigo) FROM saly.reglas l),
    'core',(SELECT jsonb_agg(to_jsonb(n) ORDER BY codigo) FROM saly.nucleo_reglas n),
    'versions',(SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM saly.nucleo_regla_versiones v),
    'eval',(SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM saly.nucleo_evaluaciones e),
    'history',(SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) FROM saly.nucleo_deprecaciones d))) IS DISTINCT FROM saly_before
  THEN RAISE EXCEPTION 'PILOTO_SALY_DRIFT'; END IF;
  RAISE NOTICE 'PILOT_PASS 09 SALY intacto';
  IF (SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM lf_ops.reglas l) IS DISTINCT FROM legacy_before
     OR EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1)
     OR EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 EXCEPT ALL SELECT * FROM lf_ops.reglas)
     OR (SELECT count(*) FROM lf_ops.nucleo_reglas_efectivas_v1('CLIENT_PAYMENTS',now()))<>2
     OR (SELECT count(*) FROM lf_ops.nucleo_reglas)<>10
  THEN RAISE EXCEPTION 'PILOTO_FINAL_INVARIANT'; END IF;
  RAISE NOTICE 'PILOT_PASS 10 listo para commit: % legacy, 10 identidades, 2 VIGENTE / 8 CANDIDATA, 0 deprecaciones reales',old_count;
END $pilot$;
COMMIT;
