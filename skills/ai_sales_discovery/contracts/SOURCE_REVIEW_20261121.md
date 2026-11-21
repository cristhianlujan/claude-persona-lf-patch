# AI Sales U07 — revisión de fuentes para adaptadores (21/11/2026)

Alcance: SKILL únicamente. Las páginas oficiales se inspeccionaron como evidencia de **existencia, tipo de recurso y restricciones**, NO como permiso de extracción masiva, almacenamiento CRM, contacto o publicidad. No se descargó el padrón RUC completo. Un dato público no equivale a finalidad comercial autorizada.

| Código candidato | Evidencia oficial | Formato comprobado en metadatos | Riesgo/gate | Estado |
|---|---|---|---|---|
| SUNAT-RUC | https://www.datosabiertos.gob.pe/dataset/padr%C3%B3n-ruc-superintendencia-nacional-de-aduanas-y-de-administraci%C3%B3n-tributaria-sunat-58 y catálogo general https://www.datosabiertos.gob.pe/dataset/padr%C3%B3n-ruc-superintendencia-nacional-de-aduanas-y-de-administraci%C3%B3n-tributaria-sunat | Archivo de octubre 2026 **PadronRUC_202610.zip**, no CSV directo. El catálogo presenta etiquetas CSV; la ficha de recurso indica formato ZIP | Requiere procesamiento streaming, tamaño máximo gobernado, protección zip bomb/zip slip, esquema del CSV interior y evaluación de datos personales (RUC también de personas naturales). No se puede heredar el normalizador PTE. | BLOQUEADO_PENDIENTE_ADAPTADOR_ARCHIVO |
| SUNARP-PJ | https://www.datosabiertos.gob.pe/dataset/personas-jur%C3%ADdicas-inscritas-en-el-registro-de-personas-jur%C3%ADdicas-%E2%80%93-sunarp | Recurso publicado como **HTML** (“Relación de personas jurídicas inscritas”), licencia del catálogo ODC-BY | Falta identificar respuesta exportable y columnas reales. No interpretar HTML como CSV ni crear personas jurídicas desde resumen estadístico. | BLOQUEADO_SCHEMA_Y_RECURSO |
| OECE-PROVEEDORES | https://www.datosabiertos.gob.pe/dataset/proveedores-y-consorcios-organismo-especializado-para-las-contrataciones-p%C3%BAblicas-eficientes | Recurso **HTML** hacia portal CONOSCE; página del catálogo indica **License Not Specified** | Derechos de reutilización, esquema y mecanismo oficial deben confirmarse independientemente. OECE es la denominación actual del organismo anteriormente llamado OSCE; no homogeneizar datos por nombre de organismo. | BLOQUEADO_LICENCIA |
| GOOGLE_PLACES_API_NEW | https://developers.google.com/maps/documentation/places/web-service/policies y https://developers.google.com/maps/documentation/places/web-service/place-id | API JSON autenticada, no CSV abierto | Revisión de términos, retención, finalidad, atribución y facturación. Place ID no es identidad jurídica; prohibido scraping; no usar credenciales sin autorización. | BLOQUEADO_TERMINOS_Y_COSTO |

## Módulo de admisión v0.3
- Archivo: `adapters/source_admission_v1.mjs`, prueba independiente `tests/source_admission_v1.test.mjs`.
- Evalúa cuatro elementos **separados**: descriptor de recurso, recibo del catálogo, política de negocio y capacidad técnica. Si alguno no corresponde, devuelve un código de bloqueo.
- La propia salida marca `runtime_authorized=false`, `write_authorized=false`, `contact_authorized=false` y `evidence_verified_by_runtime=false` incluso en un fixture totalmente favorable.
- Para ZIP exige streaming y resguardos anti zip bomb/zip slip comprobados; para API exige autorización de facturación y términos. No presume licencias ni aprueba uso de datos personales con un consentimiento ficticio.
- Las pruebas de casos positivos usan *fixtures declarados*, no evidencia legal efectiva. Un resultado `ADAPTER_DESIGN_CANDIDATE` permite **evaluar un adaptador**, nunca invocarlo.
- PTE sigue siendo el único adaptador de ejecución de lectura admitido en `adapters/registry.mjs`. No ampliar el registry con SUNAT/SUNARP/OECE/Places hasta disponer de pruebas y política verificadas.

## Evidencia pendiente y próximo lote
1. SUNAT-RUC: descargar solo metadatos/diccionario cuando estén disponibles; inspeccionar ZIP con cuotas de bytes/unpacked, entradas permitidas y CSV interior; prueba negativa de ZIP malicioso y privacidad.
2. SUNARP-PJ: resolver URL exacta de recurso, diccionario y formato transportable, sin automatizar scraping HTML.
3. OECE: conseguir condiciones/licencia de recurso y export oficial, o detener el conector.
4. Google Places: revisar finalidad de almacenamiento y presupuesto antes de cualquier llamada.
5. Cuando exista un descriptor verificado, definir un adaptador por fuente y prueba de captura/normalización/QA; conservar sin cambios la capa de perfiles y Router.
