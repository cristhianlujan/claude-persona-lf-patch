# ZIP preflight v0.4 — contrato de archivo SUNAT, no extractor productivo

**Propósito:** proteger el siguiente adaptador de datos SUNAT-RUC antes de tratar un ZIP grande como si fuera CSV directo. No descarga ni descomprime el archivo real, no ejecuta llamadas a SUNAT, no guarda contribuyentes.

## Entrada
- Ruta a un archivo **local temporal** ya descargado por un transporte gobernado; la skill no descarga archivos.
- Límites positivos entregados por una política externa autenticada: `max_download_bytes`, `max_central_directory_bytes`, `max_entries`, `max_unpacked_bytes`, `max_entry_bytes`, `max_ratio`.
- Sin política, bloquear. **Los límites usados en tests son exclusivamente fixtures y no son umbrales de producción.**

## Qué verifica
1. Archivo regular y tamaño físico dentro de la cuota.
2. EOCD ZIP y directorio central acotado; no soporta ZIP64 ni multidisco (bloqueo explícito).
3. Nombres legibles UTF-8; bloquear rutas absolutas, componentes punto/punto-punto, separadores Windows, duplicados sin distinguir mayúsculas, nombres nulos, ZIP anidados y enlaces simbólicos.
4. Entradas cifradas o métodos de compresión desconocidos se bloquean.
5. Tamaño por entrada, total declarado, ratio de compresión y número de entradas dentro de la política.
6. SHA-256 del ZIP completo calculado en stream de archivo; el resultado es **solo un manifiesto candidato**, sin archivos extraídos.

## Lo que NO demuestra
- La integridad CRC, correspondencia binaria de cabecera local/central, bomb por contenido falsificado, ni la lectura segura del CSV interior.
- Que el recurso descargado coincide con la ficha SUNAT firmada, que está permitida su ingesta comercial o que los datos de personas naturales pueden almacenarse.
- Que el algoritmo admita un recurso mayor de 4 GB o ZIP64. Estos casos son explícitamente bloqueados.
- No establece `zip_streaming_verified=true` o `zip_entry_safety_verified=true` para la admisión final: hace falta ejecutar el pipeline de descarga con cuotas, descompresión controlada y validación de contenido.

## Estado
`CANDIDATO_READ_ONLY_NO_RUNTIME`. Este módulo no se añade a `adapters/registry.mjs`; PE-PTE sigue único adaptador admitido. Su valor es QA de metadatos y resguardos para diseñar el adaptador SUNAT. Comando:

`node skills/ai_sales_discovery/tests/zip_archive_preflight.test.mjs`

Referencia oficial del tipo ZIP: https://www.datosabiertos.gob.pe/dataset/padr%C3%B3n-ruc-superintendencia-nacional-de-aduanas-y-de-administraci%C3%B3n-tributaria-sunat-58 (PadronRUC_202610.zip).
