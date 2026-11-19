-- IG Chat 12 | Familia A | REG_ATQ_002 prerequisite only.
-- Owner-authorized scope: add the existing escalation ceiling as REAL config.
-- Does NOT update lf_ops.reglas, does NOT mint a RUN, does NOT bypass V2.
-- The governed CORRECT_VIGENTE/FUNCTIONAL needs a fresh Product Director RUN
-- and separately authenticated RULE_CONTRACT_LEVEL evidence from Merge Train.
BEGIN;
DO $atq002_pre$
DECLARE
  v_existing jsonb;
BEGIN
  SELECT valor_config INTO v_existing
  FROM lf_ops.reglas
  WHERE codigo='REG_ATQ_002' AND estado='VIGENTE';
  IF v_existing IS DISTINCT FROM
    '{"condicion_activacion":"score_sospechoso_o_turnstile_fallo","max_escaladas_antes_bloqueo":2}'::jsonb
  THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_VIGENTE_PREIMAGE_DRIFT'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.lf_global_config
    WHERE scope='AUTH' AND config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK'
  ) THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_CONFIG_ALREADY_EXISTS'; END IF;
END $atq002_pre$;

-- Real same-transaction reversible probe. Live application writes only
-- AFTER the probe has rolled back and its absence was checked.
SAVEPOINT ig_chat12_atq002_probe;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
VALUES (
 'AUTH','CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK','2','INTEGER','REAL',
 'Maximo de escaladas de desafio visual antes del bloqueo; heredado exactamente de REG_ATQ_002 VIGENTE; no cambia el umbral ni el sujeto.'
);
DO $atq002_probe$
BEGIN
  IF (SELECT count(*) FROM public.lf_global_config
    WHERE scope='AUTH'
    AND config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK'
    AND config_value='2' AND value_type='INTEGER' AND value_status='REAL')<>1
  THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_PROBE_MISMATCH'; END IF;
END $atq002_probe$;
ROLLBACK TO SAVEPOINT ig_chat12_atq002_probe;
RELEASE SAVEPOINT ig_chat12_atq002_probe;

DO $atq002_rollback_verify$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_global_config
    WHERE scope='AUTH'
      AND config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK')
  THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_ROLLBACK_INCOMPLETE'; END IF;
END $atq002_rollback_verify$;

INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
VALUES (
 'AUTH','CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK','2','INTEGER','REAL',
 'Maximo de escaladas de desafio visual antes del bloqueo; heredado exactamente de REG_ATQ_002 VIGENTE; no cambia el umbral ni el sujeto.'
);

DO $atq002_post$
BEGIN
  IF (SELECT count(*) FROM public.lf_global_config
     WHERE scope='AUTH'
       AND config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK'
       AND config_value='2' AND value_type='INTEGER' AND value_status='REAL')<>1
    OR public.lf_auth_config_integer_v1(
      'CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK')<>2
    OR (SELECT valor_config FROM lf_ops.reglas
        WHERE codigo='REG_ATQ_002' AND estado='VIGENTE')
       IS DISTINCT FROM
       '{"condicion_activacion":"score_sospechoso_o_turnstile_fallo","max_escaladas_antes_bloqueo":2}'::jsonb
  THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_POSTIMAGE_MISMATCH'; END IF;
  RAISE NOTICE 'IG_CHAT12_ATQ002_CONFIG_PASS; RULE_UNCHANGED; V2_PENDING';
END $atq002_post$;
COMMIT;
