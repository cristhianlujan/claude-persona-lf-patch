# RUNBOOK — ADAPTER_WEB_ARTICLE_CAPTURE_LF

Owner: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
Estado: CANDIDATO_READ_ONLY

## Flujo

1. Resolver ACT-0052 en Supabase.
2. Confirmar modo permitido.
3. Validar URL.
4. Verificar duplicado.
5. Extraer evidencia literal.
6. Persistir solo si modo sandbox lo permite.
7. Ejecutar readback.
8. Registrar log operativo.
9. No homologar, no generar insight, no alertar.

## Modo seguro recomendado

DRY_RUN antes de cualquier escritura sandbox.
