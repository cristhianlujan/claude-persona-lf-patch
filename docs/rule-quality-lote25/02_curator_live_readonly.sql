-- L25 -- SOLO SELECT LIVE mhwmirqcgxxukpctffuv. Hash sha256 jsonb ordenado. Input literal de propuestas desde 01_propuestas_reglas.json, sin cambios en base.
-- L13 maps son fixtures PG18 referenciados por Git y NO ownership live.
-- Nota: G25_02 structural key overlap!=conflicto semantico por sí solo; requiere revisión humana.

-- G25_01 | SOLELY SELECT; hash over ALL ordered jsonb rows, no DML/DDL.
WITH source_rows AS MATERIALIZED (
SELECT categoria,estado,count(*)::integer AS n FROM lf_ops.reglas WHERE categoria IN ('pago','niubiz','checkout','notificacion') GROUP BY categoria,estado
), packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS rows FROM source_rows
)
SELECT 'G25_01'::text AS probe, jsonb_array_length(rows) AS n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- G25_02 | SOLELY SELECT; hash over ALL ordered jsonb rows, no DML/DDL.
WITH source_rows AS MATERIALIZED (
WITH proposals AS (
 SELECT * FROM jsonb_to_recordset($l25$[{"id":"L25-01","tipo":"NUEVA_PROPUESTA","codigo":"REG_CLIENT_INSTALLMENT_STATUS_025","base_codigo":null,"categoria":"pago","familia":"CHECKOUT_PAGOS","descripcion":"Cada cuota nace PENDIENTE. EN_PROCESO identifica un intento de cobro abierto; PAGADA exige pago confirmado y es final; CANCELADA es final. VENCIDA se determina por la fecha contractual: sin pago confirmado, pasa a VENCIDA al comenzar el día siguiente al vencimiento, a las 00:00 hora America/Lima; un rechazo de cobro por sí solo no produce VENCIDA. Durante la reconciliación de medianoche, un resultado NO_DETERMINADO constituye la excepción explícita: permanece EN_PROCESO con registro, alerta y escalamiento según su regla específica.","valor_config":{"estados":["PENDIENTE","EN_PROCESO","PAGADA","VENCIDA","CANCELADA"],"estado_inicial":"PENDIENTE","en_proceso_si":"INTENTO_COBRO_ABIERTO","pagada_si":"PAGO_CONFIRMADO","estados_finales":["PAGADA","CANCELADA"],"vencida_si":"FECHA_LOCAL_ACTUAL_MAYOR_QUE_FECHA_CUOTA_Y_SIN_PAGO_CONFIRMADO","gracia":false,"corte_local":"00:00","timezone":"America/Lima","rechazo_solo_no_vencida":true,"excepcion_reconciliacion":"NO_DETERMINADO_CONSERVA_EN_PROCESO"}},{"id":"L25-02","tipo":"NUEVA_PROPUESTA","codigo":"REG_CLIENT_INSTALLMENT_MIDNIGHT_RECON_025","base_codigo":null,"categoria":"pago","familia":"CHECKOUT_PAGOS","descripcion":"A las 00:00 de America/Lima el proceso revisa todas las cuotas EN_PROCESO y concilia cada intento con información o archivo Niubiz. CONFIRMADO actualiza a PAGADA. RECHAZADO actualiza a VENCIDA únicamente si ya pasó su fecha contractual, o PENDIENTE si no pasó. NO_DETERMINADO por proveedor sin respuesta, referencia ausente, referencia duplicada en el archivo o monto que no coincide conserva EN_PROCESO; se registra como excepción, se escala a un humano y se envía la alerta de excepción. La conciliación es idempotente. El formato real del archivo Niubiz no está identificado y exige revisión semántica antes de implementación.","valor_config":{"proveedor":"NIUBIZ","fuente_conciliacion":"DATA_O_ARCHIVO_NIUBIZ","formato_fuente":"DESCONOCIDO_REQUIERE_REVISION_SEMANTICA","corte_local":"00:00","timezone":"America/Lima","cuotas_objetivo_estado":"EN_PROCESO","resultado_confirmado":"PAGADA","resultado_rechazado_con_fecha_pasada":"VENCIDA","resultado_rechazado_con_fecha_no_pasada":"PENDIENTE","resultado_no_determinado":"EN_PROCESO_CON_EXCEPCION_ALERTA_Y_ESCALAMIENTO","no_determinado_motivos":["PROVEEDOR_NO_RESPONDE","REFERENCIA_AUSENTE","REFERENCIA_DUPLICADA_EN_ARCHIVO","MONTO_NO_COINCIDE"],"idempotente":true}},{"id":"L25-03","tipo":"NUEVA_PROPUESTA","codigo":"REG_CLIENT_INSTALLMENT_RECON_ALERT_025","base_codigo":null,"categoria":"notificacion","familia":"CONTENIDO_COMUNICACIONES","descripcion":"Cuando la conciliación de medianoche no determina el resultado de una cuota EN_PROCESO, debe registrar la excepción, escalarla a una persona y enviar correo con detalle de cuota, referencia, monto, fecha y motivo. El destinatario se obtiene de un parámetro configurable, nunca de una dirección fija en la regla. El correo no incluye datos de tarjeta ni nombre del cliente. Esta alerta operativa de excepción no define recordatorios de vencimiento.","valor_config":{"evento":"RECONCILIACION_NO_DETERMINADA","canal":"CORREO","destinatario":"PARAMETRO_CONFIGURABLE_SIN_VALOR","campos_detalle":["cuota","referencia","monto","fecha","motivo"],"datos_prohibidos":["datos_tarjeta","nombre_cliente"],"escalamiento":"HUMANO","registra_excepcion":true,"no_equivale_recordatorio":true}},{"id":"L25-04","tipo":"NUEVA_PROPUESTA","codigo":"REG_CLIENT_INSTALLMENT_CANCELLATION_025","base_codigo":null,"categoria":"pago","familia":"CHECKOUT_PAGOS","descripcion":"La cancelación puede solicitarse para una cuota o para el plan completo. Los estados PAGADA y CANCELADA son finales y no cambian. Para EN_PROCESO se propone bloquear la cancelación hasta reconciliar el intento, pero esta restricción es un SUPUESTO PENDIENTE DE CONFIRMACIÓN DEL DUEÑO. La posibilidad de cancelar una cuota VENCIDA permanece PENDIENTE_DE_LEGAL y no se resuelve aquí. No se definen políticas de mora, reintentos ni recordatorios.","valor_config":{"alcances":["CUOTA","PLAN_COMPLETO"],"estados_que_no_cambian":["PAGADA","CANCELADA"],"cancelacion_en_proceso":"SUPUESTO_PENDIENTE_CONFIRMACION_DUENO_NO_HASTA_RECONCILIAR","cancelacion_vencida":"PENDIENTE_DE_LEGAL","mora":"NO_DEFINIDA","reintentos":"NO_DEFINIDOS","recordatorios":"NO_DEFINIDOS"}},{"id":"L25-05","tipo":"CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE","codigo":"REG_NIU_001","base_codigo":"REG_NIU_001","categoria":"niubiz","familia":"CHECKOUT_PAGOS","descripcion":"Niubiz es el proveedor único de recaudo del producto para el mercado peruano, incluyendo cobros con tarjeta y con Yape. Toda transacción de recaudo se procesa por Niubiz; no se implementan otros gateways en el MVP. Esta regla no define si Yape permite cobros recurrentes ni su modalidad para cuotas futuras.","valor_config":{"gateway":"Niubiz","mercado":"Peru","otros_gateways_mvp":false,"alcance_proveedor_unico":["RECAUDO","TARJETA","YAPE"],"exclusividad_recaudo":"NIUBIZ_UNICO_PROVEEDOR"}},{"id":"L25-06","tipo":"CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE","codigo":"REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001","base_codigo":"REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001","categoria":"pago","familia":"CHECKOUT_PAGOS","descripcion":"Un intento de cobro de una cuota reutiliza los outcomes normalizados de pago. PAYMENT_CONFIRMED marca esa cuota como pagada. PAYMENT_DECLINED_CONFIRMED mantiene la cuota sin pagar y puede habilitar una acción de recuperación/manual solo si backend lo permite. PAYMENT_PENDING_CONFIRMATION mantiene la cuota en estado de confirmación y bloquea nuevos intentos hasta reconciliar. PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT no constituye rechazo del cliente ni pago fallido confirmado. Ninguno de estos estados técnicos, por sí solo, marca la cuota como vencida o en mora: el estado VENCIDA depende de la fecha contractual sin gracia: al día siguiente a las 00:00 de America/Lima si no existe pago confirmado. La política de mora sigue pendiente y no se define aquí. Si la reconciliación es NO_DETERMINADO, la excepción permanece EN_PROCESO hasta resolverla.","valor_config":{"front":"CLIENTE","payment_ledger":"PENDING_CANONICAL_PAYMENT_PLAN_LEDGER","source_rule_code":"REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001","PAYMENT_CONFIRMED":"MARK_TARGET_INSTALLMENT_PAID","overdue_authority":"CONTRACTUAL_DUE_DATE_NO_GRACE_AMERICA_LIMA","decline_marks_overdue":"DENY_REJECTION_ALONE_ONLY_DUE_DATE","PAYMENT_DECLINED_CONFIRMED":"KEEP_UNPAID_ALLOW_RECOVERY_ACTION_ONLY_IF_SERVER_ENABLED","grace_or_delinquency_policy":"NO_GRACE_FOR_VENCIDA_MORA_PENDING","PAYMENT_PENDING_CONFIRMATION":"KEEP_CONFIRMING_BLOCK_ALL_NEW_ATTEMPTS","technical_failure_marks_overdue":"DENY","manual_recovery_payment_rule_code":"REG_CLIENT_INSTALLMENT_PAYMENT_DUE_001","PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT":"KEEP_UNPAID_ALLOW_CONTROLLED_RETRY_LATER","undetermined_midnight_exception":"KEEP_EN_PROCESO_ESCALATE_AND_ALERT"}},{"id":"L25-07","tipo":"CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE","codigo":"REG_CHK_CUO_006","base_codigo":"REG_CHK_CUO_006","categoria":"checkout","familia":"CHECKOUT_PAGOS","descripcion":"Se mantiene la cancelación del plan en cuotas sin penalidades y su visibilidad antes del pago. El texto actual «en cualquier momento» requiere conciliarse con una restricción PROPUESTA, NO APROBADA: si una cuota está EN_PROCESO, no cancelar hasta reconciliar. La cancelación de VENCIDA permanece PENDIENTE_DE_LEGAL. El copy final requiere revisión y aprobación del dueño; no se publica esta redacción.","valor_config":{"posicion":"bajo_checkbox_autorizacion","penalidad":false,"texto_visible":"Podrás cancelar tu plan cuando lo necesites. Sin penalidades.","cancelacion_permitida":true,"cancelacion_en_proceso":"SUPUESTO_PENDIENTE_CONFIRMACION_DUENO","cancelacion_cuota_vencida":"PENDIENTE_DE_LEGAL","texto_visible_estado":"PENDIENTE_REVISION_NO_PUBLICAR"}},{"id":"L25-08","tipo":"CAMBIO_PROPUESTO_NO_ACTUALIZAR_VIGENTE","codigo":"REG_CHK_014","base_codigo":"REG_CHK_014","categoria":"checkout","familia":"CHECKOUT_PAGOS","descripcion":"La cancelación del cobro recurrente del plan se solicita desde Mis operaciones y no genera penalidades. El alcance «en cualquier momento» necesita validación del dueño cuando haya cuota EN_PROCESO: se propone esperar su reconciliación, aún no aprobado. Cancelar una cuota VENCIDA sigue PENDIENTE_DE_LEGAL. La carta de no adeudo solo corresponde a deuda totalmente cancelada.","valor_config":{"desde":"Mis operaciones","penalidades":false,"carta_no_adeudo":"al_cancelar_totalmente","cancelacion_permitida":true,"cancelacion_en_proceso":"SUPUESTO_PENDIENTE_CONFIRMACION_DUENO","cancelacion_cuota_vencida":"PENDIENTE_DE_LEGAL"}},{"id":"L25-09","tipo":"REVISADA_SIN_CAMBIO_PROPUESTO","codigo":"REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001","base_codigo":"REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001","categoria":"notificacion","familia":"CONTENIDO_COMUNICACIONES","descripcion":"Los recordatorios de una cuota pendiente se generan únicamente desde un plan activo y su cronograma contractual. Son comunicaciones operativas del plan, no marketing, y no requieren consent_marketing. La política exacta de anticipación, frecuencia y canales debe ser configurable y no se infiere de reglas antiguas de vencimiento de ofertas. El mensaje no puede inventar montos o fechas y debe evitar exponer detalles financieros sensibles en superficies no autenticadas más allá de lo autorizado por la futura política de comunicación.","valor_config":{"front":"CLIENTE","channel_policy":"PENDING_CANONICAL_NOTIFICATION_CHANNEL_POLICY","trigger_source":"ACTIVATED_PLAN_SNAPSHOT_PLUS_PAYMENT_LEDGER","schedule_policy":"PENDING_CANONICAL_DUE_REMINDER_POLICY","notification_type":"OPERATIONAL","hardcoded_24h_before":"DENY","requires_active_plan":true,"authenticated_destination":"MY_OPERATIONS_PENDING_CANONICAL_ROUTE","existing_candidate_limits":["REG_NOT_005","REG_NOT_006"],"amount_and_due_date_source":"ACTIVATED_PLAN_SNAPSHOT","marketing_consent_required":false,"requires_pending_installment":true,"existing_candidate_channel_rule":"REG_NOT_001","existing_candidate_template_rule":"REG_NOT_004","raw_dni_or_full_account_data_in_notification":"DENY","sensitive_financial_detail_in_unauthenticated_preview":"DENY_BY_DEFAULT"}},{"id":"L25-10","tipo":"REVISADA_SIN_CAMBIO_PROPUESTO","codigo":"REG_CHK_CUO_003","base_codigo":"REG_CHK_CUO_003","categoria":"checkout","familia":"CHECKOUT_PAGOS","descripcion":"Yape está habilitado para pagar el monto inicial únicamente. Las cuotas siguientes no pueden cobrarse por Yape. La configuración del cobro recurrente de cuotas para usuarios que pagaron con Yape está pendiente de definición. RESUELTO 2026-07-12 con investigacion externa (Niubiz/pasarelasdepagos.com): Yape/QR NO soporta debito automatico real -- solo tarjeta con token guardado (Niubiz Wallet) permite cobro recurrente sin accion del usuario. Yape SI puede usarse para cuotas pero el pago es MANUAL cada mes (usuario debe volver a pagar, con recordatorio WhatsApp antes del vencimiento). SOLUCION: campo configurable por aliado B2B \"acepta_yape_en_cuotas\" (boolean) -- si false, cuotas 2+ solo aceptan tarjeta; si true, se ofrece Yape con flujo de pago manual mensual + recordatorio.","valor_config":{"yape_habilitado_para":"monto_inicial_unicamente","cuotas_recurrentes_yape":"pendiente_definicion"}},{"id":"L25-11","tipo":"REVISADA_SIN_CAMBIO_PROPUESTO","codigo":"REG_CHK_CUO_009","base_codigo":"REG_CHK_CUO_009","categoria":"checkout","familia":"CHECKOUT_PAGOS","descripcion":"En el contexto de cuotas, la carta de no adeudo se emite cuando el usuario completa el pago total del plan (última cuota). No se emite al pagar el monto inicial. El texto dice: \"Se emitirá al confirmar la cancelación total de tu deuda.\"","valor_config":{"texto_ui":"Se emitirá al confirmar la cancelación total de tu deuda.","no_emitir_en":"monto_inicial","momento_emision":"ultima_cuota_pagada"}},{"id":"L25-12","tipo":"REVISADA_SIN_CAMBIO_PROPUESTO","codigo":"REG_CHK_011","base_codigo":"REG_CHK_011","categoria":"checkout","familia":"CHECKOUT_PAGOS","descripcion":"Yape está disponible para pagar el monto inicial del plan en cuotas. El mecanismo para cobrar las cuotas siguientes cuando el usuario pagó con Yape está pendiente de confirmación con el aliado y la plataforma. RESUELTO 2026-07-12 con investigacion externa (Niubiz/pasarelasdepagos.com): Yape/QR NO soporta debito automatico real -- solo tarjeta con token guardado (Niubiz Wallet) permite cobro recurrente sin accion del usuario. Yape SI puede usarse para cuotas pero el pago es MANUAL cada mes (usuario debe volver a pagar, con recordatorio WhatsApp antes del vencimiento). SOLUCION: campo configurable por aliado B2B \"acepta_yape_en_cuotas\" (boolean) -- si false, cuotas 2+ solo aceptan tarjeta; si true, se ofrece Yape con flujo de pago manual mensual + recordatorio.","valor_config":{"monto_inicial":"disponible","cuotas_siguientes":"PENDIENTE_DEFINICION","opciones_posibles":["recordatorio_whatsapp_con_link_pago","solicitar_tarjeta_adicional_para_recurrencia"]}}]$l25$::jsonb) AS p(
 id text,tipo text,codigo text,base_codigo text,categoria text,familia text,descripcion text,valor_config jsonb)
), maps(categoria,familia) AS (VALUES
 ('pago','CHECKOUT_PAGOS'),('niubiz','CHECKOUT_PAGOS'),
 ('checkout','CHECKOUT_PAGOS'),('notificacion','CONTENIDO_COMUNICACIONES')
)
SELECT p.id,p.tipo,p.codigo,p.base_codigo,p.categoria,p.familia,
 (SELECT count(*)::integer FROM lf_ops.reglas r WHERE r.codigo=p.codigo) AS same_code_live_count,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',r.codigo,'estado',r.estado)
  ORDER BY r.codigo),'[]'::jsonb) FROM lf_ops.reglas r WHERE r.codigo=p.codigo) AS same_code,
 (SELECT count(*)::integer FROM lf_ops.reglas r WHERE r.estado='VIGENTE' AND r.codigo<>p.codigo
   AND r.categoria=p.categoria AND lower(btrim(r.descripcion))=lower(btrim(p.descripcion))
   AND coalesce(r.valor_config,'{}'::jsonb)=p.valor_config) AS exact_content_duplicate_vigente_count,
 (SELECT coalesce(jsonb_agg(r.codigo ORDER BY r.codigo),'[]'::jsonb) FROM lf_ops.reglas r
  WHERE r.estado='VIGENTE' AND r.codigo<>p.codigo AND r.categoria=p.categoria
   AND lower(btrim(r.descripcion))=lower(btrim(p.descripcion))
   AND coalesce(r.valor_config,'{}'::jsonb)=p.valor_config) AS exact_content_duplicate_codes,
 (SELECT count(*)::integer FROM lf_ops.reglas r WHERE r.estado='VIGENTE' AND r.codigo<>p.codigo AND r.categoria=p.categoria
   AND jsonb_typeof(coalesce(r.valor_config,'{}'::jsonb))='object'
   AND EXISTS(SELECT 1 FROM jsonb_object_keys(p.valor_config) AS k(key)
       WHERE r.valor_config ? k.key AND r.valor_config->k.key IS DISTINCT FROM p.valor_config->k.key)
 ) AS possible_structural_config_conflict_count,
 (SELECT coalesce(jsonb_agg(code ORDER BY code),'[]'::jsonb) FROM (SELECT r.codigo AS code
  FROM lf_ops.reglas r WHERE r.estado='VIGENTE' AND r.codigo<>p.codigo AND r.categoria=p.categoria
    AND jsonb_typeof(coalesce(r.valor_config,'{}'::jsonb))='object'
    AND EXISTS(SELECT 1 FROM jsonb_object_keys(p.valor_config) AS k(key)
      WHERE r.valor_config ? k.key AND r.valor_config->k.key IS DISTINCT FROM p.valor_config->k.key)
  ORDER BY r.codigo LIMIT 12) sample) AS possible_conflict_codes_first12,
 (SELECT count(*)::integer FROM maps m WHERE m.categoria=p.categoria AND m.familia=p.familia) AS matches_l13_fixture_mapping,
 (SELECT encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') FROM lf_ops.reglas r WHERE r.codigo=p.codigo LIMIT 1) AS live_preimage_sha256
FROM proposals p
), packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS rows FROM source_rows
)
SELECT 'G25_02'::text AS probe, jsonb_array_length(rows) AS n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- G25_03 | SOLELY SELECT; hash over ALL ordered jsonb rows, no DML/DDL.
WITH source_rows AS MATERIALIZED (
SELECT codigo,categoria,estado,titulo,
 array_to_string((string_to_array(descripcion,' '))[1:12],' ') AS source_quote_max_12_words,
 encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') AS live_row_sha256,
 jsonb_strip_nulls(jsonb_build_object(
   'overdue_authority',valor_config->'overdue_authority',
   'grace_or_delinquency_policy',valor_config->'grace_or_delinquency_policy',
   'cancelacion_permitida',valor_config->'cancelacion_permitida',
   'provider_binding',valor_config->'provider_binding',
   'cuotas_siguientes',valor_config->'cuotas_siguientes',
   'channel_policy',valor_config->'channel_policy'
 )) AS config_relevant
 FROM lf_ops.reglas r WHERE codigo IN ('REG_NIU_001','REG_NIU_003','REG_CHK_010','REG_CHK_014','REG_CHK_CUO_002','REG_CHK_CUO_003','REG_CHK_CUO_005','REG_CHK_CUO_006','REG_CHK_CUO_009','REG_CHK_011','REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001','REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001','REG_CLIENT_PAYMENT_OUTCOME_NORMALIZATION_001','REG_CLIENT_CHECKOUT_PAYMENT_METHOD_ELIGIBILITY_001','REG_CLIENT_INSTALLMENT_PAYMENT_DUE_001','REG_CLIENT_INSTALLMENT_PLAN_SNAPSHOT_001') ORDER BY codigo
), packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS rows FROM source_rows
)
SELECT 'G25_03'::text AS probe, jsonb_array_length(rows) AS n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- G25_04 | SOLELY SELECT; hash over ALL ordered jsonb rows, no DML/DDL.
WITH source_rows AS MATERIALIZED (
SELECT n.nspname AS schema_name,p.proname AS function_name,
 pg_get_function_identity_arguments(p.oid) AS args,
 md5(pg_get_functiondef(p.oid)) AS function_md5
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('lf_rule_promotion_apply_v1','lf_rule_promotion_apply_batch_v1','lf_rule_promotion_decide_batch_v1',
 'lf_rule_promotion_report_v1','lf_rule_promotion_guard_v1',
 'lf_rule_promotion_citation_record_v1','lf_rule_promotion_citation_verify_v1',
 'lf_rule_promotion_citation_scope_guard_v2')
), packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS rows FROM source_rows
)
SELECT 'G25_04'::text AS probe, jsonb_array_length(rows) AS n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- G25_05 | SOLELY SELECT; hash over ALL ordered jsonb rows, no DML/DDL.
WITH source_rows AS MATERIALIZED (
SELECT codigo,estado,categoria,
 encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') AS live_full_row_sha256,
 encode(sha256(convert_to(coalesce(valor_config,'{}'::jsonb)::text,'UTF8')),'hex') AS live_config_sha256
 FROM lf_ops.reglas r WHERE codigo IN ('REG_NIU_001','REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001','REG_CHK_CUO_006','REG_CHK_014','REG_CLIENT_INSTALLMENT_DUE_NOTIFICATION_001','REG_CHK_CUO_003','REG_CHK_CUO_009','REG_CHK_011') ORDER BY codigo
), packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS rows FROM source_rows
)
SELECT 'G25_05'::text AS probe, jsonb_array_length(rows) AS n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- G25_06 | busqueda adicional acotada, solo SELECT
WITH source_rows AS MATERIALIZED (
SELECT codigo,categoria,estado,titulo,
 CASE WHEN descripcion ~* 'gracia' THEN 'GRACIA'
 WHEN descripcion ~* 'cancelar.{0,35}(plan|cobro)' OR descripcion ~* '(plan|cobro).{0,45}en cualquier momento' THEN 'CANCELACION'
 WHEN descripcion ~* '(cuota.{0,50}vencida|vencida.{0,40}cuota)' THEN 'VENCIMIENTO'
 ELSE 'OTRO' END AS motivo_busqueda
FROM lf_ops.reglas WHERE estado='VIGENTE' AND (descripcion ~* '(gracia|cancelar.{0,35}(plan|cobro)|cobro.{0,45}en cualquier momento|cuota.{0,50}vencida|vencida.{0,40}cuota)' OR titulo ~* 'cancelaci[oó]n del plan')
ORDER BY codigo
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows)
SELECT 'G25_06'::text probe,jsonb_array_length(rows) n,encode(sha256(convert_to(rows::text,'UTF8')),'hex') sha256_result,rows result_rows FROM packed;
