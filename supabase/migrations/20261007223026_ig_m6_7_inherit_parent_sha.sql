-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M6.7 / PAULO-077
-- Forward-only successor lineage binding; historical missing reasons remain UNKNOWN.
-- No production/runtime activation. Explicit authoring changes to three canonical successor producers.
-- Signed provenance receipts remain owned by existing authenticated channel; this migration does not counterfeit them.

CREATE OR REPLACE FUNCTION programacion.fn_input_successor_lineage_guard_m67_v1()
RETURNS trigger LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'pg_catalog','programacion'
AS $m67_guard$
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
$m67_guard$;

DROP TRIGGER IF EXISTS trg_input_readiness_run_00_m67_successor_lineage
ON programacion.input_readiness_runs;
CREATE TRIGGER trg_input_readiness_run_00_m67_successor_lineage
BEFORE INSERT ON programacion.input_readiness_runs
FOR EACH ROW
EXECUTE FUNCTION programacion.fn_input_successor_lineage_guard_m67_v1();

COMMENT ON FUNCTION programacion.fn_input_successor_lineage_guard_m67_v1() IS
  'M6.7: typed reason and strategy required for new successor runs; immutable parent family, classifier, semantic and snapshot SHA lineage in scope; no historical reason fabrication and no forged signed receipt.';

-- Make the three existing canonical runtime successor producers explicit.
-- Replace only a known, exact fragment in the live function; fail closed on drift.
DO $m67_writers$
DECLARE
  v_old text;
  v_new text;
  v_sig text;
  v_from text;
  v_to text;
BEGIN
  FOR v_sig,v_from,v_to IN
    SELECT * FROM (VALUES
      (
        'programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)',
        '''parent_run_id'',id,''runtime''',
        '''parent_run_id'',id,''reason'',''ASSERTION_REBIND'',''successor_strategy'',''PARENT_ASSERTION_REUSE'',''runtime'''
      ),
      (
        'programacion.fn_input_governance_recurate_v2(integer,text,text)',
        '''parent_run_id'',v_parent.id,''analysis_revision''',
        '''parent_run_id'',v_parent.id,''reason'',''CANONICAL_RECURATION'',''successor_strategy'',''REBUILD_FROM_CANONICAL_SOURCES'',''analysis_revision'''
      ),
      (
        'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)',
        '''parent_run_id'',v_parent.id,''analysis_revision''',
        '''parent_run_id'',v_parent.id,''reason'',''SOURCE_STALE_RECURATION'',''successor_strategy'',''REBUILD_CHANGED_SOURCES'',''analysis_revision'''
      )
    ) AS t(sig,old_fragment,new_fragment)
  LOOP
    SELECT pg_get_functiondef(to_regprocedure(v_sig)) INTO v_old;
    IF v_old IS NULL OR position(v_from IN v_old)=0
       OR position(v_to IN v_old)>0 THEN
      RAISE EXCEPTION 'M67_WRITER_SOURCE_DRIFT:%',v_sig;
    END IF;
    v_new:=replace(v_old,v_from,v_to);
    EXECUTE v_new;
  END LOOP;
END;
$m67_writers$;

-- Proof: compiled writers have exact typed reason/strategy; the trigger exists.
DO $m67_assert$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_trigger t
  WHERE t.tgrelid='programacion.input_readiness_runs'::regclass
    AND t.tgname='trg_input_readiness_run_00_m67_successor_lineage'
    AND t.tgenabled IN ('O','A');
  IF v_count<>1 THEN RAISE EXCEPTION 'M67_TRIGGER_NOT_ENABLED'; END IF;

  SELECT count(*) INTO v_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion'
    AND p.proname IN (
      'fn_input_governance_curator_rebind_v1',
      'fn_input_governance_recurate_v2',
      'fn_input_governance_recurate_source_stale_v1'
    )
    AND pg_get_functiondef(p.oid) LIKE '%''successor_strategy''%'
    AND pg_get_functiondef(p.oid) LIKE '%''reason''%';
  IF v_count<>3 THEN RAISE EXCEPTION 'M67_RUNTIME_WRITER_CONTRACT_INCOMPLETE'; END IF;
END;
$m67_assert$;
