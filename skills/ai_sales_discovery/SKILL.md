# SKILL_AI_SALES_DISCOVERY — candidato técnico aislado v0.1

Estado: CANDIDATO / READ_ONLY / NO_HABILITADO. Dominio de descubrimiento comercial (U07), independiente de perfiles y Router. No crea un RUN comercial. No registra ni activa esta skill en runtime. No duplica ni modifica ACT-0052, la skill canónica de captura de artículos web LF.

## Propósito
Descubrir y capturar instituciones desde una fuente autorizada sin calificar leads, identificar contactos, puntuar, contactar ni escribir en CRM. La fuente del piloto es PTE PCM. Se reutiliza el parser ya implementado en docs/saly/ventas/candidate/pte/normalize_pte_csv.mjs.

## Arquitectura del piloto
Petición y fuente -> política por negocio -> evidencia de derechos -> fetch acotado -> parser PTE -> digest exacto -> readback independiente -> recibo terminal.

## Inventario de módulos y estado (no confundir implemented con producción)
| Módulo | Función | Estado |
|---|---|---|
| D00 | Contrato, scope y admisión READ_ONLY | Implementado |
| D01 | Resolver política por negocio y límites de transporte | Implementado por inyección; integración Supabase pendiente |
| D02 | Validar catálogo, licencia, evidencia y URI de fuente | Implementado; integración Supabase pendiente |
| D03 | HTTP: respuesta, content-type, bytes, intentos y timeout | Implementado por transporte inyectado; runtime externo pendiente |
| D04 | Parsear CSV; conservar nombre, RUC literal, UBIGEO, ordinal | Reutiliza normalizador PTE ya probado |
| D05 | SHA-256 exacto de JSON de captura y control de versión | Implementado |
| D06 | Readback y reconciliación de hash, conteos, fila a fila | Contrato de callback implementado; readback SQL de caller pendiente |
| D07 | Recibo auditable, estados y cierre garantizado | Implementado |
| D08 | Persistencia gobernada de nuevas versiones | Fuera de alcance actual; NO habilitado |
| D09 | Registro de adaptadores por fuente; PTE separado del núcleo | Registro implementado; SUNAT/SUNARP/Google Places pendientes |
| D10 | Telemetría productiva, lease y cierre de RUN | Pendiente; no forzar desde esta skill |
| D11 | Pruebas E2E, negativas, timeout y retry | Archivo de tests; PASS solo tras ejecución |

## Contratos y fronteras
- Política por negocio, nunca codificada en el núcleo. Ver public.lf_global_config y public.lf_saly_discovery_pte_policy_v1(). Esos registros **solo cubren el territorio PTE**, no tienen límites productivos de max_attempts, max_bytes, max_rows y timeout_ms. El runner los exige; sin fuente gobernada debe bloquear y no inventarlos.
- El objeto de autoridad de fuente se obtiene de readback externo confiable, no del CSV ni del prompt. Derechos y licencia de lectura **no** habilitan publicidad ni contacto.
- El adaptador es por proveedor/fuente. No crear variantes SALY/LF del mismo parser.
- RUC repetidos se mantienen como hallazgos distintos; nunca homologa automáticamente. RUC ausente es null. El ordinal de origen es identificador de fila, no ID jurídico.
- Una misma version con digest distinto produce bloqueo, no un overwrite. Una nueva versión produce CANDIDATO sin escritura.
- La respuesta contiene estado, hash, conteos, origen y errores. No incluye RAW CSV ni filas del prospecto. Nunca declara db_write_confirmed=true.
- Si un provider es inestable, la skill termina con un estado explícito. El temporizador corta la espera; no se deja indefinido.
- Todas las operaciones de escritura continúan fuera de esta skill y, cuando sean autorizadas, deben usar la única puerta governada existente, nunca un INSERT directo ni una migración recurrente.
- El caller que integre una ruta nativa futura debe autenticar el recibo Router/negocio y la autoridad del readback; el runner aislado **no** verifica identidad criptográfica.

## Pruebas
Comando: node skills/ai_sales_discovery/tests/pte_readonly_pipeline.test.mjs.
Ejecución de CI: workflow existente saly-pte-resguardos-pg17.yml, no workflow nuevo.
La base SALY mantiene la extracción inicial de 519 registros; el runner actual solo inspecciona snapshots y verifica por callback. La evidencia histórica L48 de PG17 prueba al escritor, NO es un RUN de esta skill.

## Lote v0.2 — separación de adaptadores
La función genérica inspectDiscoveryReadOnly delega al registro explícito en adapters/registry.mjs; únicamente PE-PTE está admitido mediante adapters/pte_csv_adapter.mjs. La función inspectPteReadOnly queda como alias de compatibilidad con el piloto. Validación de URL/licencia, política territorial y parseo viven en el adaptador PTE. No activar conectores ausentes ni cambiar Router o perfiles.

## Lote v0.3 — preflight de nuevas fuentes sin activarlas
`adapters/source_admission_v1.mjs` comprueba coincidencia de catálogo, política del negocio, licencia, privacidad, límites de tamaño, seguridad ZIP, esquema y autorización de API. La salida **siempre** es candidata/no autorizada para runtime; no introduce SUNAT, SUNARP, OECE ni Google Places en el registro operativo. Ver `contracts/SOURCE_REVIEW_20261121.md`. Comando de regresión: `node skills/ai_sales_discovery/tests/source_admission_v1.test.mjs`.

## Lote v0.4 — ZIP del padrón SUNAT (preflight técnico)
`adapters/zip_archive_preflight.mjs` inspecciona localmente metadatos ZIP con cuotas de bytes/entradas, rutas, symlinks, cifrado, ZIP64 y ratio. Lee un archivo temporal ya descargado; **no extrae, no descarga, no registra SUNAT como adaptador ni declara seguridad de descompresión**. Ver `contracts/ZIP_PREFLIGHT_V04.md` y tests con ZIP sintéticos. El siguiente lote deberá validar cabecera local, CRC y descompresión segura bajo política efectiva antes de admitir un conector real.
