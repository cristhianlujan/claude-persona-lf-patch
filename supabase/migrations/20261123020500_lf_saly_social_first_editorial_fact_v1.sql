-- SALY U07: ONE editorial simple-fact observation from a public original report.
-- Not a general-purpose crawler or reprint. No students' or staff personal data.
-- Published 2026-11-01 11:04:35 Peru; identity: Camara de Comercio de Ica,
-- San Francisco College / Garden Kids EIRL / RUC 20534471808.
-- Rights boundary: Peru DL 822 art. 9(d) exempts simple facts/data from copyright,
-- not article copy; publication URL maintained for attribution and review.
-- No Facebook/Instagram permission inferred or activated.
-- One-time governed initialization by PR / Migration Merge Train; uses
-- the existing INGESTA_EMPRESARIAL_SALY operation + native social writer.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';

DO $saly_editorial_prest$
BEGIN
 IF to_regprocedure('saly.ventas_social_ingesta_execute_v1(text,text,bigint,jsonb)') IS NULL
 OR NOT EXISTS (SELECT 1 FROM public.lf_operation_registry
                WHERE operation_code='INGESTA_EMPRESARIAL_SALY' AND status='SANDBOX_ACTIVE')
 OR EXISTS (SELECT 1 FROM saly.ventas_discovery_catalogo WHERE source_id='PE-NEWS-FACTS-CORREO')
 OR EXISTS (SELECT 1 FROM public.lf_operation_contracts WHERE operation_code='INGESTA_EMPRESARIAL_SALY'
              AND contract_code='SALY_SOCIAL_INGESTION_V1')
 OR EXISTS (SELECT 1 FROM saly.ventas_social_publicaciones_v1)
 OR EXISTS (SELECT 1 FROM saly.ventas_social_runs_v1)
 THEN RAISE EXCEPTION 'SALY_EDITORIAL_SEED_PRESTATE_DRIFT'; END IF;
END $saly_editorial_prest$;

INSERT INTO saly.ventas_discovery_catalogo(
 catalog_version,source_id,connector_id,substep_code,step,familia,nombre,landing_page,
 rights_status,rights_evidence_ref,rights_checked_at,persist_business_data,
 habilitada,runtime_status)
VALUES (
 'PE-SALY-DISCOVERY-2026-11-V0.2',
 'PE-NEWS-FACTS-CORREO',
 'SALY-U07-S15-C01','15.01',15,'MEDIOS_DIGITALES',
 'Diario Correo: hechos simples atribuidos, URL exacta, sin articulo ni datos personales',
 'https://diariocorreo.pe/edicion/ica/ica-san-francisco-college-logro-medalla-en-basquet-masculino-de-los-juegos-escolares-nacionales-2026-noticia',
 'PERSISTENCIA_PERMITIDA',
 'WIPO-PE-DL822-ART9D-FACTS-ONLY-NO-ARTICLE-COPY-20261122',
 clock_timestamp(),true,true,
 'ONE_SHOT_HUMAN_REVIEWED_FACT_METADATA_ONLY_NO_AUTOMATED_CRAWL'
);

INSERT INTO public.lf_operation_contracts(
 operation_code,contract_code,contract_path,required_before_write,allowed,blocked,
 required_after_write,status,created_by_execution_id)
VALUES (
 'INGESTA_EMPRESARIAL_SALY','SALY_SOCIAL_INGESTION_V1',
 'skills/ai_sales_discovery/contracts/SOCIAL_MULTIFUENTE_V1_20261122.md',
 '["operation_lease","exact_source_url","published_at","rights_facts_only","identity_verified"]'::jsonb,
 jsonb_build_object(
   'writer','saly.ventas_social_ingesta_execute_v1',
   'source_id','PE-NEWS-FACTS-CORREO',
   'source_url','https://diariocorreo.pe/edicion/ica/ica-san-francisco-college-logro-medalla-en-basquet-masculino-de-los-juegos-escolares-nacionales-2026-noticia',
   'rights_scope','one_manually_reviewed_simple_fact_only_no_article_reproduction_no_automated_crawl',
   'runtime_effect_enabled',true,
   'meta_sources_enabled',false
 ),
 '["facebook_automation","instagram_automation","bulk_article_copy","student_personal_data","source_without_rights"]'::jsonb,
 '["effect_receipt","database_row_readback","partial_coverage_report"]'::jsonb,
 'ACTIVE_ENFORCEMENT','EXEC-SALY-NEWS-FACT-20261122-001'
);

DO $saly_editorial_first$
DECLARE
 v_exec constant text:='EXEC-SALY-NEWS-FACT-20261122-001';
 v_owner constant text:='SALY_EDITORIAL_FACT_ONE_SHOT';
 v_url constant text:='https://diariocorreo.pe/edicion/ica/ica-san-francisco-college-logro-medalla-en-basquet-masculino-de-los-juegos-escolares-nacionales-2026-noticia';
 v_start constant text:='2026-09-22T00:00:00-05:00';
 v_end constant text:='2026-11-22T23:59:59-05:00';
 v_date constant text:='2026-11-01T11:04:35-05:00';
 v_summary constant text:='San Francisco College de Ica obtuvo el tercer puesto en basquet masculino, categoria B, de la etapa nacional JEDPA 2026.';
 v_evidref constant text:='WIPO-PE-DL822-ART9D-FACTS-ONLY-NO-ARTICLE-COPY-20261122';
 v_manifest jsonb;v_row jsonb;v_res jsonb;v_lease jsonb;v_receipt jsonb;
 v_fence bigint;v_request text;v_sha text;
BEGIN
 v_manifest:=jsonb_build_object('social_scope',jsonb_build_object(
   'source_id','PE-NEWS-FACTS-CORREO',
   'business_key','20534471808',
   'window_start',v_start,'window_end',v_end));
 v_request:=encode(sha256(convert_to(v_manifest::text,'UTF8')),'hex');
 v_sha:=encode(sha256(convert_to(v_url||E'\n'||v_summary||E'\n'||v_date,'UTF8')),'hex');

 v_row:=jsonb_build_object(
   'source_id','PE-NEWS-FACTS-CORREO',
   'business_key','20534471808',
   'external_ref','diariocorreo-jedpa-bronce-sfc-2026-11-01',
   'url',v_url,
   'window_start',v_start,'window_end',v_end,
   'event_key','SFC_JEDPA_2026_BASQUET_B_BRONCE',
   'event_title','Reconocimiento deportivo institucional JEDPA 2026',
   'claim_key','TERCER_PUESTO_NACIONAL_BASQUET_CATEGORIA_B',
   'claim_state','REALIZADO',
   'polarity','NEUTRA',
   'identity_state','VALIDADA','match_state','REVISADO',
   'summary_non_personal',v_summary,
   'published_at',v_date,
   'rights_evidence_ref',v_evidref,
   'source_sha256',v_sha);
 v_res:=public.fn_lf_operation_reserve_execution_v1(
   v_exec,'INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE',
   'PE-NEWS-FACTS-CORREO',v_exec,v_request,v_exec,NULL,NULL,v_manifest);
 IF v_res->>'result'<>'RESERVED_NEW_EXECUTION' THEN
  RAISE EXCEPTION 'SALY_EDITORIAL_OPERATION_RESERVE %',v_res; END IF;

 v_lease:=public.fn_lf_operation_acquire_lease_v1(v_exec,v_owner,600,v_exec);
 IF v_lease->>'result'<>'LEASE_ACQUIRED' THEN
  RAISE EXCEPTION 'SALY_EDITORIAL_LEASE %',v_lease; END IF;
 v_fence:=(v_lease->>'lease_fence')::bigint;
 v_receipt:=saly.ventas_social_ingesta_execute_v1(v_exec,v_owner,v_fence,v_row);
 IF v_receipt->>'result'<>'INSERTADO'
  OR v_receipt->>'inserted_claims'<>'1'
 THEN RAISE EXCEPTION 'SALY_EDITORIAL_WRITER_RESULT %',v_receipt; END IF;

 -- One URL is a seed, not two-month coverage; close scoped RUN as INCOMPLETO.
 UPDATE saly.ventas_social_runs_v1
 SET status='INCOMPLETO',
     finished_at=clock_timestamp(),pages_read=1,
     stop_reason='ONE_EDITORIAL_FACT_ONLY_NO_HISTORICAL_PAGINATION',
     oldest_published_at=v_date::timestamptz,
     source_receipt_sha256=encode(sha256(convert_to(v_row::text,'UTF8')),'hex')
 WHERE run_ref=v_exec AND source_id='PE-NEWS-FACTS-CORREO'
   AND status='EN_EJECUCION';
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_EDITORIAL_RUN_STATE'; END IF;

 v_res:=public.fn_lf_operation_release_lease_v1(v_exec,v_owner,v_fence,v_exec);
 IF v_res->>'result'<>'LEASE_RELEASED' THEN
   RAISE EXCEPTION 'SALY_EDITORIAL_LEASE_RELEASE'; END IF;
 UPDATE public.lf_operation_execution
 SET status='COMPLETED', completed_at=clock_timestamp(),updated_by_execution_id=v_exec
 WHERE execution_id=v_exec AND status='IN_PROGRESS' AND lease_owner IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_EDITORIAL_OPERATION_CLOSURE'; END IF;

 IF (SELECT count(*) FROM saly.ventas_social_publicaciones_v1 WHERE source_id='PE-NEWS-FACTS-CORREO')<>1
 OR (SELECT count(*) FROM saly.ventas_social_afirmaciones_v1 WHERE source_id='PE-NEWS-FACTS-CORREO')<>1
 OR (SELECT count(*) FROM saly.ventas_social_eventos_v1 WHERE business_key='20534471808')<>1
 OR (SELECT count(*) FROM saly.ventas_social_runs_v1 WHERE run_ref=v_exec AND status='INCOMPLETO')<>1
 OR NOT EXISTS(SELECT 1 FROM saly.ventas_social_publicaciones_v1
  WHERE url=v_url AND source_sha256=v_sha AND published_at=v_date::timestamptz
  AND summary_non_personal=v_summary)
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
     WHERE source_id IN ('PE-FACEBOOK','PE-INSTAGRAM'))<>0
 OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE source_id='PE-NEWS-FACTS-CORREO')<>0
 THEN RAISE EXCEPTION 'SALY_EDITORIAL_READBACK_OR_UNRELATED_DATA'; END IF;
 RAISE NOTICE 'PASS_SALY_FIRST_EDITORIAL_FACT_RUN %, source %, rows 1, meta_enabled false',
  v_exec,'PE-NEWS-FACTS-CORREO';
END $saly_editorial_first$;
COMMIT;
