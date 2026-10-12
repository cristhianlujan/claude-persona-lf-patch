-- LF - Perfil de reparacion / U8. Registro de bloqueo observado, no admision de acceso.
-- Evidencia: PR #2258 merged, sandbox D1/D2 metadata 4/4 PASS,
-- fn_lf_d2_admission_readiness_v1 requiere binding y actor real.
-- No modifica perfiles, datos B2B, roles, RLS, runtime ni gates.
INSERT INTO public.lf_error_knowledge
(id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref)
SELECT md5('LF-REPAIR-U8-GOVERNED-READ-PREREQUISITES-001')::uuid,
'LF-REPAIR-U8-GOVERNED-READ-PREREQUISITES-001','GOVERNANCE',
'U8 LF Reparador: fuente tecnicamente identificada pero lectura empresarial no admitida',
'Preflight sandbox de D1/D2 para db://lf_ops.cargas_lotes: catalogo verificado; no existe binding operativo VIGENTE ni sesion de actor empresarial verificada; no existe recibo U8/U9 de lectura.',
'La calificacion tecnica de metadatos U7 no implica autorizacion empresarial U8. Falta completar binding, fachada, actor real, empresa, RLS y recibo verificable antes de permitir lectura.',
'METADATA_VERIFIED_NE_BUSINESS_READ_AUTHORIZED',
'Separar U7 de U8 y U9. U8 exige binding canonico VIGENTE con fachada SECURITY INVOKER, allowlist, actor real, empresa y prueba positiva propia/negativa cross-tenant; U9 exige recibo en private.lf_evidence_ledger_v1. No fabricar actores ni usar service_role para leer negocio.',
'2026-10-12: private.fn_lf_d2_admission_readiness_v1(db://lf_ops.cargas_lotes)=REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION; private.fn_lf_d2_facade_request_plan_v1=BLOCK_SOURCE_NOT_STRUCTURALLY_ADMITTED; receipt UUID nulo=BLOCK_CANONICAL_RECEIPT_NOT_FOUND. U7 metadata 4/4 PASS en ROLLBACK.',
'MEDIA',1,now(),now(),'LF_REPAIR_U8_PREFLIGHT','ACTIVO',
'PR #2258 merged; Supabase LF_SUPABASE_SANDBOX; funciones privadas U8 verificadas con BEGIN/ROLLBACK; sin lecturas de filas B2B.',
now(),now(),'CONSTRUCTION',ARRAY['LF_REPAIR']::text[],
'UNCLASSIFIED_WITH_REASON','LOUD_EARLY',
'LF - Perfil de reparacion / D1-D2 / U8; categoria pendiente de adjudicacion R1-R5: falta autoridad empresarial, no es error de codigo',
'db://lf_ops.cargas_lotes'
WHERE NOT EXISTS (
 SELECT 1 FROM public.lf_error_knowledge
 WHERE codigo='LF-REPAIR-U8-GOVERNED-READ-PREREQUISITES-001'
);
