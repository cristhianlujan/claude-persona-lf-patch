-- SALY Ventas PTE: owner-approved Lima/Ica territory policy in lf_global_config.
-- The adapter must receive this vetted policy; no silent hardcoded territory.
-- Configuration only: no change to previously persisted 519 source records.
-- No lease/timeout invented, no commercial RUN, no runtime grants.
BEGIN;
DO $pre$
BEGIN
 IF (SELECT count(*) FROM saly.proyecto WHERE codigo='SALY-001' AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'PTE_CONFIG_PROJECT_NOT_ACTIVE'; END IF;
 IF (SELECT count(*) FROM saly.ventas_hallazgos h
     JOIN saly.ventas_discovery_ingestas di ON di.id=h.ingesta_id
     WHERE di.source_id='PE-PTE' AND di.scope_key='LIMA_ICA')<>519
 THEN RAISE EXCEPTION 'PTE_CONFIG_BASELINE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_global_config WHERE scope='SALY_DISCOVERY' AND config_key='PTE_POLICY_V1')
 THEN RAISE EXCEPTION 'PTE_CONFIG_ALREADY_PRESENT'; END IF;
END $pre$;
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description)
VALUES('SALY_DISCOVERY','PTE_POLICY_V1',
       '{"source_id":"PE-PTE","scope_key":"LIMA_ICA","ubigeo_prefixes":["15","11"],"allowed_effect":"READ_ONLY"}',
       'JSON','REAL',
       'SALY Ventas pilot PTE: territorial selection Lima/Ica, read-only adapter policy. Owner-approved fixed scope; commercial runtime separately governed.');
CREATE FUNCTION public.lf_saly_discovery_pte_policy_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path=pg_catalog,public
AS $policy$
DECLARE
 v_policy jsonb;
 v_count int;
BEGIN
 SELECT count(*) INTO v_count FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='PTE_POLICY_V1' AND value_status='REAL';
 SELECT config_value::jsonb INTO v_policy FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='PTE_POLICY_V1' AND value_status='REAL'
 ORDER BY valid_from DESC LIMIT 1;
 IF v_count<>1 OR v_policy IS NULL OR jsonb_typeof(v_policy) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'PTE_POLICY_INVALID'; END IF;
 IF NOT (v_policy ?& ARRAY['source_id','scope_key','ubigeo_prefixes','allowed_effect'])
 OR jsonb_typeof(v_policy->'ubigeo_prefixes') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'PTE_POLICY_INVALID'; END IF;
 IF jsonb_array_length(v_policy->'ubigeo_prefixes')=0
 OR v_policy->>'source_id' IS DISTINCT FROM 'PE-PTE'
 OR v_policy->>'scope_key' IS DISTINCT FROM 'LIMA_ICA'
 OR v_policy->>'allowed_effect' IS DISTINCT FROM 'READ_ONLY'
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_policy->'ubigeo_prefixes') AS x(e)
     WHERE jsonb_typeof(e) IS DISTINCT FROM 'string' OR e#>>'{}' !~ '^[0-9]{2}$')
 OR (SELECT count(*) FROM jsonb_array_elements(v_policy->'ubigeo_prefixes'))
    <> (SELECT count(DISTINCT e) FROM jsonb_array_elements(v_policy->'ubigeo_prefixes') AS x(e))
 THEN RAISE EXCEPTION 'PTE_POLICY_INVALID'; END IF;
  RETURN v_policy;
END $policy$;
REVOKE ALL ON FUNCTION public.lf_saly_discovery_pte_policy_v1() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_saly_discovery_pte_policy_v1() TO supabase_read_only_user;
DO $tests$
DECLARE
 v_saved jsonb;
 v_rejected boolean:=false;
 v_count integer;
BEGIN
 v_saved:=public.lf_saly_discovery_pte_policy_v1();
 IF v_saved->'ubigeo_prefixes' IS DISTINCT FROM '["15","11"]'::jsonb
 OR v_saved->>'allowed_effect'<>'READ_ONLY'
 THEN RAISE EXCEPTION 'PTE_POLICY_READBACK_FAIL'; END IF;
 BEGIN
  UPDATE public.lf_global_config SET config_value='{"source_id":"PE-PTE","scope_key":"LIMA_ICA","ubigeo_prefixes":["XX"],"allowed_effect":"READ_ONLY"}'
  WHERE scope='SALY_DISCOVERY' AND config_key='PTE_POLICY_V1';
  PERFORM public.lf_saly_discovery_pte_policy_v1();
  RAISE EXCEPTION 'PTE_POLICY_NEGATIVE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'PTE_POLICY_INVALID' THEN RAISE; END IF;
  v_rejected:=true;
 END;
 IF NOT v_rejected OR public.lf_saly_discovery_pte_policy_v1() IS DISTINCT FROM v_saved
 THEN RAISE EXCEPTION 'PTE_POLICY_NEGATIVE_FIXTURE_LEAK'; END IF;
 SELECT count(*) INTO v_count FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas di ON di.id=h.ingesta_id
 WHERE di.source_id='PE-PTE' AND di.scope_key='LIMA_ICA'
 AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_saved->'ubigeo_prefixes') x(prefix)
  WHERE h.ubigeo_candidato LIKE x.prefix||'%');
 IF v_count<>519 THEN RAISE EXCEPTION 'PTE_POLICY_TERRITORY_DRIFT'; END IF;
 RAISE NOTICE 'PASS_PTE_POLICY_CONFIG_POSITIVE_NEGATIVE_ROLLBACK_519';
END $tests$;
COMMIT;
