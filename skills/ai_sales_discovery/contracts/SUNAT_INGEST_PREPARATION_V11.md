# SUNAT — preparación de ingesta SALY v1.1

Estado: CANDIDATO. No confiere habilitación de fuente, permisos de escritura ni identidad validada. No modifica esquema, Router, perfiles ni PTE. Depende del resultado real de PR #4574 y de derechos de reutilización de ambas variantes.

## Evidencia observada el 2026-11-21
- Mensual 2026-10, recurso oficial PadronRUC_202610.zip: job 136982762957, PR #4568, merge 98a3dc7fc2702d35e8a02214da038c06231b19d9. ZIP 262346323 bytes, SHA256 bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7; cabecera SHA256 e28e408c81fa69951aba6c4343a5b9fb73e8f37f988f6b183700f1c0e66c0966; CRC confirmado. 13519921 registros, 918611 prefijo 20, 478659 filas de Lima/Ica; 162 prefijo 20 con UBIGEO fuera del formato esperado. No equivalen a empresas únicas, activas ni elegibles.
- Reducido: https://orientacion.sunat.gob.pe/7-padron-reducido-del-ruc documenta RUC, razón social, estado, condición, ubicación y domicilio; https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html enlaza https://www2.sunat.gob.pe/padron_reducido_ruc.zip. Publicación consultada 2026-11-21. Formato interno, hash, cobertura y derechos comerciales específicos pendientes.
- Lectura de esquema real SALY: catálogo no tiene SUNAT; ventas_hallazgos exige nombre_provisional y no posee CIIU ni NroTrab. ventas_unidades_operativas.registro_id referencia ventas_hallazgos.id. El escritor saly.ventas_pte_ingesta_core_v1(uuid,text,text,text) exige PE-PTE y SALY-U07-S13-C03; su unicidad inter-RUN también es exclusiva de PTE. No reutilizarlo como escritor SUNAT tal cual.
- Configuración public.lf_global_config, scope SALY_DISCOVERY: PTE_POLICY_V1 REAL y READ_ONLY. No confiere política SUNAT. No fijar umbrales de trabajadores, transporte o lote a partir de fixtures.

## Mapeo candidato, no DDL
| Campo lógico | Origen | Condición de uso |
|---|---|---|
| RUC candidato | ambos | unión exacta de 11 dígitos; prefijo 20 conservador; no prueba identidad jurídica |
| nombre_provisional | reducido | nombre no vacío; conservar ordinal y hash de variante |
| ubigeo_candidato | mensual/reducido | preservar ambos literales; conflicto explícito, no escoger arbitrariamente |
| estado/condición | ambas | preservar cada observación y periodo; conflicto no equivale a descarte automático |
| CIIU | mensual | los tres campos originales de revisión 3/4; conservar literal y versión |
| NroTrab | mensual | conservar literal; normalización numérica solo cuando su semántica esté verificada; desconocido no equivale a cero |
| procedencia | ambas | URL, variante, periodo, hash ZIP, hash cabecera, ordinal de fila; no confundir hash de captura con hash de archivo |
| resultado de cruce | derivado | coincidencia única / sin coincidencia / ambigua / discrepancia; no duplicar registros por reintento |

No trasladar el domicilio fiscal ni filas de otros prefijos al candidato comercial. No seleccionar automáticamente estado más reciente si la fecha efectiva del atributo no consta. No fijar IDs de catálogo ni subpasos sin leer el catálogo y plan vigente.

## Transporte hacia tablas existentes
Usar las relaciones run → plan → ejecución → consulta → ingesta → hallazgo ya desplegadas. Mantener observaciones de origen y evidencia de unión separadas de la identidad validada. Antes de proponer DDL, decidir la ampliación mínima para atributos de origen y referencias a las dos variantes; no inventar una segunda base, ni clonar registros PTE ni duplicar relaciones derivables. El contrato común debe mantener la trazabilidad de ambos ZIP. Si el dato mensual no tiene razón social, no inventar un nombre ni introducir un falso hallazgo que vulnere el CHECK existente.

Requisitos de la escritura futura: catálogo y derechos vigentes para cada variante; operación gobernada, no DML directo ni migraciones recurrentes de datos; política y límites externos; hash de captura exacto, clave idempotente por snapshot/alcance/lote, transacción atómica, bloqueo y readback. Mantener pruebas de rechazo de fuente no habilitada, replay idéntico, replay divergente, duplicados concurrentes entre RUNs, rollback y conservación PTE. No modificar el escritor PTE sin equivalencia probada.

## Reconciliación
Consulta `skills/ai_sales_discovery/queries/source_snapshot_readback.sql`, ejecutada en Supabase real solo lectura el 2026-11-21; resultado: PE-PTE / 2026-08 / LIMA_ICA, 519 filas, 507 RUC distintos, 7 sin RUC candidato; huella 9678265f85de5e4d8e11d6a44a0d889ccfcd9d5e565cbc027089e97a4ef1f108. Sin SUNAT. Releer tras futura ingesta; no declarar PASS de preservación hasta comparar. La consulta no devuelve filas ni nombres.

## Próxima secuencia sin microaprobaciones
1. Cerrar cruce real #4574: cobertura, duplicados, diferencias, trabajadores, CIIU y schema reducido.
2. Con esa evidencia, ajustar lector candidato que exige nombre a dos variantes, probar salida real minimizada y reconciliar conteos.
3. Verificar derechos y configuración; preparar cambio de esquema mínimo y escritor común/adapter sin modificar PTE, con PG17 positivo, negativo, concurrencia y rollback.
4. Solo con autoridad vigente y checks reales, ejecutar lote de ingesta y reconciliar en la misma base SALY. Si falta autoridad, dejar listo sin activar.

## Adenda v1.5 — revisión documental y preflight técnico (2026-11-21)

Las secciones previas son históricas. Catálogo y escritor SUNAT ya existen (#4580/#4582), cruce real completo #4594, evidencia #4597 merge 72033222ea3b9449c44bf442893402d4f0e2b444.

### Frente A: base documental de reutilización
| Fuente | Evidencia y conclusión |
|---|---|
| Mensual | Catálogo oficial con ODC-BY y recurso octubre 2026: https://www.datosabiertos.gob.pe/dataset/padr%C3%B3n-ruc-superintendencia-nacional-de-aduanas-y-de-administraci%C3%B3n-tributaria-sunat ; licencia https://opendatacommons.org/licenses/by/1-0/ §§ 2–4: permite reutilización comercial, comprende derechos de base no todos los derechos del contenido; conservar atribución, avisos y enlace a licencia cuando corresponda. |
| Reducido | https://orientacion.sunat.gob.pe/7-padron-reducido-del-ruc y https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html (actualizado 21/11/2026) confirman publicación oficial, campos y descarga directa. En estas páginas no se identifica licencia específica ni prohibición comercial expresa. No trasladar ODC-BY del mensual al reducido. |
| Marco general | DS 029-2021-PCM, art. 71 y definición de datos abiertos: https://busquedas.elperuano.pe/dispositivo/NL/1929103-3 . Promueve publicación y reutilización de datos abiertos con límites legales. DL 822 art. 9(d) excluye hechos y datos simples de protección autoral: https://www.wipo.int/wipolex/es/legislation/details/3412 . Esto aporta fundamento favorable para hechos empresariales; no prueba por sí solo que la compilación completa o el fichero específico esté bajo licencia abierta. |
| Privacidad | Ley 29733 y reglamento DS 016-2024-JUS: https://www.gob.pe/institucion/anpd/normas-legales/2018427-29733-2011 y https://www.gob.pe/institucion/anpd/normas-legales/6554453-n-016-2024-jus . Limitar a personas jurídicas, sin domicilio fiscal detallado ni contactos, sin personas naturales; el prefijo 20 es indicio conservador y no distingue empresa privada de otras personas jurídicas. No autoriza contacto ni marketing. |
Conclusión candidata: mensual confirmado; reducido fundamento favorable, pero no se verificó licencia específica ni se emitió dictamen de suficiencia de base legal para persistencia comercial masiva. Mantener PENDIENTE_VERIFICAR hasta decisión jurídica documentada o confirmación del titular; no exigir arbitrariamente una licencia nueva si el fundamento jurídico aplicable es suficiente. No se ha enviado consulta externa. No modificar política oficial con este lote.

### Frente B: persistencia técnica
- Preflight ejecutado en la base SALY real solo lectura: `queries/sunat_persistence_preflight_v1.sql`. Una fila PE-SUNAT-RUC: habilitada=false; persist_business_data=false; rights_status=PENDIENTE_VERIFICAR; rights_evidence_present=false; policy_json_type=object; policy_enabled=false; max_rows_valid=false; max_bytes_valid=false; policy_rights_fields_present=false; writer_present=true; writer_security_definer=false; service_exec=false; authenticated_exec=false; ingestas=0; hallazgos=0.
- Escritor desplegado `saly.ventas_sunat_ingesta_core_v1(uuid,text)`; suite candidata PG17  https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44967399123/job/137039421367 acredita PASS_SUNAT_PG17_ROLLBACK_NEGATIVE_CROSS_RUN_LOCK_REPLAY_1_BATCH_2_COMPANIES. Dos registros sintéticos, rollback, consulta inexistente, bloqueo concurrente, replay y rechazo de solapamiento. No afirmar ejecución de carga real ni equivalencia de la suite candidata con una operación nativa aún no conectada.
- QA real agregado https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44967399123/job/137039421071 confirma 478657 cruces/479 lotes y hash agregado; los payloads fueron descartados, no existe archivo persistido de empresas listo para enviar.
- Secuencia de preparación: desde los ZIP fijados y el join existente, generar manifiesto candidato por lote (clave determinista, filas, bytes canónicos SHA256, par de hashes ZIP, alcance); conservar payloads solo en espacio efímero acotado hasta EOF/CRC y conciliación total. No usar logs/PR para datos de empresas. Reutilizar planes y consultas existentes: cada consulta FOUND debe tener evidencia URL mensual#captura-json-sha256=hash exacto del lote, cantidad y batch_key coincidentes. Una única operación gobernada autorizada deberá invocar el escritor instalado; no DML directo, migraciones recurrentes ni nuevos grants a clientes.
- Antes de activar: aprobar evidencia de derechos de ambas variantes y atribución, configurar límites operativos a partir de medición (no copiar cuotas QA como política), integrar caller y probar identidad de operación, rechazo por catálogo/política, hash divergente, fallo parcial, reintento y readback. Ejecutar primero prueba controlada del caller con fixtures, después lote real autorizado y finalmente reconciliar en la misma base, incluyendo preservación PTE. La política y código de autorización permanecen deshabilitados durante este lote.
