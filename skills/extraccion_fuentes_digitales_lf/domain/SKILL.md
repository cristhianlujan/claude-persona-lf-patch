# SKILL_EXTRACCION_FUENTES_DIGITALES_LF

> Estado: CANDIDATO_READ_ONLY
> Versión: v0.1 · Lote 20B
> Path canónico: skills/extraccion_fuentes_digitales_lf/domain/SKILL.md

---

## Identidad

```yaml
asset_code: ACT-0052
canonical_name: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
skill_id: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
owner_skill: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
child_adapter: ADAPTER_WEB_ARTICLE_CAPTURE_LF
estado: CANDIDATO_READ_ONLY
dominio: extraccion_fuentes_digitales_lf
contexto: fintech_peruano
```

---

## Propósito

Orquestar la captura estructurada de fuentes digitales y convertirlas en evidencia persistible y verificable para revisión posterior.

No evalúa. No califica. No infiere. No homologa. No promueve conocimiento. Captura y estructura, nada más.

---

## Ownership del vertical slice

Todo lo que vive bajo `skills/extraccion_fuentes_digitales_lf/` pertenece a esta skill.

```text
skills/extraccion_fuentes_digitales_lf/
  domain/
  commands/
  queries/
  adapters/
  cards/
```

Adapter funcional actual:

```text
adapters/web_article_capture/ → ADAPTER_WEB_ARTICLE_CAPTURE_LF
```

---

## Límites explícitos

```text
NO_VALIDATED: true
NO_PRODUCCION: true
NO_RUNTIME_REAL: true
NO_HOMOLOGACION: true
NO_INSIGHT_AUTOMATICO: true
NO_ALERT_AUTOMATICO: true
NO_N8N_AUTOMATICO: true
NO_KB_FINAL: true
```

---

## Arquitectura del dominio

```text
Commands:
  capture_web_article/ → escritura controlada sandbox

Queries:
  get_web_capture_readback/ → lectura y verificación

Adapters:
  web_article_capture/ → artículos web

Cards:
  evidence_layers_required.md
  no_homologation_no_insight_no_alert.md
```

---

## Tablas BD involucradas

| Tabla | Operación |
|---|---|
| `lf_capture_runs` | ESCRIBE sandbox |
| `lf_capture_records` | ESCRIBE sandbox |
| `lf_log_operativo` | ESCRIBE sandbox |
| `lf_log_config` | LEE |
| `lf_operation_registry` | LEE |
| `sbx_competitive_sources` | LEE |
| `lf_capture_judge_results` | NO TOCA |
