-- IG #4064 | READ-ONLY EVIDENCE + UNCOMMITTED FUNCTION REPLACEMENT.
-- This template MUST be assembled by ig4064_governed_live_rollback_v1.py;
-- placeholders are exact SHA-pinned migration and harness. Never run standalone.
\set ON_ERROR_STOP on
\echo IG4064_TX_BEGIN
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='22min';
SET LOCAL idle_in_transaction_session_timeout='24min';

CREATE TEMP TABLE ig4064_expected_functions(signature text PRIMARY KEY, expected_md5 text)
ON COMMIT DROP;
INSERT INTO ig4064_expected_functions(signature,expected_md5) VALUES
@@EXPECTED_FUNCTIONS@@;

DO $preflight$
DECLARE n integer; matched integer; v bigint;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE md5(pg_get_functiondef(to_regprocedure(signature)))=expected_md5)
 INTO n,matched FROM ig4064_expected_functions;
 IF n<>7 OR matched<>7 THEN RAISE EXCEPTION 'IG4064_MD5_SOURCE_DRIFT count=% matched=%',n,matched; END IF;
 SELECT max(version_id) INTO v FROM programacion.contratos
 WHERE contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY' AND estado='defined';
 IF v<>19 THEN RAISE EXCEPTION 'IG4064_REVISION_DRIFT expected=19 observed=%',v; END IF;
 IF current_setting('transaction_read_only') <> 'off' THEN
   RAISE EXCEPTION 'IG4064_DB_TRANSACTION_READ_ONLY';
 END IF;
 RAISE NOTICE 'IG4064_FUNCTION_PREIMAGE_PASS md5=7/7 rev=19';
END;
$preflight$;

CREATE TEMP TABLE ig4064_reference ON COMMIT DROP AS
WITH latest AS (
 SELECT DISTINCT ON(pantalla_id) pantalla_id,id run_id
 FROM programacion.input_readiness_runs ORDER BY pantalla_id,id DESC
)
SELECT l.pantalla_id,l.run_id,f.family_code,f.applicability old_applicability
FROM latest l JOIN programacion.input_family_assessments f ON f.run_id=l.run_id;

DO $baseline$
DECLARE n integer; target_n integer; target_app integer; target_na integer;
        other_screens integer; other_n integer; other_app integer; other_na integer;
BEGIN
 SELECT count(*) INTO n FROM ig4064_reference;
 SELECT count(*),count(*) FILTER(WHERE old_applicability='APPLICABLE'),
        count(*) FILTER(WHERE old_applicability='NOT_APPLICABLE')
 INTO target_n,target_app,target_na
 FROM ig4064_reference WHERE pantalla_id IN(52,56,53);
 SELECT count(DISTINCT pantalla_id),count(*),
        count(*) FILTER(WHERE old_applicability='APPLICABLE'),
        count(*) FILTER(WHERE old_applicability='NOT_APPLICABLE')
 INTO other_screens,other_n,other_app,other_na
 FROM ig4064_reference WHERE pantalla_id NOT IN(52,56,53);
 IF n<>1974 OR target_n<>141 OR target_app<>130 OR target_na<>11
   OR other_screens<>39 OR other_n<>1833 OR other_app<>1824 OR other_na<>9 THEN
   RAISE EXCEPTION 'IG4064_REFERENCE_DRIFT total=% targets=% positives=% others=% positives=% negatives=%',
     n,target_n,target_app,other_n,other_app,other_na;
 END IF;
 IF EXISTS(SELECT 1 FROM ig4064_reference GROUP BY pantalla_id,family_code HAVING count(*)<>1)
 THEN RAISE EXCEPTION 'IG4064_REFERENCE_DUPLICATES'; END IF;
 RAISE NOTICE 'IG4064_BASELINE_PASS screens=42 assessments=1974 targets=141 baseline_app=130 baseline_na=11 other=1833 other_app=1824 other_na=9';
END;
$baseline$;

-- Uncommitted replacement; the exact migration DO is extracted and pinned.
@@MIGRATION_DO@@

DO $migration_probe$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM ig4064_expected_functions
 WHERE md5(pg_get_functiondef(to_regprocedure(signature))) IS DISTINCT FROM expected_md5;
 IF n<>7 THEN RAISE EXCEPTION 'IG4064_MIGRATION_NOT_ALL_7_CHANGED changed=%',n; END IF;
 RAISE NOTICE 'IG4064_MIGRATION_CHANGED_IN_TX definitions=7';
END;
$migration_probe$;

-- Original #4064 12-case focal test, without its BEGIN/\ir/ROLLBACK wrappers.
@@HARNESS_DO@@

CREATE TEMP TABLE ig4064_graph ON COMMIT DROP AS
SELECT x.pantalla_id,programacion.fn_input_screen_canonical_graph(x.pantalla_id,19) graph
FROM (SELECT DISTINCT pantalla_id FROM ig4064_reference) x;
CREATE UNIQUE INDEX ig4064_graph_pkey ON ig4064_graph(pantalla_id);

-- Full real evaluation: 42 screens * 47 families = 1,974 classifier calls.
CREATE TEMP TABLE ig4064_after ON COMMIT DROP AS
WITH classified AS MATERIALIZED (
 SELECT b.pantalla_id,b.run_id,b.family_code,b.old_applicability,
        programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
          b.pantalla_id,b.family_code,19,g.graph
        ) AS result
 FROM ig4064_reference b JOIN ig4064_graph g ON g.pantalla_id=b.pantalla_id
)
SELECT pantalla_id,run_id,family_code,old_applicability,
       result->>'applicability' new_applicability,
       result->'source_refs' source_refs
FROM classified;

DO $verify$
DECLARE sid integer; hits integer; nas integer; refs integer;
        others integer; losses integer; changes integer; found integer; v_source_refs jsonb;
BEGIN
 IF (SELECT count(*) FROM ig4064_after)<>1974
    OR EXISTS(SELECT 1 FROM ig4064_after WHERE new_applicability IS NULL)
 THEN RAISE EXCEPTION 'IG4064_FULL_CLASSIFIER_MISSING_RESULT'; END IF;

 FOREACH sid IN ARRAY ARRAY[52,56,53] LOOP
   SELECT count(*) FILTER(
     WHERE family_code NOT IN ('FEATURE_FLAGS','I18N_FORMATS')
       AND new_applicability='APPLICABLE'
   ),count(*) FILTER(
     WHERE family_code IN ('FEATURE_FLAGS','I18N_FORMATS')
       AND new_applicability='NOT_APPLICABLE'
   ),count(*) FILTER(
     WHERE family_code IN ('FEATURE_FLAGS','I18N_FORMATS')
       AND new_applicability='NOT_APPLICABLE'
       AND EXISTS(
         SELECT 1 FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(source_refs)='array' THEN source_refs ELSE '[]'::jsonb END
         ) s WHERE s->>'kind'='RULE'
             AND s->>'codigo'='B2B-RULE-INPUT-APPLICABILITY-001'
       )
   ) INTO hits,nas,refs
   FROM ig4064_after WHERE pantalla_id=sid;
   IF hits<>45 OR nas<>2 OR refs<>2 THEN
     RAISE EXCEPTION 'IG4064_TARGET_FAILED screen=% recall=%/45 na=%/2 refs=%/2',
        sid,hits,nas,refs;
   END IF;
 END LOOP;
 RAISE NOTICE 'IG4064_RECALL_PASS P52=45/45 P56=45/45 P53=45/45 TOTAL=135/135';
 RAISE NOTICE 'IG4064_NA_REFS_PASS 6/6 rule=B2B-RULE-INPUT-APPLICABILITY-001';

 SELECT jsonb_agg(jsonb_build_object(
   'pantalla_id',pantalla_id,'family',family_code,'source_refs',source_refs
 ) ORDER BY pantalla_id,family_code)
 INTO v_source_refs FROM ig4064_after
 WHERE pantalla_id IN(52,56,53)
   AND family_code IN ('FEATURE_FLAGS','I18N_FORMATS');
 IF jsonb_array_length(coalesce(v_source_refs,'[]'::jsonb))<>6
 THEN RAISE EXCEPTION 'IG4064_NA_SOURCE_ROWS_INCOMPLETE'; END IF;
 RAISE NOTICE 'IG4064_NA_SOURCE_REFS_REAL=%',v_source_refs;

 SELECT count(*),
        count(*) FILTER(WHERE old_applicability='APPLICABLE'
           AND new_applicability IS DISTINCT FROM 'APPLICABLE'),
        count(*) FILTER(WHERE old_applicability IS DISTINCT FROM new_applicability)
 INTO others,losses,changes
 FROM ig4064_after WHERE pantalla_id NOT IN(52,56,53);
 IF others<>1833 OR losses<>0 THEN
   RAISE EXCEPTION 'IG4064_REGRESSION_FAILED rows=% lost_applicable=%',others,losses;
 END IF;
 RAISE NOTICE 'IG4064_OTHER_39_REGRESSION_PASS screens=39 assessments=1833 baseline_app=1824 baseline_na=9 applicable_lost=0 applicability_changes=%',changes;
END;
$verify$;

\echo IG4064_TX_ROLLBACK_START
ROLLBACK;
\echo IG4064_TX_ROLLBACK_DONE

-- Same psql session, AFTER rollback. Fail if definitions or historical rows drifted.
DO $post$
DECLARE n integer; matched integer; others integer; positives integer; negatives integer;
        screens integer; targets integer;
BEGIN
 WITH expected(signature,md5_expected) AS(VALUES @@EXPECTED_FUNCTIONS@@)
 SELECT count(*),count(*) FILTER(WHERE md5(pg_get_functiondef(to_regprocedure(signature)))=md5_expected)
 INTO n,matched FROM expected;
 IF n<>7 OR matched<>7 THEN
    RAISE EXCEPTION 'IG4064_POST_ROLLBACK_MD5_MISMATCH matched=%/7',matched; END IF;
 WITH latest AS(
   SELECT DISTINCT ON(pantalla_id) pantalla_id,id run_id
   FROM programacion.input_readiness_runs ORDER BY pantalla_id,id DESC
 )
 SELECT count(DISTINCT l.pantalla_id),count(*),
        count(*) FILTER(WHERE f.applicability='APPLICABLE'),
        count(*) FILTER(WHERE f.applicability='NOT_APPLICABLE')
 INTO screens,others,positives,negatives
 FROM latest l JOIN programacion.input_family_assessments f ON f.run_id=l.run_id
 WHERE l.pantalla_id NOT IN(52,56,53);
 IF screens<>39 OR others<>1833 OR positives<>1824 OR negatives<>9 THEN
   RAISE EXCEPTION 'IG4064_POST_ROLLBACK_HISTORY_CHANGED'; END IF;
 WITH latest AS (
   SELECT DISTINCT ON(pantalla_id) pantalla_id,id run_id
   FROM programacion.input_readiness_runs ORDER BY pantalla_id,id DESC
 )
 SELECT count(*) INTO targets
 FROM latest l JOIN programacion.input_family_assessments f ON f.run_id=l.run_id
 WHERE l.pantalla_id IN(52,56,53);
 IF targets<>141 THEN RAISE EXCEPTION 'IG4064_POST_ROLLBACK_TARGET_HISTORY_CHANGED'; END IF;
 RAISE NOTICE 'IG4064_POST_ROLLBACK_PASS original_md5=7/7 other=1833 app=1824 na=9 target=141';
END;
$post$;
