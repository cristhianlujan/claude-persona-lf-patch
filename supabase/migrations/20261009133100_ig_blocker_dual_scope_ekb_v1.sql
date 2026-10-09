-- EKB: permanent decision rule for current and future engineering blocker repairs.
INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,source_ref)
SELECT gen_random_uuid(),'ENGINEERING-BLOCKER-DUAL-SCOPE-REPAIR-001',
 'ENGINEERING_GOVERNANCE',
 'Reparar bloqueo en contrato de unidad y gobernanza dentro del mismo lote',
 'Cada bloqueo IG se analiza en dos pistas; no se crea un nuevo gate.',
 'Unicamente corregir la unidad deja una dependencia transversal obsoleta y reproducira el bloqueo.',
 'UNIT_CONTRACT + TRANSVERSAL_GOVERNANCE -> reversible test -> Git-first -> readback -> closure',
 'Usar el prepass de bloqueos V2: cada resultado repair_pair identifica el contrato local y el estado de gobernanza. Corregir ambos cuando aplique, en el mismo lote; cuando no haya cambio transversal, demostrar NOT_APPLICABLE. Las versiones mayores requieren prueba de compatibilidad: prohibido rebind ciego o saltar SAFE_CHANGE_ADMISSION. Sin doble evidencia no hay cierre.',
 'Prueba reversible de 4 bloqueos y 2 dependencias con version drift, 0 residuo; Git, PR y readback requeridos.',
 'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','CANDIDATO',
 'M7.13 y SAFE_CHANGE_ADMISSION 1.0.1 vs INDEPENDENT_ASSURANCE 2.0.1; 2026-10-09',
 now(),now(),'programacion.fn_engineering_plan_blocker_repair_prepass_v2'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='ENGINEERING-BLOCKER-DUAL-SCOPE-REPAIR-001');
