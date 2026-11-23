# SALY Ventas — OECE Socios.csv v1 | recuperación reproducida 2026-11-23

Estado del lote: **CANDIDATO de vínculos históricos; no significa control societario actual**.

## Fuente
- Portal oficial OECE/Confluence: https://osce-gob-pe.atlassian.net/wiki/api/v2/pages/106889267/attachments?limit=100
- Archivo `Socios.csv`, adjunto `att106893232`, versión **1**, fecha de creación del adjunto **2021-11-11**, tamaño **32,017,514 bytes**.
- Enlace: https://osce-gob-pe.atlassian.net/wiki/rest/api/content/106889267/child/attachment/att106893232/download
- Esquema leído: `Tipo_Documento|Nro_Documento|Nombre_o_RazonSocial|Ruc_Proveedor`; separador `|`.
- La fecha `fuente_corte=2021-11-11` en las nuevas filas denota **fecha documental del adjunto**, no fecha de actualización societaria ni vigencia jurídica. La fecha de extracción fue 2026-11-23.
- El consolidado `conformacion_juridica.csv`, actualizado 2026-11-02, pesa 227,314,041 bytes; no se procesó: la herramienta devolvió `content_too_large`. Por tanto esta carga es histórica y explícitamente separada del consolidado vigente.

## Ejecución reproducida
- 7,514 RUC jurídicos del snapshot real `saly.ventas_hallazgos` / `PE-SUNAT-RUC`.
- 413,016 filas OECE; 16 filas irregulares. 2,810 empresas SALY reconocidas.
- 519 propietarios RUC jurídicos encontrados en al menos una empresa SALY.
- 75 propietarios distintos vinculados a ≥2 empresas SALY; 161 empresas SALY distintas; **195 pares propietario/empresa únicos**.
- 1 par duplicado en la fuente; se conserva la primera fila. No se agregan nombres, DNI ni datos naturales en SALY.
- Clave por par `(ruc_empresa_saly,ruc_propietario_juridico)`; no se aplica transitividad ni se atribuye control.

## Persistencia propuesta y controles
- Migración única: `supabase/migrations/*_lf_saly_oece_socios_candidates_v1.sql`.
- Solo inserta 195 filas en `saly.ventas_vinculos_empresariales_v1` con `SOCIO_DECLARADO` / `CANDIDATO`; 195 evidencias en `saly.ventas_vinculos_evidencias_v1`, una por vínculo, con línea fuente y URL oficial.
- Campos de participación y control quedan `NULL`; no se activan escrituras desde cliente ni contacto comercial.
- Sin evaluación de permisos de reutilización ni nuevas condiciones de licencia: se ejecuta el lote de datos públicos indicado por el propietario.
- RLS de ambas tablas permanece activado y forzado. Ningún GRANT.
- Prueba PostgreSQL 17 desechable: aplicación de esquema y lote, readback 195/161/75, evidencia 1:1, controles negativos (duplicados, RUC inválido, control no probado), transacción de prueba con ROLLBACK y verificación posterior.
- Aplicar solo por PR + Merge Train; no por SQL manual. Después del merge, **leer** tablas de SALY y comprobar cantidad y evidencia real.

## Alcance pendiente
- Este lote no importa las 413,016 filas completas: persiste únicamente 195 aristas correspondientes a los 75 propietarios candidatos de agrupación.
- Recuperación y cruce del consolidado OECE 2026 de 227 MB, seguido de reconciliación histórica y vigencia.
