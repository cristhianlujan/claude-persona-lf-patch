# LF — Contrato director v2: estrategia, definiciones y reglas PREVIAS a reclasificar
**Fecha:** 2026-10-28 · **Estado:** propuesta técnica versionada para revisión de diseño; no autoriza re-clasificación ni publicación · **PR:** #3269 (draft) · **Ámbito:** Input Governance LF / T-REMED / N-4.

## 0. Cambio de secuencia obligatorio

**STOP RECLASSIFICATION.** El inventario existente es una fotografía de diagnóstico; no es una cola aprobada de reglas a reclasificar. Se suspende cualquier inferencia de alcance a partir de números, familias de categoría o shells hasta cerrar este contrato.

Orden de dependencias: **Estrategia → Definiciones → Normas de evaluación y decisión → Casos adversariales sintéticos → Revisión de roles / contrato → Autorización de metodología → Reclasificación por evidencia → Validación independiente → Integración posterior.**

P00 y los inventarios previos no se borran; solo sirven de línea base para demostrar que el diseño futuro preserva las herencias legítimas y no arrastra herencias incorrectas.

## 1. Objetivo y criterios de calidad

**Objetivo:** que una regla existente o futura se aplique automáticamente a un destino **solo cuando** sus precondiciones, autoridad, estado, consumidor y selector autorizado lo permitan; mantener una cascada contextual dinámica, capaz de incorporar nuevas pantallas sin editar el código.

**Requisitos no negociables:**
1. Ninguna regla se declara global solo por `es_transversal`, frecuencia, mismo shell, categoría o similitud semántica.
2. Herencia **permitida** y reutilizable: un selector ratificado debe alcanzar nuevos destinos compatibles sin reescritura ni asociación física manual.
3. No introducir una taxonomía fija de niveles de negocio ni códigos particulares de reglas en el resolvedor. La jerarquía de autoridad es funcional, **no** un “la pantalla siempre gana”.
4. Contexto base `screen/module/app_shell` existente; otros atributos son **opcionales, demandados por el selector**, con fuente y vigencia. No crear campos para todas las pantallas.
5. Una regla con evidencia o atributo insuficiente no habilita alcance nuevo. El estado de incertidumbre es específico de esa regla; otras reglas independientes continúan.
6. Mantener distintas: regla candidata, regla vigente, permiso de aplicabilidad y permiso de ejecutar/promover cambios.
7. Sin investigación LLM en el camino operativo ordinario. El análisis semántico ocurre al crear/revisar política; el matching efectivo es determinista y acotado.
8. Prohibido eliminar masivamente las herencias existentes sin decisión de preservación o exclusión de cada definición afectada.
9. Toda modificación con impacto transversal exige trazabilidad de versión, owner, competencia, readback y casos negativos.

**Componentes reutilizados (sin nuevos motores):** T-REMED descubre/propone/repara; N-4 valida selectores y compara contra contexto; Curator investiga; Validator comprueba; autoridad funcional/gerencial ratifica cambios de criterio; EKB alerta de precedentes; consumidores ejecutan solo decisiones vigentes y autorizadas. `fn_input_validator_semantic_scope_v1` controla el alcance de validación por familias de Input Governance: **no es** el clasificador de herencia de reglas. No confundir estos contratos.

## 2. Diccionario normativo — términos separados

| Término | Definición exacta | No significa |
|---|---|---|
| **Regla** | Proposición trazable: sujeto, evento, condición, acción/obligación, limitación, consecuencia, fuente y owner | Un título o un registro asociado a muchas pantallas |
| **Política** | Fuente de autoridad que establece valores, prohibiciones, derechos o parámetros, posiblemente compartida | Una regla duplicada con números hardcodeados |
| **Intención** | Propósito funcional y riesgo que la regla busca resolver, interpretado desde fuente y contraejemplos | Coincidencia por palabras clave |
| **Naturaleza** | Tipo de efecto que produce la regla, con su criticidad y fuerza normativa | Alcance geográfico o en número de pantallas |
| **Aplicabilidad** | Evaluación de las precondiciones del destino/consumidor bajo selector autoritativo | Estado `VIGENTE`, marca transversal o vínculo explícito por sí solos |
| **Ámbito / scope** | Conjunto contextual de destinos autorizados donde la regla puede aplicar | Lista fija de cinco niveles o permiso universal |
| **Herencia** | Reutilización dinámica de una regla por descendencia/contexto **cuando coincide su selector autorizado** | Copia ciega de toda regla del ancestro |
| **Cascada** | Composición de reglas aplicables por capacidades y relaciones canónicas, con manejo de colisiones | Precedencia “screen > module > shell” automática |
| **Contexto canónico** | Datos del destino obtenidos de fuentes autorizadas, con versión/procedencia y solo atributos requeridos | Todos los atributos posibles obligatorios para cada pantalla |
| **Candidato** | Hipótesis/regla/selector a revisar que NO es fuente de ejecución operativa | Un permiso parcialmente concedido |
| **Conflicto** | Dos efectos aplicables incompatibles o una excepción que viola una restricción superior | Dos reglas que coinciden sin más |
| **Excepción** | Restricción o desviación documentada del alcance previamente autorizado, con owner y vencimiento/revisión | Un override creado automáticamente por especificidad |
| **Autoridad** | Capacidad trazable de una persona/órgano o política para aprobar un tipo y alcance de decisión | Ser quien escribió el texto, puntuación alta o permiso SQL |
| **Evidencia** | Fuente primaria/decisión/contrato/negativo cuya procedencia y versión pueden verificarse | Cantidad de apariciones o narrativa del propio agente |
| **UNKNOWN** | Condición no demostrable por atributo ausente, ambiguo, de fuente no confiable o vencida | Una negación verdadera; tampoco es evidencia de FALSE |
| **HOLD** | Resultado de no ampliación de alcance operativo de la regla, pendiente de prueba o decisión | Bloqueo automático de todas las pantallas y familias |

**Matiz de seguridad:** cuando una regla obligatoria es precondición de una operación sensible, `UNKNOWN` puede impedir **esa operación** de acuerdo con su política superior. No significa apagar Input Governance completo.

## 3. Clasificación multiaxial — se define antes de leer más datos

No se debe asignar una única etiqueta “global/local” con un score. La ficha de regla debe cubrir **dimensiones independientes**:

| Eje | Pregunta obligatoria | Contrato de salida conceptual (extensible, no enum DB nuevo) |
|---|---|---|
| A. Naturaleza funcional | ¿Qué comportamiento prescribe? | Efecto / evento / sujeto / salida estructurados. Las familias (sesión, seguridad, validación, experiencia, legal, etc.) son etiquetas analíticas, no condiciones de ejecución ni lista exhaustiva |
| B. Fuerza normativa | ¿Es restricción obligatoria, requisito condicionado o recomendación/experimento? | Mandatoriedad + fuente normativa + potestad de excepción; ninguna categoría exonera evidencia |
| C. Alcance propuesto | ¿Sobre qué propiedades comprobables de destino/consumidor depende? | Selector candidato con condiciones positivas, negativas, exclusiones y procedencia; puede ser muy amplio si una fuente lo autoriza explícitamente |
| D. Efecto de composición | ¿Se acumula, especializa, sustituye, contradice o duplica a otra? | Relación con IDs de reglas/políticas y evidencia comparativa |
| E. Autoridad y riesgo | ¿Quién puede aprobar, veto o modificar la regla? ¿Qué daño causa aplicarla donde no corresponde o no aplicarla donde sí? | Owner, autoridad especializada, criticidad, riesgo bidireccional, policy refs |
| F. Evidencia/madurez | ¿Qué está probado, propuesto, pendiente o contradicho? | Fuente, versión, actualness, casos +/−/UNKNOWN; estado de decisión separado del estado técnico |

Una regla puede ser **obligatoria y condicional** a la vez; o **reutilizable entre productos y local a un tipo de proceso**. Un título de “transversal” no captura estas dimensiones. La ficha puede añadir nuevas etiquetas con un proceso de extensión del contrato; nunca añadir operadores o estados al runtime por un caso aislado sin demostrar necesidad.

### Matriz de decisiones por resultado del análisis

1. **Ya autorizada y condición demostrada:** N-4 aplica automáticamente; no pide a gerencia aprobación individual por cada nueva pantalla equivalente.
2. **Candidata con fuente clara, sin conflictos:** Curator propone selector; Validator comprueba positivos/negativos; owner ratifica ampliación según competencia.
3. **Fuente incompleta/atributo ausente:** HOLD de la propuesta de alcance; investigación puntual de fuente.
4. **Contradicción o política superior:** bloqueo de ampliación; revisión por autoridad competente; puntuación no prevalece.
5. **Duplicado equivalente comprobado:** proponer unificación/reutilización, preservar IDs de procedencia y efectos; sin borrado silencioso.
6. **Nueva naturaleza no contemplada:** activar procedimiento de evolución del contrato (sección 9); no reclasificar forzadamente.

## 4. Comparación semántica — contra qué y en qué orden

El Curator extrae una ficha `sujeto/evento/acción/precondiciones/exclusiones` de la definición **y verifica**:
1. Fuente de la regla y decisiones/políticas superiores vigentes.
2. Finalidad y acciones reales del destino, a partir de contratos y contexto canónico, no nombres.
3. Positivos donde existe precondición demostrada.
4. Negativos donde la precondición no se cumple, y escenarios de dato ausente.
5. Contradicciones con otras reglas y excepciones autorizadas.
6. Precedentes EKB, incidencias y resultados de validadores.
7. Revisión adversarial independiente buscando falsar la hipótesis preferida.

**Resultado de autoría:** alternativas razonadas, selector candidato, atributos puntuales exigidos, contrapropuesta, riesgos de error, fuentes citables y conclusión propuesta. **Nunca selector ACTIVE por la sola opinión del modelo.**

**Resultado de consumo:** N-4 evalúa determinísticamente el selector ratificado, el consumer permitido, versión, estado y el contexto real; el runtime actual es booleano; la propuesta distingue MATCH, NO_MATCH y UNKNOWN **en diagnóstico** sin afirmar que v1 lo tenga implementado.

## 5. Reglas de herencia, composición y conflicto (normas propuestas para ratificación)

| ID | Norma | Verificación negativa obligatoria |
|---|---|---|
| H01 | Ningún enlace por frecuencia/categoría/shell autoriza herencia efectiva nueva | Regla muy usada de onboarding no alcanza login por popularidad |
| H02 | Selector ACTIVE/versionado y consumer autorizado son precondiciones de expansión | CANDIDATO/UNRESOLVED/nonmatch nunca generan vínculo operativo nuevo |
| H03 | La nueva pantalla compatible hereda sin editar código | Pantalla incompatible no hereda al estar en mismo módulo |
| H04 | Vínculos explícitos históricos se tratan como evidencia/patrimonio a auditar, no como autoridad final | No promover alcance por existir vínculo físico sin selector |
| H05 | Contexto de una regla se consulta solo si esa regla lo requiere | Falta de sesión no invalida una regla visual independiente |
| H06 | Valor ausente o fuente inválida jamás satisface condición de negación | `NOT(NULL)` no se transforma en TRUE |
| H07 | Acumular reglas compatibles por efecto; duplicado real puede deduplicarse con prueba de equivalencia | Dos reglas visual/seguridad no compiten por puntuación |
| H08 | Misma acción con resultados o límites incompatibles requiere política de precedencia expresamente autorizada, en su defecto HOLD | El orden de SELECT o la etiqueta “más específica” no decide |
| H09 | Reglas locales no pueden debilitar controles obligatorios superiores; una excepción requiere dueño competente | Override local no elimina MFA/política legal |
| H10 | Gerencia decide cambios de cobertura, excepciones y conflictos de competencia; no cada match de N-4 | Ningún SCORE 6/6 se convierte en recibo de gerencia |
| H11 | Estado de publicación técnico ≠ autoridad de aplicabilidad | Promover regla `CANDIDATO→VIGENTE` no la convierte en global |
| H12 | Estados/lifecycles de pantalla y reglas deben respetarse conforme consumidor (operativo/análisis/histórico) | Pantalla duplicada/inactiva no recibe reglas como acción operativa |
| H13 | Las decisiones/selecciones son reproducibles y auditables en su versión | Cambiar evidencia/owner invalida un approval de alcance viejo |
| H14 | No crear motores, capas o pipelines paralelos cuando N-4, T-REMED, Curator/Validator u owner puedan resolverlo | Ninguna extensión se admite sin caso de falla reproducible |
| H15 | Todo matching debe mantener límites de consumer y policy refs | Consumidor no permitido y policy ref CANDIDATO no ejecutan |

**Precedencia:** autoridad normativa > competencia legal/seguridad aplicable > permiso funcional delegado > especificidad contextual, con la aclaración de que “mayor autoridad” debe derivarse de **fuente registrada** y no de una lista de categorías en el motor. Se permite acumular obligaciones compatibles. Si el vínculo jerárquico no está demostrado, HOLD, no inventar prioridad.

## 6. Evaluación y scoring — rol limitado

**Primero gates determinísticos** (estado, autoridad, selector, fuente y competiciones/vetos); luego hipótesis semánticas; finalmente puntuación ligera para **ordenar investigación y seleccionar qué presentar a revisión**.

Se conserva provisionalmente la rúbrica 0–2 en semántica reutilizable, expresabilidad de condiciones y fuerza de evidencia (0..6), pero **sin umbral de autorización, sin interpretar 6 como 100% ni elevarlo automáticamente a global**. La elección técnica no termina por el score: requiere positivos/negativos, confianza en la fuente, posible revisión independiente y aprobación competente si se modifica alcance. Los valores 5/6 y delta 2 del helper actual siguen siendo hipótesis no calibradas.

**Empate / margen estrecho:** HOLD de la expansión y revisión humana de alternativas y evidencias. Una diferencia muy marcada tampoco habilita una política si falla un veto. Se medirán tasas de falsos positivos, falsos negativos y abstención sobre casos oro, por nivel de riesgo.

## 7. Decisión de gerencia y recibos

La ficha a elevar cuando se crea/amplía/restringe alcance debe contener: ID+versión+hash de regla; propósito y efecto; status; owner; comparación A/B; fuentes y vigencia; atributos puntuales; alcance previsto, exclusiones y consecuencias; impacto **estimado, no autorizado**; reglas superiores/conflictos; pruebas positivas/negativas/UNKNOWN; score auxiliar; recomendación; decisión expresa, identidad y competencia; condiciones; fecha de reevaluación y recibo vinculado al selector versionado.

Resultados propuestos: **APROBAR / APROBAR_CONDICIONADO / RECHAZAR / PEDIR_EVIDENCIA / ESCALAR**. Son acciones conceptuales a **homologar** con el contrato de autorización existente, no nuevos enums en SQL.

Se verificó que existen `programacion.human_decisions`, `programacion.authority_attestations`, `lf_ops.system_audit_human_decisions` y logs de decisión. No se ha demostrado que cualquiera sea responsable del scope de N-4; `human_decisions` requiere ejecución, head y recibo. **No reutilizar ni crear tabla sin comprobar competencia/contrato**. Gerencia de negocio no reemplaza veto de Seguridad/Legal, ni el owner técnico sustituye decisión funcional.

## 8. Pipeline de diseño (offline) vs ejecución (online)

**Definición / actualización de alcance (offline):**

`INICIAR → EKB+SOURCE_CURRENTNESS → CLASIFICAR_NATURALEZA → IDENTIFICAR_FAMILIA/SITUACIÓN → INVESTIGAR_EVIDENCIA → HIPOTESIS_ALTERNATIVAS → VALIDAR_ATRIBUTOS/NEGATIVOS → ANALIZAR_CONFLICTOS → PRIORIDAD_ASESORA → VALIDATOR_INDEPENDIENTE → DECISION_OWNER/GERENCIA_SI_APLICA → REGISTRO_RECIBO → PROPUESTA_PUBLICACION`.

El contrato de cada paso incluye input/source/version, resultado, motivo de skip/HOLD, evidencia y siguiente permitido. No se confunde con Stage 1/2 del Router ni con las etapas ya existentes de selección determinista→semántica de familias de IG.

**Consumo efectivo (online):**

`CONSUMER_AUTORIZADO → SELECTOR_GOBERNADO_VIGENTE → ATRIBUTOS_MINIMOS_VERIFICADOS → MATCH_N4 → CONFLICTOS_PREDETERMINADOS → REGLAS_EFECTIVAS → CONSUMIDOR`.

No LLM/gerencia/investigación EKB en el camino normal. La publicación posterior requiere un carril gobernado; en este PR no se modifica Supabase ni Router.

## 9. Cómo incorporar categorías y reglas nuevas durante el futuro análisis

**Descubrimiento no significa modificación.** Si la investigación revela una clase no representada o una regla nueva:
1. Generar `MODEL_GAP` con evidencia del caso, ejemplos positivos/negativos y falla del contrato actual.
2. Determinar si es solo un nuevo **valor de datos / etiqueta** (preferible), una nueva condición expresable con N-4 existente, o una modificación semántica mayor que requiere versionado de contrato.
3. Buscar equivalencia con fuente/política/regla existente; priorizar reutilización y especialización antes de duplicar.
4. Evaluar riesgo, owner, efecto en reglas y consumidores existentes y costo incremental.
5. Crear propuesta en rama dev, pruebas de no regresión y decisión de autoridad. **No modificar retroactivamente la clasificación ya analizada** sin versionarla.
6. Solo tras aceptación del modelo revisado volver a ejecutar los casos afectados (no todo el inventario indiscriminadamente).
7. Nunca fabricar aprobaciones, extender scopes o modificar reglas por inferencia en ausencia de autorización.

**Regla de extensibilidad:** la taxonomía del análisis evoluciona por datos gobernados y versiones; el motor de coincidencias no incorpora condiciones específicas de un negocio en duro.

## 10. Definición de listo ANTES de reclasificar

Gate `PRECLASS_READY` solo cuando: estrategia y glosario revisados; H01–H15 ratificadas; autoridad responsable de cada decisión identificada; contrato de ficha y criterios de evidencia completos; casos adversariales sintéticos ejecutados; conflictos y UNKNOWN manejados; plan de cambio de taxonomía aprobado; criterios de aceptación medibles; auditor independiente valida el método; dependencias de SQL candidato revisadas. **Hasta entonces: NO_RECLASSIFY / NO_CHANGE_SOURCE_OF_TRUTH / NO_CUTOVER.**

**Referencias:** EKB `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`; funciones vigentes N-4 y T-REMED verificadas en solo lectura el 28-oct-2026; NIST SP 800-162 (ABAC, actualizada 2019), OMG DMN (composición y colisiones), OPA Policy Testing (tests), exclusivamente **como criterio metodológico**.
