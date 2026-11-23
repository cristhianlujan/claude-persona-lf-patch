\set ON_ERROR_STOP on
DO $tests$
DECLARE v_new bigint; v_old bigint; v_next bigint; v_item bigint; v_msg text;
BEGIN
 SELECT id INTO STRICT v_new FROM saly.creative_orders
 WHERE code='SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123';
 SELECT id INTO STRICT v_old FROM saly.creative_orders
 WHERE code='SALY_HOME_V015_SINGLE_20261123';
 SELECT id INTO STRICT v_next FROM saly.creative_orders
 WHERE code='SALY_ADELANTO_V015_SINGLE_20261123';
 SELECT id INTO STRICT v_item FROM saly.creative_order_items
 WHERE order_id=v_new AND code='HOME_MIDISPONIBLE';

 -- Positive: the new request is exactly one narrow DRAFT, not a new render RUN.
 IF (SELECT count(*) FROM saly.creative_orders
   WHERE id=v_new AND request_kind='APP_SCREEN_SINGLE' AND status='BORRADOR'
   AND scope_json->>'change_scope'='ONLY_MI_DISPONIBLE_AS_VIEW_CALCULATION_LINK'
   AND scope_json->>'render_authorized'='false'
   AND scope_json->>'rendering_authority'='false'
   AND scope_json->>'review_only'='true'
   AND scope_json#>>'{intake_semantic_qa,verdict}'='PENDING'
   AND scope_json->>'literal_request'
       ='un refinanmiento al perido donde se indica que el mi disonible es un ver para que vea como se calcual.')<>1
 OR (SELECT count(*) FROM saly.creative_order_items
    WHERE order_id=v_new AND id=v_item AND ordinal=1 AND kind='SCREEN'
     AND status='PENDIENTE')<>1
 OR (SELECT count(*) FROM saly.creative_order_sequence_v1
    WHERE order_id=v_new AND depends_on_order_id=v_old)<>1
 OR (SELECT count(*) FROM saly.creative_orders
    WHERE id IN(v_old,v_next) AND status='PLANIFICADO'
      AND scope_json->>'render_authorized'='false')<>2
 OR EXISTS(SELECT 1 FROM saly.creative_runs)
 THEN RAISE EXCEPTION 'SALY_REFINEMENT_POSITIVE_READBACK_FAILED'; END IF;

 -- Negative: second item in APP_SCREEN_SINGLE must fail.
 BEGIN
  INSERT INTO saly.creative_order_items(order_id,code,ordinal,kind,title,status)
  VALUES(v_new,'DUPLICATE',1,'SCREEN','Extra screen','PENDIENTE');
  RAISE EXCEPTION 'SALY_REFINEMENT_EXTRA_ITEM_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_SINGLE_SCREEN_MULTIPLE_ITEMS' THEN RAISE; END IF;
 END;

 -- Negative: cannot arm rendering without independent QA.
 BEGIN
  UPDATE saly.creative_orders
  SET scope_json=scope_json||'{"render_authorized":true}'::jsonb
  WHERE id=v_new;
  RAISE EXCEPTION 'SALY_REFINEMENT_UNAUTHORIZED_RENDER_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_INTAKE_SEMANTIC_QA_NOT_ATTESTED' THEN RAISE; END IF;
 END;

 -- Negative: cannot activate in execution while source and parent are pending.
 BEGIN
  UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE id=v_new;
  RAISE EXCEPTION 'SALY_REFINEMENT_PREMATURE_RUN_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT IN('CREATIVE_INTAKE_SEMANTIC_QA_NOT_ATTESTED',
                    'CREATIVE_ORDER_PREREQUISITE_NOT_TERMINADO')
  THEN RAISE; END IF;
 END;

 -- Existing historic first batch is untouched, as are #7 / #8.
 IF (SELECT count(*) FROM saly.creative_order_items
      WHERE order_id=1)<>2
 OR (SELECT count(*) FROM saly.creative_orders
      WHERE code IN('SALY_HOME_V015_SINGLE_20261123',
                    'SALY_ADELANTO_V015_SINGLE_20261123'))<>2
 OR (SELECT count(*) FROM saly.creative_orders
      WHERE status='BORRADOR' AND code='SALY_HOME_MIDISPONIBLE_REFINEMENT_20261123')<>1
 THEN RAISE EXCEPTION 'SALY_REFINEMENT_LEGACY_OR_PENDING_DRIFT'; END IF;
 RAISE NOTICE 'PASS_SALY_MIDISPONIBLE_PG17_ONE_DRAFT_ONE_ITEM_ZERO_RUN_TWO_NEGATIVES';
END $tests$;
