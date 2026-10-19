# M10.7 / B — integración onepass en guards por UPDATE

**Ámbito estricto:** misma ruta Input Governance, familia y propuesta de una pantalla (43), sin Router, sin Curator/Validator nuevos y sin prueba integral.

## Decisión técnica

No se admite caché entre triggers, filas, sentencias o transacciones. En las dos rutas `UPDATE`, se mantiene el trigger previo de continuación para controles de inmutabilidad, pero la lectura de autoridad se delega al guard final obligatorio. Este invoca `fn_ig_m107_manifest_guard_bundle_v1` una sola vez y exige por separado `g1.continuation_current=true` y `full_manifest_current=true`. No se desactiva ni elimina ningún trigger.

**Tercer consumidor protegido:** `fn_guard_input_governance_continuation_currentness_v1` también gobierna `INSERT` en `input_validator_chunk_timings`. Para esta tabla y operación retiene su consulta de currentness original; no se delega nada.

El guard final de familia sigue validando componentes, identidades, contrato fijado, fuente, aserciones, cálculo y hash del recibo. El guard final de propuesta sigue verificando independencia, fuentes de propuestas, estado de decisión y hash. Ni el helper ni los guards admiten datos de un cliente como manifiesto.

## Prueba de regresión atómica en Train

Previo al cambio se verifica el hash de las tres funciones y sus tres bindings gobernados. Después del cambio se confirma la cantidad de 16 triggers activos entre las tablas. Se reutiliza el fixture reversible del EKB 008, que crea un run temporal `VALIDATING`, valida una familia y una propuesta, prueba el rechazo de un SHA manipulado y mide todos sus triggers. Se agrega un negativo de fuente real: retirar temporalmente el visual activo y exigir que una propuesta `PASS` sea rechazada. Ambas mutaciones de fuente y los recibos del run se revierten con savepoint implícito/subtransacción, sin residuos.

EKB previsto `IG-M107-B-ACTIVE-GUARD-ONEPASS-033`. La revisión y aplicación se hacen exclusivamente por PR + LF Migration Train. Si falla una sola prueba, la transacción debe revertir las funciones y los datos.

**Fuera de alcance:** optimización C, integración consumidor G, ejecución integral H, CP3–CP5, cambio de timeouts, rutas de Router.

No se extrapola el resultado previo 4/4 del microbenchmark al rendimiento real del Validator. Esta integración necesitará su propia medición y verificación negativa antes de declarar B completamente verde.
