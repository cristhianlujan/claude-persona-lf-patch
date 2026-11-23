-- SALY reconciliation of five *actual* ChatGPT chat PNG files, 2026-11-22.
-- QA note only. A delivered local PNG is NOT evidence of a governed RUN or independent QA.
-- This migration MUST NOT change order/item terminal state, generate a fake RUN,
-- backdate events, bypass guards, issue host receipts or grant permissions.
-- The source PNG bytes were inspected and their SHA256 values independently
-- compared with the local manifest; they are not uploaded by this migration.
BEGIN;
DO $reconcile$
DECLARE
  v record;
  v_note jsonb;
  v_count integer := 0;
  v_run_count integer;
BEGIN
  SELECT count(*) INTO v_run_count
    FROM saly.creative_runs
    WHERE item_id = ANY(ARRAY[5,6,7,8,9]::bigint[]);
  IF v_run_count<>0
  THEN RAISE EXCEPTION 'SALY_CHAT_RECONCILE_RUNS_EXIST'; END IF;
  IF (SELECT count(*) FROM saly.creative_order_items
      WHERE id=ANY(ARRAY[5,6,7,8,9]::bigint[]))<>5
  THEN RAISE EXCEPTION 'SALY_CHAT_RECONCILE_ITEM_SET_DRIFT'; END IF;
  FOR v IN
    SELECT * FROM (VALUES
      (5::bigint,'SALY_HOME_BATCH_001','HOME',
       '03_HOME_PRINCIPAL_LOGO_OFICIAL.png',
       'cba43bc26d06f40eb037c24c7d8f2ed8fe666042e3bdf9748e0cc4cc775f0990',
       1086,1448,
       'Archivo Home entregado en chat, color CTA #008200 presente; requiere QA independiente y comparacion de fuente. No acreditar RUN.'),
      (6::bigint,'SALY_HOME_BATCH_001','ADELANTO',
       '04_SOLICITUD_ADELANTO.png',
       '9f08caec72e426bd0253bf2d28cb2c9ef70e742fb5e83d42ca9dcfd1ee283a92',
       1086,1448,
       'Archivo entregado; dimensiones 1086x1448 difieren del blueprint 1024x1536: NO APROBAR sin correccion o criterio documentado.'),
      (7::bigint,'SALY_HOME_BATCH_001','REWARDS',
       '05_SALY_REWARDS.png',
       '6cbe7c336ed0e1d39ba93c37a39fe9822a54f9f288a04e1c6274cc56504b62cd',
       1086,1448,
       'Copy de sorteos presente; Habito 1/2/3 son marcadores provisionales, no reglas aprobadas. QA independiente pendiente.'),
      (8::bigint,'SALY_HOME_TEMPLATE_AB_001','HOME_A',
       '01_HOME_A_IPHONE16PRO.png',
       '5d0960b46b9140da69b6157b0b6a5ae9b7de365551aaad30bc9b96550de5a3d9',
       1024,1536,
       'Imagen revisada con cifras S/575, 28 nov y S/300; pedido de origen REVIEW_ONLY y render_authorized=false. No crear RUN retrospectivo.'),
      (9::bigint,'SALY_HOME_TEMPLATE_AB_001','HOME_B',
       '02_HOME_B_LOGO_FOOTER.png',
       'c39e2f99aa949c8bc57b12e3aa7f1ef5567a299c2ddc67ea9d7ecfb562c7319f',
       1086,1448,
       'Imagen revisada con logo y footer; pedido de origen REVIEW_ONLY y render_authorized=false. No crear RUN retrospectivo.')
    ) v(item_id,order_code,item_code,filename,sha256,width,height,comment)
    ORDER BY item_id
  LOOP
    v_note := jsonb_build_object(
      'schema_version','SALY_CHAT_ARTIFACT_RECONCILIATION_V1',
      'status','ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE',
      'chat_delivery_observed',true,
      'source','LOCAL_CHAT_PNG_BYTES_20261122',
      'filename',v.filename,'sha256',v.sha256,
      'width',v.width,'height',v.height,
      'sha256_locally_verified',true,
      'qa_comment',v.comment,
      'qa_verdict','PENDING_INDEPENDENT',
      'official_run_verified',false,
      'terminal_item_verified',false,
      'avoid_regeneration',true
    );
    UPDATE saly.creative_order_items i
    SET qa_receipt = jsonb_set(coalesce(i.qa_receipt,'{}'::jsonb),
      '{chat_artifact_reconciliation_v1}',v_note,true)
    FROM saly.creative_orders o
    WHERE i.id=v.item_id AND i.order_id=o.id
      AND i.code=v.item_code AND o.code=v.order_code
      AND i.status='PENDIENTE' AND o.status='PLANIFICADO'
      AND coalesce(i.qa_receipt,'{}'::jsonb)='{}'::jsonb;
    IF NOT FOUND
    THEN RAISE EXCEPTION 'SALY_CHAT_RECONCILE_STATE_OR_SCOPE_DRIFT:item=%',v.item_id; END IF;
    v_count:=v_count+1;
  END LOOP;
  IF v_count<>5
  THEN RAISE EXCEPTION 'SALY_CHAT_RECONCILE_COUNT_MISMATCH'; END IF;
  IF (SELECT count(*) FROM saly.creative_order_items
      WHERE id=ANY(ARRAY[5,6,7,8,9]::bigint[])
        AND status='PENDIENTE'
        AND qa_receipt#>>'{chat_artifact_reconciliation_v1,status}'
            ='ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE')<>5
  THEN RAISE EXCEPTION 'SALY_CHAT_RECONCILE_POST_WRITE_MISMATCH'; END IF;
  RAISE NOTICE 'SALY_CHAT_RECONCILE_5_EVIDENCE_NOTES_NO_TERMINAL_STATES';
END $reconcile$;
COMMIT;
