# SALY Ventas · Antigüedad observada del RUC v1

## Uso
El resultado es un límite inferior de presencia en el padrón. La fecha de inscripción en el RUC y la fecha declarada de inicio de actividades son atributos distintos. Para un requisito que exija alguna de esas fechas, obtener evidencia oficial que identifique el RUC y la fecha exacta; conservar fuente, fecha de consulta y referencia. No inferir continuidad, fecha de constitución ni años sin interrupciones.

## Ejecución
1. Definir cohorte de RUC y fecha de corte. Para SALY la cohorte puede salir del cruce actual de Lima e Ica. Buscar cada RUC en todo el archivo histórico: la empresa pudo cambiar de departamento.
2. Resolver cada mensual en el catálogo oficial. Acreditar período, URL, SHA-256 del ZIP y cabecera en un manifiesto revisado antes de ejecutar. Usar el descargador acotado existente. Esta versión admite el patrón PadronRUC_AAAAMM.zip y CSV UTF-8; otras variantes requieren validar su contrato. Incluir archivos ya revisados aunque tengan brechas. Guardar qué períodos se revisaron y cuáles faltan respecto del calendario deseado.
3. Ejecutar con Python 3.11+ desde la raíz: `python3 skills/ai_sales_discovery/adapters/sunat_history_v1.py MANIFEST.json`. La salida es JSON de trabajo para consumo autorizado; evitar publicarla en logs con RUC reales. El evaluador no escribe en Supabase.
4. El lector fija el límite de bytes, filas y tamaño de cohorte; verifica ZIP y cabecera y lee hasta EOF para CRC. Rechaza el lote ante errores de integridad o formato. Una coincidencia en dos filas del mismo mes produce una sola observación por RUC. El ordinal empieza en 1 después de la cabecera.
5. Para cada RUC, guardar en el resultado el primer período observado, archivo referenciado en sources, ordinal y meses completos mínimos al corte. Para evitar sobreestimar cuando solo se conoce el mes, contar desde su último día. Un período faltante deja la estimación como límite inferior. Sin coincidencia se devuelve null. Si luego se incorpora un archivo anterior, recalcular con un manifiesto versionado.
6. La política comercial posterior elegirá indicador y umbral. Si el mínimo observado supera o iguala el umbral, hay evidencia de esa antigüedad registral mínima. Si queda por debajo, la edad real sigue abierta. Para años de actividad declarada, usar la fecha de inicio verificada. Documentación oficial: https://orientacion.sunat.gob.pe/sites/default/files/inline-files/Ficha%20RUC.pdf

## Contrato del manifiesto
`as_of` fecha ISO, `rucs` lista de cadenas de 11 dígitos, `snapshots` lista de objetos con `period` (AAAA-MM), `path`, `url`, `sha256` y `header_sha256` (hex minúscula, cabecera sin CR/LF). `limits` lleva enteros positivos para `zip_bytes`, `unpacked_bytes`, `line_bytes`, `rows_per_archive`, `cohort_size` y `snapshots`. Las cuotas pertenecen al ejecutor. La primera versión procesa una cohorte acotada por pasada.

Prueba reproducible: `python3 skills/ai_sales_discovery/tests/test_sunat_history_v1.py`. Casos sintéticos de cambio territorial, brechas, duplicados, RUC ausente, corte antes del aniversario, ZIP alterado, período abierto y archivo repetido.
