# SALY · V09 Native dispatch freshness fence (candidato)

**Alcance:** PR #4616, solo `sandbox`. Sin render, SQL DML/DDL, host receipt, QA, `DONE`, GRANT ni merge.

## Por qué existe
La admisión V04 comprueba el lease y la política **antes** del archivado V08. El archivado de archivos originales consume tiempo; un claim puede expirar o ser reemplazado después. V09 vuelve a comprobar la autoridad SQL **después de leer todo el archivo** y antes de cualquier futuro despacho Native.

## Secuencia
1. V08: archivo `HANDOFF_ARCHIVED_NOT_SENT`, lectura de fuentes reales y protección de componentes.
2. V09: relee `archive.json`, `payload.json`, `prompt.txt`, originales `references/`, `protected/` cuando exista; rechaza symlinks, archivos extra, cambios de bytes y recibos de entrega ficticios.
3. Solicita **hora de base** a un lector independiente del pedido, no al reloj del worker. Reinvoca `queue_v04.validate_render_ready` con lectores de política, binding RUN/claim y wire SQL de fuente confiable.
4. Compara RUN, claim, modo, SHA del wire y del prompt con lo archivado.
5. Devuelve `FRESHNESS_AND_ARCHIVE_VERIFIED_NOT_SENT`. Jamás inicia herramienta Native ni marca entrega.

**Límite importante:** V09 es una validación local, no un bloqueo SQL atómico. Entre su lectura final y el efecto Native puede haber una carrera. El futuro despachador debe cerrar esa brecha usando fencing atómico en la ruta gobernada, además de contar con host real y atestación verificable. Un puerto inyectado desde JSON del pedido no es confiable. Ni `READY` ni `HANDOFF_ARCHIVED_NOT_SENT` constituyen autorización productiva.

## Pruebas y evidencia
- `test_dispatch_fence_v1.py`: 18 casos sintéticos PASS, incluido activo protegido; la respuesta V04 del test V09 se simula con mock. Evidencia en `unit_results.txt`.
- **CI real** [#45073378089](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45073378089), SHA `55cff2deecaada87a1168dfd71b1a30ca94e94a1`: 43/43 V08+V09 PASS (25+18), 2/2 mutantes V08 muertos por aserción. El archivo temporal de workflow debe retirarse; PASE del HEAD final se comprueba por separado.
- Se contrastó el blob SHA de cada fuente creada con el `git hash-object` del archivo local antes de declarar paridad de persistencia.
- El nuevo control de privacidad de V08 (modo 0700 incluso con umask 022) tiene test agregado, pero requiere ejecutar esa regresión con el módulo V08 real.

## Bloqueos
- `CREATIVE_FACTORY` sigue 0/4 y `creative_runs` sigue en 0 por lectura RO de Supabase.
- `queue_v02/v05/v06` son candidatos sin despliegue, sin puerta de host autenticada ni recepción de mensaje real.
- No usar este módulo para invocar una imagen hasta resolver fuente de autoridad, lease atómico y entrega.

**Estado:** candidato, NO MERGE / NO DEPLOY / NO RENDER / NO FALSE DONE.
