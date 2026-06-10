# SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1

> Estado: CANDIDATO_READ_ONLY
> Versión: v0.1 · Lote 20B
> Path canónico: skills/jie_observation_intake_lf/domain/SKILL.md
> Evidencia Supabase: lf_eventos id=242, 243, 244

---

## Identidad

```yaml
# ── GOBERNANZA ─────────────────────────────────────────
asset_code:      ACT-0052                                    # código estable Supabase — nunca cambia
canonical_name:  SKILL_EXTRACCION_FUENTES_DIGITALES_LF      # nombre canónico en Supabase desde Fase 1
legacy_skill_id: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1  # ID técnico GitHub — Fase 2 pendiente
# ───────────────────────────────────────────────────────
skill_id:    SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
owner_skill: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
child_adapter: ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2

estado:  CANDIDATO_READ_ONLY
dominio: inteligencia_editorial_JIE
contexto: fintech_peruano
```

---

## 1. Propósito

Orquestar el intake y observación de fuentes externas (URLs, posts, contenido web)
y convertirlos en evidencia estructurada persistida en `lf_capture_records`
para revisión posterior por un operador humano o proceso autorizado.

No evalúa. No califica. No infiere. No homologa. No promueve conocimiento.
Captura y estructura — nada más.

---

## 2. Ownership del vertical slice

Este archivo es la raíz del vertical slice `jie_observation_intake_lf`.
Todo lo que vive bajo `skills/jie_observation_intake_lf/` pertenece a esta skill.

```
skills/jie_observation_intake_lf/
  domain/       ← definición del dominio (estás aquí)
  commands/     ← operaciones con posible escritura
  queries/      ← lectura, readback, verificación
  adapters/     ← conectores a fuentes externas (hijo funcional)
  cards/        ← reglas y aprendizajes específicos del dominio
```

El adapter hijo funcional de esta skill es:
- `adapters/web_article_capture/` → `ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2`

No existen adapters globales huérfanos para este dominio.

---

## 3. Límites explícitos

```
NO_VALIDATED:            true  — no validado, no usar en producción
NO_PRODUCCION:           true  — solo sandbox autorizado
NO_RUNTIME_REAL:         true  — no ejecución automática real
NO_HOMOLOGACION:         true  — FUTURE_BLOCKED_NO_HOMOLOGATION
NO_INSIGHT_AUTOMATICO:   true  — no genera insights por sí sola
NO_ALERT_AUTOMATICO:     true  — no dispara alertas por sí sola
NO_N8N_AUTOMATICO:       true  — no conectada a n8n en ningún modo
NO_KB_FINAL:             true  — no actualiza base de conocimiento
NO_PR:                   true  — no genera PR
NO_MERGE:                true  — no hace merge
NO_MAIN:                 true  — branch candidato únicamente
```

---

## 4. Arquitectura del dominio

```
Commands (escritura controlada):
  capture_web_article/
    → Recibe URL · ejecuta GATE_00–GATE_15 · persiste en lf_capture_records
    → Modo: FULL_EXTRACTION_REGISTER_SANDBOX_ONLY
    → Cualquier escritura real queda bloqueada salvo sandbox autorizado

Queries (solo lectura):
  get_web_capture_readback/
    → Lee lf_capture_records · verifica evidencia · retorna read_model
    → No escribe. No modifica. No infiere.

Adapters (conectores externos):
  web_article_capture/
    → Conecta URLs de fuentes fintech peruanas catalogadas en sbx_competitive_sources
    → Hijo funcional de esta skill · no adapter global · no adapter huérfano

Cards (reglas del dominio):
  evidence_layers_required.md
  no_homologation_no_insight_no_alert.md
```

---

## 5. Handoff permitido

Esta skill puede entregar evidencia estructurada a una capa de revisión posterior.

```yaml
handoff_permitido:
  destino: revisión_posterior_operador_humano
  condicion: extraction_successful=true AND db_write_confirmed=true
  entrega: record_id + run_id en lf_capture_records

handoff_bloqueado:
  - promoción automática de conocimiento → FUTURE_BLOCKED_NO_HOMOLOGATION
  - generación de insight → FUTURE_BLOCKED_NO_HOMOLOGATION
  - generación de alert → FUTURE_BLOCKED_NO_HOMOLOGATION
  - actualización de KB final → FUTURE_BLOCKED_NO_HOMOLOGATION
  - invocación de n8n → FUTURE_BLOCKED_NO_HOMOLOGATION
```

---

## 6. Tablas BD involucradas

| Tabla | Operación | Notas |
|---|---|---|
| `lf_capture_runs` | ESCRIBE (sandbox) | Una fila por corrida |
| `lf_capture_records` | ESCRIBE (sandbox) | Una fila por URL |
| `lf_log_operativo` | ESCRIBE (sandbox) | Trazabilidad |
| `lf_log_config` | LEE | Verifica log_keys |
| `lf_operation_registry` | LEE | Verifica operation_code en GATE_00 |
| `sbx_competitive_sources` | LEE | Catálogo de fuentes |
| `lf_capture_judge_results` | NO TOCA | Capa posterior fuera de alcance |

---

## 7. Restricciones de este paquete candidato

```
No crear PR.
No subir a main.
No declarar APROBADO.
No declarar VALIDATED.
No declarar READY_FOR_PRODUCTION.
No declarar KNOWLEDGE_VALIDATED.
No ejecutar runtime real.
No conectar n8n.
No generar insight ni alert automático.
```
