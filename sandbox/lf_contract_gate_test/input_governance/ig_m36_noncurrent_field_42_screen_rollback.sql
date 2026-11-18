-- IG M36 real PG17/PG18 source-bound BEGIN/ROLLBACK test (NOT a migration).
-- Requires protected PostgreSQL authority. Never run from untrusted PR with DB secrets.
\set ON_ERROR_STOP on
\echo IG_M36_TX_BEGIN
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='28min';

DO $pre$
BEGIN
  IF md5(pg_get_functiondef(
      'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure))
     <> '61d47a6400cf910ace71936413863e16'
  THEN RAISE EXCEPTION 'IG_M36_TEST_SOURCE_MD5_DRIFT'; END IF;
END;
$pre$;

CREATE TEMP TABLE ig_m36_reference ON COMMIT DROP AS
WITH latest AS(
 SELECT DISTINCT ON(pantalla_id) pantalla_id,id run_id
 FROM programacion.input_readiness_runs ORDER BY pantalla_id,id DESC
)
SELECT l.pantalla_id,l.run_id,f.family_code,f.applicability old_applicability
FROM latest l JOIN programacion.input_family_assessments f ON f.run_id=l.run_id;

DO $baseline$
DECLARE n integer; screens integer; others integer; other_app integer; other_na integer;
 targets integer; target_app integer; target_na integer;
BEGIN
 SELECT count(*),count(DISTINCT pantalla_id),
        count(*) FILTER(WHERE pantalla_id NOT IN (52,53,56)),
        count(*) FILTER(WHERE pantalla_id NOT IN (52,53,56) AND old_applicability='APPLICABLE'),
        count(*) FILTER(WHERE pantalla_id NOT IN (52,53,56) AND old_applicability='NOT_APPLICABLE'),
        count(*) FILTER(WHERE pantalla_id IN (52,53,56)),
        count(*) FILTER(WHERE pantalla_id IN (52,53,56) AND old_applicability='APPLICABLE'),
        count(*) FILTER(WHERE pantalla_id IN (52,53,56) AND old_applicability='NOT_APPLICABLE')
 INTO n,screens,others,other_app,other_na,targets,target_app,target_na FROM ig_m36_reference;
 IF n<>1974 OR screens<>42 OR others<>1833 OR other_app<>1824 OR other_na<>9
    OR targets<>141 OR target_app<>130 OR target_na<>11
 THEN RAISE EXCEPTION 'IG_M36_BASELINE_DRIFT n=% screens=% others=% app=% na=% targets=% app=% na=%',
 n,screens,others,other_app,other_na,targets,target_app,target_na;
 END IF;
 IF EXISTS (SELECT 1 FROM ig_m36_reference GROUP BY pantalla_id,family_code HAVING count(*)<>1)
 THEN RAISE EXCEPTION 'IG_M36_BASELINE_DUPLICATE_PAIRS'; END IF;
 RAISE NOTICE 'IG_M36_BASELINE_PASS screens=42 assessments=1974 other_screens=39 other=1833 applicable=1824 na=9 targets=141 applicable=130 na=11';
END;
$baseline$;

\ir ../../../supabase/migrations/20261118052000_lf_ig_m36_noncurrent_candidate_authority_v1.sql

CREATE TEMP TABLE ig_m36_graph ON COMMIT DROP AS
SELECT z.pantalla_id,programacion.fn_input_screen_canonical_graph(z.pantalla_id,19) graph
FROM (SELECT DISTINCT pantalla_id FROM ig_m36_reference) z;
CREATE UNIQUE INDEX ig_m36_graph_idx ON ig_m36_graph(pantalla_id);

CREATE TEMP TABLE ig_m36_after ON COMMIT DROP AS
WITH classified AS MATERIALIZED(
 SELECT b.pantalla_id,b.family_code,b.old_applicability,
        programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
          b.pantalla_id,b.family_code,19,g.graph
        ) AS result
 FROM ig_m36_reference b JOIN ig_m36_graph g ON g.pantalla_id=b.pantalla_id
)
SELECT pantalla_id,family_code,old_applicability,
       result->>'applicability' new_applicability,
       result->'blockers' blockers,
       result->'source_refs' source_refs
FROM classified;

DO $verify$
DECLARE total integer; distinct_screens integer; other_app integer; other_na integer;
 target_app integer; target_na integer; losses integer; alterations integer;
 noncurrent_count integer; typed_count integer; bad_refs integer; info jsonb;
BEGIN
 SELECT count(*),count(DISTINCT pantalla_id),
        count(*) FILTER(WHERE pantalla_id NOT IN (52,53,56) AND new_applicability='APPLICABLE'),
        count(*) FILTER(WHERE pantalla_id NOT IN (52,53,56) AND new_applicability='NOT_APPLICABLE'),
        count(*) FILTER(WHERE pantalla_id IN (52,53,56) AND new_applicability='APPLICABLE'),
        count(*) FILTER(WHERE pantalla_id IN (52,53,56) AND new_applicability='NOT_APPLICABLE'),
        count(*) FILTER(WHERE old_applicability='APPLICABLE' AND new_applicability IS DISTINCT FROM 'APPLICABLE'),
        count(*) FILTER(WHERE old_applicability IS DISTINCT FROM new_applicability)
 INTO total,distinct_screens,other_app,other_na,target_app,target_na,losses,alterations
 FROM ig_m36_after;
 IF total<>1974 OR distinct_screens<>42 OR other_app<>1824 OR other_na<>9
    OR target_app<>130 OR target_na<>11 OR losses<>0 OR alterations<>0
 THEN RAISE EXCEPTION 'IG_M36_REGRESSION n=% screens=% other_app=% other_na=% target_app=% target_na=% lost=% changed=%',
 total,distinct_screens,other_app,other_na,target_app,target_na,losses,alterations; END IF;
 IF EXISTS (
 SELECT 1 FROM ig_m36_after WHERE new_applicability IS NULL OR
       jsonb_typeof(blockers)<>'array'
 ) THEN RAISE EXCEPTION 'IG_M36_NULL_OR_UNTYPED_ASSESSMENT'; END IF;
 SELECT count(*),count(*) FILTER (WHERE b.value->>'uncertainty_type'='CANDIDATE_AUTHORITY'
  AND b.value->>'state'='BLOCKED'
  AND b.value->>'blocking_stage'='STORY'
  AND jsonb_typeof(b.value->'evidence')='object')
 INTO noncurrent_count,typed_count
 FROM ig_m36_after a CROSS JOIN LATERAL jsonb_array_elements(a.blockers) b(value)
 WHERE a.pantalla_id=67 AND a.family_code='FIELDS'
   AND b.value->>'code'='EXPLICIT_FIELD_REFERENCE_NONCURRENT';
 IF noncurrent_count<>1 OR typed_count<>1 THEN
  RAISE EXCEPTION 'IG_M36_CANDIDATE_AUTHORITY_NOT_TYPED screen=67 noncurrent=% typed=%',
   noncurrent_count,typed_count; END IF;
 SELECT blockers INTO info FROM ig_m36_after WHERE pantalla_id=67 AND family_code='FIELDS';
 RAISE NOTICE 'IG_M36_CANDIDATE_AUTHORITY_PASS screen=67 blocker=EXPLICIT_FIELD_REFERENCE_NONCURRENT count=1 state=BLOCKED stage=STORY evidence=OBJECT actual=%',info;
 RAISE NOTICE 'IG_M36_ALL_42_REGRESSION_PASS screens=42 assessments=1974 applicable_lost=0 applicability_changes=0';
 RAISE NOTICE 'IG_M36_OTHER_39_PASS assessments=1833 applicable=1824 na=9';
END;
$verify$;

\echo IG_M36_TX_ROLLBACK_START
ROLLBACK;
\echo IG_M36_TX_ROLLBACK_DONE

DO $post$
BEGIN
 IF md5(pg_get_functiondef(
  'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'::regprocedure))
  <> '61d47a6400cf910ace71936413863e16'
 THEN RAISE EXCEPTION 'IG_M36_ROLLBACK_SOURCE_NOT_RESTORED'; END IF;
 RAISE NOTICE 'IG_M36_POST_ROLLBACK_PASS original_md5=61d47a6400cf910ace71936413863e16';
END;
$post$;
