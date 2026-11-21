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
