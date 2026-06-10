# ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2

> Estado: CANDIDATO_READ_ONLY · Versión: v0.2 · Lote 20B
> asset_code: ACT-0052
> canonical_name: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
> legacy_skill_id: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Owner (Supabase): SKILL_EXTRACCION_FUENTES_DIGITALES_LF
> Owner (GitHub interno): SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Path: skills/jie_observation_intake_lf/adapters/web_article_capture/
> operation_code: CAPTURE_INTAKE_MULTI_SOURCE_FIXTURE_V0_1
> created_by (BD): ADAPTER_JIE_WEB_V0_2_CANDIDATO
> Evidencia Supabase: lf_eventos id=242, 243, 244, 247

⚠️ CANDIDATO. Solo sandbox. No producción. No VALIDATED. No main.

---

## Identidad y relación

```yaml
owner_skill:   SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
child_adapter: ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2
rol:           adapter_hijo_funcional
```

Este adapter NO es global ni huérfano.
Vive bajo el vertical slice de su skill madre.
Su command es: `commands/capture_web_article/`

---

## Qué hace

Extrae contenido literal de artículos web de fuentes fintech peruanas
catalogadas en `sbx_competitive_sources` y persiste en `lf_capture_records`.

No evalúa. No infiere. No homologa.
No genera insight. No genera alert. No conecta n8n.

---

## Estructura de este adapter

```
adapters/web_article_capture/
├── ADAPTER.md         ← estás aquí
├── README.md          ← navegación por perfil
├── RUNBOOK.md         ← protocolo paso a paso
├── permissions/
│   └── roles_matrix.md
├── schemas/
│   ├── extraction_fields.schema.yaml
│   └── db_field_mapping.yaml
├── db/
│   ├── ddl_extension.sql   ← ya aplicado en Supabase
│   └── log_config.sql      ← ya aplicado en Supabase
├── examples/
│   ├── good_reevalua.yaml
│   └── bad_kambista.yaml
└── fixtures/
    └── antiduplicate_hashes.yaml
```

La lógica de gates, judge y evals vive en el command:
```
commands/capture_web_article/
├── command_contract.yaml
├── input_contract.yaml
├── output_contract.yaml
├── gates.md
├── judge.yaml
└── evals.yaml
```

---

## Modos disponibles

| Modo | Escritura | Sandbox only |
|---|:---:|:---:|
| `FULL_EXTRACTION_REGISTER_SANDBOX_ONLY` | ✅ | ✅ |
| `DRY_RUN` | ❌ | ✅ |
| `READ_ONLY_RESULT` | ❌ | — |
| `ADDENDUM_ONLY` | ✅ | ✅ |
| `ADMIN_OVERRIDE` | FUTURE_BLOCKED | FUTURE_BLOCKED |

---

## Tablas BD

| Tabla | Tipo |
|---|---|
| `lf_capture_runs` | ESCRIBE |
| `lf_capture_records` | ESCRIBE |
| `lf_log_operativo` | ESCRIBE |
| `lf_log_config` | LEE |
| `lf_operation_registry` | LEE |
| `sbx_competitive_sources` | LEE |

---

## Hashes anti-duplicado reales (Lote 20B)

| url_hash | Label | Estado en BD |
|---|---|---|
| `e5ef8029e79db297c9660fa9e44a6e1a` | Reevalúa infocorp | TEST |
| `84a5bc12d53b9f0dee9d156fa0d8e958` | RTC consolidación | TEST |

Ver `fixtures/antiduplicate_hashes.yaml` para detalles completos.
