-- B06 G03 SELECT-ONLY. No temp tables, no DML/DDL.
-- Cutoff is the exact started_at of the real #3806 backfill Train execution.
-- Expected root from frozen GitHub chunks: 7bae2d2952c1dae06bbe32e498421a3752f9802078d29da4e218d62749512a02
WITH run_hashes AS MATERIALIZED(
  SELECT e.execution_id,
    encode(extensions.digest(convert_to(to_jsonb(e)::text,'UTF8'),'sha256'),'hex') AS run_sha256,
    st.steps_n,st.steps_sha256
  FROM public.lf_operation_execution e
  LEFT JOIN LATERAL(
    SELECT count(*)::integer AS steps_n,
      CASE WHEN count(*)=0 THEN NULL ELSE
       encode(extensions.digest(convert_to(string_agg(
         s.step_order::text||chr(9)||s.step_id||chr(9)||
         encode(extensions.digest(convert_to(to_jsonb(s)::text,'UTF8'),'sha256'),'hex'),
         chr(10) ORDER BY s.step_order,s.step_id COLLATE "C"),'UTF8'),'sha256'),'hex')
      END AS steps_sha256
    FROM public.lf_operation_execution_steps s WHERE s.execution_id=e.execution_id
  ) st ON true
  WHERE e.started_at<'2026-11-13 07:20:12.513028+00'::timestamptz
)
SELECT count(*) AS historical_runs,count(DISTINCT execution_id) AS distinct_runs,
 sum(steps_n)::bigint AS historical_steps,
 encode(extensions.digest(convert_to(string_agg(
   execution_id||chr(9)||run_sha256||chr(9)||steps_n::text||chr(9)||coalesce(steps_sha256,'-'),
   chr(10) ORDER BY execution_id COLLATE "C"),'UTF8'),'sha256'),'hex') AS root_sha256
FROM run_hashes;
