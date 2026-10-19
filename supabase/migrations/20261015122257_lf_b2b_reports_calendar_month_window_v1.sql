-- LF B2B: calendar-month export windows replace fixed 30-day horizon.
-- The Reportes module remains candidate; no new screen is created here.
-- Exact scope: rules 685 and 608; no UI/runtime activation.
BEGIN;
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas WHERE id=685 AND codigo='B2B-RULE-REPORTS-EXTRACTION-001'
       AND estado='CANDIDATO' AND valor_config->>'contextual_export_max_days'='30'
       AND valor_config->>'historical_export_threshold'='GREATER_THAN_30_DAYS') <> 1
 THEN RAISE EXCEPTION 'B2B_REPORT_MONTH_RULE_GUARD_FAILED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas WHERE id=608 AND codigo='B2B-RULE-PORTAL-TREE-001'
       AND estado='CANDIDATO'
       AND valor_config->'menu_gap_audit'->>'reports_exports'='HYBRID_CONTEXTUAL_UP_TO_30_DAYS_AND_REPORTS_FOR_HISTORICAL'
       AND (SELECT count(*) FROM jsonb_array_elements(valor_config->'sidebar_nodes') j
            WHERE j->>'family'='REPORTS' AND j->>'contextual_export_max_days'='30')=1)<>1
 THEN RAISE EXCEPTION 'B2B_REPORT_NAV_RULE_GUARD_FAILED'; END IF;
 IF (SELECT count(*) FROM lf_ops.modulos WHERE module_code='B2B_REPORTES'
     AND app_shell_code='B2B_APP_SHELL' AND status='CANDIDATO')<>1
 THEN RAISE EXCEPTION 'B2B_REPORT_MODULE_MISSING'; END IF;
END $preflight$;

-- One functional source. The month boundaries are computed by backend
-- using the authorized enterprise timezone and calendar months,
-- never 30-day arithmetic or client-provided privileged scope.
UPDATE lf_ops.reglas
SET valor_config=(valor_config-'contextual_export_max_days'-'historical_export_threshold')
 || jsonb_build_object(
   'contextual_export_period_mode','CALENDAR_MONTH',
   'contextual_export_period_options',jsonb_build_array('CURRENT_MONTH','PREVIOUS_MONTH'),
   'current_month_semantics','MONTH_TO_DATE',
   'previous_month_semantics','FULL_CALENDAR_MONTH',
   'historical_export_threshold','BEFORE_PREVIOUS_CALENDAR_MONTH',
   'period_timezone_source','lf_ops.empresas.timezone',
   'server_side_period_resolution','REQUIRED'
 ),
 descripcion=replace(
   replace(descripcion,
     'horizonte máximo de 30 días',
     'horizonte de mes calendario en curso o mes calendario anterior'),
   'periodos mayores a 30 días',
   'periodos anteriores al mes calendario anterior'
 ),
 updated_at=clock_timestamp()
WHERE id=685 AND codigo='B2B-RULE-REPORTS-EXTRACTION-001' AND estado='CANDIDATO';

-- Navigation contains no business-parameter copy.
UPDATE lf_ops.reglas
SET valor_config=jsonb_set(
     jsonb_set(valor_config,'{sidebar_nodes}',
       (SELECT jsonb_agg(
         CASE WHEN item->>'family'='REPORTS'
          THEN item-'contextual_export_max_days'-'historical_export_threshold'
          ELSE item END ORDER BY ord)
        FROM jsonb_array_elements(valor_config->'sidebar_nodes')
             WITH ORDINALITY AS n(item,ord)),false),
     '{menu_gap_audit,reports_exports}',
     to_jsonb('HYBRID_CONTEXTUAL_CURRENT_OR_PREVIOUS_CALENDAR_MONTH_AND_REPORTS_FOR_PRIOR_HISTORY'::text),false),
 updated_at=clock_timestamp()
WHERE id=608 AND codigo='B2B-RULE-PORTAL-TREE-001' AND estado='CANDIDATO';

DO $readback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas WHERE id=685
     AND NOT(valor_config ? 'contextual_export_max_days')
     AND valor_config->>'contextual_export_period_mode'='CALENDAR_MONTH'
     AND valor_config->'contextual_export_period_options'='["CURRENT_MONTH","PREVIOUS_MONTH"]'::jsonb
     AND valor_config->>'period_timezone_source'='lf_ops.empresas.timezone'
     AND descripcion NOT ILIKE '%30 días%'
     AND estado='CANDIDATO')<>1
 OR (SELECT count(*) FROM lf_ops.reglas WHERE id=608
     AND NOT (valor_config::text LIKE '%contextual_export_max_days%')
     AND valor_config->'menu_gap_audit'->>'reports_exports'
         ='HYBRID_CONTEXTUAL_CURRENT_OR_PREVIOUS_CALENDAR_MONTH_AND_REPORTS_FOR_PRIOR_HISTORY'
     AND (SELECT count(*) FROM jsonb_array_elements(valor_config->'sidebar_nodes') j
          WHERE j->>'family'='REPORTS')=1
     AND estado='CANDIDATO')<>1
 THEN RAISE EXCEPTION 'B2B_REPORT_MONTH_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
