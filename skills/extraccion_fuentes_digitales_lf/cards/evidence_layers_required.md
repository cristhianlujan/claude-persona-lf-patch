# CARD: EVIDENCE_LAYERS_REQUIRED

> Owner: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
> Estado: CANDIDATO_READ_ONLY · Lote 20B

## Propósito

Define las capas mínimas de evidencia antes de entregar una captura a revisión posterior.

## Capas obligatorias

```text
1. Evidencia de ejecución:
   - lf_capture_runs con status=COMPLETED
   - lf_capture_records creado por ADAPTER_WEB_ARTICLE_CAPTURE_LF
   - extraction_successful=true
   - db_write_confirmed=true

2. Evidencia de contenido:
   - title_or_hook no vacío
   - raw_text >= 100 caracteres
   - url_hash calculado
   - estado_extraccion_web válido

3. Evidencia de trazabilidad:
   - lf_log_operativo con WEB_EXTRACTION_COMPLETE
   - operation_code existe en lf_operation_registry

4. Evidencia de seguridad:
   - prompt_injection_detectado declarado
   - url_solicitada declarada
   - redireccion_detectada declarada
```

## No suficiente

```text
DRY_RUN_PREVIEW_READY solo
extraction_successful=true sin readback
campos inferidos
claims_json con verificado_fuente_primaria=true
```
