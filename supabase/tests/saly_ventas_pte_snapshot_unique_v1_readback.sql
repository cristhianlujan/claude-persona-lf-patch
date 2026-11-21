SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='saly' AND tablename='ventas_discovery_ingestas' AND indexname='saly_pte_source_batch_once_v1';
SELECT source_id,source_version,scope_key,batch_key,count(*) AS ingestas FROM saly.ventas_discovery_ingestas WHERE source_id='PE-PTE' GROUP BY source_id,source_version,scope_key,batch_key;
SELECT count(*) AS hallazgos FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.source_id='PE-PTE';
