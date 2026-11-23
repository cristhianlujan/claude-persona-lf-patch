---
name: creative-factory-standalone
description: Orquesta la composición gráfica de revisión reutilizando el compilador, adaptador por negocio y verificador de transporte existentes, sin invocar Router, perfiles ni generación de producción.
---

# Fábrica Digital — skill autónoma v0.14 (PLAN_ONLY / REVIEW_ONLY)

## Política transversal de eficiencia espacial y decoración v0.14 (22/11/2026)

**Autoridad:** instrucción expresa del dueño en el chat SALY (22/11/2026); aplica a toda imagen propuesta por esta skill, no solo al Home. Esta política no modifica activos oficiales ni inventa nuevos tokens, contenidos, métricas o permisos.

- **HARD LOCK, sin excepciones decorativas:** nunca dibujar trazos radiales, palitos de énfasis, rayos de explosión, destellos o líneas cinéticas/impacto que rodean iconos, cifras, botones, ilustraciones o fotografías para simular movimiento, emoción o energía. También queda prohibido usarlos como ornamento suelto, en cualquier composición o modelo gráfico receptor. Conservar las líneas estructurales imprescindibles de iconos funcionales (p. ej. calendario, reloj, chevron, símbolo informativo), separadores necesarios y elementos exigidos por un activo oficial; ante conflicto con un activo oficial, no modificarlo ni sustituirlo: registrar la contradicción y bloquear el componente para decisión del dueño.
- **Eficiencia espacial (habilidad v0.11 reforzada):** antes de seleccionar la composición, identificar áreas o alturas ociosas, quiebres de texto, columnas desiguales y filas dedicadas solo a iconos. Comparar al menos dos distribuciones factibles para los grupos afectados (icono al lado de etiqueta y valor frente a icono superior; agrupación horizontal/mixta; sección frente a tarjeta), y seleccionar la que conserve legibilidad y jerarquía con menos desperdicio. No imponer distribución horizontal por defecto ni comprimir tipografía o márgenes por estética. Expresar la alternativa seleccionada mediante relaciones renderizables en `hierarchy.instruction`, `components[].instruction` y `selected_alternative.design_move`; mantener la comparación y descarte en `hierarchy.rationale`/QA. El generador recibe **solo** la dirección elegida.
- **Caso SALY ilustrado (evidencia adjunta 1001948503.jpg):** el resumen «Próximo descuento / Importe estimado / Mi disponible» reserva una franja superior para tres iconos, introduce saltos en las etiquetas y deja espacio libre no compensado. En propuestas nuevas evaluar iconos laterales con etiqueta/valor agrupados, distribución de dos datos y acceso «Mi disponible» en otra fila, o un esquema sin contenedor extra, sin alterar los textos. No convertir esta solución posible en plantilla global.
- **QA objetivo, no prueba de usuario:** el QA previo verifica que existe una comparación espacial y que el handoff no pide decoración prohibida; el QA de imagen señala rayos/palitos decorativos, huecos evitables y desbordes cuando son visibles. La efectividad, satisfacción y aprobación estética la evalúa exclusivamente el dueño mediante sus iteraciones; no exigir ni simular pruebas de usuarios.
- **Estado:** tras entregar la imagen solicitada con evidencia técnica real, el pedido puede quedar `TERMINADO`, sin esperar aceptación subjetiva. `TERMINADO` no significa `APROBADO`; los ajustes posteriores son nuevas instrucciones acotadas. Un fallo real de entrega sigue impidiendo marcarlo terminado.

## Alcance y activación

La skill puede invocarse directamente en modo PLAN_ONLY mediante el adaptador
SALY de lectura, o por CLI con un **paquete congelado** y archivos locales.
NO ejecuta ni llama Router, perfiles, RUN de perfil, proveedores ni aprobaciones.
PLAN_ONLY lee Supabase exclusivamente por la RPC autorizada descrita abajo;
COMPOSE_REVIEW_ONLY permanece offline. No se registra en el selector de perfiles durante este lote.
No reemplaza ni duplica `SALY_VISUAL_CONTEXT_INVENTORY`, `SALY_APP_VISUAL_PROBE`,
`adapter_saly_review_v1`, `native_transport_capture_v1` o `compositor_core_v1`.

**Estado actual:** demostrable con SALY usando un paquete L2C de revisión y un
cuerpo gráfico **sintético**. No admite cuerpos declarados como resultados de GPT Native
sin origen autenticado. Sin adaptador específico no se ejecutan LF ni negocios nuevos.

## Preparación autónoma de un pedido (Macrolote A)

**Entrada inicial:** texto literal del usuario + negocio + objetivo. La interpretación
semántica pertenece a la skill, no al Router. Antes de compilar, separar el texto
literal (no corregirlo ni resumirlo como si fuera original) de una propuesta con:
- objetivo funcional y entregable solicitado;
- pantalla/variante y qué debe conservarse;
- contenido/copy/cifras con autoridad de origen;
- áreas fijas y libertad creativa;
- fuentes requeridas y criterios de aceptación técnicos y semánticos.

No inventar valores ni declarar una interpretación propuesta como aprobada.
Si todavía no existe pedido e interpretación sellados, devolver la propuesta
`NEW_INTENT_REQUIRES_INTERPRETATION` y los datos pendientes, sin construir
un prompt operativo usando otro pedido. La creación/persistencia de pedidos
nuevos no se implementa en este lote.

**Para un pedido existente:** una vez localizado el objetivo exacto por negocio,
proyecto, código de pedido e item, invocar la RPC de solo lectura
`saly.creative_skill_prepare_v1(p_request jsonb)` desde el cliente autorizado
`service_role`. No usar credenciales del usuario como autoridad ni elevar el
rol de solo lectura. El JSON tiene exactamente siete campos:

```json
{
  "schema_version": "CREATIVE_SKILL_PREPARE_REQUEST_V1",
  "mode": "PLAN_ONLY",
  "business_code": "SALY",
  "project_code": "SALY-001",
  "order_code": "<código localizado>",
  "item_code": "<código de variante localizada>",
  "literal_request": "<texto original exacto del pedido>"
}
```

La RPC reutiliza `creative_item_work_packet_l2c` para descubrir y verificar
fuentes y contrato; `creative_native_canonical_wire_v1` para devolver los
bytes exactos, no una reconstrucción por Python o por el modelo.
El resultado `CREATIVE_SKILL_PLAN_V1` muestra en orden:

1. **Interpretación**: negocio, objetivo y variante. Texto original y
   estrategia separada en `work_packet.review_contract.contract.acceptance_criteria.semantic_qa`;
   hashes del literal y mensajes originales.
2. **Descubrimiento**: versión de plantilla, tokens y cadenas de resolución en
   `work_packet.review_contract.contract.handoff.trace`, logo (proveedor,
   archivo, versión, SHA), frame/iconos con sus bytes y referencias en
   `work_packet.composition_svg_assets`. Valores CANDIDATE no se promueven.
3. **Blueprint**: geometría, áreas fijas/creativas y prompt literal desde el
   handoff; `canonical_wire.wire_base64` y `wire_sha256` son los bytes del
   mensaje que debe usarse después, sin reenviar ni reserializar ahora.
4. **QA preparado, no ejecutado**: criterios técnicos y semánticos de la
   fuente. Exponer conteos y códigos; nunca afirmar el resultado visual.

Mostrar al usuario los valores efectivamente leídos en cada etapa. Solo
`PLAN_PREPARED_REVIEW_ONLY` permite pasar a revisión del plan. Ante
`SKILL_PLAN_SOURCE_NOT_READY` mostrar el estado real y bloquear; ante
`SKILL_NEW_INTENT_REQUIRES_INTERPRETATION` separar nueva intención del
contrato anterior. Si negocio o proyecto carecen de adaptador, no buscar
en fuentes de otro negocio. No invocar GPT Native ni producir imágenes.

La prueba SQL de despliegue consume Home B canónico, compara ambos outputs
directos de las funciones existentes, ejecuta 13 negativos y verifica que las
cantidades de pedidos, items, RUNs, capturas y recibos QA no cambian.
El cliente limitado de lectura puede cotejar filas/hashes pero no llamar esta RPC.

## Constructor de dirección de arte y QA previo (v0.5)

**Objetivo:** interpretar el entregable completo, no confundir el arte final con
el cuerpo que recibe un generador parcial. No convertir el ejemplo Home en
una receta fija. La dirección de arte es propuesta por la skill en función
de cada intención y de las fuentes del negocio.

### Secuencia obligatoria antes de compilar un nuevo handoff

1. **Entregable y destino:** aclarar en la interpretación si el pedido exige
   escena completa de producto (`FULL_SCENE`), cuerpo separado
   (`BODY_ONLY`) u otro activo (`OTHER_ASSET`). Mantener vista, encuadre,
   soporte y finalidad pedidos. Una escena completa puede incluir partes que
   ejecutan distintos componentes; no degradarla a cuerpo aislado ni hacer
   dibujar a Native un activo fijo que corresponde al compositor.
2. **Descubrimiento de fuentes:** localizar identidad, tokens, activos,
   textos, datos, reglas/patrones, referencia visual y geometría aplicables.
   Usar las fuentes del adaptador del negocio y la versión congelada; si
   un elemento (logo, dispositivo, icono, copy, etc.) es obligatorio y
   no está resuelto, declararlo pendiente. No inventar leyendas, valores,
   permisos, ubicación de archivos ni decisiones oficiales.
3. **Dirección de arte:** especificar seis dimensiones con una instrucción
   concreta y una justificación ligada al pedido/fuentes: escena y
   presentación, estilo y lenguaje visual, fondo y ambiente (incluye luz
   y sombras cuando procede), tipografía, jerarquía/composición y calidad
   visual/impacto buscado. Para una dimensión no aplicable explicar por qué.
   No basta "premium", "moderno" o "wow": describir qué los materializa.
   Aplicar el método v0.11 de razonamiento compositivo y el ciclo de criterio
   creativo, alternativas y refinamiento v0.12 descrito abajo.
4. **Desglose por componente:** recorrer toda la jerarquía del
   `CREATIVE_VISUAL_BLUEPRINT_V1`, no un checklist fijo de Home. Cada parte
   precisa propósito, posición/relación, estilo, textos exactos cuando
   correspondan, iconografía/imagen, fuente y responsable de ejecución.
   Reutilizar `design_lock.LOCK/GUIDED/FREE`: preservar contenido fijo,
   orientar tratamiento creativo y delimitar libertades. Separar los
   responsables NATIVE / COMPOSITOR / REFERENCE_ONLY para evitar duplicación.
   Un texto solicitado se conserva literal y no autoriza cambiar una fuente
   oficial; si hay conflicto mostrarlo y bloquear la compilación afectada.
5. **Preflight estructural obligatorio:** invocar
   `sandbox/creative_factory/art_direction_preflight_v1.py:preflight(plan)`
   con el blueprint y la propuesta. El plan incluye `business_code`,
   `literal_request`, `blueprint`, `presentation` (mode, destination),
   `direction`, `components`, `sources` y `requirements`.
   Las seis claves de direction son scene/style/background/typography/
   hierarchy/visual_impact, cada una con instruction, rationale, requirements.
   Cada componente contiene name, owner, freedom, instruction, copy,
   source_ids, requirements. Cada requisito tiene id, source y quote literal
   del pedido (REQUEST) o de una fuente; cada fuente tiene id,
   business_code, ref, version, status, text y sha256 de sus bytes UTF-8.
   Obtener snapshots reales del adaptador; la huella del texto es integridad
   local, no autenticación de origen ni hash del archivo gráfico.
   El resultado `STRUCTURAL_PASS_SEMANTIC_PENDING` es un suplemento
   de planificación para el constructor existente, **no** un payload Native.
   Un fallo bloquea y muestra el código, aplicando el protocolo de incidencias.
6. **QA semántico previo independiente:** un revisor diferente del autor de
   la propuesta coteja el pedido literal y las fuentes, no solo el resumen del
   autor. Evaluar (a) completitud del entregable, (b) cobertura real de todos
   los requisitos, incluida la detección de requisitos omitidos antes de
   construir la lista, (c) consistencia con activos/tokens/copy oficiales y
   candidatos, (d) especificidad de dirección de arte y tratamiento por
   componente, (e) responsabilidad y ausencia de contradicciones entre
   generador y compositor, (f) creatividad compatible con LOCK/GUIDED/FREE,
   (g) que la instrucción final sea renderizable y libre de metadatos QA,
   y (h) hash del plan y evidencia de la revisión, incluido el QA de eficiencia
   espacial y las dimensiones de calidad creativa v0.12 descritas abajo.
   No confundir un resultado
   estructural ni una autorrevisión con PASS independiente.
   Si el revisor o la evidencia no están disponibles, mantener
   `SEMANTIC_QA_PENDING` y no enviar.
7. **Compilación:** tras el QA previo, adaptar los campos de arte y componentes
   al blueprint canónico y reutilizar el compilador vigente para su nuevo
   contrato/hash. No concatenar el suplemento directamente al prompt
   sellado, no reescribir contratos históricos, no alterar el modo de
   revisión, permisos ni activos. Mostrar el payload exacto (únicamente las
   instrucciones pertinentes al receptor) y continuar automáticamente
   solo si existe canal y autoridad, conforme a los controles de abajo.

### Habilidad de razonamiento compositivo y eficiencia espacial (v0.11)

La dirección visual es una habilidad de decisión y redacción, no una lista fija
de posiciones ni un prompt genérico. Aplicarla al construir hierarchy, a las
instrucciones de cada componente y a su proyección gráfica. Es transversal:
interfaces, escenas, piezas promocionales, diagramas u otros activos según su
destino. No crear otro motor ni imponer el ejemplo SALY a todos los pedidos.

**Método de trabajo de la skill antes de redactar:**

1. Interpretar la función y prioridad de cada unidad visual: dato, acción,
   navegación, promoción, explicación u otra. Identificar contenido literal,
   longitud, relaciones semánticas, orden de lectura, soporte, área disponible,
   restricciones de marca/legibilidad, fuentes y referencias. Separar lo fijo
   de lo orientable y lo libre según LOCK/GUIDED/FREE.
2. Leer críticamente la referencia, si existe: qué agrupaciones, alineaciones,
   proporciones, densidad, espacios y jerarquía ayudan al objetivo, y cuáles
   ocasionan filas evitables, saltos incómodos, espacios muertos o competencia
   visual. No copiar errores, textos antiguos ni activos aproximados.
   Sin referencia, analizar el blueprint y el destino; no inventar mediciones.
3. Comparar configuraciones horizontales, verticales o mixtas que sean
   pertinentes. Para cada alternativa relevante, evaluar uso de ancho/alto,
   legibilidad del contenido real, agrupación, alineación, ritmo, jerarquía,
   accesibilidad y conflictos con zonas fijas. Explicar qué se gana y qué se
   sacrifica. Preferir agrupar icono y contenido asociado cuando evita una
   fila adicional, pero no imponerlo si el ancho disponible exige otra
   composición. Preservar áreas de interacción y tamaños legibles; no ocultar
   información ni comprimir fuentes, márgenes o controles indebidamente.
4. Elegir y justificar la alternativa por componente y comprobar el conjunto:
   contenido de mayor prioridad obtiene énfasis; componentes secundarios
   ocupan el espacio necesario; relaciones, márgenes y separaciones son
   coherentes. Si la solución no cabe o contradice un LOCK, revisar la
   alternativa o bloquear la parte afectada, no mover reservas por cuenta propia.
5. Transformar la decisión en instrucciones renderizables de arte:
   disposición y dirección de lectura, icono respecto del texto, agrupación
   de etiqueta/valor, alineaciones, distribución de ancho/alto, jerarquía
   tipográfica, comportamiento de líneas y espacios, y qué evitar.
   Especificar solo restricciones que puedan sustentarse; cuando exista
   geometría congelada respetarla, y cuando no, expresar relaciones visuales
   sin inventar coordenadas o umbrales. No dictar contenido nuevo ni dar
   instrucciones al generador sobre activos de otro responsable.
6. Conservar el razonamiento y las alternativas descartadas como justificación
   de planificación en los campos existentes de dirección de arte
   (hierarchy.rationale) y del QA; la instrucción elegida alimenta
   hierarchy.instruction y components[].instruction. No añadir claves al
   contrato, ni concatenar razonamientos, estados o checks al prompt gráfico.
   Releer la proyección final contra el plan: debe conservar las relaciones
   elegidas, el copy literal, reservas, responsables y libertades.

**QA de eficiencia espacial:** antes de enviar, el revisor independiente
evalúa si la instrucción indica el tratamiento específico y su fundamentación,
si la distribución elegida es adecuada para el contenido y destino, si
preserva legibilidad, jerarquía y restricciones, y si la proyección ha perdido
alguna relación visual. Sobre el arte recibido, comparar con referencia
aplicable y plan: inspeccionar agrupación, filas evitables, desbordes, saltos,
alineación, equilibrio, altura innecesaria y tamaño/legibilidad de textos y
controles. Separar observación comprobable de preferencia estética. Cuando
la evidencia permita cuantificar espacio o geometría, registrar medidas del
arte real y su fuente; no fabricar métricas ni exigir un umbral universal.
Distinguir un defecto de una elección válida por restricciones de espacio.
Ante desviación, localizar el componente y la primera causa sustentable
(dirección, proyección, render o composición), mejorar la instrucción de
esa etapa preservando lo correcto y conservar los intentos conforme al
protocolo de handoff. Si solo se dispone del arte y del registro previo,
no atribuir divergencias a transformaciones internas del generador.

**Casos de razonamiento de referencia (no son layouts globales):**
- Resumen financiero móvil compacto: iconos laterales y grupos etiqueta/valor
  pueden eliminar una fila reservada a iconos; verificar ancho de columnas,
  salto legible de etiquetas, alineación de valores y chevron. Si esa
  alternativa no cabe, evaluar otra distribución sin eliminar copy.
- Tarjeta promocional de ancho reducido: icono superior puede favorecer
  identidad, lectura y mensaje; evitar forzar icono lateral si estrecha el
  texto y aumenta su altura. Elegir según la pieza y referencia.
- Diagrama o infografía: comparar lectura horizontal y vertical según
  relaciones, destino y proporción; preservar texto y conexiones.
- Negativos: una instrucción que solo dice "premium y compacto", una que
  impone iconos laterales a todos los activos, o una que reduce fuentes o
  altera una reserva para encajar, no satisface la revisión de esta habilidad.

La incorporación es una capacidad metodológica del constructor semántico.
El preflight estructural existente no mide la calidad visual ni sustituye
la revisión independiente; los casos anteriores no acreditan por sí mismos
una prueba gráfica ejecutada.

### Desarrollo de criterio creativo y dirección visual avanzada (v0.12)

**Propósito:** mejorar la calidad del pensamiento de la skill y del texto que
produce, antes de delegar al generador. No sustituir criterio por adjetivos,
copiar una plantilla universal, multiplicar agentes ni crear otro motor.
La calidad creativa se decide dentro de la intención, fuentes y libertades
del pedido. Una alternativa atractiva que contradice el contenido o un LOCK
es inválida. Aplicar el razonamiento espacial v0.11 como parte de este método.

#### A. Seis habilidades que se ejercitan en cada dirección de arte

1. **Dirección de arte y criterio estético.** Formular una tesis visual
   ligada al público, función, emoción y medio: qué debe entenderse primero,
   qué sensación debe producir y qué evidencia visual la sustenta. Derivar
   un lenguaje coherente de formas, color, contraste, luz, profundidad,
   tipografía, iconografía y proporciones según el activo. Comparar la
   coherencia entre esas decisiones; no confundir más adornos, sombras,
   brillo o saturación con calidad. Identificar la primera lectura, la
   segunda y la acción esperada. Cuando una dimensión no corresponda,
   justificarlo en lugar de agregar decoración artificial.
2. **Creatividad funcional y exploración divergente.** Buscar alternativas
   realmente distintas en concepto, composición, ritmo o recurso visual,
   no simples variaciones de color. Para un pedido nuevo o una revisión
   sustancial con libertad, desarrollar al menos dos enfoques viables
   cuando existan; incluir un enfoque conservador y otro que mejore el
   problema observado. Si el cambio es acotado o no hay libertad suficiente,
   comparar solo las soluciones permitidas y explicar el límite, sin
   expandir el alcance. Identificar riesgo y beneficio de cada enfoque.
   Elegir por adecuación al objetivo y originalidad útil, no por novedad
   obligatoria. No alterar copy, identidad, cifras, funciones, geometría
   bloqueada ni hechos para hacer una propuesta más llamativa.
3. **Composición y jerarquía.** Construir el esqueleto visual antes de
   ornamentar: ancla dominante, grupos semánticos, grilla o ejes pertinentes,
   relaciones de tamaño, pesos y contrastes, dirección de lectura, balance,
   repetición y espacios de separación. Distinguir alineación óptica de
   alineación geométrica cuando proceda y explicitar por qué. Deducir
   el tratamiento de cada componente desde su función; comprobar que la
   escena completa conserve foco y ritmo. No hacer que todos los bloques
   compitan ni aplicar simetría si contradice su función.
4. **Eficiencia espacial y legibilidad.** Aplicar v0.11 a la longitud real
   de las etiquetas, valores y descripciones. Comparar distribución
   horizontal, vertical o mixta; eliminar filas o contenedores redundantes
   antes de reducir letra o área de interacción. Mantener agrupaciones,
   espacios útiles, separación y consistencia entre componentes. Considerar
   cambios de longitud del contenido y ancho del destino; distinguir
   envoltura natural de fragmentación innecesaria. En un mockup no afirmar
   cumplimiento de accesibilidad o medidas de producto que no se puedan
   comprobar. Si existe especificación dimensional aprobada, respetarla.
5. **Redacción gráfica de alta precisión.** Convertir cada decisión en
   lenguaje de render, no instrucciones para que el receptor vuelva a
   diseñar la estrategia. Especificar efecto buscado mediante relaciones
   observables: posición relativa, tamaño relativo, orden, agrupación,
   alineación, tratamiento tipográfico, contraste, material, iluminación,
   separación, encuadre y límites pertinentes. Usar copy literal y fuentes
   de autoridad; separar requisitos obligatorios de orientación flexible.
   Evitar palabras ambiguas, contradicciones, redundancias y prohibiciones
   genéricas. Ejemplo: sustituir "tarjeta elegante y compacta" por una
   descripción de cómo se reduce una fila, dónde se alinea el valor y qué
   separación se conserva. Releer el prompt como lo entendería un receptor
   que no conoce el contexto: ninguna referencia implícita a nombres,
   archivos ni decisiones que no estén resueltos en el contrato.
6. **Autocrítica y QA visual.** Distinguir intención, diseño propuesto,
   instrucción efectiva e imagen obtenida. Primero examinar la propuesta
   como autor, buscando omisiones, incoherencia, repetición, exceso y
   alternativas mejores; luego someter el plan a la revisión independiente
   vigente. En el arte real observar a tamaño normal de destino y, cuando
   aplique, en detalle: foco, orden de lectura, texto, contraste, agrupación,
   proporciones, espacios, consistencia iconográfica, integridad de activos,
   desbordes y artefactos. Señalar componente, evidencia visible, impacto
   y corrección concreta. No atribuir el defecto a una transformación
   interna del generador sin evidencia de transporte; no solicitar texto
   al generador de imágenes como condición de QA. Usar el registro anterior
   al envío y la imagen recibida. Para otro receptor con readback disponible,
   mantener el protocolo existente. Sin imagen, declarar QA visual pendiente.

#### B. Método de decisión y refinamiento

Ejecutar las seis habilidades como un ciclo dentro de los pasos 3, 4 y 6 del
constructor: interpretar → diagnosticar → explorar → comparar → seleccionar
→ redactar → revisar → refinar. La decisión debe ser rastreable a la intención
y las fuentes, no a preferencias inventadas. Comparar alternativas sobre
criterios explícitos del destino, descartar las inviables antes de ponderar
calidad, explicar el compromiso de la elegida e identificar su principal
riesgo. No presentar exploración como entrega final ni invocar un proveedor
para cada alternativa sin autorización. Ante ajustes menores preservar todo
lo que funciona; no rediseñar por iniciativa propia.

Conservar tesis, alternativas, evaluación y motivo de elección en rationale
de las dimensiones existentes, y el análisis por componente en el plan/QA
existentes. Solo la dirección elegida y las instrucciones renderizables
pasan a instruction y la proyección gráfica. No añadir claves ni estados
al contrato canónico, ni meter deliberaciones, puntuaciones o QA en el
mensaje al generador. Las reservas y propietarios se conservan. La mejora
creativa no añade autoridad de ejecución, ni cambia campos, tokens, copy,
fuentes oficiales o el modo de revisión.

#### C. Evaluación verificable y mejora continua

Usar una rúbrica de revisión comparativa, no una predicción automática de
calidad ni una certificación académica. Para cada criterio registrar
evidencia observable, observación y resultado (0 = deficiente; 1 = básico;
2 = funcional; 3 = sólido; 4 = excelente). Si no hay evidencia usar
NO_EVALUADO, nunca asignar una puntuación ficticia.
- Dirección: coherencia entre propósito, lenguaje visual y efecto.
- Creatividad: diferencia sustantiva entre alternativas viables y utilidad
  de la solución seleccionada.
- Composición: foco, jerarquía, alineación, ritmo y relaciones.
- Espacio: aprovechamiento, adaptación del texto y legibilidad.
- Handoff: instrucciones concretas, completas, no contradictorias y
  comprensibles para el receptor sin conocimientos implícitos.
- QA: diagnóstico localizado, reproducción de la evidencia y propuesta
  de corrección que preserve lo correcto.

Los controles duros del contrato (identidad, copy/cifras, LOCK, fuentes,
dueño de ejecución, autorización, alcance) no se compensan con puntuaciones.
Una revisión de texto no demuestra calidad de imagen. Evaluar por separado
la dirección escrita y el resultado visual. No declarar excelencia ni
promover a producción solo por una rúbrica; la revisión independiente y
la ruta gobernada siguen vigentes. Conservar hallazgos y versiones con la
trazabilidad existente; proponer mejoras reutilizables sin convertir una
preferencia de un pedido en política global sin aprobación.

**Prueba comparativa de la capacidad:** congelar un pedido y sus fuentes,
referencias, modo, restricciones y baseline; producir una dirección con la
versión candidata sin enseñar la solución esperada. En una revisión
independiente/pareada comparar baseline y candidato sobre la misma evidencia,
idealmente ocultando las versiones al evaluador. Si se autoriza render,
mantener las condiciones comparables del proveedor que estén disponibles,
archivar cada intento antes de generar y cotejar los resultados. No repetir
generaciones indefinidamente; aislar la primera desviación sustentable.
Registrar resultados por criterio, evidencia, condiciones no controlables
y limitaciones. Sin evidencia comparativa suficiente no afirmar mejora
medida. Los casos de evaluación de abajo son criterios y ejemplos de
contraste, no certifican un benchmark ejecutado.

**Casos de contraste para evaluar transferencia:**
- HOME financiero: separar foco de saldo/acción y resumen secundario.
  Comparar iconos superiores vs laterales con el copy actual y el ancho
  real; seleccionar agrupación compacta si mejora lectura sin recortar
  texto. Mantener montos, logo y CTA protegidos. Rechazar una dirección
  que solo diga "más premium" o copies históricos de una referencia.
- Tarjeta promocional estrecha: elegir una estructura que permita destacar
  el mensaje y conserve lectura; no forzar la solución lateral del HOME.
  Contrastar qué aporta una jerarquía vertical frente a una mixta.
- Infografía de proceso: convertir relaciones y pasos en recorrido visual
  entendible; comparar flujo horizontal/vertical según medio y conservar
  cada dependencia. Rechazar líneas decorativas que falseen el proceso.
- Corrección localizada: si solo cambia una cifra u otro elemento fijo
  autorizado, preservar layout y activos no afectados; no usar la
  creatividad como permiso para cambiar el resto.
- Negativos transversales: alternativas cosméticas disfrazadas de
  exploración, adjetivos sin instrucciones visibles, modificar una fuente
  oficial, comprimir texto hasta perder legibilidad o aprobar una imagen
  no inspeccionada. El diagnóstico debe detectar el motivo específico.

Este desarrollo modifica la metodología de la skill, no el generador de
imágenes. El preflight existente valida estructura, no creatividad ni
percepción; el benchmark creativo y visual requiere casos ejecutados y
evidencia independiente.

### Pruebas y límites

```bash
cd sandbox/creative_factory
python -m unittest -v test_art_direction_preflight_v1.py
```

El preflight es transversal y local: no llama Router, perfiles, Supabase
ni proveedores. Valida los requisitos **declarados**, no descubre por sí solo
todos los requisitos ni autentica las fuentes. Los escenarios positivos
incluyen escena completa, cuerpo aislado y otro negocio/activo; los 19
negativos incluyen fuentes cruzadas, hash alterado, omisiones de componentes,
copy no sustentado, falta de dirección y conflicto de responsables.
No declara QA semántico independiente, render real ni persistencia de
nuevos pedidos. El flujo L2C anterior permanece intacto.

## Decisión creativa positiva y transporte v0.13

**Origen:** instrucción expresa del dueño (23/11/2026): mejorar la
especificación, privilegiar objetivos positivos y dejar espacio creativo
para una evaluación posterior. No modifica pedidos anteriores y no autoriza
generación de imágenes.

**Integrado en la skill vigente, no en otra skill ni pipeline:**

Solicitud literal + fuentes versionadas → interpretación del objetivo →
modo y áreas LOCK/GUIDED/FREE → dirección de arte positiva →
dos composiciones diferentes cuando se explora → selección motivada →
preflight estructural vigente → control creativo positivo →
QA semántico independiente → compilador y wire canónico existentes
(solo con autoridad real) → QA de arte obtenido.

### Modo y libertad real

- EXPLORE_CREATIVE: cuando el usuario quiere proponer, explorar, mejorar la
  creatividad o comparar diseños. La referencia previa orienta identidad
  y objetivo, no bloquea automáticamente su composición.
- CORRECTION_STRICT: únicamente si el usuario pide correcciones localizadas.
  Aquí se preserva lo que no fue incluido en el cambio.
- Registrar el texto literal y la cita de la que se deriva el modo,
  separando solicitud e interpretación. Una coincidencia de texto
  no acredita interpretación semántica; esa revisión sigue independiente.
- Para EXPLORE_CREATIVE, design_lock.FREE debe permitir al menos una
  región propiedad de NATIVE. No aceptar FREE vacío o bloqueo de todos
  los componentes. GUIDED orienta el resultado; no inmoviliza su geometría.
- LOCK se reserva para identidad, activos oficiales, contenido/cifras
  respaldadas, obligaciones funcionales, seguridad o geometría de
  compositor verdaderamente fija. Cada restricción debe tener origen
  (resguardo B19). No convertir una preferencia heredada en prohibición
  global. Mantener protegidas las fuentes y evitar funciones inventadas.

### Decisión positiva antes del handoff

Para cada componente expresar propósito, efecto deseado e instrucciones
observables: foco visual, agrupación, relación de tamaños, contraste,
alineación, lectura, ritmo, profundidad, iconografía y legibilidad.
No reemplazar instrucciones concretas por "premium", "wow", "moderno".
En EXPLORE_CREATIVE construir al menos dos alternativas con composición
realmente diferente; registrar su beneficio, compromiso y elección.
La exploración cambia el tratamiento visual, nunca inventa contenido
financiero, funciones, cifras, logos ni autoridad de fuente.

Antes del compilador existente ejecutar
sandbox/creative_factory/creative_positive_gate_v1.py:
prepare_positive_review(plan, decision), que reutiliza el preflight v1.
El complemento SALY_CREATIVE_POSITIVE_PROCESS_V1 recibe:
mode, mode_evidence, positive_outcomes, creative_zones, alternatives,
selected_alternative y transport. Valida origen de las citas, libertad
coherente con los componentes, alternativas distintas, instrucciones
positivas renderizables y referencias de fuente; no altera el plan.
Devuelve CREATIVE_REVIEW_PREPARED_SEMANTIC_QA_PENDING y hashes del plan,
decisión y prompt propuesto. Para CORRECTION_STRICT se permite FREE vacío
si se desprende de la solicitud. La ausencia de libertad en
EXPLORE_CREATIVE devuelve CREATIVE_EXPLORE_FREEDOM_EMPTY y no avanza.

**Transporte:** convertir solo la dirección elegida en instrucciones
gráficas para el receptor. Mantener deliberación, hashes, puntuaciones,
estados y diagnósticos en el sobre de trazabilidad, no en el prompt Native.
El resultado del gate es un **borrador verificable**, no un nuevo canal
de envío ni autorización. El compilador y la captura Native vigentes
vuelven a comprobar prompt, attachment, item, contrato y hash.
El integrador debe releer bytes/versión/estado de logo, frame e iconos
antes de enviar; un identificador o texto no prueba entrega de un
activo real. Si falta un activo obligatorio, bloquear ese handoff sin
dibujar un sustituto no oficial. Nunca inferir que transmitted=false
significa enviado.

**QA en dos capas:**
1. Antes de generar, revisor independiente coteja pedido literal,
   fuentes, alternativas, dirección y proyección final; evidencia
   vinculada al hash del plan. El preflight local no sustituye esa
   evaluación ni puede autootorgar PASS.
2. Después de generar, evaluar la imagen real y su composición,
   jerarquía, originalidad funcional, espacios, legibilidad,
   identidad y copy. Registrar lo observable, el elemento afectado
   y la corrección específica. La rúbrica sin PNG real queda
   NO_EVALUADO y jamás se transforma en aprobación. Separar
   cierre técnico TERMINADO de aprobación creativa.

No abrir otra solicitud, modificar estados, producir imágenes, crear RUN
ni activar transporte Native con este cambio. La prueba visual comparativa
queda para un lote posterior autorizado por el dueño.

**Pruebas de proceso (sin generación):**
cd sandbox/creative_factory &&
python -m unittest -v test_creative_positive_gate_v1.py
test_art_direction_preflight_v1.py

El resultado PASS de esas pruebas acredita solo forma y guardas de
proceso, no superioridad estética ni ejecución Native real.

---

## Contrato de entrada

`CREATIVE_SKILL_STANDALONE_REVIEW_V1`, modo `COMPOSE_REVIEW_ONLY`:
- `business_code`: código del negocio declarado en el input aislado. No confiere permisos.
- `packet_path` + `packet_sha256`: paquete inmutable con su hash **de bytes**.
- `logo_path`, `fonts_path`, `body_path`: fuentes y cuerpo local.
- `body_origin=SYNTHETIC_REVIEW`: no equivale a respuesta del proveedor.
- `output_dir`: directorio **nuevo** para resultado y recibo técnico.

No recibe perfil, Router, skill de inventario, credenciales, write authority ni
instrucciones para omitir validaciones. El esquema del paquete SALY
(`SALY_WORK_PACKET_L2C_V1`) se verifica contra el adaptador registrado. Un código
LF/futuro nunca reutiliza los datos de SALY como sustituto.

## Flujo obligatorio

1. Validar modo, negocio y campos exactos. Seleccionar adaptador autorizado;
   si falta, `SKILL_BUSINESS_ADAPTER_NOT_AVAILABLE`.
2. Leer el paquete como bytes locales (sin red) y comprobar su hash, versión y
   permisos `REVIEW_ONLY`.
3. Reutilizar `native_transport_capture_v1.sealed_envelope` para comprobar
   prompt literal, adjuntos, item, contrato y SHA; **no enviar**.
4. Reutilizar `adapter_saly_review_v1.from_packet` para materializar en un
   directorio temporal solo SVGs de fuente con SHA y resolver tokens, logo y
   tipografía del contrato. No inventar paleta, copy ni plantilla.
5. Reutilizar `compositor_core_v1.compose` con el cuerpo sintético en slots
   autorizados; producir dos composiciones y compararlas para determinismo.
6. Escribir `composition_review.png` y `receipt.json`; reabrir PNG, comparar
   bytes/píxeles y registrar hashes. La entrega contiene solo esos dos archivos.
7. Cualquier error impide la publicación y devuelve código específico.
   No modificar artefactos previos.

## Composición flexible por blueprint (v0.6, revisión local)

No imponer el layout de Home B a una escena nueva. El mismo entrypoint
`compositor_core_v1.compose(manifest, body)` admite el contrato histórico
`CREATIVE_COMPOSITION_REVIEW_V1` y el contrato candidato
`CREATIVE_COMPOSITION_BLUEPRINT_REVIEW_V2`. La extensión
`compositor_blueprint_layers_v2.py` reutiliza primitives y preflight
existentes; no es otra skill ni otro pipeline.

Para preparar V2:
- Partir del plan de dirección de arte y jerarquía, con la propuesta de
  geometría aprobable por el flujo de QA. Incluir en el blueprint
  `composition_layout` y en `design_lock.LOCK.composition_layout` la misma
  estructura {canvas, backdrop, regions}. Congelar el hash de propuesta del
  preflight. El manifest no puede sustituir esas posiciones.
- Cada región respeta nombre, orden y propietario de los componentes del
  plan; contiene name, owner, box (x,y,ancho,alto), coverage y ops. NATIVE
  reserva zonas BOX sin operaciones fijas; REFERENCE_ONLY usa NONE, box null,
  ops vacías. COMPOSITOR BOX reserva toda la caja, ALPHA reserva únicamente
  los píxeles no transparentes de un único activo fijado (por ejemplo, marco).
- Las operaciones compositor, ordenadas dentro de cada caja, son FILL
  (box, color_source, radius), ASSET (box, source_id) o TEXT
  (box, copy, size, weight, font_source, color_source). Sus fuentes deben
  pertenecer al componente; los textos coinciden con el copy declarado.
  FILL y TEXT pueden compartir la caja del CTA dentro de una tarjeta mayor.
  Un activo con texto sigue necesitando verificación visual del copy.
- El fondo es TRANSPARENT, COLOR vinculado al token, o ASSET con archivo
  fijado por SHA y dimensiones exactas de salida. Cada fuente usada como
  archivo incluye file_sha256 en su snapshot JSON, y las fuentes tipográficas
  además weight; no inventar huellas de archivos oficiales. El registro
  files mapea identificadores de fuente a las rutas materializadas.
- El cuerpo RGBA sintético tiene exactamente las dimensiones canvas. Debe
  dejar transparentes los píxeles fijos y no invadir zonas ajenas. No recortar
  arbitrariamente un resultado Native para hacerlo pasar. El marco con
  apertura transparente se compone mediante su silueta; cajas de activos
  fijos BOX no pueden colisionar con otras máscaras fijas.
- Manifest V2 contiene schema_version, review_only=true,
  render_authorized=false, body_origin=SYNTHETIC_REVIEW, plan,
  proposal_sha256, canvas, backdrop, regions y files. Realizar preflight
  antes de componer, comprobar SHA de los activos, generar recibo y
  aplicar el protocolo de incidencia ante fallo. No declarar un resultado
  de Native desde un fixture ni usar el modo revisión para eludir autoridad.

Ejecución técnica directa, sin Router, perfiles, proveedor ni generación:

```bash
python sandbox/creative_factory/compositor_core_v1.py manifest.json body.png preview.png --receipt receipt.json
cd sandbox/creative_factory
python -m unittest -v test_compositor_blueprint_layers_v2.py
```

El recibo V2 `LOCAL_BLUEPRINT_COMPOSITOR_PASS` acredita composición local
reproducible, no QA semántico ni autenticidad de fuentes por sí solo.
El adaptador L2C histórico conserva su contrato V1 y no se migra
automáticamente a V2. El nuevo layout es un candidato local: todavía
requiere materialización/compilación gobernada, revisión independiente y
canal de recepción Native verificable antes de cualquier uso productivo.

## Ejecución integrada desde la skill (v0.7)

Usar el mismo CLI `sandbox/creative_factory/skill_run_review_v1.py --request request.json`
para V1 histórico y para la rama V2 de revisión. No invocar otros perfiles o
Router. En V2 el constructor toma el layout exclusivamente del LOCK del
plan, en lugar de usar un manifest redactado de nuevo por el ejecutor.

El request V2 tiene exactamente:
```json
{
  "schema_version": "CREATIVE_SKILL_BLUEPRINT_REVIEW_V2",
  "mode": "BLUEPRINT_REVIEW_ONLY",
  "business_code": "<negocio del plan>",
  "plan_path": "<plan local con layout en LOCK>",
  "plan_sha256": "<SHA de bytes del plan>",
  "body_path": "<PNG RGBA de ensayo o PNG RGB de referencia>",
  "body_sha256": "<SHA de bytes del cuerpo>",
  "body_origin": "SYNTHETIC_REVIEW",
  "files": {"<id de fuente>": "<ruta materializada>"},
  "output_dir": "<directorio nuevo>"
}
```

Secuencia automática de `skill_blueprint_review_v2.run_blueprint_review`:

1. Leer bytes fijados, ejecutar el preflight existente, comprobar negocio
   y construir manifest V2 a partir del layout bloqueado.
2. Emitir el evento visible PREPARED_NOT_SENT con el **handoff local literal
   completo**, SHA y hash del cuerpo adjunto. El CLI hace flush antes
   de invocar al receptor local. Sin aprobación intermedia, pasar los mismos
   bytes al compositor en esta ejecución. No es un handoff GPT Native.
3. El receptor local verifica los bytes y el hash del adjunto antes de
   deserializar y ejecutar el compositor existente. Conservar su readback.
4. Ante rechazo, emitir REJECTION_READBACK con el mensaje realmente
   recibido, hashes preparado/recibido y código; si se rechazó antes de
   invocar, HANDOFF_NOT_SENT. No simular una recepción de Native.
5. Validar recibo del compositor, manifest/propuesta, dimensiones, hash
   de píxeles y lectura del PNG. Guardar solo revisión local en directorio
   nuevo: composition_review.png, local_handoff.json y receipt.json.
6. Estado LOCAL_REVIEW_COMPLETE_SEMANTIC_PENDING: QA técnico local PASS;
   QA semántico independiente pendiente, entrega final no autorizada.
   No compilar ni enviar Native a partir de este manifest local.
   No declarar un fixture como arte generado ni admitir body_origin
   PROVIDER_IMAGE sin contrato y evidencia independientes de origen.

El preflight no produce todavía un blueprint canónico nuevo ni autentica
la fuente de cada snapshot. Mantener separadas la futura compilación
gobernada, la recepción de Native y el QA independiente del resultado.
Los tests ejercitan envío/diagnóstico local real; ninguna prueba de
recepción local acredita el canal externo.

```bash
cd sandbox/creative_factory
python -m unittest -v test_skill_blueprint_review_v2.PipelineTests test_compositor_blueprint_layers_v2.LayerTests
```

## Referencia RGB completa: composición protegida (v0.8)

El mismo flujo local admite body_origin RGB_REFERENCE_REVIEW cuando el plan
declara FULL_SCENE y una referencia previa RGB, sin acreditar origen Native.
El snapshot de referencia debe identificar los bytes (file_sha256), modo RGB,
dimensiones exactas y role previous_generated_visual_reference_only.
El blueprint y su LOCK contienen el mismo rgb_reference_binding con source_id,
pixel_sha256 y alignment CANDIDATE_MANUAL_REVIEW. No es una validación
automática de alineación ni aprobación semántica.

La geometría bloqueada debe cubrir todo el lienzo y reservar cajas BOX
explícitas para cada elemento fijo. No se permite ALPHA en este modo.
El receptor comprueba el hash del archivo; el compositor valida píxeles,
geometría, cobertura y fondo limpio opaco. No redimensiona, recorta ni
reconstruye el cuerpo. Convierte RGB a RGBA conservando los píxeles creativos
y retirando únicamente las cajas protegidas. Compone los activos oficiales
en esas cajas y compara el resultado contra la referencia original.
Si cambia un píxel exterior, se bloquea. El recibo registra máscara, cantidades
reservadas, preservadas y cambiadas, y origen no verificado.

Revisar visualmente la correspondencia de las cajas, continuidad del fondo
limpio, logo, CTA y demás componentes. LOCAL_REVIEW_COMPLETE_SEMANTIC_PENDING
no autoriza entrega final, publicación ni render de producción. No confundir
esta referencia con una respuesta certificada del proveedor, ni declarar que
componentes no reemplazados son activos oficiales.

Prueba local:
```bash
cd sandbox/creative_factory
python -m unittest -v test_rgb_reference_review.RGBTests test_compositor_blueprint_layers_v2.LayerTests
```

## Proyección gráfica del handoff (v0.9, candidato)

Antes de compilar el wire canónico, construir una proyección visual del
blueprint existente, no un segundo pedido ni otro motor. La skill redacta
instrucciones visuales específicas de la dirección de arte y del componente,
sin estados de aprobación, hashes, resultados de QA, rutas locales ni
metadatos operativos en el texto gráfico. Trasladar las decisiones de
composición y eficiencia espacial a relaciones visuales explícitas y cotejar
que la proyección no las pierda; no trasladar el razonamiento interno.
Aplicar la habilidad v0.12 de redacción gráfica al texto final, conservando
el copy y la asignación de propietarios.

Invocar `graphical_handoff_candidate_v1.build_candidate(plan, projection, files)`.
La proyección contiene direction (las seis dimensiones del preflight),
components (mapa de nombres exactos de componentes NATIVE a su instrucción
visual) y references (source_id, guidance). El constructor vuelve a ejecutar
el preflight, recorre la jerarquía bloqueada, añade el copy literal de cada
componente NATIVE y usa las cajas BOX de cada COMPOSITOR exclusivamente como
reservas limpias. No pedir a Native que redibuje el logo o botón asignado al
compositor. El lienzo, encuadre, dirección de arte y demás componentes siguen
siendo los de la escena completa cuando así se solicita.

Para referencias PNG de arte previo, usar snapshots del negocio con role
previous_generated_visual_reference_only y file_sha256; el mapa files
materializa sus rutas. Verificar los bytes antes de preparar descriptores de
adjunto sin rutas internas. No adjuntar fuentes reservadas solo al compositor.
Las reservas ALPHA y otros roles de adjunto no se soportan en este candidato:
bloquear en lugar de inventar otro formato. No inferir geometría exacta a
partir de la referencia. El alineamiento de la imagen obtenida deberá pasar
QA antes de aplicar la normalización RGB protegida.

El resultado GRAPHICAL_CANDIDATE_SEMANTIC_PENDING contiene payload {prompt,
attachments} y huella de bytes calculada localmente. Mostrarlo literalmente
junto con cada referencia materializada; el hash local no es el wire
canónico de Supabase ni un recibo de Native. El filtro léxico solo detecta
metadatos operativos comunes y no sustituye la revisión semántica de las
instrucciones redactadas. Un revisor independiente debe cotejar el literal
original, la dirección, las fuentes, el copy, los límites de responsabilidades,
las referencias, las reservas y la totalidad del pedido. Nunca presentar
la cobertura estructural como aprobación. Si falla, aplicar el protocolo
de incidencia; no enviar. Solo continuar automáticamente conforme al protocolo de registro previo,
QA y autorización aplicables. El wire canónico sigue siendo necesario para
el flujo gobernado de producción; una prueba gráfica autorizada no acredita
recepción literal ni habilita producción. Este módulo no ejecuta proveedores.

Pruebas locales:
```bash
cd sandbox/creative_factory
python -m unittest -v test_graphical_handoff_candidate_v1.CandidateTests
```

## Cierre de activos oficiales en el resultado

Cuando el pedido requiere un logo oficial, resolver su archivo vigente y
aprobado del negocio mediante el adaptador y materializarlo con el hash de
la fuente. El plan lo asigna a COMPOSITOR como LOCK con operación ASSET;
guardar sus bytes junto al handoff previo, separados de los adjuntos de
Native. Una referencia previa con una marca aproximada no sustituye el
activo oficial. Si no hay archivo aprobado o no coincide su SHA, bloquear.

La imagen de Native es un insumo, nunca se entrega como arte final si
todavía tiene logo inventado, omitido o aproximado. Ejecutar automáticamente
la composición autorizada e inspeccionar la geometría, el resultado visible,
la extracción de la región del logo y su correspondencia con el archivo
oficial transformado y compuesto según el blueprint. El hash del archivo
fuente por sí solo no acredita que aparezca en el resultado. Si no puede
verificarse su presencia e integridad visual, rechazar la entrega. No requerir
un logo para piezas cuyo contrato no lo solicita. No promover candidatos ni
alterar activos oficiales sin autorización.

## Resultado y límites de QA

`LOCAL_TECHNICAL_REVIEW_PASS` solo acredita revisión técnica determinista:
hashes, integridad, geometría, aislamiento de áreas, reproducibilidad y readback.

El recibo SIEMPRE declara:
`native_transmitted=false`, `provider_receipt=null`,
`semantic_qa=NOT_EVALUATED`, `production_approved=false`,
`image_generation_allowed=false`, `router_invoked=false`,
`profile_invoked=false`, `database_written=false`.

No elevar a `QA_PASS`, `NATIVE_DELIVERED` ni `RENDER_AUTHORIZED`.
Un juicio visual/semántico independiente y la recepción del proveedor requieren
contratos y evidencias separados, fuera del alcance autónomo actual.

## Control automático antes y después de cada envío — handoff visible

**Disparadores obligatorios, sin intervención del usuario:**
- Al preparar cualquier handoff operativo entre componentes de la skill:
  mostrarlo y, si el envío ya está autorizado y es técnicamente posible,
  transmitirlo inmediatamente en la misma ejecución, sin esperar respuesta,
  confirmación, mensaje nuevo ni microaprobación del usuario.
- Al detectar cualquier error, rechazo o incumplimiento: solicitar al
  receptor con readback disponible el handoff del mismo intento; para un
  generador de salida solo imagen, recuperar el registro previo y diagnosticar
  el resultado. Comparar y mostrar el diagnóstico
  automáticamente según el protocolo siguiente, sin esperar una instrucción.

La visualización no es una pausa de aprobación. No agrega permisos, no
habilita proveedores ni convierte un resultado de revisión en producción.

### Antes del envío

1. Resolver y congelar el payload y adjuntos exactos del contrato autorizado.
   Para Native, si existe wire canónico, reutilizar sus bytes y SHA sin
   reserializar. Para una prueba gráfica autorizada por separado, conservar
   el payload candidato literal y distinguirlo del wire canónico.
   **Guardar antes de invocar**, mediante `native_transport_capture_v1.archive_pre_dispatch`
   o el almacén gobernado equivalente: bytes del payload, prompt íntegro,
   archivos de referencia, activos protegidos del blueprint y sus pins de
   fuente, hash y lectura posterior. Cada intento tiene un registro nuevo
   e inmutable para el flujo; jamás sobrescribir el anterior. La evidencia
   local de revisión no equivale a persistencia en Supabase: para producción
   usar la ruta gobernada existente. Si falla el guardado, no invocar.
2. **Mostrar al usuario el handoff completo y literal antes de invocar
   al receptor**, en una salida visible intermedia de la misma ejecución.
   Incluir emisor, receptor, negocio, pedido/item/variante, intento si existe,
   prompt íntegro, adjuntos y referencias exactos, SHA del payload y estado
   `HANDOFF_PREPARED_NOT_SENT`. Indicar explícitamente si no hay adjuntos.
   Excluir credenciales, secretos e instrucciones internas del sistema.
   La cabecera del diagnóstico no forma parte del mensaje al receptor.
3. Sin esperar al usuario, comprobar que el contenido a emitir y los
   adjuntos son los mismos que se acaban de mostrar. No regenerar, resumir,
   reserializar ni añadir contexto operativo o QA a un payload que no lo
   incluye. Si cambian, volver a congelar y mostrar el handoff antes del
   envío. Una vista previa no sustituye la evidencia de transmisión.
4. Si ya existe autorización y canal de invocación aplicable, invocar al
   receptor inmediatamente en la misma ejecución. La falta de un eco del
   receptor no bloquea por sí sola una prueba gráfica autorizada de revisión.
   Si el canal solo usa contexto y no acepta un campo literal de prompt,
   guardar el texto funcional preparado y registrar la invocación real y
   sus argumentos expuestos; declarar `HANDOFF_SENT_UNVERIFIED` después de
   una invocación real, nunca afirmar envío byte a byte. No usar esta
   excepción para autorizar producción, cambiar permisos o saltar el QA
   requerido. Si falta autoridad o el canal no puede ejecutar el pedido,
   informar `HANDOFF_NOT_SENT` y la causa.

### Después del envío

5. Mostrar automáticamente el resultado de la invocación y su evidencia
   real: referencia del intento, recibo disponible, huella de bytes emitidos
   cuando el canal la exponga, adjuntos enviados y cotejo con lo mostrado.
   Si hubo una invocación real sin evidencia exacta suficiente, informar
   `HANDOFF_SENT_UNVERIFIED`. Si no hubo invocación, `HANDOFF_NOT_SENT`.
   Nunca presentar el hash preparado como prueba de envío o recepción.
6. Continuar automáticamente con recepción y QA autorizados. Ante fallo
   aplicar el protocolo de readback de abajo en esa misma ejecución:
   solicitar al receptor su handoff funcional exacto únicamente si el canal
   admite readback; cuando el resultado sea solo imagen, recuperar el registro
   previo y comparar el arte. Mostrar divergencias sin esperar otro turno.
   Si el canal no recupera el payload recibido, informar
   `HANDOFF_RECEIVER_READBACK_UNAVAILABLE` y recuperar automáticamente el
   registro previo y evidencia de la invocación. Continuar con el QA técnico
   y visual permitido sobre el resultado real; no inventar evidencia, ni
   reintentar sin resolver las causas de rechazo y respetar la autorización.

**Criterios de aceptación:** (a) vista literal visible antes de invocar,
(b) envío automático sin confirmación intermedia cuando está autorizado,
(c) evidencia de salida visible inmediatamente después, (d) readback
automático ante rechazo, (e) registro previo obligatorio, bloqueo verificable si falta autoridad
   o capacidad, trazabilidad de recepción no verificable cuando corresponda. Una imagen con recibos
o indicadores PASS no satisface estos controles.

Este cambio define el comportamiento obligatorio de la skill; la integración
real con un proveedor sigue condicionada a un canal disponible y autorizado.
No se crea ni invoca Router, perfiles o RUNs de perfil.

## Protocolo obligatorio ante rechazo o incidencia — readback del handoff

**Disparador:** cualquier ERROR, BLOCKED, FAIL, REJECTED o incumplimiento observado
durante la preparación, transporte, generación, composición o QA. No esperar
a que el usuario pida el handoff. Disparar el diagnóstico automáticamente en
la misma ejecución; detener solo la entrega y el reintento no verificado.

1. Identificar etapa, componente emisor y receptor, pedido/item/variante y
   referencia real de la ejecución o intento, si existe.
2. Recuperar el handoff funcional exacto preparado por el emisor y, si hubo
   envío, su evidencia de salida. Mantener referencias, adjuntos y hashes
   originales; no regenerar el prompt.
3. **Si el receptor admite readback, solicitar inmediatamente el handoff
   funcional que recibió en el mismo intento**. Para un generador cuyo
   único resultado es una imagen y cuyo canal no dispone de readback,
   omitir esta solicitud, recuperar el registro previo y evaluar el arte. Mensaje de diagnóstico, no de generación:
   "Devuelve el handoff funcional exacto que recibiste para este intento, sin
   resumirlo, corregirlo ni completarlo. Incluye los adjuntos/referencias
   recibidos y el identificador del intento, si están disponibles. Si no
   puedes recuperar el mensaje exacto, indícalo expresamente. No generes
   otra imagen ni ejecutes otro pedido."
   Usar solo un canal de readback disponible y autorizado. No pedir
   instrucciones internas, credenciales ni datos de otros negocios.
4. Mostrar al usuario ambos handoffs, distinguiendo explícitamente:
   PREPARADO, ENVIADO (solo evidencia de salida) y RECIBIDO (respuesta del
   receptor). Comparar texto/bytes, adjuntos, fuentes y huellas disponibles;
   señalar las diferencias y qué comprobación falló. Una declaración del
   receptor no equivale a atestación del proveedor. No fabricar readback
   ni presentar el handoff de Supabase como si fuera el recibido.
5. Si no hubo envío, informar HANDOFF_NOT_SENT y el último contrato
   disponible. Si no hay canal de consulta o no hay readback del mismo
   intento, informar HANDOFF_RECEIVER_READBACK_UNAVAILABLE y recuperar
   el registro previo. Mantener el rechazo visual/técnico que corresponda,
   no bloquear el diagnóstico ni la revisión por ausencia de eco. Mostrar
   por separado el handoff preparado y la evidencia real disponible;
   nunca inventar un identificador o recibo.
6. Localizar la primera divergencia, corregir solo la etapa responsable y
   conservar la evidencia del intento rechazado. Reintentar únicamente
   dentro de la autorización vigente cuando la causa esté resuelta. No
   elevar permisos de render ni promover QA por el simple hecho de obtener
   el handoff.

**Aceptación del protocolo:** rechazo con ambos handoffs permite comparar;
rechazo sin evidencia de recepción usa el archivo previo y conserva el rechazo; error antes del
envío identifica HANDOFF_NOT_SENT. Un eco local, una imagen con texto PASS
o una respuesta reconstruida no prueba recepción. En todos los casos el
usuario recibe el diagnóstico y handoff disponible sin tener que solicitarlo.

Este es un contrato de actuación de la skill; no agrega capacidades al
proveedor ni activa un transporte nuevo. No invoca Router, perfiles ni sus
RUNs y no cambia permisos o registros de Supabase.

## Ejecución y prueba

```bash
PYTHONPATH=sandbox/creative_factory \
  python sandbox/creative_factory/skill_run_review_v1.py --request /ruta/request.json
PYTHONPATH=sandbox/creative_factory \
  python -m unittest -v sandbox/creative_factory/test_skill_run_review_v1.py
```

Pruebas: positivos, determinismo, no sobrescritura, aislamiento SALY/LF/futuro,
fuentes y tipografías por SHA, mutación de prompt y adjuntos, intento de activar
render, logo alterado, invasión de CTA, JSON duplicado, symlinks, salida no
autorizada y ausencia de efectos de Router/perfiles.

## Extensibilidad

La skill es **una sola** para múltiples negocios. Cada negocio adicional aporta
su contrato fuente y un adaptador probado; el motor, los tests de transporte,
compositor, recibo técnico y QA permanecen compartidos.

Hasta contar con adaptador y pruebas contractuales, la ausencia de fuentes
se trata como **bloqueo**, no como permiso para consultar reglas de otro negocio.
Para integrar posteriormente Router y perfiles se requiere otro lote; aquí no
se implementan ni modifican.
