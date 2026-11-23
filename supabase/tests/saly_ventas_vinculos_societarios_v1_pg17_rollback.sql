-- SALY: PG17 aislado, DML sintético con ROLLBACK.
\set ON_ERROR_STOP on
DO $pre$
BEGIN
 IF current_database() <> 'saly_vinculos_ci'
 OR current_setting('server_version_num')::int / 10000 <> 17
 THEN RAISE EXCEPTION 'UNSAFE_TARGET_NOT_DISPOSABLE_PG17'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='saly' AND c.relname IN
 ('ventas_vinculos_empresariales_v1','ventas_vinculos_evidencias_v1')
 AND c.relrowsecurity AND c.relforcerowsecurity) <> 2
 THEN RAISE EXCEPTION 'RLS_NOT_FORCED_ON_BOTH_TABLES'; END IF;
 IF has_table_privilege('anon','saly.ventas_vinculos_empresariales_v1','SELECT')
 OR has_table_privilege('authenticated','saly.ventas_vinculos_empresariales_v1','INSERT')
 OR has_table_privilege('service_role','saly.ventas_vinculos_evidencias_v1','SELECT')
 THEN RAISE EXCEPTION 'UNEXPECTED_CLIENT_GRANT'; END IF;
END $pre$;
BEGIN;
SET LOCAL statement_timeout='15s';
DO $cases$
DECLARE v_id uuid; v_failed boolean;
BEGIN
 INSERT INTO saly.ventas_vinculos_empresariales_v1
 (empresa_ruc,vinculada_ruc,tipo_relacion,fuente_id,fuente_version,fuente_corte)
 VALUES('20100000001','20100000002','SOCIO_DECLARADO','FIXTURE-OECE','TEST-2026-11','2026-11-02')
 RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'POSITIVE_INSERT_FAILED'; END IF;
 INSERT INTO saly.ventas_vinculos_evidencias_v1
 (vinculo_id,evidencia_ref,url_fuente,clase_evidencia,derechos_estado)
 VALUES(v_id,'fixture://test-evidence-001','https://example.invalid/oece',
 'DECLARACION_RNP','NO_DETERMINADOS');
 IF (SELECT count(*) FROM saly.ventas_vinculos_evidencias_v1 WHERE vinculo_id=v_id) <> 1
 THEN RAISE EXCEPTION 'EVIDENCE_NOT_LINKED'; END IF;

 v_failed:=false;
 BEGIN
  INSERT INTO saly.ventas_vinculos_empresariales_v1
  (empresa_ruc,vinculada_ruc,tipo_relacion,fuente_id,fuente_version,fuente_corte)
  VALUES('20100000001','20100000001','SOCIO_DECLARADO','X','V1','2026-11-02');
 EXCEPTION WHEN check_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'SELF_LINK_ACCEPTED'; END IF;

 v_failed:=false;
 BEGIN
  INSERT INTO saly.ventas_vinculos_empresariales_v1
  (empresa_ruc,vinculada_ruc,tipo_relacion,fuente_id,fuente_version,fuente_corte)
  VALUES('10100000001','20100000002','SOCIO_DECLARADO','X','V1','2026-11-02');
 EXCEPTION WHEN check_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'NON_JURIDICAL_RUC_ACCEPTED'; END IF;

 v_failed:=false;
 BEGIN
  INSERT INTO saly.ventas_vinculos_empresariales_v1
  (empresa_ruc,vinculada_ruc,tipo_relacion,estado,fuente_id,fuente_version,fuente_corte)
  VALUES('20100000003','20100000004','CONTROL_ACCIONARIO','CONTROL_VERIFICADO','X','V1','2026-11-02');
 EXCEPTION WHEN check_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'CONTROL_WITHOUT_PROOF_ACCEPTED'; END IF;

 v_failed:=false;
 BEGIN
  INSERT INTO saly.ventas_vinculos_empresariales_v1
  (empresa_ruc,vinculada_ruc,tipo_relacion,estado,fuente_id,fuente_version,fuente_corte)
  VALUES('20100000003','20100000004','PERTENENCIA_CORPORATIVA','CORROBORADO','X','V1','2026-11-02');
 EXCEPTION WHEN check_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'CORROBORATED_WITHOUT_PROOF_ACCEPTED'; END IF;

 v_failed:=false;
 BEGIN
  INSERT INTO saly.ventas_vinculos_empresariales_v1
  (empresa_ruc,vinculada_ruc,tipo_relacion,fuente_id,fuente_version,fuente_corte)
  VALUES('20100000001','20100000002','SOCIO_DECLARADO','FIXTURE-OECE','TEST-2026-11','2026-11-02');
 EXCEPTION WHEN unique_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'DUPLICATE_LINK_ACCEPTED'; END IF;

 v_failed:=false;
 BEGIN
  INSERT INTO saly.ventas_vinculos_evidencias_v1
  (vinculo_id,evidencia_ref,url_fuente,clase_evidencia,derechos_estado)
  VALUES(v_id,'fixture://test-evidence-001','https://example.invalid/oece','DECLARACION_RNP','NO_DETERMINADOS');
 EXCEPTION WHEN unique_violation THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'DUPLICATE_EVIDENCE_ACCEPTED'; END IF;
 RAISE NOTICE 'PASS_PG17_VINCULOS_POSITIVE_NEGATIVE';
END $cases$;
ROLLBACK;
DO $post$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_vinculos_empresariales_v1) <> 0
 OR (SELECT count(*) FROM saly.ventas_vinculos_evidencias_v1) <> 0
 THEN RAISE EXCEPTION 'PG17_ROLLBACK_LEAK'; END IF;
 RAISE NOTICE 'PASS_PG17_ROLLBACK_EMPTY';
END $post$;
