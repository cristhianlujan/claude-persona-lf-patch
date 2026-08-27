# Context Resolver Protocol — PROFILE_RUNTIME_CONTEXT_V1

## Propósito

Permitir que el runtime obtenga contexto canónico sin incorporar credenciales,
SDKs ni lógica específica de un backend dentro del perfil.

Para LF, el resolver debe consultar Supabase como fuente canónica. Drive no puede
reemplazar esa autoridad.

## Entrada

stdin recibe:

```json
{
  "runtime_contract": "PROFILE_RUNTIME_CONTEXT_V1",
  "request": {}
}
```

El request debe contener identidad suficiente para resolver el objetivo, por
ejemplo `screen_code`, operación o activo.

## Salida

stdout debe emitir exactamente:

```json
{
  "canonical_context": {},
  "source_refs": [
    "supabase:<schema.table>:<identity>"
  ]
}
```

`source_refs` debe apuntar a fuentes efectivamente consultadas. Un nombre de tabla
inventado o una referencia que no fue leída invalida el resultado.

## LF screen resolution

Cuando el request afecta una pantalla LF, la resolución mínima es:

```text
lf_ops.pantallas
→ lf_ops.modulos
→ lf_ops.app_shells
→ lf_ops.pantalla_variantes / lf_ops.pantalla_elementos cuando existan
→ lf_design.* tokens aplicables
```

El resolver no decide UI ni producto. Solo entrega contexto y procedencia.

## Fail closed

Debe retornar exit distinto de cero cuando:

- la pantalla/activo no puede resolverse;
- hay conflicto canónico sin precedencia;
- faltan referencias de fuente;
- el resultado dependería de una fuente no autorizada;
- se requeriría inventar una versión/estado/token.

El harness persiste stdout/stderr RAW del resolver antes de usar el contexto.
