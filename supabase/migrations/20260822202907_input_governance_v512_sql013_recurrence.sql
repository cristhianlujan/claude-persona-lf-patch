update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 INPUT_GOVERNANCE v5.12 successor pilot: a PL/pgSQL record variable named a collided with SQL alias a in INSERT ... SELECT, raising record-not-assigned. The apply_migration transaction rolled back completely; ledger and successor readback confirmed zero residual rows.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12 recurrence: DO-block record variables use v_* names and SQL relations use src_*/cur_* aliases; never reuse a declared record variable as a SQL alias. Verify failed migration leaves zero ledger/write residue before retry.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'Retry must use non-overlapping v_* record variables and src_* SQL aliases; migration must complete atomically and failed attempt must remain absent from supabase_migrations.schema_migrations.'),
    source_context='INPUT_GOVERNANCE_V512_SCREEN56_SUCCESSOR_PILOT_20260822',
    source_ref='failed migration input_governance_v512_successor_screen56_semantic_coherence; zero residual successor rows'
where codigo='SQL-013';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12: en DO blocks de sucesores usar variables v_* y aliases src_*/cur_* disjuntos; verificar rollback cero antes de reintento.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22 durante sucesor AUTH-006; el rollback fue limpio y el reintento debe usar aliases inequívocos.')
where regla_codigo='PRV-SQL-013';