BEGIN;
DO $pilot$
DECLARE o record; i record; c jsonb; p jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('saly:creative:serial:v1',0));
 SELECT * INTO STRICT o FROM saly.creative_orders WHERE id=23 AND project_id=3 AND status='PLANIFICADO' FOR UPDATE;
 SELECT * INTO STRICT i FROM saly.creative_order_items WHERE id=27 AND order_id=23 AND status='PENDIENTE' FOR UPDATE;
 IF EXISTS(SELECT 1 FROM saly.creative_runs WHERE state IN ('EN_COLA','EJECUTANDO')) THEN RAISE EXCEPTION 'LF_QUEUE_NOT_FREE'; END IF;
 -- Owner amendment 2026-11-26 23:45 America/Lima; preserve original literal for audit.
 IF position('marcadores literales S/ [CUOTA], por [N] meses, total S/ [TOTAL]; no inventar cifras' in o.scope_json->>'literal_request')=0 OR NOT (i.acceptance_json->'qa_checklist' ? 'placeholders_exact') THEN RAISE EXCEPTION 'LF_OWNER_AMENDMENT_SOURCE_DRIFT'; END IF;
 UPDATE saly.creative_orders SET scope_json=scope_json||jsonb_build_object(
 'original_literal_request',o.scope_json->>'literal_request',
 'literal_request',replace(o.scope_json->>'literal_request','marcadores literales S/ [CUOTA], por [N] meses, total S/ [TOTAL]; no inventar cifras','cifras de muestra autorizadas: S/ 189.00, por 12 meses, total S/ 2,268.00; no añadir otras cifras; no son datos de cliente'),
 'owner_amendment',jsonb_build_object('at','2026-11-26T23:45:00-05:00','text','Los montos deben ser reales no texto','illustrative',true))
 WHERE id=23 AND project_id=3 RETURNING * INTO o;
 UPDATE saly.creative_order_items SET acceptance_json=jsonb_set(acceptance_json,'{qa_checklist}',(acceptance_json->'qa_checklist'-'placeholders_exact')||jsonb_build_object('authorized_sample_amounts_exact',true)),
 context_json=context_json||jsonb_build_object('authorized_sample_amounts',jsonb_build_object('monthly','S/ 189.00','term','por 12 meses','total','S/ 2,268.00','illustrative',true),'owner_amendment_at','2026-11-26T23:45:00-05:00')
 WHERE id=27 AND order_id=23 RETURNING * INTO i;
 IF (o.scope_json->>'literal_request') ~ '[\[\]]' OR 189*12<>2268 THEN RAISE EXCEPTION 'LF_SAMPLE_AMOUNT_DRIFT'; END IF;
 c:=saly.creative_queue_claim_by_id_v1(23,'GPT_SELF_QA_LF_PILOT_23',86400);
 IF c->>'status' IS DISTINCT FROM 'CLAIMED' OR c->>'order_id' IS DISTINCT FROM '23' OR c->>'item_id' IS DISTINCT FROM '27' THEN RAISE EXCEPTION 'LF_CLAIM_MISMATCH'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.creative_queue_claims_v1 WHERE id=(c->>'claim_id')::bigint AND order_id=23 AND item_id=27 AND state='ACTIVE' AND lease_until-claimed_at=interval '24 hours') THEN RAISE EXCEPTION 'LF_LEASE_MISMATCH'; END IF;
 p:=saly.creative_skill_prepare_v1(jsonb_build_object('schema_version','CREATIVE_SKILL_PREPARE_REQUEST_V1','mode','AUTONOMOUS','business_code','LF','project_code','LF','order_code',o.code,'item_code',i.code,'literal_request',o.scope_json->>'literal_request'));
 IF p->>'status' IS DISTINCT FROM 'LF_DISCOVERY_PREPARED' OR p->>'order_id' IS DISTINCT FROM '23' OR p->>'item_id' IS DISTINCT FROM '27' OR jsonb_typeof(p->'tokens') IS DISTINCT FROM 'array' OR jsonb_typeof(p->'assets') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'LF_PREPARE_FAILED'; END IF;
 RAISE NOTICE 'LF_23_CLAIMED claim_id=% prepare=%',c->>'claim_id',p->>'status';
END $pilot$;
COMMIT;
