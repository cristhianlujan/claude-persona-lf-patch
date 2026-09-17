-- Candidate only. Not a migration and not applied to Supabase.
-- Reuse-first: extends EJECUCION_ESTRATEGIA_LF; creates no operation, table, EKB store, router or workflow engine.
-- Baseline lineage: PR #846 head 158dcec66175ff443c6086c15673ac67917fd5e1.

-- Objective: make EKB preflight a server-validated prerequisite of Strategy execution before write/effect.
-- PRV-GOV-010 requires relevant active EKB rules to be loaded before action and every applicable
-- High/Critical prevention to be bound to a preflight/gate/negative test or explicitly blocked.

CREATE OR REPLACE FUNCTION public.lf_strategy_execution_ekb_preflight_v1(
  p_execution_id text,
  p_applicable_rule_codes text[],
  p_controlled_rule_codes text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','public','transversal','extensions'
AS $fn$
DECLARE
  x public.lf_operation_execution%rowtype;
  v_requested integer;
  v_active integer;
  v_missing text[];
  v_uncontrolled text[];
  v_digest text;
BEGIN
  IF btrim(coalesce(p_execution_id,''))='' THEN
    RAISE EXCEPTION 'LF_STRATEGY_EKB_PREFLIGHT_EXECUTION_ID_REQUIRED';
  END IF;
  IF p_applicable_rule_codes IS NULL OR cardinality(p_applicable_rule_codes)=0 THEN
    RAISE EXCEPTION 'LF_STRATEGY_EKB_PREFLIGHT_APPLICABLE_RULES_REQUIRED';
  END IF;
  IF NOT ('PRV-GOV-010'=ANY(p_applicable_rule_codes)) THEN
    RAISE EXCEPTION 'LF_STRATEGY_EKB_PREFLIGHT_CORE_RULE_MISSING:PRV-GOV-010';
  END IF;

  SELECT * INTO x
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;
  IF NOT FOUND OR x.operation_code<>'EJECUCION_ESTRATEGIA_LF' OR x.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'LF_STRATEGY_EKB_PREFLIGHT_EXECUTION_BINDING_INVALID:%',p_execution_id;
  END IF;

  v_requested:=cardinality(p_applicable_rule_codes);

  SELECT count(*) INTO v_active
  FROM transversal.prevention_rules r
  WHERE r.activa=true AND r.regla_codigo=ANY(p_applicable_rule_codes);

  SELECT array_agg(code order by code) INTO v_missing
  FROM (
    SELECT unnest(p_applicable_rule_codes) code
    EXCEPT
    SELECT r.regla_codigo FROM transversal.prevention_rules r
    WHERE r.activa=true AND r.regla_codigo=ANY(p_applicable_rule_codes)
  ) q;
  IF coalesce(cardinality(v_missing),0)>0 THEN
    RAISE EXCEPTION 'LF_STRATEGY_EKB_PREFLIGHT_RULE_NOT_ACTIVE_OR_MISSING:%',array_to_string(v_missing,',');
  END IF;

  -- Priority is not treated as severity because the EKB taxonomy is heterogeneous.
  -- High/Critical is derived from the linked error severity after normalization.
  SELECT array_agg(r.regla_codigo order by r.regla_codigo) INTO v_uncontrolled
  FROM transversal.prevention_rules r
  JOIN transversal.error_knowledge e ON e.codigo=r.error_codigo
  WHERE r.activa=true
    AND r.regla_codigo=ANY(p_applicable_rule_codes)
    AND upper(coalesce(e.severidad,'')) IN ('HIGH','CRITICAL','ALTA','CRITICA','CRÍTICA','P0')
    AND NOT (r.regla_codigo=ANY(coalesce(p_controlled_rule_codes,ARRAY[]::text[])));

  IF coalesce(cardinality(v_uncontrolled),0)>0 THEN
    RAISE EXCEPTION 'LF_STRATEGY_EKB_PREFLIGHT_HIGH_CRITICAL_UNCONTROLLED:%',array_to_string(v_uncontrolled,',');
  END IF;

  SELECT encode(extensions.digest(convert_to(string_agg(r.regla_codigo||':'||coalesce(r.error_codigo,'')||':'||coalesce(r.prioridad::text,''),'|' order by r.regla_codigo),'UTF8'),'sha256'),'hex')
  INTO v_digest
  FROM transversal.prevention_rules r
  WHERE r.activa=true AND r.regla_codigo=ANY(p_applicable_rule_codes);

  RETURN jsonb_build_object(
    'result','PASS_CLEAN',
    'execution_id',p_execution_id,
    'operation_code',x.operation_code,
    'applicable_rule_count',v_requested,
    'active_rule_count',v_active,
    'controlled_rule_count',coalesce(cardinality(p_controlled_rule_codes),0),
    'uncontrolled_high_critical_count',0,
    'active_rules_digest_sha256',v_digest,
    'core_rule','PRV-GOV-010',
    'source','transversal.prevention_rules+transversal.error_knowledge'
  );
END
$fn$;

-- Intended integration into existing steps only (no new step):
-- 40 policy_and_quality_resolve: require ekb_preflight_receipt, ekb_active_rules_digest_sha256,
--    ekb_applicable_rule_codes, ekb_control_bindings.
-- 70 pre_write_execution_binding_gate: fail closed if the step-40 EKB receipt is absent, stale,
--    belongs to another execution, or reports any uncontrolled High/Critical applicable rule.
-- CONTRACT-EJECUCION-ESTRATEGIA-LF-v1 required_before_write gains:
-- EKB_PREFLIGHT_ACTIVE_RULES_BOUND_TO_CONTROLS.
