SELECT scope,config_key,config_value,value_type,value_status FROM public.lf_global_config WHERE scope='SALY_DISCOVERY' AND config_key='PTE_POLICY_V1';
SELECT public.lf_saly_discovery_pte_policy_v1() AS policy;
SELECT count(*) AS hallazgos FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas di ON di.id=h.ingesta_id WHERE di.source_id='PE-PTE';
