# LF — mantenimiento documental de reglas VIGENTE

**Estado:** generador de candidato, no operación de escritura ni permiso adicional.

Reutiliza la ruta existente ACTUALIZACION_DB_LF → LF Migration Merge Train. No toca el Router, el contrato candidate-only de ACTUALIZACION_REGLA_LF, los estados ni Input Governance. La unidad inicial solo permite actualizar lf_ops.reglas.pendiente_detalle, conservando todos los campos materiales y estado=VIGENTE.

## Entrada

Archivo JSON efímero, no persistir secretos en el repositorio:

    {
      "schema_version": "LF_VIGENTE_DOCUMENTARY_MAINTENANCE_REQUEST_V1",
      "operation_code": "ACTUALIZACION_DB_LF",
      "train": {
        "pr_number": 123,
        "migration_version": "20261109120000",
        "migration_name": "lf_example_documentary_reconcile_v1"
      },
      "target": {
        "rule_id": 435,
        "rule_code": "B2B-RULE-AUTH-016",
        "state": "VIGENTE",
        "column": "pendiente_detalle"
      },
      "before": {
        "row_md5": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "material_md5": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "field_text": "texto anterior exacto"
      },
      "after": {"field_text": "texto corregido aprobado"},
      "authority": {
        "decision_ref": "github://owner/repo/issues/123",
        "source_ref": "supabase://lf_ops.reglas/RULE-CODE"
      }
    }

row_md5 proviene de md5(to_jsonb(r)::text) y material_md5 de md5((to_jsonb(r)-'pendiente_detalle'-'updated_at')::text) en la base vigente. **Los hashes del ejemplo son ficticios y no sirven para aplicar una migración.** Referenciar una decisión no certifica por sí solo la autoridad del cambio.

## Secuencia

EKB → decisión vigente → lectura exacta de regla → readback MD5 → PR (obtener número) → SQL candidato → pruebas positivas/negativas → revisión → commit del archivo en PR → PASE y pruebas especializadas → etiqueta humana ready-to-merge → Train (preflight, escritura, ledger) → readback de regla y RUN.

    python3 sandbox/lf_contract_gate_test/db_write_transport/lf_vigente_documentary_migration.py \
      --packet /tmp/lf-approved-request.json \
      --output supabase/migrations/20261109120000_lf_example_documentary_reconcile_v1.sql

    python3 -m unittest discover \
      -s sandbox/lf_contract_gate_test/db_write_transport -p 'test_*.py' -v

## Protecciones

Un único DO atómico (el error aborta toda la actualización), identidad exacta, hash original de fila, hash material invariante, texto anterior exacto, VIGENTE, pendiente_decision=false, RUN Train ligado a PR/nombre/archivo y paso preflight PASS_CLEAN con trust_validation.valid=true, cardinalidad de una fila y readback.

**No permitido:** modificar valor_config, descripcion, razon, políticas, estado, promoción, QA, producción ni fuentes oficiales fuera del Train. Las mutaciones funcionales requieren proceso y autoridad separados. El generador no demuestra ejecución PostgreSQL ni rollback en staging: esas pruebas requieren evidencia propia antes de declarar la operación de negocio verificada. Una vez aplicada, una reversión requiere una nueva migración gobernada, no repetir el efecto.
