# DECISIONES_PENDIENTES — IG 08:15 · 2026-11-16

Estado: PENDIENTE. No se modifican ni se cierran los PR históricos.

## Pregunta exacta al owner, solo DESPUÉS del merge y readback real

**¿Autoriza cerrar #3795, #3948 y #3777 como SUPERSEDIDOS si, tras el merge de IG 08:15, sus guardas de preimagen siguen sin coincidir con las definiciones actuales desplegadas de `lf_rule_promotion_request_v1` y/o `lf_rule_promotion_decide_v1`?**

| PR | Rama / característica | Dato actual | Comprobación posterior obligatoria |
|---|---|---|---|
| #3795 | `lf/issue-3779-lote3-governed-rule-promotion-v1`; DRAFT | Sustituye ambas funciones, guardas preimagen anteriores | Readback `pg_get_functiondef` después del merge y comparación literal con sus guards |
| #3948 | `lf/rule-v2-auto-verified-batch-audit-20261114` | Guarda MD5 de `request_v1` antigua | Readback posterior; no tocar su batch V2 |
| #3777 | `lf/issue-3774-rule-promotion-authority-v1`; DRAFT | Guarda MD5 de `decide_v1` antigua | Readback posterior; no tocar su gobernanza histórica |

## Conservado conceptualmente de #3795

- Autoridad del RUN padre con pasos y evidencias enlazadas; no confiar en declaración del perfil.
- `HUMAN:...` como único decisor manual y rejection de actores inválidos; `AUTO_SCORE_V1` únicamente en ruta AUTO con score y fuente vinculados.
- CANDIDATO, no duplicidad de solicitud, hashes 40/50/60/70, snapshot SHA y rechazo STALE; toda aplicación pasa por escritor oficial.
- Restricciones de origen y trazabilidad de la promoción. No se importan su esquema viejo de juez externo, guardas antiguas, ni permisos de promoción por rol para AUTO.

## Fuentes del parche IG 08:15

- PREIMAGEN READBACK: request `61ab4c8363f09309385ff80a82697717`, decide `e36f54b29ad49e2b87b1a670e31cde30`.
- El parche no modifica `lf_rule_promotion_score_v1`, `lf_rule_promotion_apply_v1`, `lf_rule_promotion_guard_v1`, contratos del Paso 80 ni otros PR.
- El fixture PG17/PG18 contiene definiciones actuales capturadas por SELECT, con BEGIN/ROLLBACK y datos totalmente sintéticos.
- Estado de la decisión de cierre: PENDIENTE de readback postmerge y autorización nueva del owner.
