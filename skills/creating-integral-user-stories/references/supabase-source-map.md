# Mapa de fuente operativa Supabase

Juez asociado: `J01_SOURCE_INTEGRITY`.

Proyecto: `mhwmirqcgxxukpctffuv`. Vista rectora: `public.v_lf_fuente_operativa`.

## Lectura obligatoria antes de disenar

```text
public.lf_operation_contracts
public.lf_operation_steps
public.lf_operation_step_contracts
public.lf_operation_step_judge_bindings
public.lf_operation_judges
public.lf_operation_execution_steps
public.lf_operation_execution
public.v_lf_operation_contract
public.v_lf_operation_steps_with_contracts
public.v_lf_operation_step_contract_judge_coverage
public.v_lf_profile_runtime_protocol
```

## Regla de verificacion

Verificar nombres y columnas reales contra `information_schema.columns` y
`pg_constraint` antes de usarlos. Prohibido inventar tablas o columnas. Si una
tabla listada no existe, registrar hallazgo y continuar con las disponibles.

## Destino de artefactos

```text
public.v_lf_artifact_destination_registry
```

Resuelve `repo`, `branch`, `base_folder`, `naming_rule` y `filename_suffix`
por `operation_code` y `artifact_type`. Las rutas declaradas en un handoff no
prevalecen sobre el registro vigente; la diferencia se registra.

## Almacen canonico de artefactos

```text
private.lf_skill_artifacts
```

Fuente canonica del contenido de la skill. GitHub es transporte y espejo, no
fuente. La igualdad se verifica por `content_sha256` sobre contenido UTF-8,
sin BOM, saltos LF y newline final.

## Evidencia

Toda ejecucion registra evidencia en `public.lf_eventos` con
`entidad_codigo = EXEC-BISC-001`.
