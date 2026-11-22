# SKILL_AI_SALES_DISCOVERY — candidato técnico aislado v1.9

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
| 12.01.1 | Admisión y transporte | PUBLIC_REUSE_DECISION_REGISTERED_RUNTIME_DISABLED |
| 12.01.2 | Integridad ZIP y esquema | PINNED_DUAL_ARCHIVE_QA_PASS |
| 12.01.3 | Lectura y selección | PINNED_DUAL_PROJECTION_QA_PASS |
| 12.01.4 | Cruce por RUC | PINNED_DUAL_JOIN_QA_PASS |
| 12.01.5 | Proyección empresarial y lotes | PINNED_BATCH_RECEIPT_QA_PASS |
| 12.01.6 | Antigüedad mínima observada | OPTIONAL_COMPONENT_NOT_WIRED |
| 12.01.7 | Persistencia gobernada | VERIFIED_PAYLOAD_DELIVERY_CANDIDATE_TEST_PENDING_GOVERNED_CALLER_PENDING |
| 12.01.8 | Reconciliación y cierre | PINNED_REAL_MANIFEST_QA_PASS_DB_READBACK_PENDING |

Flujo candidato: admisión/descarga → integridad/esquema → lectura/proyección de origen → cruce y proyección empresarial (`joined_batches` llama internamente a `company` y `batches`) → antigüedad separada si se solicita → cierre READ_ONLY. La persistencia es una rama externa gobernada desde 12.01.5, independiente de antigüedad. No se promete orquestación automática: faltan los lectores dual-source de streams con política, el caller integrado y readback. El cierre de ingesta exige reconciliar filas, lotes y hashes con una lectura independiente.

Evidencia: PR #4583, 478657 coincidencias únicas con nombre, 32 filas de piloto en seco y cero publicadas (`tests/evidence/sunat_202610_join_20261121.json`). #4586 incorporó antigüedad y #4588/#4589 su piloto y corrección de codificación; no afirmar resultado del piloto sin log. #4582 instaló escritor invoker deshabilitado; captura empresarial v1 no admite antigüedad. Mensual aporta 13 campos, reducido 5 observaciones (RUC compartido, razón social, estado, condición, UBIGEO). No activar runtime, persistencia ni regla comercial en este lote.

Criterio de avance: actualizar secuencia, componente, prueba y estado en el mismo PR cada vez que cambie un subpaso. Mantener separado registro operativo de candidatos. No declarar integración hasta probar la secuencia completa con casos positivos y negativos y evidencia de cierre correspondiente.

## Lote v1.2 — lectura dual y cruce candidato desde ZIP locales

`adapters/sunat_dual_stream_v1.py#candidate_receipt` enlaza las fuentes locales fijadas por URL, SHA-256 ZIP y SHA-256 de cabecera con `joined_batches`, que conserva `company` y `batches` sin modificación. No descarga ni autentica derechos: requiere archivos revisados entregados por el caller. Límites inyectados para ZIP, bytes descomprimidos, ratio, filas, línea, cohorte, spool, lotes y tiempo; lectura hasta EOF/CRC antes de emitir cualquier lote. Procesa RUC 20, departamentos parametrizados según UBIGEO mensual; duplicados del mensual se controlan dentro del ámbito seleccionado, y los del reducido en toda la fuente para la cohorte seleccionada. Excluye claves identificables con filas reducidas malformadas, descarta domicilios y conserva discrepancias y evidencia de origen. No afirma unicidad nacional del mensual. El recibo contiene solo métricas y hash encadenado de lotes (SHA-256 de hashes binarios concatenados en orden); no incluye RUC, nombres ni payloads. No tiene salida de persistencia ni habilita runtime. Fecha de antigüedad no solicitada en esta secuencia.

Prueba local exacta: `python3 skills/ai_sales_discovery/tests/test_sunat_dual_stream_v1.py` (4/4 métodos unittest: selección, duplicados, cuarentena, codificación y huella de captura exacta; hash y cabecera; CRC; cuotas y URL). Blobs probados del lector `e65511eada8be8bd3a1bd069fcee6dc855b58910`, prueba `8cf25a126a8c235a69bb7bc080e205c4b6070bf8`, proyector `caba5f2cd9266feb9e7e585e662de50a6ce672a4`, join `7d3d5f9e0bc774707506355f41abd930c5dfdf8e`. No confundir con resultado real del nuevo lector. Pendiente: caller de admisión/descarga, política y derechos efectivos, prueba con archivos reales, readback independiente, rama histórica opcional y escritor externo. El registro ejecutable PTE no cambia.

## Lote v1.3 — QA integral de archivos fijados

`adapters/sunat_candidate_run_v1.py#run_candidate_qa` conecta `acquire` al lector/cruce v1.2. Solo acepta `PINNED_QA_ONLY`, manifiesto con ambas URL oficiales y hashes de ZIP/cabecera, referencia de evidencia, ámbito y cuotas explícitas. Acota tiempo global y por etapa, limpia temporales incluso al fallar y bloquea ante mutación de archivos o discrepancia de cuatro conteos frente a evidencia precedente. El solicitante debe aportar manifiesto revisado; este QA no autentica derechos ni reemplaza `source_admission_v1` o política efectiva de negocio. No permite persistencia, runtime, scoring ni contacto. La prueba real usa la evidencia agregada de #4583: 478657 coincidencias, 13519921 filas mensual, 478659 seleccionadas y 18542615 filas reducido; si el reducido cambia, se bloquea por SHA, no se relaja el control. Comparación agregada, no readback fila a fila ni de BD.

Pruebas locales: 4/4 `test_sunat_candidate_run_v1.py` con transporte HTTP simulado y ZIP sintéticos, 4/4 regresión `test_sunat_dual_stream_v1.py`. Blobs probados: runner `78b1baffaf60b749578ce428ca705aa46ea584df`, test `995c163ac1dc7cecbdab7e160a458a5373d506fc`. El workflow existente incorpora regresión y un job QA real de una sola corrida, activado por el título del merge `SUNAT flujo integrado v1.3`; no implica éxito hasta leer su log. Pendientes: resultado real, derechos y admisión efectiva, rama histórica y persistencia gobernada. Sin alta de fuente ni cambios a Supabase.

## Lote v1.4 — evidencia real del QA integral

La corrida de #4594 (merge `678d21ed253ec7212050321f2dda71866abdbd0c`, Actions 44967399123/job 137039421071) terminó exitosa. El recibo real se conserva sin filas empresariales en `tests/evidence/sunat_integrated_qa_20261121.json`. Ambos hashes coinciden con la evidencia previa; los cuatro conteos coinciden: 13519921 filas mensual, 478659 seleccionadas, 18542615 filas reducido y 478657 cruces válidos. Dos claves reducidas en cuarentena, 479 lotes, hash agregado `b18e50b01672327a2225f88246e9580e4a50b11af5b3ec92fc05f5b217b67652`. Cada descarga requirió un intento. Cierre de QA candidato por conciliación agregada; no confundir con una relectura independiente por RUC ni una ingesta en BD. Antigüedad no solicitada en la corrida. Derechos pendientes de verificar, fuente deshabilitada, escritor externo sin permiso de persistencia. Sin activación, scoring ni contacto. El siguiente lote es resolver admisión y derechos efectivos sin omitir el gate de autorización.

## Lote v1.5 — derechos y preparación de persistencia en paralelo

La evaluación documental y la preparación del escritor avanzan juntas; solo la escritura efectiva depende de ambas. Ver `contracts/SUNAT_INGEST_PREPARATION_V11.md` (adenda v1.5) y `queries/sunat_persistence_preflight_v1.sql`, ejecutada en Supabase SALY real solo lectura el 2026-11-21. Mensual ODC-BY confirmado en catálogo oficial; reducido publicado por SUNAT sin licencia específica localizada, con fundamento favorable de datos públicos y hechos no protegidos pero alcance de reutilización comercial masiva pendiente de validación jurídica documentada. No aplicar licencia mensual al reducido por analogía. Escritor invoker desplegado, PG17 candidato positivo/negativo, rollback, concurrencia y replay PASS (job 137039421367); no es prueba de la operación gobernada real. Preflight real: catálogo y política deshabilitados, sin evidencia de derechos, límites max_rows/max_bytes ausentes, campos de atribución/derechos requeridos ausentes, service_role/authenticated sin EXECUTE, cero ingestas y hallazgos SUNAT. Preparar contrato de entrega de bytes canónicos por lote y operación gobernada existente, no otro escritor ni GRANT a clientes. No activar ni cargar. En cada corrida avanzar controles independientes y conservar el gate final de autorización.

## Lote v1.6 — manifiesto candidato por lote y fundamento público

`adapters/sunat_batch_plan_v1.py#plan_verified_batches` consume los bytes canónicos del `joined_batches` existente y un recibo QA previo confiable. Revalida proyección con `company`, RUC 20 ordenado sin duplicados, territorio Lima/Ica, fuentes exactas, cuotas inyectadas, conteos y hash terminal; devuelve solo metadatos por lote, sin RUC ni nombres, clave determinista por fuente/par de ZIP/alcance/ordinal, cantidad, bytes, SHA256 y referencia de consulta. Prueba de 10/10 métodos locales incluyendo integración directa con join real sobre fixtures y captura alterada con hash recalculado. Blobs exactos: planner `2edd032f98c156c85ba90600dffcc544967c3cc1`, test `ec21da31f9e48dd677b8ee48ebc18682e77225d3`, proyector `caba5f2cd9266feb9e7e585e662de50a6ce672a4`, join `7d3d5f9e0bc774707506355f41abd930c5dfdf8e`. No hay caller integrado desde descarga ZIP ni entrega de bytes al escritor todavía; no declarar 479 manifiestos generados con archivos reales. No autentica recibos ni autoriza escrituras. Regresión añadida al workflow existente.

Frente jurídico: Resolución 003820-2023-JUS/TTAIP-PRIMERA SALA, p. 2, recoge respuesta oficial SUNAT que orienta a descargar y procesar el reducido con un manejador de BD, en aplicación de transparencia. Art. 71 y glosario DS 029-2021-PCM, marco general de reutilización; DS 098-2025-PCM art. 3 no modifica art. 71. Portal PNDA de PCM incluye análisis de oportunidades comerciales. Ver adenda del contrato. Publicidad y procesamiento confirmados; no equiparar a licencia específica. Se mantiene bloqueo por derechos pendientes. No enviar consulta externa ni activar la fuente.

## Lote v1.7 — integración de manifiesto en flujo fijado

`run_candidate_qa` admite opcionalmente `batch_plan={expected,limits}` con recibo anterior, coteja fuente/snapshot/ámbito/baseline y cuotas antes de descargar. `candidate_receipt` entrega el stream acotado al planificador existente, conserva la barrera EOF/CRC, el orden, los hashes y la conciliación de todas las estadísticas; devuelve solo manifiestos con metadatos al concluir y elimina temporales. No hay entrega al escritor ni permiso operativo. Nuevos casos: flujo completo reproducible, digest divergente, snapshot distinto, estadísticas discrepantes y cuotas incompatibles. Pruebas ejecutadas en GitHub Actions, job 137079287411, head 1dc2d61372e82ba23f59729200fa007dd623bfeb: lector 4/4, runner 9/9, planificador 10/10, escritor PG17 positivo/negativo/rollback/concurrencia PASS. Link: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44980351563/job/137079287411 . Código de adapters y pruebas sin cambios después de este run. El workflow retorna a push/main y workflow_dispatch: se retira el trigger pull_request agregado porque PASE exige entrada ordinaria única (job 137079287570). No se modifica PASE ni las pruebas. Los probes reales siguen siendo push a main y título exacto. `tests/sunat_pinned_plan_real_probe.py` usa el recibo v1.4 fijado; emite únicamente 478657/479 esperados, hash de manifiesto agregado, métricas y frontera sin escritura si todos los controles pasan. Si cambia el ZIP reducido, bloquea por hash; no reemplazar por versión no revisada. Derechos y caller gobernado pendientes.

## Lote v1.8 — decisión de uso interno y evidencia real

Prueba real https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44982843282/job/137086915653 PASS, 478657 observaciones, 479 lotes únicos, 765896698 bytes; digest de manifiesto 3e12083fc487a4d1281e69b0868676fa66f0be42ad3d41966662a610545bd77e. Recibo: `skills/ai_sales_discovery/tests/evidence/sunat_pinned_batch_plan_20261121.json`. Propietario aprobó uso B2B interno de hechos empresariales públicos, sin reventa, datos personales innecesarios ni contacto automático. Fundamento, límites y riesgo residual: `skills/ai_sales_discovery/contracts/SUNAT_INTERNAL_REUSE_DECISION_V18.md`. Migración candidata registra decisión y nueva versión de SUNAT_POLICY_V1 sin activar fuente ni escritor. Catálogo real hasta merge conserva PENDIENTE_VERIFICAR. No repetir descarga QA salvo cambio de snapshot; siguiente trabajo caller gobernado y entrega de bytes, límites operativos y prueba de carga.

## Lote v1.9 — entrega efímera de bytes verificados

PR #4609, main 9f49e17eb104a802524e5c4d8f10503fd1edf918, Train 44984450761 success. Readback: rights_status=PERSISTENCIA_PERMITIDA; habilitada=false, persist_business_data=false, SUNAT_POLICY_V1.enabled=false, ledger=1, ingestas=0; decision execution EXEC-DB-TRAIN-PR4609-20261122041500-R44984450761. Implementación candidata en `skills/ai_sales_discovery/adapters/sunat_verified_delivery_v1.py`: staged stream exacto, límites, barrera digest de manifiesto, lectura revalidada, limpieza; pruebas nuevas preparadas sin declarar PASS. Contrato `skills/ai_sales_discovery/contracts/SUNAT_GOVERNED_DELIVERY_V19.md`; la autoridad comercial de ingesta no aparece registrada, no reusar maintenance DB, read-only skill ni KB. Integrar con motor de operaciones existente, tablas SALY ya instaladas y único writer invoker. Sin nuevas escrituras comerciales ni habilitación.