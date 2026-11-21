SELECT d.run_ref,d.scope,d.estado,o.status AS train_status,i.archivo_sha256,count(h.id) AS hallazgos,
 count(h.id) FILTER(WHERE h.ubigeo_candidato LIKE '15%') AS lima,
 count(h.id) FILTER(WHERE h.ubigeo_candidato LIKE '11%') AS ica,
 count(h.id) FILTER(WHERE h.estado_identidad='SIN_RUC') AS sin_ruc
FROM saly.ventas_discovery_runs d JOIN public.lf_operation_execution o ON o.execution_id=d.run_ref
JOIN saly.ventas_discovery_ingestas i ON i.run_ref=d.run_ref JOIN saly.ventas_hallazgos h ON h.ingesta_id=i.id
WHERE d.scope->>'mode'='FIRST_LOAD_BOOTSTRAP_TRAIN' GROUP BY d.run_ref,d.scope,d.estado,o.status,i.archivo_sha256;
