-- IG Familia A, REG_ATQ_005: prueba funcional source-bound en el PostgreSQL 17 real.
-- No altera lf_ops.reglas, ni Owner V2, ni evidencias. Solo TEMP y reversión.
-- PG17: BEGIN + dos SAVEPOINT/ROLLBACK reales + SELECT independiente posterior.
BEGIN;
CREATE TEMP TABLE ig_chat12_atq005_rule_probe (payload jsonb NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ig_chat12_atq005_cfg_probe (
  scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,
  value_type text NOT NULL,value_status text NOT NULL
) ON COMMIT DROP;
INSERT INTO ig_chat12_atq005_rule_probe(payload)
SELECT to_jsonb(r) FROM lf_ops.reglas r WHERE codigo='REG_ATQ_005';
INSERT INTO ig_chat12_atq005_cfg_probe
SELECT scope,config_key,config_value,value_type,value_status
FROM public.lf_global_config WHERE scope='AUTH' AND config_key='OTP_HMAC_TIMESTAMP_WINDOW_SECONDS';
DO $pre$
DECLARE v_src constant text:='a10969d2ce8d452ff678df72537878dd597f8fce503cd33346848a033aa60075';
 v_prop constant text:='c2a6546681a4cf440edb28fb34253eacf7f095f734a4b86807462bb49d9a472f';
 v_p text; v_v jsonb; v_cfg text;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17
 OR (SELECT count(*) FROM ig_chat12_atq005_rule_probe)<>1
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo='REG_ATQ_005' AND estado='VIGENTE')<>1
 OR (SELECT count(*) FROM public.lf_operation_execution
     WHERE execution_id='EXEC-PROFILE-GATE2-F9CDD41E2C453E81A88CF268'
       AND status='IN_PROGRESS' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
       AND manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_002'
       AND manifest->>'no_write'='true')<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
      JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
      WHERE r.codigo='REG_ATQ_005' AND p.codigo='ONB_002')
 OR (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id='EXEC-PROFILE-GATE2-F9CDD41E2C453E81A88CF268'
        AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE'
        AND evidence_payload->>'output_contract_result'='PASS')<>1
 THEN RAISE EXCEPTION 'IG_ATQ005_PG17_SOURCE_OR_RUN_NOT_CURRENT'; END IF;
 SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 INTO v_p FROM ig_chat12_atq005_rule_probe;
 IF v_p IS DISTINCT FROM v_src OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_005')<>v_src
 THEN RAISE EXCEPTION 'IG_ATQ005_PREIMAGE_SHA_DRIFT'; END IF;
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' INTO v_v
 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id='EXEC-PROFILE-GATE2-F9CDD41E2C453E81A88CF268'
 AND s.step_id='execute_profile' AND s.status='STEP_PASS_WITH_EVIDENCE';
 IF v_v->>'rule_code'<>'REG_ATQ_005' OR v_v->>'change_kind'<>'FUNCTIONAL'
 OR encode(extensions.digest(convert_to(v_v::text,'UTF8'),'sha256'),'hex')<>v_prop
 OR v_v#>>'{changes,valor_config,ventana_validez_config,config_key}'<>'OTP_HMAC_TIMESTAMP_WINDOW_SECONDS'
 OR v_v#>>'{changes,valor_config,ventana_validez_config,scope}'<>'AUTH'
 OR (v_v#>'{changes,valor_config}')?'ventana_validez_segundos'
 OR v_v#>>'{changes,valor_config,algoritmo}'<>'HMAC-SHA256'
 OR v_v#>>'{changes,valor_config,secreto}'<>'configurable_sin_hardcode'
 OR v_v#>>'{changes,valor_config,incluir_timestamp}'<>'true'
 OR position('firma HMAC-SHA256' in v_v#>>'{changes,descripcion}')=0
 OR position('rechaza silenciosamente' in v_v#>>'{changes,descripcion}')=0
 THEN RAISE EXCEPTION 'IG_ATQ005_PROFILE_PATCH_OR_SEMANTICS_INVALID'; END IF;
 SELECT config_value INTO v_cfg FROM ig_chat12_atq005_cfg_probe
 WHERE scope='AUTH' AND config_key='OTP_HMAC_TIMESTAMP_WINDOW_SECONDS'
 AND value_type='INTEGER' AND value_status='REAL';
 IF v_cfg IS DISTINCT FROM '30'
 OR public.lf_auth_config_integer_v1('OTP_HMAC_TIMESTAMP_WINDOW_SECONDS')<>30
 OR (SELECT payload#>>'{valor_config,ventana_validez_segundos}' FROM ig_chat12_atq005_rule_probe)
    IS DISTINCT FROM v_cfg
 THEN RAISE EXCEPTION 'IG_ATQ005_GLOBAL_CONFIG_DRIFT'; END IF;
 RAISE NOTICE 'IG_ATQ005_CHECKS_PRE_1_TO_5_PASS';
END $pre$;
SAVEPOINT ig_atq005_positive;
UPDATE ig_chat12_atq005_rule_probe t
SET payload=t.payload || jsonb_build_object(
  'descripcion',(SELECT s.evidence_payload#>>'{profile_output,deliverable_created,governed_rule_patch,changes,descripcion}'
    FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-F9CDD41E2C453E81A88CF268' AND s.step_id='execute_profile'),
  'valor_config',(SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch,changes,valor_config}'
    FROM public.lf_operation_execution_steps s WHERE s.execution_id='EXEC-PROFILE-GATE2-F9CDD41E2C453E81A88CF268' AND s.step_id='execute_profile'));
DO $post$
DECLARE v_sha text;
BEGIN
 SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 INTO v_sha FROM ig_chat12_atq005_rule_probe;
 IF v_sha IS DISTINCT FROM '39777caafe889a61a5f752d6f921a22bfce4bd2b5100ddd422db345f65151835'
 THEN RAISE EXCEPTION 'IG_ATQ005_CANDIDATE_SHA_INVALID:%',v_sha; END IF;
 RAISE NOTICE 'IG_ATQ005_CANDIDATE_POSITIVE_SQL_PASS';
END $post$;
ROLLBACK TO SAVEPOINT ig_atq005_positive;
RELEASE SAVEPOINT ig_atq005_positive;
DO $rb$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
      FROM ig_chat12_atq005_rule_probe)
    IS DISTINCT FROM 'a10969d2ce8d452ff678df72537878dd597f8fce503cd33346848a033aa60075'
 THEN RAISE EXCEPTION 'IG_ATQ005_POSITIVE_ROLLBACK_NOT_RESTORED'; END IF;
 RAISE NOTICE 'IG_ATQ005_POSITIVE_ROLLBACK_READBACK_PASS';
END $rb$;
SAVEPOINT ig_atq005_negative;
UPDATE ig_chat12_atq005_rule_probe SET payload=jsonb_set(payload,'{descripcion}','"DRIFT_SOURCE"'::jsonb);
DELETE FROM ig_chat12_atq005_cfg_probe;
DO $neg$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
       FROM ig_chat12_atq005_rule_probe)
    = 'a10969d2ce8d452ff678df72537878dd597f8fce503cd33346848a033aa60075'
 OR EXISTS(SELECT 1 FROM ig_chat12_atq005_cfg_probe)
 THEN RAISE EXCEPTION 'IG_ATQ005_NEGATIVE_DRIFT_OR_CONFIG_NOT_DETECTED'; END IF;
 RAISE NOTICE 'IG_ATQ005_NEGATIVE_SOURCE_AND_MISSING_CONFIG_DETECTED';
END $neg$;
ROLLBACK TO SAVEPOINT ig_atq005_negative;
RELEASE SAVEPOINT ig_atq005_negative;
DO $final$
BEGIN
 IF (SELECT encode(extensions.digest(convert_to((payload-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
       FROM ig_chat12_atq005_rule_probe)
    <> 'a10969d2ce8d452ff678df72537878dd597f8fce503cd33346848a033aa60075'
 OR (SELECT count(*) FROM ig_chat12_atq005_cfg_probe WHERE config_value='30')<>1
 OR public.lf_asset_snapshot_sha_v1('REGLA','REG_ATQ_005')
    <> 'a10969d2ce8d452ff678df72537878dd597f8fce503cd33346848a033aa60075'
 OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2
    WHERE parent_execution_id='EXEC-PROFILE-GATE2-F9CDD41E2C453E81A88CF268'
       AND rule_code='REG_ATQ_005')
 THEN RAISE EXCEPTION 'IG_ATQ005_POST_NEGATIVE_READBACK_OR_UNAUTHORIZED_MUTATION'; END IF;
 RAISE NOTICE 'IG_ATQ005_REAL_PG17_PROOF_COMPLETE; POSITIVE_ROLLBACK_PASS; NEGATIVE_ROLLBACK_PASS; READBACK_SELECT_PASS; REMOTE_RULE_UNCHANGED; BACKEND_E2E_NOT_TESTED';
END $final$;
COMMIT;