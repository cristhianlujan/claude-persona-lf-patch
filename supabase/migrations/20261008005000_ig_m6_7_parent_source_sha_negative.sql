-- IG M6.7 forward-only SHA prerequisite; signed receipts unchanged.
CREATE OR REPLACE FUNCTION programacion.fn_input_successor_lineage_guard_m67_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
DECLARE
  v_parent programacion.input_readiness_runs%ROWTYPE;
  v_reason text;
  v_strategy text;
  v_family_bindings jsonb;
  v_lineage jsonb;
BEGIN
  IF NEW.supersedes_run_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_parent FROM programacion.input_readiness_runs
  WHERE id=NEW.supersedes_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'IG_SUCCESSOR_PARENT_NOT_FOUND'; END IF;
  IF coalesce(v_parent.source_snapshot_sha256,'') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'IG_SUCCESSOR_PARENT_SOURCE_SHA_REQUIRED';
  END IF;
  IF v_parent.version_id IS DISTINCT FROM NEW.version_id
     OR v_parent.pantalla_id IS DISTINCT FROM NEW.pantalla_id THEN
    RAISE EXCEPTION 'IG_SUCCESSOR_PARENT_CONTEXT_MISMATCH';
  END IF;
  IF jsonb_typeof(NEW.scope) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'IG_SUCCESSOR_SCOPE_NOT_OBJECT';
  END IF;
  IF NEW.scope->>'parent_run_id' IS DISTINCT FROM NEW.supersedes_run_id::text THEN
    RAISE EXCEPTION 'IG_SUCCESSOR_PARENT_BINDING_REQUIRED';
  END IF;

  v_reason:=coalesce(nullif(btrim(NEW.scope->>'reason'),''),
                     nullif(btrim(NEW.scope->>'supersession_reason'),''));
  v_strategy:=nullif(btrim(NEW.scope->>'successor_strategy'),'');
  IF v_reason IS NULL OR v_reason !~ '^[A-Z][A-Z0-9_]{2,127}$' THEN
    RAISE EXCEPTION 'IG_SUCCESSOR_REASON_REQUIRED';
  END IF;
  IF v_strategy IS NULL OR v_strategy !~ '^[A-Z][A-Z0-9_]{2,127}$' THEN
    RAISE EXCEPTION 'IG_SUCCESSOR_STRATEGY_REQUIRED';
  END IF;

  SELECT coalesce(jsonb_object_agg(
    a.family_code,
    jsonb_build_object(
      'curator_sha256',a.curator_sha256,
      'classifier_sha256',a.curator_evidence->>'bootstrap_classifier_sha256',
      'semantic_depth_sha256',a.semantic_depth_sha256
    ) ORDER BY a.family_code
  ), '{}'::jsonb)
  INTO v_family_bindings
  FROM programacion.input_family_assessments a
  WHERE a.run_id=v_parent.id;

  v_lineage:=jsonb_build_object(
    'schema_version','IG_SUCCESSOR_PARENT_LINEAGE_V1',
    'parent_run_id',v_parent.id,
    'parent_source_snapshot_sha256',v_parent.source_snapshot_sha256,
    'parent_contract_snapshot_sha256',v_parent.contract_snapshot_sha256,
    'parent_curator_classifier_semantic_sha',v_family_bindings,
    'reason',v_reason,
    'successor_strategy',v_strategy,
    'successor_binding',jsonb_build_object(
      'version_id',NEW.version_id,'pantalla_id',NEW.pantalla_id,
      'universe_rule_id',NEW.universe_rule_id,
      'curator_identity',NEW.curator_identity
    )
  );
  NEW.scope:=NEW.scope || jsonb_build_object(
    'reason',v_reason,
    'successor_strategy',v_strategy,
    'lineage_binding_v1',v_lineage,
    'lineage_binding_sha256',programacion.fn_v09_sha256_jsonb(v_lineage)
  );
  RETURN NEW;
END;
$function$


DO $m67_check$
BEGIN
 IF position('IG_SUCCESSOR_PARENT_SOURCE_SHA_REQUIRED' IN pg_get_functiondef('programacion.fn_input_successor_lineage_guard_m67_v1()'::regprocedure))=0 THEN RAISE EXCEPTION 'M67_SHA_GUARD_NOT_INSTALLED'; END IF;
END $m67_check$;
