-- Only IG M10.7 CP2: repair the read-only verification to reuse M9.11 certified
-- as-of receipt, independently observe historical cohort and persist CP2.
-- Preflight: both new SQL queries executed on canonical RO connector: PASS
-- and PASS_OBSERVED, 13/13 screens, 47 distinct families, 199 completed runs;
-- raw completed runs DO NOT replace historical eligibility in receipt 38.
-- Prior declared query 1 returned SQLSTATE 42501 to RO role and confused
-- simultaneous CURRENT with as-of historical authority.
-- No grant, runtime, new runs, external operations, or activation.
DO $m107cp2$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 u constant text := 'M10.7';
 actor constant text := 'IG_M107_CP2_CANONICAL_20261014';
 w constant bigint := 478;
 old_queries jsonb;
 new_queries jsonb := jsonb_build_array(
 $read1$with p as (
 select payload,receipt_sha256,subject_ref from programacion.provenance_receipts
 where id=38 and receipt_kind='EVIDENCE_VERIFICATION'
), v as (
 select case when
 payload->>'schema_version'='SOAK_OBSERVATION_HISTORY_V2' and
 payload->>'verification_status'='VERIFIED' and payload->>'pass'='true' and
 subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2' and
 receipt_sha256 ~ '^[0-9a-f]{64}$' and
 (payload->>'screens_total')::integer=13 and
 (payload->>'families_total')::integer=47 and
 (payload->>'screens_below_2')::integer=0 and
 (payload->>'families_below_2')::integer=0 and
 (payload->>'known_false_pass_signals')::integer=0 and
 (payload->>'unresolved_d4')::integer=0
 then 'PASS' else 'FAIL' end verdict, receipt_sha256, payload->>'schema_version' policy
 from p)
select * from v$read1$,
 $read2$with m as (
 select unit_metadata->'m9_11_soak_readback_v1' historical_cohort
 from programacion.engineering_plan_units
 where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M9.11'
), c as (
 select distinct value::integer pantalla_id from m,
 lateral jsonb_array_elements_text(
  coalesce(historical_cohort#>'{coverage,covered_screen_ids}','[]'::jsonb) ||
  coalesce(historical_cohort#>'{coverage,missing_screen_ids}','[]'::jsonb)) x(value)
), obs as (
 select c.pantalla_id,count(r.id) filter(where r.status='COMPLETED') completed
 from c left join programacion.input_readiness_runs r on r.pantalla_id=c.pantalla_id
 group by c.pantalla_id
), agg as (
 select count(*) screens,count(*) filter(where completed>=2) screens_at_least_two,
 min(completed) minimum_completed,sum(completed) total_completed from obs
), fam as (
 select count(distinct a.family_code) distinct_families,count(distinct a.run_id) assessed_runs
 from programacion.input_family_assessments a
 join programacion.input_readiness_runs r on r.id=a.run_id
 where r.status='COMPLETED' and a.validator_outcome is not null
   and r.pantalla_id in (select pantalla_id from c)
)
select case when agg.screens=13 and agg.screens_at_least_two=13
 and fam.distinct_families=47 then 'PASS_OBSERVED' else 'FAIL_OBSERVED' end verdict,
 agg.*,fam.*, 'HISTORICAL_AS_OF_ELIGIBILITY_ONLY_FROM_VERIFIED_RECEIPT_38'::text semantic_limit
from agg cross join fam$read2$
 );
 new_objects jsonb := jsonb_build_array(
   'programacion.input_readiness_runs',
   'programacion.input_family_assessments',
   'programacion.provenance_receipts',
   'programacion.engineering_plan_units'
 );
 receipt programacion.provenance_receipts%rowtype;
 meta jsonb;
 spec jsonb;
 state jsonb;
 observed_screens integer;
 observed_ge2 integer;
 observed_min integer;
 observed_families integer;
 observed_runs integer;
 evidence text;
 trial integer;
BEGIN
 SELECT unit_metadata INTO STRICT meta
 FROM programacion.engineering_plan_units
 WHERE plan_code=p AND unit_code=u AND work_item_id=w AND disposition='ASSIGNED';
 old_queries:=meta#>'{source_pack_v1,checkpoint_inputs,OBSERVATION_COVERAGE,inputs,queries}';
 IF jsonb_array_length(old_queries)<>2
 OR old_queries->>0 NOT LIKE '%fn_input_readiness_run_is_current%'
 OR old_queries->>1 NOT LIKE '%order by id desc limit 13%'
 OR meta#>'{action_specs_v1,OBSERVATION_COVERAGE}' IS NOT NULL
 THEN RAISE EXCEPTION 'M107_CP2_ORIGINAL_SOURCE_PACK_CHANGED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'IN_PROGRESS'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=w AND checkpoint_code='SOAK_CRITERIA_ASIS')<>'DONE'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=w AND checkpoint_code='OBSERVATION_COVERAGE')<>'PENDING'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=w AND status='PENDING')<>4
 OR programacion.fn_engineering_effective_open_blocker_count_v1(w)<>0
 OR EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(w) d WHERE d.is_unmet)
 THEN RAISE EXCEPTION 'M107_CP2_EXPECTED_20_PERCENT_CHANGED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items w2
    JOIN programacion.engineering_plan_units p2 ON p2.work_item_id=w2.id
    WHERE p2.plan_code=p AND p2.unit_code='M9.11')<>'DONE'
 THEN RAISE EXCEPTION 'M107_CP2_M911_NOT_DONE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
 WHERE operation_code='ACTUALIZACION_DB_LF' AND asset_type='MIGRATION'
   AND action_code='UPDATE' AND status='ACTIVE' AND write_allowed)
 THEN RAISE EXCEPTION 'M107_CP2_TRAIN_ROUTE_NOT_READY'; END IF;

 SELECT * INTO STRICT receipt FROM programacion.provenance_receipts
 WHERE id=38 AND receipt_kind='EVIDENCE_VERIFICATION'
 AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2';
 IF receipt.receipt_sha256 !~ '^[0-9a-f]{64}$'
 OR receipt.payload->>'schema_version' IS DISTINCT FROM 'SOAK_OBSERVATION_HISTORY_V2'
 OR receipt.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
 OR receipt.payload->>'pass' IS DISTINCT FROM 'true'
 OR (receipt.payload->>'screens_total')::integer<>13
 OR (receipt.payload->>'families_total')::integer<>47
 OR (receipt.payload->>'screens_below_2')::integer<>0
 OR (receipt.payload->>'families_below_2')::integer<>0
 OR (receipt.payload->>'known_false_pass_signals')::integer<>0
 OR (receipt.payload->>'unresolved_d4')::integer<>0
 THEN RAISE EXCEPTION 'M107_CP2_CANONICAL_RECEIPT_NOT_PASS'; END IF;

 WITH m AS (
 select unit_metadata->'m9_11_soak_readback_v1' historical_cohort
 from programacion.engineering_plan_units
 where plan_code=p and unit_code='M9.11'
 ), c AS (
 select distinct value::integer pantalla_id from m,
 lateral jsonb_array_elements_text(
  coalesce(historical_cohort#>'{coverage,covered_screen_ids}','[]'::jsonb) ||
  coalesce(historical_cohort#>'{coverage,missing_screen_ids}','[]'::jsonb)) x(value)
 ), obs AS (
 select c.pantalla_id,count(r.id) filter(where r.status='COMPLETED') completed
 from c left join programacion.input_readiness_runs r on r.pantalla_id=c.pantalla_id
 group by c.pantalla_id
 ), ag AS (
 select count(*) screens,count(*) filter(where completed>=2) screens_ge2,
 min(completed) min_completed,sum(completed) total_completed from obs
 ), fam AS (
 select count(distinct a.family_code) distinct_families
 from programacion.input_family_assessments a
 join programacion.input_readiness_runs r on r.id=a.run_id
 where r.status='COMPLETED' AND a.validator_outcome is not null
   and r.pantalla_id in(select pantalla_id from c)
 )
 SELECT ag.screens,ag.screens_ge2,ag.min_completed,ag.total_completed,fam.distinct_families
 INTO observed_screens,observed_ge2,observed_min,observed_runs,observed_families
 FROM ag cross join fam;
 IF observed_screens<>13 OR observed_ge2<>13 OR observed_min<2
 OR observed_families<>47
 THEN RAISE EXCEPTION 'M107_CP2_OBSERVED_COHORT_CHANGED'; END IF;
 evidence:='supabase://programacion.provenance_receipts/38#sha256='||
 receipt.receipt_sha256||';asof=VERIFIED;screen=13/13;families=47/47;min_hist=2;raw_completed='||
 observed_runs::text||';NO_PRODUCTION';

 FOR trial IN 1..2 LOOP
   BEGIN
     UPDATE programacion.engineering_plan_units
     SET unit_metadata=jsonb_set(
        jsonb_set(unit_metadata,
        '{source_pack_v1,checkpoint_inputs,OBSERVATION_COVERAGE,inputs,queries}',
        new_queries,true),
        '{source_pack_v1,checkpoint_inputs,OBSERVATION_COVERAGE,inputs,db_objects}',
        new_objects,true)
     WHERE plan_code=p AND unit_code=u AND work_item_id=w
       AND unit_metadata#>'{source_pack_v1,checkpoint_inputs,OBSERVATION_COVERAGE,inputs,queries}'=old_queries;
     IF NOT FOUND THEN RAISE EXCEPTION 'M107_CP2_SOURCE_PACK_EDIT_NOT_APPLIED'; END IF;
     spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p,u,'OBSERVATION_COVERAGE');
     IF spec->>'status' IS DISTINCT FROM 'READY'
     OR spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
     OR (spec->>'requires_material_execution')::boolean IS DISTINCT FROM false
     OR spec->'verification_queries' IS DISTINCT FROM new_queries
     OR NOT (spec#>'{target,declared_objects}' @> jsonb_build_array('programacion.provenance_receipts'))
     THEN RAISE EXCEPTION 'M107_CP2_NEW_ACTION_SPEC_NOT_READY'; END IF;
     state:=programacion.fn_engineering_checkpoint_transition_snapshot_v1(
       p,u,'OBSERVATION_COVERAGE','DONE',evidence,actor,
       'CP2 verified independent authorized-read queries; as-of authority receipt 38; no new runs.');
     IF state#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     THEN RAISE EXCEPTION 'M107_CP2_TRANSITION_NOT_APPLIED'; END IF;
     IF trial=1 THEN
       RAISE EXCEPTION 'M107_CP2_ROLLBACK_SENTINEL' USING ERRCODE='PZ108';
     END IF;
   EXCEPTION WHEN SQLSTATE 'PZ108' THEN
     IF trial<>1 THEN RAISE; END IF;
   END;
   IF trial=1 AND
    ((SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=w AND checkpoint_code='OBSERVATION_COVERAGE')<>'PENDING'
     OR (SELECT unit_metadata#>'{source_pack_v1,checkpoint_inputs,OBSERVATION_COVERAGE,inputs,queries}'
         FROM programacion.engineering_plan_units
         WHERE plan_code=p AND unit_code=u) IS DISTINCT FROM old_queries)
   THEN RAISE EXCEPTION 'M107_CP2_ROLLBACK_RESIDUE'; END IF;
 END LOOP;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND status='DONE')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND status='PENDING')<>3
 OR (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'M107_CP2_LEDGER_DRIFT'; END IF;

 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='IG-M107-CP2-READ-ROLE-CURRENTNESS-001')
 THEN RAISE EXCEPTION 'M107_CP2_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
 validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
 estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
 source_context,source_ref)
 VALUES (
 gen_random_uuid(),'IG-M107-CP2-READ-ROLE-CURRENTNESS-001','GOVERNANCE',
 'CP2 soak declaraba consulta CURRENT sin permiso y ventana latest13 no representativa',
 'Consulta inicial del CP2 llamaba fn_input_readiness_run_is_current no concedida al conector read-only (42501). Otra leía solo últimas 13 ejecuciones en lugar de cohorte histórica. Ninguna prueba es equivalente al as-of certificado M9.11.',
 'Desalineación entre verificación CP2, autoridad histórica M9.11 y privilegios de lectura declarados.',
 'UNAUTHORIZED_CURRENTNESS_IN_READBACK_AND_LATEST_13_SAMPLE',
 'Leer EKB y action_spec. No elevar EXECUTE ni crear motor. Reusar recibo verificado SOAK_OBSERVATION_HISTORY_V2 y revisar la cohorte mediante tablas con SELECT autorizado. Considerar recuentos brutos como evidencia complementaria, nunca sustituto de as-of. Rectificar únicamente queries CP2.',
 '2026-10-14: Q1 receipt 38 PASS, Q2 cohort PASS_OBSERVED 13/13 screens, 47 families, 199 completed runs. SQL 42501 reproducido. Migración revierte primer ensayo y lee CP2 DONE, otros tres pendientes sin autorizar producción.',
 'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
 'VALIDATED_TESTED',evidence,now(),now(),'EXECUTION',
 'R4_NO_CUESTIONA','LOUD_EARLY',
 'M10.7 CP2 authorized Supabase read-only source queries',
 'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7'
 );
END
$m107cp2$;
