# Prueba local de auditoría V2: forward fixture

**Avance del lote: 100%. Flujo LF: NO ACREDITADO.**

Lectura: 6/6 fuentes y 3/3 funciones del fixture. Ejecución real: **32/32 assertions, exit 0**, incluidas reproducciones de defectos. Solo la copia `correct/` recibió cambios. `source_revision=null`; estado `FIXTURE_COMMIT_NOT_RESOLVED`.

Este reporte usa formato propio autorizado. No acredita conformidad de un reporte LF V2 completo, independencia, autoridad, despliegue ni promoción.

## Ejecución y evidencia

Comando, desde la raíz del paquete:

```bash
python -B reports/forward_v2/reproduce.py
```

Resultado: `exit 0; total=32; assertions_passed=32; assertions_failed=0`. Un ASSERT_OK del baseline puede significar que se reprodujo el error esperado.

| Evidencia | Archivo | SHA256 |
|---|---|---|
| SOURCES | [source_capture.json](source_capture.json) | `72feaad73f21ce96afdff6cd2d06aabecf9c7403cb6d516ea97c1d9f1906887e` |
| EXEC | [execution.json](execution.json) | `684cda832bcc895b8df9d06ebfea633ba171b86829add2458a5553fd2213f556` |
| CASES | [reproduction.json](reproduction.json) | `66af3be88e11b863e3e9578435f902482c45371db27d7beddd5cb22f7f762ab5` |

## Hallazgos y corrección

| ID | Estado y alcance | Causa/acción |
|---|---|---|
| F01 | FIX_VERIFIED / FIXTURE | Schema admite entrada incompleta para el entrypoint descubierto. Required de cinco campos y currency PEN/USD; sin afirmar que exista loader integrado. |
| F02 | FIX_VERIFIED / FIXTURE | prepare descarta currency y source_revision. Conservar literalmente currency/source_revision junto con portfolio_key/execution_id. |
| F03 | FIX_VERIFIED / FIXTURE | run omite as_of y falla antes de evaluar el mensaje. Pasar as_of por keyword y corregir la pérdida upstream; una sola reparación no restituye el flujo local. |
| F04 | CONFIRMED / PROPOSAL_ONLY | Handoff no determina receptor, causa, cambio ni oráculo. Identificar causa, archivos/funciones, código exacto, positivo/negativo, alcance, receptor y rollback. |
| F05 | NOT_VERIFIED / PROPOSAL_ONLY | Tipo y origen confiable de los tokens no están definidos. Resolver tipo, nulos y origen de as_of antes de interpretar READY como actualidad externa. No se declara inválido un dato sin contrato. |
| F06 | HYPOTHESIS / PROPOSAL_ONLY | Compatibilidad de claves extra depende de un loader no descubierto. Si el schema se usa como entrada directa, decidir proyección de argumentos o additionalProperties=false. La integración real está sin verificar. |

**Orden causal:** `raw run nominal → TypeError(as_of)`. Al entregar solo `as_of`, aparece `KeyError('currency')`; al reponer solo currency, aparece `KeyError('source_revision')`. No se confunden estas tres causas.

Corrección mínima probada:

```python
def prepare(portfolio_key, execution_id, *, currency, source_revision):
    return {
        "portfolio_key": portfolio_key,
        "execution_id": execution_id,
        "currency": currency,
        "source_revision": source_revision,
    }

from producer import prepare
from consumer import assess


def run(portfolio_key, execution_id, *, currency, source_revision, as_of):
    message = prepare(
        portfolio_key,
        execution_id,
        currency=currency,
        source_revision=source_revision,
    )
    return assess(message, as_of=as_of)
```

`consumer.py` es byte por byte igual al original. El schema candidato añade required/enum; conserva extensibilidad y no inventa un tipo de revisión. Su validación no está integrada al pipeline.

## Transporte y descubrimiento

| Salto | Disponible/enviado | Pérdida/resultado raw |
|---|---|---|
| Caller sintético → run | Cinco argumentos | Firma completa; no caller LF real |
| run → prepare | portfolio_key, execution_id, currency, source_revision | Binding correcto. as_of permanece en run intencionalmente |
| prepare → message | Recibe cuatro, devuelve dos IDs | Pierde currency y source_revision |
| run → assess | message; as_of disponible en run | as_of omitido; falla antes de leer message |
| assess → retorno local | READY y execution_id bajo guardas | Solo directo raw o pipeline correct; sin efecto LF |

Obligaciones no declaradas en el schema: currency/PEN-USD, source_revision, as_of keyword-only y la igualdad de ambos tokens. execution_id sí estaba declarado y se conserva como eco; no se autentica.

## Comparación semántica de textos

| Texto | Veredicto del cometido | Por qué |
|---|---|---|
| handoff.txt | 🔴 LOW | «Datos necesarios», «equipo correspondiente» y «evaluación apropiada» no fijan campos, receptor, cambio ni oráculo |
| error_contract.txt | 🟢 ACCEPTABLE en sus tres cláusulas | Identifica currency/source_revision/as_of, PEN/USD, desigualdad, ValueError/código y receptor assess; dos negativos reales coinciden |

La nota evalúa significado, condición y comprobabilidad. No se usa longitud, conteo de palabras ni cantidad de títulos. Aceptar el parcial de errores no acredita el pipeline roto ni política externa del token.

## Matriz por perfil

Leyenda: 🟢 ACCEPTABLE; 🟡 WEAK; 🔴 MISSING/CONTRADICTORY; ⚪ NOT_EVALUATED; — NOT_APPLICABLE. El peor requisito crítico decide; no se promedian verdes.

### C_INPUT: input.schema.json

Perfil `INPUT` / formato nativo `JSON_SCHEMA` apropiado. **Nota: LOW**. Contrato de entrada contrastado con la firma de run; integración de un loader no demostrada.

| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |
|---|---|---|---|---|---|
| scope | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Schema de entrada; no necesita repetir el objetivo general del sistema. | Schema de entrada; no necesita repetir el objetivo general del sistema. | Sin cambio en esta celda |
| input (crítico) | 🔴 MISSING | "required":["portfolio_key","execution_id"] | pipeline.run exige también currency, source_revision y as_of | El schema admite payload sin tres argumentos obligatorios; el único entrypoint descubierto no puede consumirlo. | "required":["portfolio_key","execution_id","currency","source_revision","as_of"] |
| types (crítico) | 🟡 WEAK | "portfolio_key":{"type":"string"},"execution_id":{"type":"string"} | assess consume moneda PEN/USD y compara dos tokens | Tipos de IDs concretos, moneda sin enum; dominio/nulos de revisión no definidos. No se impone string por preferencia. | currency: {"type":"string","enum":["PEN","USD"]}; documentar tokens opacos sin adivinar su tipo. |
| preconditions | 🔴 MISSING | Ausencia comprobada en fuente indicada | run debe recibir cinco argumentos; assess compara source_revision con as_of | No hay enlace al receptor ni condición de igualdad. JSON Schema estándar no expresa esa igualdad mediante required. | description: "Entrada de pipeline.run. La igualdad source_revision == as_of se comprueba en consumer.assess." |
| behavior | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Las ramas de decisión pertenecen al consumidor; no se exige duplicarlas físicamente en JSON Schema. | Las ramas de decisión pertenecen al consumidor; no se exige duplicarlas físicamente en JSON Schema. | Sin cambio en esta celda |
| output | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Este artefacto valida entrada, no especifica la salida READY. | Este artefacto valida entrada, no especifica la salida READY. | Sin cambio en esta celda |
| errors | 🔴 MISSING | Ausencia comprobada en fuente indicada | El caller necesita distinguir rechazo de schema, TypeError y ValueError de assess | No existe mapeo ni consumidor de validación de schema en los tres Python leídos. | description: "Validar required/enum antes de run; conservar CURRENCY_UNSUPPORTED y SOURCE_REVISION_STALE del consumidor. La integración del loader queda pendiente." |
| authority | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Schema puro sin acciones externas; no es prueba de autoridad. | Schema puro sin acciones externas; no es prueba de autoridad. | Sin cambio en esta celda |
| version_hash | 🟡 WEAK | Ausencia comprobada en fuente indicada | Fijar interpretación del schema para otro validador | Sin $schema ni $id; esta auditoría eligió explícitamente Draft 2020-12 para ejecutar las pruebas. | "$schema":"https://json-schema.org/draft/2020-12/schema", "$id":"urn:forward-v2:run-input:proposed-1" |
| tests | 🟢 ACCEPTABLE | Evidencia ejecutada adjunta; no se atribuye al raw una suite previa. | Oráculo positivo/negativo reproducible de esta auditoría | Los casos enlazados se ejecutaron y conservaron resultado literal, incluidos errores esperados del baseline. | Sin cambio en esta celda |
| consumer (crítico) | 🔴 MISSING | Ausencia comprobada en fuente indicada | pipeline.run y consumer.assess son los consumidores descubiertos | Ningún Python carga input.schema.json. La correspondencia se audita por firma; no se inventa integración runtime. | title: "Entrada de pipeline.run del fixture sintético"; añadir referencia al loader cuando exista. |
| examples | 🔴 MISSING | Ausencia comprobada en fuente indicada | Otro ejecutor necesita un payload de cinco campos que pueda reproducir | No hay ejemplo en el schema original. | {"portfolio_key": "portfolio-A", "execution_id": "run-A", "currency": "PEN", "source_revision": "revision-1", "as_of": "revision-1"} |
| freshness | ⚪ NOT_EVALUATED | Ausencia comprobada en fuente indicada | Definir quién suministra as_of y qué revisión es vigente | No hay fuente confiable, presupuesto de frescura ni dominio del token en los seis archivos. La igualdad no prueba actualidad. | Decisión pendiente: identificar fuente de as_of y política de nulos/tipos antes de acreditar frescura externa. |
| currency_enum (crítico) | 🔴 MISSING | Ausencia comprobada en fuente indicada | assess: message["currency"] in ("PEN", "USD") | Obligación adicional descubierta en consumidor; no declarada por el schema. | "currency":{"type":"string","enum":["PEN","USD"]} |

Fuentes: `fixtures/forward_v2/raw/input.schema.json`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda.

### C_PRODUCER: producer.py

Perfil `TRANSPORT` / formato nativo `PYTHON` apropiado. **Nota: LOW**. Primer salto que pierde currency/source_revision; no se exige enviar as_of a prepare porque no lo consume.

| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |
|---|---|---|---|---|---|
| scope | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Transformación local de argumentos a mensaje; sin otro efecto. | Transformación local de argumentos a mensaje; sin otro efecto. | Sin cambio en esta celda |
| input (crítico) | 🟢 ACCEPTABLE | def prepare(portfolio_key, execution_id, *, currency, source_revision): | run entrega cuatro valores a prepare | La firma exige todos los valores y run los pasa por nombre correctamente. | Sin cambio en esta celda |
| types | 🟡 WEAK | currency, source_revision | Preservar valor y tipo hasta assess | No hay anotaciones ni contrato referenciado del mensaje; el tipo de los tokens sigue sin decisión. | Conservar literalmente los cuatro valores; enlazar al schema del mensaje cuando se defina su dominio. |
| preconditions | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | prepare no es el juez de moneda/frescura; no se exige duplicar sus controles. | prepare no es el juez de moneda/frescura; no se exige duplicar sus controles. | Sin cambio en esta celda |
| behavior | 🔴 MISSING | return {"portfolio_key": portfolio_key, "execution_id": execution_id} | assess necesita currency y source_revision | Los dos parámetros existen pero nunca se copian al mensaje. | return {"portfolio_key":portfolio_key,"execution_id":execution_id,"currency":currency,"source_revision":source_revision} |
| output (crítico) | 🔴 MISSING | {"portfolio_key": portfolio_key, "execution_id": execution_id} | El mensaje debe llevar las claves leídas por assess | Pérdida material demostrada mediante readback y dos KeyError sucesivos. | Añadir "currency": currency y "source_revision": source_revision al dict devuelto. |
| errors | 🟢 ACCEPTABLE | def prepare(portfolio_key, execution_id, *, currency, source_revision): | Faltas de argumentos se rechazan por la firma Python | La función no atrapa ni convierte fallas en READY; el defecto es de transporte, no falta de try/except. | Sin cambio en esta celda |
| authority | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Solo construye un dict local; no autoriza acciones. | Solo construye un dict local; no autoriza acciones. | Sin cambio en esta celda |
| version_hash | 🟢 ACCEPTABLE | c1c0231df4d33229ead2e29e7de9ec8cb0d1b6b2e6df40f4dc0d2b3a08098f7e | Identificar los bytes exactos revisados del fixture local | Hash SHA256 calculado de la fuente; commit desconocido. No se afirma compatibilidad entre versiones ni Git HEAD. | Sin cambio en esta celda |
| tests | 🟢 ACCEPTABLE | Evidencia ejecutada adjunta; no se atribuye al raw una suite previa. | Oráculo positivo/negativo reproducible de esta auditoría | Los casos enlazados se ejecutaron y conservaron resultado literal, incluidos errores esperados del baseline. | Sin cambio en esta celda |
| consumer (crítico) | 🔴 CONTRADICTORY | return {"portfolio_key": portfolio_key, "execution_id": execution_id} | consumer.assess lee message["currency"] y message["source_revision"] | El payload disponible no satisface al consumidor real, aunque la llamada a prepare sí es compatible. | Transportar ambas claves; no reconstruirlas en assess ni inventar defaults. |
| examples | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | La función ejecutable y los cuatro casos enlazados proporcionan ejemplo; no se exige otro bloque narrativo para TRANSPORT. | La función ejecutable y los cuatro casos enlazados proporcionan ejemplo; no se exige otro bloque narrativo para TRANSPORT. | Sin cambio en esta celda |
| freshness | 🔴 MISSING | source_revision | Comparación de revisión en assess | La revisión ya recibida se pierde; esta omisión sí está demostrada y es distinta de validar su fuente. | Incluir "source_revision": source_revision; mantener as_of en run para entregarlo a assess. |

Fuentes: `fixtures/forward_v2/raw/producer.py`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda.

### C_PIPELINE: pipeline.py

Perfil `TRANSPORT` / formato nativo `PYTHON` apropiado. **Nota: LOW**. Binding del argumento obligatorio; TypeError primero, pérdidas de payload después.

| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |
|---|---|---|---|---|---|
| scope | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Orquestación local sin pasos LF ni DB. | Orquestación local sin pasos LF ni DB. | Sin cambio en esta celda |
| input (crítico) | 🟢 ACCEPTABLE | def run(portfolio_key, execution_id, *, currency, source_revision, as_of): | El caller debe dar cinco argumentos | Todos están explícitos, sin defaults. as_of está disponible antes de llamar al consumidor. | Sin cambio en esta celda |
| types | 🟡 WEAK | currency, source_revision, as_of | Mantener tipos/valores sin reinterpretación | Sin enlace al contrato de entrada y tokens de tipo no resuelto. | Enlazar schema de entrada; no convertir los tokens durante transporte. |
| preconditions | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Las guardas de moneda/revisión se delegan a assess; no se pide duplicación. | Las guardas de moneda/revisión se delegan a assess; no se pide duplicación. | Sin cambio en esta celda |
| behavior | 🔴 CONTRADICTORY | return assess(message) | assess(message, *, as_of) exige el argumento keyword-only | El argumento recibido no se entrega. La firma Python falla antes de ejecutar las guardas del consumidor. | return assess(message, as_of=as_of) |
| output (crítico) | 🔴 CONTRADICTORY | return assess(message) | Entrada nominal debe poder producir READY local | Todo recorrido nominal de run termina en TypeError; no puede propagar el retorno de assess. | Pasar as_of y preservar currency/source_revision en producer; corregir solo una causa no basta. |
| errors | 🟡 WEAK | return assess(message) | Un negativo debe llegar al rechazo semántico de assess | TypeError de binding enmascara tanto los campos perdidos como los errores de negocio declarados. | Corregir la llamada; mantener excepciones de assess sin convertirlas en READY. |
| authority | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | No hay escritura ni promoción; retorno local no acredita permiso. | No hay escritura ni promoción; retorno local no acredita permiso. | Sin cambio en esta celda |
| version_hash | 🟢 ACCEPTABLE | 83bcb284d96f55c603c6b87ff3a07c32578cecb3245fd1e25f3409c155403e23 | Identificar los bytes exactos revisados del fixture local | Hash SHA256 calculado de la fuente; commit desconocido. No se afirma compatibilidad entre versiones ni Git HEAD. | Sin cambio en esta celda |
| tests | 🟢 ACCEPTABLE | Evidencia ejecutada adjunta; no se atribuye al raw una suite previa. | Oráculo positivo/negativo reproducible de esta auditoría | Los casos enlazados se ejecutaron y conservaron resultado literal, incluidos errores esperados del baseline. | Sin cambio en esta celda |
| consumer (crítico) | 🔴 CONTRADICTORY | assess(message) | consumer.py:1 requiere as_of keyword-only | Firma y llamada incompatibles: primer fallo real probado. | assess(message, as_of=as_of) |
| examples | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | TRANSPORT permite revisión de código y casos ejecutados sin plantilla narrativa adicional. | TRANSPORT permite revisión de código y casos ejecutados sin plantilla narrativa adicional. | Sin cambio en esta celda |
| freshness | 🔴 MISSING | as_of | assess necesita el valor esperado para comparar la revisión | El dato existe en run pero falta en la llamada siguiente. | Entregar as_of por keyword y probar source_revision distinta. |
| as_of_binding (crítico) | 🔴 CONTRADICTORY | return assess(message) | def assess(message, *, as_of) | Obligación descubierta en firma del receptor, ausente del mensaje/callsite. | return assess(message, as_of=as_of) |

Fuentes: `fixtures/forward_v2/raw/pipeline.py`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda.

### C_CONSUMER: consumer.py

Perfil `EVAL` / formato nativo `PYTHON` apropiado. **Nota: NOT_EVALUATED**. Guardas y retorno local; política externa de tipos/procedencia sin evaluar.

| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |
|---|---|---|---|---|---|
| scope | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Evaluador puro del fixture, no juez de promoción. | Evaluador puro del fixture, no juez de promoción. | Sin cambio en esta celda |
| input | 🟢 ACCEPTABLE | def assess(message, *, as_of): | Recibir mensaje y token esperado | Lecturas directas identifican currency/source_revision/execution_id; ausencia se traduce en KeyError, sin default silencioso. | Sin cambio en esta celda |
| types (crítico) | ⚪ NOT_EVALUATED | message["source_revision"] != as_of | Definir dominio y nulos de tokens si READY pretende significar revisión vigente | No hay especificación del tipo/procedencia que permita afirmar que None u otro token igual es inválido. | Resolver política antes de añadir validación de tipos/nulos; no cambiar consumer en la corrección mínima. |
| preconditions | 🟢 ACCEPTABLE | message["currency"]; message["source_revision"]; message["execution_id"] | Claves necesarias presentes para retornar READY | Python define rechazo de claves ausentes y del keyword as_of. No se exige una plantilla de precondiciones separada. | Sin cambio en esta celda |
| behavior (crítico) | 🟢 ACCEPTABLE | if message["currency"] not in ("PEN", "USD"): | Moneda primero, revisión después | Ambos rechazos coinciden literalmente con error_contract; prioridad probada. | Sin cambio en esta celda |
| output (crítico) | 🟢 ACCEPTABLE | return {"decision": "READY", "execution_id": message["execution_id"]} | READY local con mismo execution_id del mensaje | Retorno preciso; no hay APPLIED ni efectos externos. Otro ID se copia, no se autentica. | Sin cambio en esta celda |
| errors | 🟢 ACCEPTABLE | raise ValueError("CURRENCY_UNSUPPORTED"); raise ValueError("SOURCE_REVISION_STALE") | Rechazo antes del retorno READY | Códigos y condiciones ejecutados para moneda inválida y revisión distinta; KeyError de faltantes también observado. | Sin cambio en esta celda |
| authority | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Ninguna autoridad real se infiere de esta función pura. | Ninguna autoridad real se infiere de esta función pura. | Sin cambio en esta celda |
| version_hash | 🟢 ACCEPTABLE | 55385451af4c5319c4d8435210f536e404e9832791615a87b13810443ba5903a | Identificar los bytes exactos revisados del fixture local | Hash SHA256 calculado de la fuente; commit desconocido. No se afirma compatibilidad entre versiones ni Git HEAD. | Sin cambio en esta celda |
| tests (crítico) | 🟢 ACCEPTABLE | Evidencia ejecutada adjunta; no se atribuye al raw una suite previa. | Oráculo positivo/negativo reproducible de esta auditoría | Los casos enlazados se ejecutaron y conservaron resultado literal, incluidos errores esperados del baseline. | Sin cambio en esta celda |
| consumer | 🟢 ACCEPTABLE | pipeline.py: return assess(message) | run es el caller descubierto; el retorno se entrega directamente | Consumidor resuelto por import explícito; el binding roto se registra en C_PIPELINE, sin culpar a la guarda correcta. | Sin cambio en esta celda |
| examples | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | EVAL no exige ejemplos adicionales cuando el código y las pruebas enlazadas determinan los oráculos. | EVAL no exige ejemplos adicionales cuando el código y las pruebas enlazadas determinan los oráculos. | Sin cambio en esta celda |
| freshness | ⚪ NOT_EVALUATED | message["source_revision"] != as_of | Contrastar igualdad local con fuente autorizada si se reclama actualidad | Dos valores iguales ajenos pasan. Fuente, período y presupuesto no existen en el fixture. | No llamar a esta igualdad prueba de actualidad; documentar fuente de as_of antes de ampliar el efecto. |

Fuentes: `fixtures/forward_v2/raw/consumer.py`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda.

### C_HANDOFF: handoff.txt

Perfil `HANDOFF` / formato nativo `MD_HANDOFF` apropiado. **Nota: LOW**. Accionabilidad de una entrega: causa, archivos, cambio, prueba, alcance y receptor.

| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |
|---|---|---|---|---|---|
| scope | 🟡 WEAK | casos relevantes | Mantenedor necesita archivos, funciones y alcance de cambio | No identifica implementación ni operación concreta. | Revisar solo fixtures/forward_v2: producer.prepare y pipeline.run; sin efectos LF. |
| input | 🟡 WEAK | Entregar los datos necesarios | Identificar campos, fuente y destino | No enumera currency/source_revision/as_of ni su origen. | run recibe currency/source_revision/as_of; prepare devuelve los dos primeros y run entrega as_of a assess. |
| types | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | El handoff puede referenciar contratos de tipos; no necesita duplicar un JSON Schema. | El handoff puede referenciar contratos de tipos; no necesita duplicar un JSON Schema. | Sin cambio en esta celda |
| preconditions | 🟡 WEAK | validar todo lo necesario | Saber cuándo detener adopción del candidato | No hay guard ni criterio de bloqueo. | Detener adopción si falla el positivo nominal o si EUR/revisión distinta no se rechazan. |
| behavior | 🟡 WEAK | La solución deberá ser robusta, suficiente y completa | Otro ejecutor debe poder aplicar un cambio exacto | Los adjetivos no determinan la instrucción ni una condición verificable. | prepare: añadir "currency":currency y "source_revision":source_revision; run: assess(message, as_of=as_of). |
| output (crítico) | 🟡 WEAK | informar los resultados y las recomendaciones oportunas | Entregar causa/código/prueba/readback al receptor | Salida sin artefacto, resultado esperado ni binding al candidato. | Entregar reporte JSON/Markdown, diff de correct, comando y resultado literal del before/after. |
| errors | 🟡 WEAK | Gestionar correctamente los errores | Códigos y siguiente acción concretos | No diferencia TypeError de binding, KeyError de payload o ValueError de las guardas. | TypeError as_of: corregir callsite; KeyError currency/source_revision: reparar prepare; EUR/mismatch deben conservar sus ValueError. |
| authority (crítico) | 🔴 MISSING | Ausencia comprobada en fuente indicada | Distinguir prueba local autorizada de cambios LF/envío externo | No acota efecto ni actor; no puede conceder permisos por adjetivos. | Solo candidato local y sus pruebas en rutas autorizadas. Sin producción, envío, Git, promoción ni cambios LF. |
| version_hash | 🔴 MISSING | Ausencia comprobada en fuente indicada | Vincular diagnóstico y cambio a fuentes concretas | El handoff no identifica archivos ni revisiones/hash del código afectado. | Resolver hashes de raw/correct desde reports/forward_v2/reproduction.json; source_revision=null, FIXTURE_COMMIT_NOT_RESOLVED. |
| tests | 🟡 WEAK | una evaluación apropiada | Positivo/negativo con entrada y resultado esperado | Ningún oráculo ni comando permite demostrar suficiencia. | python -B reports/forward_v2/reproduce.py; PEN/USD→READY, EUR→CURRENCY_UNSUPPORTED, mismatch→SOURCE_REVISION_STALE. |
| consumer (crítico) | 🟡 WEAK | enviar al equipo correspondiente | Identificar receptor y acción siguiente | No existe receptor concreto ni mecanismo de entrega. No se inventa un equipo real. | Receptor: mantenedor del fixture fixtures/forward_v2; revisar propuesta local. No enviar automáticamente. |
| examples | 🔴 MISSING | Ausencia comprobada en fuente indicada | Mostrar al menos una llamada/negativo reproducible | No hay ejemplo operativo en las cinco líneas originales. | run('portfolio-A','run-A',currency='PEN',source_revision='revision-1',as_of='revision-1') → READY. |
| freshness | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Este handoff no es un snapshot ni define política de vigencia; debe remitir al pendiente ya descrito. | Este handoff no es un snapshot ni define política de vigencia; debe remitir al pendiente ya descrito. | Sin cambio en esta celda |

Fuentes: `fixtures/forward_v2/raw/handoff.txt`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda.

### C_ERRORS: error_contract.txt

Perfil `SPEC` / formato nativo `MD_SPEC` apropiado. **Nota: ACCEPTABLE**. Solo las tres cláusulas de rechazo. ACCEPTABLE no afirma completitud de la implementación, tipo del token, autoridad, independencia ni E2E.

| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |
|---|---|---|---|---|---|
| scope | 🟢 ACCEPTABLE | El receptor assess rechaza el mensaje antes de emitir READY. | Definir dos rechazos del receptor identificado | El cometido del artefacto está delimitado por sus dos condiciones y el receptor; no pretende ser contrato completo de promoción. | Sin cambio en esta celda |
| input | 🟢 ACCEPTABLE | currency fuera de PEN/USD; source_revision distinta de as_of | Identificar datos de las dos guardas | Los tres nombres resuelven a las lecturas y al argumento de consumer.assess; execution_id no interviene en estos dos rechazos. | Sin cambio en esta celda |
| types | 🟢 ACCEPTABLE | currency fuera de PEN/USD; source_revision distinta de as_of | Conjunto admitido de moneda y predicado de comparación | PEN/USD fija valores concretos; distinta fija desigualdad de tokens. El parcial no afirma un tipo más estricto ni procedencia externa. | Sin cambio en esta celda |
| preconditions | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | El contrato parcial no afirma exhaustividad de todas las excepciones Python; claves/as_of obligatorios se resuelven en la firma y lecturas del receptor. | El contrato parcial no afirma exhaustividad de todas las excepciones Python; claves/as_of obligatorios se resuelven en la firma y lecturas del receptor. | Sin cambio en esta celda |
| behavior (crítico) | 🟢 ACCEPTABLE | currency fuera de PEN/USD → ValueError("CURRENCY_UNSUPPORTED").<br>source_revision distinta de as_of → ValueError("SOURCE_REVISION_STALE").<br>El receptor assess rechaza el mensaje antes de emitir READY. | Cada condición debe conducir al rechazo nombrado | Las tres cláusulas coinciden con consumer.py:2-6. Prioridad de moneda observada; no se usa longitud como nota. | Sin cambio en esta celda |
| output (crítico) | 🟢 ACCEPTABLE | ValueError("CURRENCY_UNSUPPORTED"); ValueError("SOURCE_REVISION_STALE"); antes de emitir READY | Resultado/error entendible y comprobable | Tipo/código y exclusión de READY están determinados para ambas condiciones; los dos negativos los reproducen. | Sin cambio en esta celda |
| errors | 🟢 ACCEPTABLE | currency fuera de PEN/USD → ValueError("CURRENCY_UNSUPPORTED").<br>source_revision distinta de as_of → ValueError("SOURCE_REVISION_STALE"). | No adivinar los dos códigos de rechazo | Condición y código exactos, sin frases abiertas. No se extiende esta aceptación al pipeline roto. | Sin cambio en esta celda |
| authority (crítico) | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | Reglas de rechazo de función pura: no es una política de permiso ni un dictamen independiente. | Reglas de rechazo de función pura: no es una política de permiso ni un dictamen independiente. | Sin cambio en esta celda |
| version_hash | 🟢 ACCEPTABLE | bf356486e8f53373d2551187ae385e94ea4ca24a27dcc0f556fc20369b4c309f | Identificar los bytes exactos revisados del fixture local | Hash SHA256 calculado de la fuente; commit desconocido. No se afirma compatibilidad entre versiones ni Git HEAD. | Sin cambio en esta celda |
| tests | 🟢 ACCEPTABLE | Evidencia ejecutada adjunta; no se atribuye al raw una suite previa. | Oráculo positivo/negativo reproducible de esta auditoría | Los casos enlazados se ejecutaron y conservaron resultado literal, incluidos errores esperados del baseline. | Sin cambio en esta celda |
| consumer | 🟢 ACCEPTABLE | El receptor assess | Resolver función y rutas de error | Nombre resuelto a consumer.py por pipeline.py:2; revisión contextual de la función completa. | Sin cambio en esta celda |
| examples | 🟢 ACCEPTABLE | ValueError("CURRENCY_UNSUPPORTED"); ValueError("SOURCE_REVISION_STALE") | Contraejemplos concretos que cubran los dos predicados | EUR y revision-0/as_of revision-1 de la evidencia actual instancian ambas cláusulas sin completar por adivinanza. | Sin cambio en esta celda |
| freshness | — NOT_APPLICABLE | Ausencia comprobada en fuente indicada | El predicado declara desigualdad con as_of; comprobar vigencia externa requiere otro contrato y no se acredita aquí. | El predicado declara desigualdad con as_of; comprobar vigencia externa requiere otro contrato y no se acredita aquí. | Sin cambio en esta celda |

Fuentes: `fixtures/forward_v2/raw/error_contract.txt`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda.

## Resultados por caso

| Caso | Resultado real | Comprobación |
|---|---|---|
| RAW_RUN_VALID | TypeError: assess() missing 1 required keyword-only argument: 'as_of' | ASSERT_OK |
| RAW_PREPARE_LOSS | {"portfolio_key": "portfolio-A", "execution_id": "run-A"} | ASSERT_OK |
| RAW_AFTER_BINDING_ONLY | KeyError: 'currency' | ASSERT_OK |
| RAW_AFTER_CURRENCY_ONLY | KeyError: 'source_revision' | ASSERT_OK |
| RAW_DIRECT_CONSUMER_PEN | {"decision": "READY", "execution_id": "run-A"} | ASSERT_OK |
| RAW_DIRECT_CONSUMER_USD | {"decision": "READY", "execution_id": "run-A"} | ASSERT_OK |
| RAW_UNSUPPORTED | ValueError: CURRENCY_UNSUPPORTED | ASSERT_OK |
| RAW_STALE | ValueError: SOURCE_REVISION_STALE | ASSERT_OK |
| RAW_ERROR_PRECEDENCE | ValueError: CURRENCY_UNSUPPORTED | ASSERT_OK |
| RAW_SCHEMA_MINIMAL | SCHEMA: True | ASSERT_OK |
| RAW_MINIMAL_TO_RUN | TypeError: run() missing 3 required keyword-only arguments: 'currency', 'source_revision', and 'as_of' | ASSERT_OK |
| RAW_SCHEMA_UNSUPPORTED | SCHEMA: True | ASSERT_OK |
| CORRECT_RUN_PEN | {"decision": "READY", "execution_id": "run-A"} | ASSERT_OK |
| CORRECT_RUN_USD | {"decision": "READY", "execution_id": "run-A"} | ASSERT_OK |
| CORRECT_PREPARE_READBACK | {"portfolio_key": "portfolio-A", "execution_id": "run-A", "currency": "PEN", "source_revision": "revision-1"} | ASSERT_OK |
| CORRECT_UNSUPPORTED | ValueError: CURRENCY_UNSUPPORTED | ASSERT_OK |
| CORRECT_STALE | ValueError: SOURCE_REVISION_STALE | ASSERT_OK |
| CORRECT_ERROR_PRECEDENCE | ValueError: CURRENCY_UNSUPPORTED | ASSERT_OK |
| CORRECT_EXECUTION_ID | {"decision": "READY", "execution_id": "run-B"} | ASSERT_OK |
| CORRECT_MISSING_CURRENCY | KeyError: 'currency' | ASSERT_OK |
| CORRECT_MISSING_SOURCE_REVISION | KeyError: 'source_revision' | ASSERT_OK |
| CORRECT_MISSING_EXECUTION_ID | KeyError: 'execution_id' | ASSERT_OK |
| CORRECT_SCHEMA_NOMINAL | SCHEMA: True | ASSERT_OK |
| CORRECT_SCHEMA_MISSING_CURRENCY | SCHEMA: False | ASSERT_OK |
| CORRECT_SCHEMA_MISSING_SOURCE_REVISION | SCHEMA: False | ASSERT_OK |
| CORRECT_SCHEMA_MISSING_AS_OF | SCHEMA: False | ASSERT_OK |
| CORRECT_SCHEMA_UNSUPPORTED | SCHEMA: False | ASSERT_OK |
| CORRECT_SCHEMA_STALE | SCHEMA: True | ASSERT_OK |
| CORRECT_NULL_REVISION_BOUNDARY | {"decision": "READY", "execution_id": "run-A"} | ASSERT_OK |
| CORRECT_WRONG_AS_OF_BOUNDARY | {"decision": "READY", "execution_id": "run-A"} | ASSERT_OK |
| CORRECT_SCHEMA_EXTRA_BOUNDARY | SCHEMA: True | ASSERT_OK |
| CORRECT_RUN_EXTRA_BOUNDARY | TypeError: run() got an unexpected keyword argument 'extra' | ASSERT_OK |

## Once pasos LF y límites

| Paso | Estado | Motivo |
|---|---|---|
| 0 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 10 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 20 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 30 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 40 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 45 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 47 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 50 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 60 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 70 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |
| 80 | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |

No hay SQL ni cohorte live: N real de corridas LF = 0, tasa de falsos PASS = null. Los 32 escenarios locales no se presentan como muestra del sistema. EKB vigente no consultada por alcance sin DB; checklist local solo orientativo.

Pendientes antes de ampliar alcance:

- Sin red, DB, Git, PR, CI ni producción; ningún reporte anterior leído.
- No se acredita independencia, autoridad real, registro ni promoción.
- No commit real disponible; no se fabrica SHA40. Hashes de archivos sí calculados.
- No despliegue LF reparado: solo candidatos correct y baseline raw sin alterar por esta tarea.
- No loader integrado del schema: la comparación schema→run es una prueba local explícita, no un camino desplegado.
- Tokens null o ajenos iguales pasan; riesgo contextual sin política no se convierte en defecto confirmado.
- HANDOFF corregido revisado estáticamente, sin envío ni prueba de ejecución por receptor real.
- Este JSON es reporte propio de prueba, no certificado de conformidad con un reporte LF V2 de once pasos.
- No evaluación de SQL/RLS/concurrencia/retry/tenant/hash de payload o E2E porque el fixture no los define.

Siguiente acción: revisar la propuesta aislada y resolver tipo/nulos/fuente de tokens y loader de schema. No hay aprobación ni efecto LF implícito.
