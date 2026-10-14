# Instalación del carril `RECONCILE_SOURCE_ONLY`

Este directorio contiene el workflow como parche de texto. **No lo copies ni lo guardes en `.github/workflows/` hasta que Cristhian complete los prerequisitos y dé el OK.** La PR de implementación solo versiona código, pruebas y documentación; no consulta credenciales ni escribe en Supabase.

## Prerequisitos para Cristhian

1. Crear un rol PostgreSQL dedicado de solo lectura, con `SELECT` únicamente sobre `supabase_migrations.schema_migrations`; limitar la conexión al pooler.
2. Crear el secret `LF_SUPABASE_RO_DATABASE_URL` en el Environment `lf-merge-train`, restringido a `main`. No reutilizar ni añadir `LF_SUPABASE_DB_PASSWORD`.
3. Crear la etiqueta `ready-to-reconcile`.
4. Confirmar que la GitHub App del Train tiene permisos mínimos para leer contenidos, publicar statuses, comentar y fusionar PRs. El parche usa esa App para checkout y llamadas de GitHub; no depende de un token PAT adicional.
5. Definir la decisión pendiente de nombres del caso `lf_pilot_srcr_g12` que cruza el baseline. La lane exige identidad exacta contra el ledger y no inventa una equivalencia de nombre.

## Instalación para Paulo, después del OK

1. Copiar `lane_workflow.patch.yml` a `.github/workflows/lf-migration-reconcile-lane.yml` en una PR de instalación separada, tras comprobar el SHA del código del verificador en `main`.
2. Confirmar que el workflow comparte exactamente `concurrency.group: lf-migrations` con el Merge Train y que el Environment restringe el secret a `main`.
3. Verificar antes de habilitarlo que el route guard devuelve sin publicar `lf-merge-train/verified` para PRs con `ready-to-reconcile` y que la App sea el único emisor de ese status en esta lane.
4. Fusionar la PR de instalación por el procedimiento vigente. No pegar el YAML desde el head de una PR de reconciliación: el parche y el verificador deben venir de `main`.

## Límites operativos

- El workflow compara el head exacto con el ledger usando solo `SELECT`, produce un recibo artifact y no ejecuta archivos `.sql`.
- `PASS` publica `lf-merge-train/verified` sobre el SHA exacto y solicita el merge con `sha=<head>`; `FAIL`/`BLOCKED` quita la etiqueta y comenta la causa.
- `ready-to-merge` y `ready-to-reconcile` son mutuamente excluyentes. La route guard genérica no publica success para el segundo label.
- El paso mínimo que debe añadirse a la lógica de admisión del Train (en un helper de política, no editando el workflow existente) es clasificar el diff antes de la asignación de versión o de cualquier escritor: si solo contiene A/M/D/R bajo `supabase/migrations/` y el contenido destino ya coincide con una entrada exacta del ledger, detener con `RECONCILE_SOURCE_ONLY_REQUIRED` y remitir a `ready-to-reconcile`. Si contiene SQL nuevo, una identidad distinta o ambos labels, fallar cerrado. La lane reconciliadora es la única que puede publicar el status de esa PR después de verificarla.

## Formato de snapshot offline

El verificador acepta `--ledger-json` para pruebas aisladas con:

```json
{
  "schema_version": "lf-migration-reconcile-ledger-snapshot/v1",
  "rows": [
    {"version": "20261014110000", "name": "lf_probe_v1", "statements": ["select 1;"]}
  ]
}
```

Para la ejecución del workflow se usa `--database-url-env LF_SUPABASE_RO_DATABASE_URL`; el DSN nunca se incluye en recibos, comentarios ni logs del verificador.
