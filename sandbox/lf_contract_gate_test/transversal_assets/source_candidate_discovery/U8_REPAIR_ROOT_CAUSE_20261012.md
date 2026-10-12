# LF Perfil Reparador — U8: diagnóstico y reparación propuesta (NO aceptación)
Fecha: 2026-10-12 UTC. Alcance exclusivo LF D1/D2, sin IG ni Análisis.

## Evidencia observada
- Supabase LF_SUPABASE_SANDBOX: evento 20729 (`LF_D2_U8_FAIL_CLOSED_PREFLIGHT`), 22/22 pruebas reversibles de denegación PASS, sin filas B2B leídas ni actor empresarial.
- `private.fn_lf_d2_admission_readiness_v1('db://lf_ops.cargas_lotes')` retorna `REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION`; binding `BLOCK_BINDING_ABSENT_OR_AMBIGUOUS`.
- `private.fn_lf_d2_source_binding_candidate_v1` retorna candidato, no autorización; `read_facade_ref=null`, `admission_status=CANDIDATO`, columnas/filtros vacíos.
- `private.fn_lf_d2_binding_readback_v1` requiere un activo único vigente, policy SHA y schema fingerprint actuales, allowlists, máximo de filas, fachada SECURITY INVOKER, operación/paso vigente, referencias de evidencia/aprobación.
- `public.lf_write_pipeline_ekb_v1` es writer de EKB exclusivamente para operaciones con contrato activo PRE_EKB_GATE; no usarlo con código de operación inventado. `public.lf_error_knowledge` es una vista de `transversal.error_knowledge`.
- La rama de preflight es idéntica a main al iniciar esta propuesta. Este documento no crea binding ni concede permisos.

## Primera frontera defectuosa
Se calificó correctamente la fuente técnica, pero no existe el contrato empresarial admitido que vincule esa fuente con una fachada y un actor real autorizado. Confundir U7 técnico con U8 operativo produciría una aceptación falsa; los controles actuales la bloquean.

## Alternativas contrastadas
1. Otorgar SELECT directo, relajar RLS o suplantar actor con service_role: RECHAZADA (salta control por empresa).
2. Mantener U8 bloqueada hasta contar con actor y no construir nada: INSUFICIENTE (impide completar construcción independiente).
3. Construir primero fachada invoker de lectura limitada, contrato de binding candidato y controles reversibles; admitir binding solo con recibo de gobernanza independiente, luego probar con actor real y tenant negativo: ELEGIDA.

## Reparación mínima suficiente
1. Conservar las reglas RLS actuales y separar `TECHNICAL_CONSTRUCTION` de `BUSINESS_ADMISSION` en el contrato/estado de U8.
2. Definir fachada `SECURITY INVOKER` con columnas/filtros permitidos y límite; reutilizar los diagnósticos y catálogos existentes, sin rutas hardcodeadas de producto.
3. Crear contrato de admisión de binding con aprobador verificable, policy SHA, fingerprint, operación/paso vigentes y readback; prohibir autoaprobación por simple metadata.
4. Probar con ROLLBACK el positivo técnico y negativos (URI inválida, ausencia de binding, columna/filtro fuera de allowlist, tenant ajeno, falta de permiso, replay/stale binding).
5. Solo con identidad empresarial REAL y autorización de empresa, ejecutar lectura positiva/negativa RLS y emitir recibo U9 en ledger por ruta gobernada.
6. No declarar U8 DONE por 22/22 negativas. EKB: crear writer genérico gobernado o usar ruta vigente demostrada; no disfrazar incidente de migración DDL.

## Condiciones de cierre
Git PR+merge+readback si se modifica código; migración exacta si hay DDL; pruebas positivas y negativas con actor real; binding vigente con admisión independiente; recibo canónico verificable; Git=ledger=DB. Hasta entonces `BLOCKED_BUSINESS_ADMISSION`.

## Riesgo residual / segunda recurrencia
Una versión vieja de policy/fingerprint, actor o empresa cruzada, rutas alternativas de lectura, replay y recibo autodeclarado podrían recrear la falla. Verificar en consumidor y readback, no solo en el productor.
