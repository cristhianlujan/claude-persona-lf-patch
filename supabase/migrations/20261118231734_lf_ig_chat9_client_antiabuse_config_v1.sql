-- IG Chat9 Lot2, prerequisite definitions for two governed V2 CORRECT_VIGENTE runs.
-- Owner 2026-11-18 18:10 America/Lima. NO lf_ops.reglas modifications.
-- Numeric baselines derived from existing VIGENTE Client rules and policy.
BEGIN;
DO $chat9_pre$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config)<>40
 OR (SELECT count(*) FROM lf_ops.reglas)<>579
 OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>438
 OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')<>141
 OR (SELECT count(*) FROM lf_ops.politicas_sesion
     WHERE policy_code='SESSION-CLIENT-DEFAULT' AND status='VIGENTE'
       AND max_concurrent_sessions=3)<>1
 OR (SELECT count(*) FROM lf_ops.reglas
     WHERE codigo='REG_SES_003' AND estado='VIGENTE'
       AND valor_config='{"max_sesiones":1,"ventana_minutos":5}'::jsonb)<>1
 OR (SELECT count(*) FROM lf_ops.reglas
     WHERE codigo='REG_ATQ_016' AND estado='VIGENTE'
       AND valor_config='{"accion":"bloqueo_ip_1h_y_alerta","patron_1":{"ventana_minutos":10,"dni_distintos_por_ip":20},"patron_2":{"ips_por_dni":5,"ventana_minutos":10}}'::jsonb)<>1
 THEN RAISE EXCEPTION 'IG_CHAT9_L2_CLIENT_BASELINE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_global_config
     WHERE scope='CLIENT' AND config_key IN (
       'ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS',
       'ONBOARDING_ACCOUNT_WINDOW_MINUTES',
       'ATQ_DISTINCT_DNI_PER_IP_SIGNAL_LIMIT',
       'ATQ_DISTINCT_IP_PER_DNI_SIGNAL_LIMIT',
       'ATQ_SIGNAL_WINDOW_MINUTES',
       'ATQ_ACCOUNT_HOLD_MINUTES'))
 THEN RAISE EXCEPTION 'IG_CHAT9_L2_KEY_EXISTS'; END IF;
END $chat9_pre$;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
VALUES
('CLIENT','ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS','3','INTEGER','REAL',
 'Maximo concurrente por CUENTA en onboarding; origen politica SESSION-CLIENT-DEFAULT VIGENTE; no limita una IP compartida.'),
('CLIENT','ONBOARDING_ACCOUNT_WINDOW_MINUTES','5','INTEGER','REAL',
 'Ventana de observacion onboarding por CUENTA; valor heredado de REG_SES_003 sin mantener el bloqueo IP.'),
('CLIENT','ATQ_DISTINCT_DNI_PER_IP_SIGNAL_LIMIT','20','INTEGER','REAL',
 'Senal de riesgo por DNIs distintos por IP, no prueba contra usuarios individuales, nunca bloquear IP compartida solo por este umbral.'),
('CLIENT','ATQ_DISTINCT_IP_PER_DNI_SIGNAL_LIMIT','5','INTEGER','REAL',
 'Senal de riesgo por IPs distintas observadas para la misma identidad DNI; no sancion automatica por IP compartida.'),
('CLIENT','ATQ_SIGNAL_WINDOW_MINUTES','10','INTEGER','REAL',
 'Ventana de deteccion de senales REG_ATQ_016, umbral historico; las acciones afectan solo cuenta validada.'),
('CLIENT','ATQ_ACCOUNT_HOLD_MINUTES','60','INTEGER','REAL',
 'Duracion heredada del antiguo bloqueo IP una hora; aplicar exclusivamente a cuenta individual con verificacion de abuso adicional y control de recurso.');
DO $chat9_post$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config)<>46
 OR (SELECT count(*) FROM public.lf_global_config WHERE scope='CLIENT' AND value_status='REAL' AND value_type='INTEGER')<>6
 OR (SELECT count(*) FROM lf_ops.reglas)<>579
 OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>438
 OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')<>141
 OR (SELECT count(*) FROM lf_ops.reglas
     WHERE codigo IN ('REG_SES_003','REG_ATQ_016')
       AND estado='VIGENTE'
       AND (valor_config ? 'max_sesiones' OR valor_config ? 'patron_1'))<>2
 THEN RAISE EXCEPTION 'IG_CHAT9_L2_CONFIG_READBACK_MISMATCH'; END IF;
 RAISE NOTICE 'IG_CHAT9_L2_CONFIG_PASS_40_TO_46_6_PARAMS_RULES_UNCHANGED';
END $chat9_post$;
COMMIT;
