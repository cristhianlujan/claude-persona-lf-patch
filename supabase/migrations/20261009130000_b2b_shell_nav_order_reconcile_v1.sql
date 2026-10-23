-- B2B_APP_SHELL/S02. Source authority: B2B-RULE-SHELL-NAV-001. Candidate only.
-- Exact code bindings exclude other modules with identical labels (e.g. CLIENT_NAV_HOME).
-- Idempotent; updates only display_order and updated_at; no permissions or activation.
DO $b2b_nav$
DECLARE v_count integer; v_bad integer; v_changed integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM lf_ops.app_shells
                 WHERE app_shell_code='B2B_APP_SHELL' AND version='v1.0' AND status='CANDIDATO')
    OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas
                   WHERE codigo='B2B-RULE-SHELL-NAV-001' AND estado='CANDIDATO'
                     AND jsonb_typeof(valor_config->'ordered_modules')='array'
                     AND jsonb_array_length(valor_config->'ordered_modules')=10) THEN
    RAISE EXCEPTION 'B2B_NAV_AUTHORITY_DRIFT';
  END IF;
  WITH bindings(code,label) AS (VALUES
      ('B2B_MENU_INICIO','Inicio'),
      ('B2B_MENU_CARTERA','Cartera'),
      ('B2B_MENU_SIMULADOR','Simulador'),
      ('B2B_MENU_CARGAS_APROBACIONES','Aprobaciones'),
      ('B2B_MENU_OFERTAS','Ofertas'),
      ('B2B_MENU_RECAUDACION','Recaudación'),
      ('B2B_MENU_LIQUIDACIONES','Liquidaciones'),
      ('B2B_MENU_REPORTES','Reportes'),
      ('B2B_MENU_CONTROVERSIAS','Controversias'),
      ('B2B_MENU_CONFIGURACION','Configuración')
  ), canonical AS (
    SELECT item->>'label' AS label,(item->>'order')::integer AS ord
    FROM lf_ops.reglas r
    CROSS JOIN LATERAL jsonb_array_elements(r.valor_config->'ordered_modules') item
    WHERE r.codigo='B2B-RULE-SHELL-NAV-001'
  )
  SELECT count(*),count(*) FILTER(WHERE c.label IS NULL OR m.menu_item_code IS NULL
        OR m.label IS DISTINCT FROM b.label OR m.parent_menu_item_code IS NOT NULL
        OR m.status IS DISTINCT FROM 'CANDIDATO')
  INTO v_count,v_bad
  FROM bindings b LEFT JOIN canonical c ON c.label=b.label
  LEFT JOIN lf_ops.menu_items m ON m.menu_item_code=b.code;
  IF v_count<>10 OR v_bad<>0 THEN
    RAISE EXCEPTION 'B2B_NAV_SCOPE_BINDING_DRIFT rows=% invalid=%',v_count,v_bad;
  END IF;
  WITH bindings(code,label) AS (VALUES
      ('B2B_MENU_INICIO','Inicio'),
      ('B2B_MENU_CARTERA','Cartera'),
      ('B2B_MENU_SIMULADOR','Simulador'),
      ('B2B_MENU_CARGAS_APROBACIONES','Aprobaciones'),
      ('B2B_MENU_OFERTAS','Ofertas'),
      ('B2B_MENU_RECAUDACION','Recaudación'),
      ('B2B_MENU_LIQUIDACIONES','Liquidaciones'),
      ('B2B_MENU_REPORTES','Reportes'),
      ('B2B_MENU_CONTROVERSIAS','Controversias'),
      ('B2B_MENU_CONFIGURACION','Configuración')
  ), canonical AS (
    SELECT item->>'label' AS label,(item->>'order')::integer AS ord
    FROM lf_ops.reglas r
    CROSS JOIN LATERAL jsonb_array_elements(r.valor_config->'ordered_modules') item
    WHERE r.codigo='B2B-RULE-SHELL-NAV-001'
  )
  UPDATE lf_ops.menu_items m SET display_order=c.ord,updated_at=now()
  FROM bindings b JOIN canonical c ON c.label=b.label
  WHERE m.menu_item_code=b.code AND m.display_order IS DISTINCT FROM c.ord;
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  WITH bindings(code,label) AS (VALUES
      ('B2B_MENU_INICIO','Inicio'),
      ('B2B_MENU_CARTERA','Cartera'),
      ('B2B_MENU_SIMULADOR','Simulador'),
      ('B2B_MENU_CARGAS_APROBACIONES','Aprobaciones'),
      ('B2B_MENU_OFERTAS','Ofertas'),
      ('B2B_MENU_RECAUDACION','Recaudación'),
      ('B2B_MENU_LIQUIDACIONES','Liquidaciones'),
      ('B2B_MENU_REPORTES','Reportes'),
      ('B2B_MENU_CONTROVERSIAS','Controversias'),
      ('B2B_MENU_CONFIGURACION','Configuración')
  ), canonical AS (
    SELECT item->>'label' AS label,(item->>'order')::integer AS ord
    FROM lf_ops.reglas r
    CROSS JOIN LATERAL jsonb_array_elements(r.valor_config->'ordered_modules') item
    WHERE r.codigo='B2B-RULE-SHELL-NAV-001'
  )
  SELECT count(*) FILTER(WHERE m.display_order IS DISTINCT FROM c.ord)
  INTO v_bad FROM bindings b JOIN canonical c ON c.label=b.label
    JOIN lf_ops.menu_items m ON m.menu_item_code=b.code;
  IF v_bad<>0 THEN RAISE EXCEPTION 'B2B_NAV_POST_UPDATE_PARITY_FAILED %',v_bad; END IF;
  RAISE NOTICE 'B2B_NAV_ORDERS_RECONCILED updated=%',v_changed;
END
$b2b_nav$;
