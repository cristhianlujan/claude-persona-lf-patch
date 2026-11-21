BEGIN;
DO $ekb$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('SALY-NATIVE-HANDOFF-REWRITE-20261121-001','LF-JS-REPLACE-DOLLAR-SUFFIX-SQL-20261121-001'))
 THEN RAISE EXCEPTION 'SALY_CREATIVE_EKB_CODE_ALREADY_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
 primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'SALY-NATIVE-HANDOFF-REWRITE-20261121-001','TRANSPORT','Reescritura del prompt sellado antes de generar imagen','La prueba Home B recibió una instrucción ampliada para generar el dispositivo completo; la orden sellada pedía solo el cuerpo. La imagen resultante incluyó marco, logo, botón y navegación que eran responsabilidad del compositor.','El invocador reconstruyó el texto y adjuntó referencias en vez de transportar el payload compilado.','NATIVE_PROMPT_REWRITE_AT_INVOCATION','Derivar el payload directamente del work packet, validar versión, forma, bytes UTF-8, SHA-256 y adjuntos exactos; separar parámetros de composición. No confundir captura local con recibo del proveedor.','PR #4513 integrado; PR #4514 integrado (migración 20261121074101); 15/15 casos de validación preliminar y controles por código en la migración. Recepción efectiva del proveedor aún no acreditada.','HIGH',1,now(),now(),'SALY_CREATIVE_TRANSPORT_20261121','#4514','ACTIVO','Piloto Home B; el prompt del invocador pidió una imagen final compuesta y el handoff sellado excluía marco, logo, CTA y navegación.','DESIGN',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R5_EROSION_PROCESO','SILENT','SALY Fábrica Digital','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4514',now(),now()),
(gen_random_uuid(),'LF-JS-REPLACE-DOLLAR-SUFFIX-SQL-20261121-001','DevOps/CI','Sustitución JavaScript interpretó dólar y apóstrofo en SQL','Una sustitución de expresión regular SQL mediante String.replace con cadena de reemplazo interpretó el marcador dólar-apóstrofo como sufijo del texto. Duplicó el resto del archivo y dejó la expresión sin comilla final; PASE falló por SQL dollar string sin terminar.','Se utilizó una cadena de reemplazo con metacaracteres en lugar de una función de reemplazo literal.','JS_REPLACEMENT_META_EXPANSION','Usar reemplazo por función para inyectar SQL literal, exigir una coincidencia del ancla, verificar archivo completo recuperado de GitHub y ejecutar PASE sobre el HEAD corregido.','Reproducción JS: reemplazo por cadena duplica TAIL y pierde cierre; reemplazo por función conserva expresión y TAIL único. PASE fallido 44877904062 y exitoso 44881183552; PR #4514 fusionado.','MEDIUM',1,now(),now(),'SALY_CREATIVE_TRANSPORT_20261121','#4514','RESUELTO','PR #4514, commit defectuoso efc27b68; corrección 610786dc; HEAD integrado 3285478a.','DESIGN',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','LOUD_EARLY','SALY Fábrica Digital','https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44877904062',now(),now());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN ('SALY-NATIVE-HANDOFF-REWRITE-20261121-001','LF-JS-REPLACE-DOLLAR-SUFFIX-SQL-20261121-001'))<>2
 THEN RAISE EXCEPTION 'SALY_CREATIVE_EKB_READBACK_FAILED'; END IF;
 -- Same incident family, new observed recurrence; no duplicate EKB code.
 UPDATE public.lf_error_knowledge SET frecuencia=frecuencia+1,ultima_vez=now(),updated_at=now(),
   source_ref=concat_ws(';',source_ref,'github://cristhianlujan/claude-persona-lf-patch/pull/4519#train-44881563302'),
   evidencia=concat_ws(' | ',evidencia,'SALY #4519 PRE-APPLY STOP run 44881563302: 20261121074000 occupied by the checkout pilot migration (ledger identity verified in the linked Train run). Renamed to unused provisional version 20261121075843, exact blob c605c5c274b572cd652b88e574ab335953b5eedb; no SQL replay.')
 WHERE codigo='IG-M96-MIGRATION-VERSION-COLLISION-001'
 AND position('pull/4519#train-44881563302' in coalesce(source_ref,''))=0;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALY_CREATIVE_EKB_RECURRENCE_MISSING_OR_DUPLICATE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M96-MIGRATION-VERSION-COLLISION-001'
 AND position('pull/4519#train-44881563302' in coalesce(source_ref,''))>0)
 THEN RAISE EXCEPTION 'SALY_CREATIVE_EKB_RECURRENCE_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
