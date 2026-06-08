# READ MODEL — get_web_capture_readback

> Owner: SKILL_JIE_OBSERVATION_INTAKE_LF_CANDIDATO_V0_1
> Estado: CANDIDATO_READ_ONLY · Lote 20B
> Tipo: READ_ONLY — no escribe en ninguna tabla

---

## Estructura del resultado

```yaml
read_model:
  query_executed: true          # siempre true al finalizar
  writes_performed: false       # siempre false — es una query
  query_type: enum              # el tipo de query ejecutado

  resultados:
    tipo: array
    una_entrada_por_registro: true
    campos:
      record_id:            uuid
      run_id:               uuid
      url:                  string
      url_hash:             string
      url_solicitada:       string o null
      operation_code:       string
      record_status:        string
      extraction_successful: boolean
      db_write_confirmed:   boolean
      estado_extraccion_web: string
      final_state:          string
      title_or_hook:        string o null
      autor_declarado:      string o null   # NOT_FOUND si no visible
      fecha_publicacion_declarada: string o null
      created_by:           string
      captured_at:          timestamp
      fecha_proxima_revision: date o null
      redireccion_detectada: boolean
      prompt_injection_detectado: boolean
      truncado_en:          string o null
      campos_truncados_json: array
      actor_id:             string o null
      actor_role:           string o null
      modo_ejecucion:       string o null

  trazabilidad:
    lf_capture_run_id: uuid o null
    run_status: string
    log_event_ids: array[bigint]
```

---

## SQL de referencia

### Por record_id
```sql
SELECT
  record_id, run_id, url, url_hash, url_solicitada,
  operation_code, record_status,
  title_or_hook, autor_declarado, fecha_publicacion_declarada,
  estado_extraccion_web, redireccion_detectada,
  prompt_injection_detectado, truncado_en,
  fecha_proxima_revision, created_by, captured_at
FROM public.lf_capture_records
WHERE record_id = '<uuid>'
  AND created_by = 'ADAPTER_JIE_WEB_V0_2_CANDIDATO';
```

### Por run_id
```sql
SELECT r.run_id, r.status, r.records_inserted, r.created_at,
       c.record_id, c.url, c.estado_extraccion_web
FROM public.lf_capture_runs r
LEFT JOIN public.lf_capture_records c ON c.run_id = r.run_id
WHERE r.run_id = '<uuid>';
```

### Por url_hash (verificación de duplicado)
```sql
SELECT record_id, url, url_hash, content_hash,
       record_status, captured_at
FROM public.lf_capture_records
WHERE url_hash = '<hash>';
```

---

## Qué NO retorna esta query

```
❌ No retorna claims_json evaluados o puntuados
❌ No retorna insights derivados
❌ No retorna alertas
❌ No retorna estado de homologación
❌ No invoca el command capture_web_article
```
