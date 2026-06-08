# CARD: EVIDENCE_LAYERS_REQUIRED

> Owner: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Tipo: Card específica del dominio · No card genérica
> Estado: CANDIDATO_READ_ONLY · Lote 20B

---

## Propósito

Define las capas mínimas de evidencia que deben existir antes de que
cualquier registro de captura pueda ser entregado a revisión posterior.

---

## Capas obligatorias

### Capa 1 — Evidencia de ejecución
```
✅ lf_capture_runs: run_id con status=COMPLETED
✅ lf_capture_records: record_id con created_by=ADAPTER_JIE_WEB_V0_2_CANDIDATO
✅ extraction_successful = true
✅ db_write_confirmed = true (readback de GATE_13 confirmado)
```

### Capa 2 — Evidencia de contenido
```
✅ title_or_hook: valor literal (no NOT_FOUND)
✅ raw_text: ≥ 100 caracteres
✅ url_hash: calculado y único en BD
✅ estado_extraccion_web: COMPLETA o EXTRACCION_PARCIAL (no BLOCKED_*)
```

### Capa 3 — Evidencia de trazabilidad
```
✅ lf_log_operativo: al menos 1 evento con log_key WEB_EXTRACTION_COMPLETE
✅ lf_eventos: evento de creación registrado (id=242, 243 o posterior)
✅ operation_code: existe en lf_operation_registry
```

### Capa 4 — Evidencia de seguridad
```
✅ prompt_injection_detectado declarado (true o false)
✅ url_solicitada declarado (aunque sea igual a url_final)
✅ redireccion_detectada declarado
```

---

## Lo que NO es evidencia suficiente

```
❌ DRY_RUN_PREVIEW_READY solo (no hay escritura real)
❌ extraction_successful=true sin db_write_confirmed=true
❌ run en lf_capture_runs sin record en lf_capture_records
❌ campos con valores inferidos (no NOT_FOUND explícito)
❌ claims_json con verificado_fuente_primaria=true
```

---

## Cuándo un registro está listo para revisión posterior

Cuando las 4 capas están completas.
No antes.
Revisión posterior ≠ homologación.
Revisión posterior la ejecuta un operador humano.
