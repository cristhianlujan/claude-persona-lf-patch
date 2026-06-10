# REGLAS OPERATIVAS — SKILL_EXTRACCION_FUENTES_DIGITALES_LF

> Estado: CANDIDATO_READ_ONLY · Lote 20B

## Reglas de dominio

```text
RULE_D01: No inferir campos no visibles. Campo no visible → NOT_FOUND.
RULE_D02: claims_json[].verificado_fuente_primaria siempre false.
RULE_D03: No declarar extraction_successful=true sin readback confirmado.
RULE_D04: flow_terminated=true en todos los caminos.
RULE_D05: Anti-duplicado obligatorio antes de cualquier INSERT.
RULE_D06: Solo FULL_EXTRACTION_REGISTER_SANDBOX_ONLY escribe en sandbox.
RULE_D07: ADMIN_OVERRIDE bloqueado por defecto.
RULE_D08: No escribir en lf_capture_judge_results ni producción.
RULE_D09: Todo log usa log_key registrado en lf_log_config.
RULE_D10: No homologar, no generar insight, no generar alert, no conectar n8n.
```

## Reglas de arquitectura

```text
RULE_A01: Domain no contiene infraestructura.
RULE_A02: Commands = operaciones; Queries = lectura/readback.
RULE_A03: web_article_capture vive como adapter hijo.
RULE_A04: Cards específicas viven en cards/.
RULE_A05: GitHub debe ser navegable sin depender de memoria del chat.
```

## Reglas de trazabilidad

```text
RULE_T01: Supabase es índice rector.
RULE_T02: GitHub es fuente autora de archivos.
RULE_T03: No declarar estados fuera de states.md.
RULE_T04: Todo uso debe resolver primero ACT-0052.
```
