# SUNAT: integración ZIP y lector de registros v0.7

Estado: CANDIDATO TÉCNICO / READ_ONLY / SIN RUNTIME. El formato ZIP es transporte, no fuente. El recurso sigue siendo SUNAT. No se crea un perfil, RUN, conector nativo ni permiso de escritura.

## Flujo local
1. Validar el esquema y política (variante/versión coincidentes) antes de abrir el archivo temporal controlado.
2. Reutilizar el inspector ZIP, su directorio central y el mismo descriptor abierto. Seleccionar por nombre exacto de entrada; toda entrada queda sujeta a las cuotas y CRC.
3. Pasar por stream STORE/DEFLATE los bytes acotados al lector de registros existente. El consumidor interno es puro; debe agotar el stream, sin efectos externos.
4. Retener privadamente el resultado del lector. Si otra entrada falla, el resultado entero se rechaza. Verificar CRC/tamaños de TODAS las entradas, SHA-256 del ZIP y estabilidad de archivo; comparar bytes leídos por el parser con bytes descomprimidos de la entrada seleccionada.
5. Devolver un único candidato de lectura con digest SHA-256 de filas, procedencia de esquema/política y recibo de archivo. Las filas son candidatos, no identidad verificada ni leads contactables.

API interna: `inspectSunatZipCandidate({filePath,entryName,archiveLimits,schema,policy})`.
API reutilizable: `readZipEntryCandidate(filePath,limits,entryName,consume)`. El consumidor debe ser confiable, puro y no publicar resultados provisionales; no exponerlo como RPC ni aceptar callbacks externos arbitrarios.
Timeout explícito en `archiveLimits.timeout_ms` para inspección/stream con AbortController + deadline monotónico y limpieza finally. No es una garantía de cancelación de I/O de un filesystem remoto o callback arbitrario; solo archivos temporales locales controlados y consumidor interno.
Los límites del fixture no son configuración productiva. ZIP64, descriptor de datos y formatos fuera del subconjunto v0.5 permanecen bloqueados. Las APIs anteriores de metadatos/verificación se conservan.

## Evidencia local previa al PR
Node v22.16.0:
- PASS_AI_SALES_SUNAT_ZIP_INTEGRATION 16 cases; CRC barrier, bounded streaming, no writes.
- PASS_AI_SALES_SUNAT_ZIP_MUTATION 1 CRC barrier mutation killed by intended assertion.
- Prueba de CRC inválido en entrada posterior: el original rechaza todo; al anular exactamente el control CRC, el mutante entrega un candidato incorrecto.
- 4000 registros sintéticos cruzando múltiples bloques descomprimidos, sin pérdida. Casos de timeout, esquema incorrecto, cuota de candidatos, entrada ausente/insegura, consumidor que termina antes de agotar el stream, modo STORE y modo DEFLATE.
Blobs Git cotejados contra el código ejecutado:
`zip_content_verify.mjs`: 52a6ad08d31bcb0c90aa954e420189648512ae52
`zip_archive_preflight.mjs`: 349fb65c4310b36955097545c9e4cab9923cdbe9
`sunat_records_candidate.mjs`: 4627de8ec7c423c546302337f10820e71217ef38
`sunat_zip_candidate.mjs`: 476f88b7e5d48750e83bde95087041a74449aaac
`sunat_zip_candidate.test.mjs`: 11562aeab82b155b8e698c38b2a035427a5deb14
Comando: node skills/ai_sales_discovery/tests/sunat_zip_candidate.test.mjs. Regresión en CI existente.

## Fuente real: NO_VERIFICADO
El padrón reducido documenta RUC, nombre o razón social, estado, condición de domicilio, UBIGEO y domicilio fiscal (https://orientacion.sunat.gob.pe/padron-reducido-del-ruc-para-descarga). No trasladar sus columnas al mensual. El catálogo mensual publica PadronRUC_202610.zip, pero no se obtuvo su cabecera interna exacta ni una muestra reproducible autorizada. No se descargó el archivo completo. No activar SUNAT en adapters/registry.mjs. Faltan transporte acotado autorizado, contrato de esquema real, compatibilidad ZIP real, revisión de finalidad/privacidad y reconciliación real.
