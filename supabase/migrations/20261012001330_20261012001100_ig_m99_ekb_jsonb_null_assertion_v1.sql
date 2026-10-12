-- Verified EKB M9.9 root cause. No runtime change or release promotion.
do $ekb$ declare n integer;
begin
 select count(*) into n from public.lf_error_knowledge where codigo='IG-M99-JSONB-PARENT-NULL-ASSERTION-001';
 if n<>0 then raise exception 'EKB_M99_DUPLICATE_%',n; end if;
 insert into public.lf_error_knowledge(
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,lote_origen,pr,estado,evidencia,lifecycle_phase,
 consumer_role,root_cause_family,detectability,source_context,source_ref)
 values(
 'IG-M99-JSONB-PARENT-NULL-ASSERTION-001','ENGINEERING_VALIDATION',
 'JSONB sin padre y aserción NULL podían producir falso PASS de reparación',
 'En el primer ensayo M9.9 no existía blocker_reconciliation_v1. jsonb_set con ruta anidada no creó el padre; IF receipt.proof_passed <> true no rechazó NULL por lógica SQL trivalente; reconciliador devolvió checked=0.',
 'JSONB anidado sin objeto padre y comparación SQL no null-safe.',
 'MISSING_JSONB_PARENT + NULL_TREATED_AS_TEST_PASS',
 'Crear explícitamente objeto padre con jsonb_set raíz, exigir existencia de regla y checked=1; probar con IS DISTINCT FROM, casos positivos y negativos; efectuar ROLLBACK y readback sin residuos antes del PR.',
 'PR #2249: ROLLBACK PASS positivo + tres negativos (capacidad, dependencia, cohorte); reconciliación 1/1 y bootstrap CONTINUE_CURRENT_CHECKPOINT; COHORT_BINDING DONE, M9.9 35%.',
 'HIGH',1,'IG_CURATOR_VALIDATOR_REFACTOR_V2','2249','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2249; supabase migration 20261012002200_ig_m99_cohort_authority_reconcile_v1; function md5 d328eebbb8dd3b8a6c7c61241a00db0f; blocker 101 RESOLVED.',
 'VALIDATION',ARRAY['ENGINEERING_EXECUTOR','VALIDATOR']::text[],
 'R2_NO_VE','PROCESS_DEPENDENT','M9.9 sandbox recovery and reversible SQL tests','programacion.fn_engineering_blocker_reconcile_v1');
 if (select count(*) from public.lf_error_knowledge where codigo='IG-M99-JSONB-PARENT-NULL-ASSERTION-001')<>1
 then raise exception 'EKB_M99_READBACK_INCORRECT'; end if;
end $ekb$;