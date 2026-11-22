# SKILL_AI_SALES_DISCOVERY — candidato técnico aislado v1.3

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

## Lote v0.5 — procesador ZIP transversal
`verifyZipContentCandidate` reutiliza el preflight y valida CRC y bytes reales mediante descompresión por stream. No extrae archivos ni analiza registros. Los límites vienen del consumidor; los 18 casos locales usan fixtures, no política real. Formatos no compatibles bloqueados. Contrato: `contracts/ZIP_CONTENT_V05.md`. Próximo módulo: verificar el recurso y esquema interior de SUNAT, no activar conectores ni perfiles.

## Lote v0.6 — lector candidato SUNAT
`adapters/sunat_records_candidate.mjs` procesa flujos de bytes con esquema exacto y política inyectados. Selección conservadora RUC 20, territorio configurable, cuotas y detección de cambios de columnas; descarta otros prefijos y columnas fuera del contrato. El esquema mensual real sigue sin verificar; no usar el reducido como equivalente. Prueba local 24 casos sintéticos, sin conexión a ZIP ni altas de fuentes. Ver `contracts/SUNAT_RECORDS_V06.md`.

## Lote v0.7 — integración ZIP → lector SUNAT
`adapters/sunat_zip_candidate.mjs` conecta el procesador ZIP reutilizable con el lector por stream sin descomprimir a disco. Valida toda la estructura/CRC del ZIP antes de entregar filas candidatas; controla bytes reales, selección exacta, cuotas y timeout externo explícito. 16 pruebas locales y 1 mutación CRC, fixtures únicamente. Contrato: `contracts/SUNAT_ZIP_INTEGRATION_V07.md`. Sigue pendiente el esquema real, transporte y autorización comercial de fuente. No se habilita runtime.

## Lote v1.1 — secuencia candidata SUNAT 12.01

La fuente de catálogo es `PE-SUNAT-RUC` (`SALY-U07-S12-C01`, paso 12.01). `contracts/source_registry.v1.json`, entrada SUNAT, define `sequence.steps` con dependencias, componentes y gates. La numeración 12.01.1–12.01.8 es interna, no nuevos substeps registrados en Supabase. La fuente sigue `SPEC_ONLY_NOT_CONNECTED` y el registro ejecutable conserva solo PTE. Las secciones v0.2–v0.7 son históricas; este bloque actualiza el estado de SUNAT.

| Subpaso | Función | Estado técnico |
|---|---|---|
| 12.01.1 | Admisión y transporte | PINNED_QA_TRANSPORT_LOCAL_PASS_RIGHTS_PENDING |
| 12.01.2 | Integridad ZIP y esquema | DUAL_ZIP_LOCAL_FIXTURES_PASS |
| 12.01.3 | Lectura y selección | DUAL_PROJECTION_LOCAL_FIXTURES_PASS |
| 12.01.4 | Cruce por RUC | DUAL_JOIN_LOCAL_FIXTURES_PASS |
| 12.01.5 | Proyección empresarial y lotes | DUAL_BATCH_HASH_LOCAL_FIXTURES_PASS |
| 12.01.6 | Antigüedad mínima observada | OPTIONAL_COMPONENT_NOT_WIRED |
| 12.01.7 | Persistencia gobernada | WRITER_DEPLOYED_DISABLED |
| 12.01.8 | Reconciliación y cierre | QA_BASELINE_COMPARATOR_LOCAL_PASS_REAL_RUN_PENDING |

Flujo candidato: admisión/descarga → integridad/esquema → lectura/proyección de origen → cruce y proyección empresarial (`joined_batches` llama internamente a `company` y `batches`) → antigüedad separada si se solicita → cierre READ_ONLY. La persistencia es una rama externa gobernada desde 12.01.5, independiente de antigüedad. No se promete orquestación automática: faltan los lectores dual-source de streams con política, el caller integrado y readback. El cierre de ingesta exige reconciliar filas, lotes y hashes con una lectura independiente.

Evidencia: PR #4583, 478657 coincidencias únicas con nombre, 32 filas de piloto en seco y cero publicadas (`tests/evidence/sunat_202610_join_20261121.json`). #4586 incorporó antigüedad y #4588/#4589 su piloto y corrección de codificación; no afirmar resultado del piloto sin log. #4582 instaló escritor invoker deshabilitado; captura empresarial v1 no admite antigüedad. Mensual aporta 13 campos, reducido 5 observaciones (RUC compartido, razón social, estado, condición, UBIGEO). No activar runtime, persistencia ni regla comercial en este lote.

Criterio de avance: actualizar secuencia, componente, prueba y estado en el mismo PR cada vez que cambie un subpaso. Mantener separado registro operativo de candidatos. No declarar integración hasta probar la secuencia completa con casos positivos y negativos y evidencia de cierre correspondiente.

## Lote v1.2 — lectura dual y cruce candidato desde ZIP locales

`adapters/sunat_dual_stream_v1.py#candidate_receipt` enlaza las fuentes locales fijadas por URL, SHA-256 ZIP y SHA-256 de cabecera con `joined_batches`, que conserva `company` y `batches` sin modificación. No descarga ni autentica derechos: requiere archivos revisados entregados por el caller. Límites inyectados para ZIP, bytes descomprimidos, ratio, filas, línea, cohorte, spool, lotes y tiempo; lectura hasta EOF/CRC antes de emitir cualquier lote. Procesa RUC 20, departamentos parametrizados según UBIGEO mensual; duplicados del mensual se controlan dentro del ámbito seleccionado, y los del reducido en toda la fuente para la cohorte seleccionada. Excluye claves identificables con filas reducidas malformadas, descarta domicilios y conserva discrepancias y evidencia de origen. No afirma unicidad nacional del mensual. El recibo contiene solo métricas y hash encadenado de lotes (SHA-256 de hashes binarios concatenados en orden); no incluye RUC, nombres ni payloads. No tiene salida de persistencia ni habilita runtime. Fecha de antigüedad no solicitada en esta secuencia.

Prueba local exacta: `python3 skills/ai_sales_discovery/tests/test_sunat_dual_stream_v1.py` (4/4 métodos unittest: selección, duplicados, cuarentena, codificación y huella de captura exacta; hash y cabecera; CRC; cuotas y URL). Blobs probados del lector `e65511eada8be8bd3a1bd069fcee6dc855b58910`, prueba `8cf25a126a8c235a69bb7bc080e205c4b6070bf8`, proyector `caba5f2cd9266feb9e7e585e662de50a6ce672a4`, join `7d3d5f9e0bc774707506355f41abd930c5dfdf8e`. No confundir con resultado real del nuevo lector. Pendiente: caller de admisión/descarga, política y derechos efectivos, prueba con archivos reales, readback independiente, rama histórica opcional y escritor externo. El registro ejecutable PTE no cambia.

## Lote v1.3 — QA integral de archivos fijados

`adapters/sunat_candidate_run_v1.py#run_candidate_qa` conecta `acquire` al lector/cruce v1.2. Solo acepta `PINNED_QA_ONLY`, manifiesto con ambas URL oficiales y hashes de ZIP/cabecera, referencia de evidencia, ámbito y cuotas explícitas. Acota tiempo global y por etapa, limpia temporales incluso al fallar y bloquea ante mutación de archivos o discrepancia de cuatro conteos frente a evidencia precedente. El solicitante debe aportar manifiesto revisado; este QA no autentica derechos ni reemplaza `source_admission_v1` o política efectiva de negocio. No permite persistencia, runtime, scoring ni contacto. La prueba real usa la evidencia agregada de #4583: 478657 coincidencias, 13519921 filas mensual, 478659 seleccionadas y 18542615 filas reducido; si el reducido cambia, se bloquea por SHA, no se relaja el control. Comparación agregada, no readback fila a fila ni de BD.

Pruebas locales: 4/4 `test_sunat_candidate_run_v1.py` con transporte HTTP simulado y ZIP sintéticos, 4/4 regresión `test_sunat_dual_stream_v1.py`. Blobs probados: runner `78b1baffaf60b749578ce428ca705aa46ea584df`, test `995c163ac1dc7cecbdab7e160a458a5373d506fc`. El workflow existente incorpora regresión y un job QA real de una sola corrida, activado por el título del merge `SUNAT flujo integrado v1.3`; no implica éxito hasta leer su log. Pendientes: resultado real, derechos y admisión efectiva, rama histórica y persistencia gobernada. Sin alta de fuente ni cambios a Supabase.
