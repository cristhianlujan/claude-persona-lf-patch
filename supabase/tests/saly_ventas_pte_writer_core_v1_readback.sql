-- Read-only after governed migration.
SELECT to_regprocedure('saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)') AS writer_core;
SELECT role,has_function_privilege(role,'saly.ventas_pte_ingesta_core_v1(uuid,text,text,text)','EXECUTE') AS can_execute FROM unnest(ARRAY['anon','authenticated','service_role','supabase_read_only_user']) AS role;
SELECT count(*) AS fixture_runs FROM saly.ventas_discovery_runs WHERE run_ref='RUN-PTE-WRITER-FIXTURE';
SELECT count(*) AS real_pte_hallazgos FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id WHERE i.source_id='PE-PTE';
