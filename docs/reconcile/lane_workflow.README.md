# Instalación del carril `RECONCILE_SOURCE_ONLY`

El carril ya está instalado. El YAML completo de esta actualización se entrega en el chat para que Paulo lo pegue por la web de GitHub en la rama autorizada; los agentes no editan `.github/workflows/**`. La actualización requiere OK de Cristhian antes de etiquetar y merge exclusivamente por el Train. Los prerequisitos siguientes documentan la instalación original.

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

## Instalación segura

- Antes de habilitar la cola, ejecutar un canario obligatorio con una PR real de renombre y confirmar el recibo, el status sobre el head exacto y el merge esperado.
- Si el canario falla, retirar el workflow instalado y no volver a etiquetar esa PR.
- Una PR que quede `BLOCKED` se reemplaza con una PR nueva; no se reetiqueta ni se reintenta la misma clave.

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

## Sincronización con main antes de verificar

La lane comparte `lf-migrations`, dispone de 40 minutos y sincroniza el head
exacto con el main resuelto en preflight. Si main ya es ancestro no crea commit;
en otro caso usa `merge-tree --write-tree` y `commit-tree` con padres (head, main).
El push automático usa `--force-with-lease` sobre el head esperado, autenticación
solo por entorno de Git y readback de rama y PR con reintentos. Un conflicto
termina con `FAIL_RECONCILE_SYNC_CONFLICT` (exit 2), comenta el PR y no mergea.

Tras re-fetch/checkout del head resultante, espera los checks requeridos usando
exclusivamente el guard y el JSON de `trusted/` (main), 90 intentos cada 5 s y
`--final` en el último; timeout: `FAIL_RECONCILE_REQUIRED_CHECK_TIMEOUT`.
El verificador y el merge consumen ese head. Se mantienen los rechazos de
etiquetas mezcladas, `BLOCKED_STALE_MAIN`/`BLOCKED_STALE_HEAD`, el recibo, los
comentarios y la prohibición de borrados o ejecución de SQL/código del PR.

`lane_workflow.patch.yml` conserva la fuente histórica de instalación y no se actualiza en esta PR.

`test_reconcile_workflow_sync.py` ejecuta los bloques Bash del workflow instalado
(o del YAML propuesto mediante `LF_RECONCILE_WORKFLOW_SOURCE`)
contra Git real y una API GitHub simulada: rama atrasada → sync → checkout →
verificador offline PASS; conflicto → exit 2, comentario, ningún push/merge.
Esto no prueba el runtime de GitHub Actions ni el ledger vivo. Después del merge
se requiere un canario real: PR RECONCILE de 1 rename exacto con base vieja.

Requiere OK de Cristhian. Probar con un PR RECONCILE de 1 rename exacto con base vieja después del merge.
