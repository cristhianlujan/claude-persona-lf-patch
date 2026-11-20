-- IG Niubiz unique e-mail per client: parameters only.
-- Does NOT create/correct R-PAY-040/041: absent from canonical lf_ops.reglas at 2026-11-18 inspection.
-- Does NOT claim Niubiz accepts '-' in hosted form; R-PAY-045 remains sandbox NOT_TESTED.
-- Values REAL are owner-approved configuration values, NOT evidence of runtime QA/production.
BEGIN;
DO $niubiz_pre$
DECLARE
  n_total integer;
  n_rules integer;
BEGIN
  IF to_regclass('public.lf_global_config') IS NULL
     OR to_regclass('lf_ops.reglas') IS NULL THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_REQUIRED_TABLE_MISSING';
  END IF;
  SELECT count(*) INTO n_total FROM public.lf_global_config;
  SELECT count(*) INTO n_rules FROM lf_ops.reglas;
  IF n_total <> 11 OR n_rules <> 579 THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_PREIMAGE_COUNT_DRIFT config=% rules=%',n_total,n_rules;
  END IF;
  IF (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH') <> 10
     OR (SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS') <> 1 THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_PREIMAGE_SCOPE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.lf_global_config
        WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_GENERICO'
          AND config_value='niubiz-generico@lf-ficticio.invalid'
          AND value_type='EMAIL' AND value_status='FICTICIO') <> 1 THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_PREIMAGE_PLACEHOLDER_DRIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lf_global_config
       WHERE scope='PAGOS' AND config_key IN
        ('NIUBIZ_EMAIL_TEMPLATE','NIUBIZ_EMAIL_DOMAIN')) THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_TARGET_ALREADY_EXISTS';
  END IF;
END;
$niubiz_pre$;

DELETE FROM public.lf_global_config
 WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_GENERICO'
   AND config_value='niubiz-generico@lf-ficticio.invalid'
   AND value_type='EMAIL' AND value_status='FICTICIO';

INSERT INTO public.lf_global_config
 (scope,config_key,config_value,value_type,value_status,description)
VALUES
 ('PAGOS','NIUBIZ_EMAIL_TEMPLATE','{nombre}.{apellido}.lf-{codigo}',
  'TEXT','REAL',
  'Plantilla local para el correo tecnico unico por cliente ante Niubiz. Normalizar nombre y apellido a minusculas sin tildes ni espacios; codigo corto, estable y unico por cliente. Solo identificador Niubiz, no destino del recibo; uso sujeto a validacion Niubiz sandbox del guion.'),
 ('PAGOS','NIUBIZ_EMAIL_DOMAIN','gmail.com',
  'TEXT','REAL',
  'Dominio definido por el dueno para el identificador tecnico Niubiz. No acredita creacion/propiedad de cuentas gmail.com, entrega, ni autorizacion de produccion. Los recibos deben seguir al correo real del cliente.');

DO $niubiz_post$
DECLARE
  n_total integer;
  n_rules integer;
BEGIN
  SELECT count(*) INTO n_total FROM public.lf_global_config;
  SELECT count(*) INTO n_rules FROM lf_ops.reglas;
  IF n_total <> 12 OR n_rules <> 579 THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_POSTIMAGE_COUNT_DRIFT config=% rules=%',n_total,n_rules;
  END IF;
  IF (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH') <> 10
     OR (SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS') <> 2
     OR (SELECT count(*) FROM public.lf_global_config WHERE value_status='REAL') <> 12
     OR EXISTS (SELECT 1 FROM public.lf_global_config
       WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_GENERICO') THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_POSTIMAGE_SCOPE_OR_STATUS_DRIFT';
  END IF;
  IF (SELECT count(*) FROM public.lf_global_config
      WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_TEMPLATE'
        AND config_value='{nombre}.{apellido}.lf-{codigo}'
        AND value_type='TEXT' AND value_status='REAL') <> 1
     OR (SELECT count(*) FROM public.lf_global_config
      WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_DOMAIN'
        AND config_value='gmail.com'
        AND value_type='TEXT' AND value_status='REAL') <> 1 THEN
    RAISE EXCEPTION 'NIUBIZ_EMAIL_POSTIMAGE_PARAMETERS_DRIFT';
  END IF;
  RAISE NOTICE 'NIUBIZ_EMAIL_CONFIG_IN_TX_PASS config=12 auth=10 pagos=2 rules=579 ficticio=0';
END;
$niubiz_post$;
COMMIT;
