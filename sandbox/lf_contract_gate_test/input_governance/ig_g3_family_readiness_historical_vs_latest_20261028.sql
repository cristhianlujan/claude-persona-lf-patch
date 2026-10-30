-- IG G3 read-only guard: distinguish historical from latest completed family assessments.
WITH completed AS MATERIALIZED (
 SELECT id,pantalla_id,created_at,invalidated_at
 FROM programacion.input_readiness_runs WHERE status='COMPLETED'
),
family_counts AS MATERIALIZED (
 SELECT r.id,r.pantalla_id,r.created_at,r.invalidated_at,
 count(a.id) families,
 count(a.id) FILTER(WHERE a.applicability='UNRESOLVED') unresolved,
 count(a.id) FILTER(WHERE a.applicability='APPLICABLE') applicable,
 count(a.id) FILTER(WHERE a.applicability='NOT_APPLICABLE') not_applicable
 FROM completed r LEFT JOIN programacion.input_family_assessments a ON a.run_id=r.id
 GROUP BY r.id,r.pantalla_id,r.created_at,r.invalidated_at
),
ranked AS MATERIALIZED (
 SELECT *,row_number() OVER (PARTITION BY pantalla_id ORDER BY created_at DESC,id DESC) seq
 FROM family_counts
)
SELECT 'HISTORICAL_COMPLETED' AS cohort,count(*) AS runs,
sum(families) AS family_assessments,sum(unresolved) AS unresolved,
count(*) FILTER(WHERE families<>47) AS non47
FROM family_counts
UNION ALL
SELECT 'LATEST_COMPLETED_PER_SCREEN',count(*),sum(families),sum(unresolved),
count(*) FILTER(WHERE families<>47 OR invalidated_at IS NOT NULL)
FROM ranked WHERE seq=1;