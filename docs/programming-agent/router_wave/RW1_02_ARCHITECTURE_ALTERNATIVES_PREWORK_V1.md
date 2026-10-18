# RW1-02 — Comparación preliminar de arquitecturas para ACT-0001 (NO DECISIÓN)

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`. **Naturaleza:** PREWORK para RW1-02; **no** inicia el checkpoint RW1-02_C1, no lo declara READY/DONE y no sustituye las dependencias de RW1-01_C2/C3.
**Fecha de fuentes:** 2026-10-17. **Aislamiento:** LF, sin Saly. **Datos de referencia:** 12 necesidades N01–N12 de RW1-01_C1, corpus de 30 oráculos RW1-01_C2, A16Q_C1 ya realizado y fuentes EKB Router/Train.

## 1. Tesis que deben competirse, no aceptarse por consenso

| Alternativa | Mecanismo exacto de derivación | Ventaja hipotética | Riesgo falsable |
|---|---|---|---|
| **A — Router semántico centralizado** | ACT-0001 interpreta modos, roles, positivos/negativos, descompone objetivos, decide especialista y genera la representación de alcance | Mayor precisión inicial si toda interpretación y catálogo son correctos | Agranda la superficie de fallo, acopla reglas de negocio al router, posible regreso del bloqueo de Train y mayor coste de mantenimiento |
| **B — Router mínimo de catálogo** | ACT-0001 resuelve identidad/capacidad del registro y deriva texto original a especialista; éste interpreta exclusiones, multiobjetivos y modo | Núcleo pequeño y potencialmente extensible; aprovecha expertos existentes | Puede seleccionar destino equivocado antes de detectar negaciones, o no reconocer que hay varios responsables; los expertos podrían devolver la solicitud unos a otros |
| **C — Router con sobre mínimo de intención** | ACT-0001 preserva literal+hash, detecta señales mínimas para distinguir modo/no-efecto, objetos incluidos/excluidos y roles tentativos; descubre responsable(s). El especialista decide semántica profunda, alcance y composición; la operación autoriza efectos | Busca equilibrio entre continuidad, prevención de rutas peligrosas y especialización | «Mínimo» puede crecer ilimitadamente o ocultar clasificaciones por palabra si no se congela interfaz y se mide la cobertura |
| **D — Planificador de capacidades/descomposición** | Una capacidad orquestadora gobernada descompone pedidos multiobjetivo, consulta catálogo, compone rutas a varios especialistas, recoge sus salidas; Router queda de entrada y procedencia | Podría resolver pedidos compuestos y extensibilidad sin añadir reglas por cada tipo al Router | Costo de coordinación, nuevo componente redundante, posibles bucles de replanificación y complejidad de autoridad si se vuelve decisor de efectos |

**Ninguna es ganadora todavía.** La alternativa C puede parecer intuitiva a raíz de los errores conocidos, pero favorecerla sin evaluar A/B/D repetiría el sesgo de confirmación. Incluso B puede funcionar si el contrato de descubrimiento encuentra responsable amplio real y el experto está obligado a conservar el literal completo. D solo se justifica si la composición multiobjetivo no puede resolverse con capacidades ya registradas.

## 2. Necesidades que no deben negociarse

1. **Ruta versus efecto:** un `handoff` de exploración no concede write; un bloqueo por ACL o ámbito no elimina el trabajo read-only independiente.
2. **Identidad y procedencia:** mantener solicitud literal, hash, contexto autorizable, fuente/revisión, estado de incertidumbre y responsabilidad seleccionada.
3. **Negaciones y exclusiones:** `ACT-0052` en «no tocar ACT-0052» **no** es un target positivo; debe viajar como exclusión y ser comprobado antes de cualquier efecto.
4. **Varios objetivos:** «crear regla y skill» **no** se convierte silenciosamente en «crear skill». Debe existir derivación compuesta o un responsable competente y registrado que conserve los dos objetivos.
5. **Simulación y consulta:** «simula crear» no ejecuta CREATE. Si hay ambigüedad sobre la entrega final, la resuelve el especialista apropiado sin consulta anticipada innecesaria del Router.
6. **Activos futuros:** ningún tipo nuevo se inventa como ejecutor; se recurre a descubrimiento real de capacidades/relaciones o a un gap verificable.
7. **Frontera Train:** autoridad de migración técnica no depende de una solicitud humana ficticia. Catálogo válido **no** implica alcance ni escritura autorizada.
8. **Regla Router First:** el siguiente consumidor tiene evidencia del mismo pedido; no basta con `READY` o un nombre de perfil tentativo.
9. **No imponer cableado actual:** registries/triggers heredados se evalúan después de comprobar utilidad de la arquitectura objetivo; invariantes de seguridad válidos pueden conservarse aunque se reemplace el acoplamiento.
10. **Sin dependencia circular:** no permitir que una verificación de efecto técnico necesite un `READY_TO_EXECUTE` emitido desde otra interpretación de pedido.

## 3. Falsificadores comunes (misma prueba, cuatro diseños)

| Caso de corpus | Comportamiento requerido | Falsificador material de cada alternativa |
|---|---|---|
| R01–R03, R24 | Investigación sin write, responsable real o capacidad de investigación registrada | BLOCKED terminal sin consumidor, o «inspección» lexical que no encuentra responsabilidad |
| R04–R06 | Simulación/DEMO sin efectos, especialista correcto | Enrutamiento como CREATE con permiso de mutación |
| R07–R09 | Cambio acotado respetando exclusiones | Excluir `ACT-0052` aparece entre targets positivos; deriva a adapter auxiliar como ejecutor por coincidencia lexical |
| R10–R14 | Múltiples objetivos y capacidades | Pérdida de objetivo, selección arbitraria de solo un ejecutor sin composición o conservación en el consumidor |
| R15 | «Modifica eso» sin referente recuperable | Inventar dos responsables; elegir uno sin antecedente; repetir preguntas innecesarias |
| R16 | Dos rutas competentes distintas en fixture declarado | Derivar a cualquiera sin aclaración mínima ni contexto adicional |
| R17–R18 | Referente sí recuperable del contexto autorizado | Pedir de nuevo información ya disponible |
| R19–R22 | Capacidades futuras desconocidas | Inventar skill/perfil o declarar `READY` sin binding; bloqueo definitivo cuando existe responsable de descubrimiento verificable |
| R23, R25 | Migración gobernada frente a pedido de evadir controles | Ruta técnica se rompe por semántica de usuario; o deriva una escritura saltándose autoridad |
| R26–R30 | Separación perfil/sujeto/adapter, evidencia y determinismo | Perfil/adapter equivocado por keyword, permiso no acreditado, salidas inestables sobre mismo snapshot |

**Advertencia metodológica:** los 30 son **oráculos de siguiente paso con fixtures declarados**, no 30 resultados E2E ni 30 pruebas independientes. Solo 21 tienen `context=""`; la evaluación del resto requiere contexto controlado. La observación real 21/21 `BLOCKED` del Router actual tampoco equivale a 21 fallas de seguridad: no autorizar efectos puede ser correcto aun sin probar continuidad.

## 4. Qué medir, sin inventar números

- **Acierto funcional:** destino/responsabilidad registrada y exacta, preservación de múltiples objetivos, exclusiones, modo y texto/hash; errores de derivación versus rechazo de efecto en dimensiones separadas.
- **Continuidad material:** mismo `request_sha256`, identidad de consumidor, recibo de recepción y evidencia de que empezó trabajo permitido. Un JSON con `semantic_handoff` pero sin `semantic_consumer_receipt` no supera esta dimensión.
- **Seguridad:** ningún falso permiso write, ninguna exclusión ignorada, ningún bypass a Train o prewrite, y casos negativos que efectivamente fallen.
- **Extensibilidad:** agregar a un fixture una nueva capacidad y un tipo no nombrado; observar si basta cambiar registro/manifiesto o hay que editar código del Router. Evitar medir solo casos que inspiraron la alternativa.
- **Simplicidad verificable:** número de decisiones duplicadas, fronteras de autoridad, acoplamientos nuevos, consultas repetidas, nuevos estados/catálogos y necesidad real de orquestador adicional.
- **Rendimiento:** medir la solicitud completa de la misma fuente, misma versión y mismo lote con tiempos observados (no inventar p90, costos ni valores de mejora); comparar lecturas por run y reconstrucciones redundantes.
- **Calidad de fallos:** contexto insuficiente, ACL, actualizaciones de catálogos, consumidor no disponible, conexión con Train; comprobar que una falta de una capacidad no detiene trabajo independiente.
- **Independencia y coste:** resultados de una prueba ciega no conocida por diseñadores, esfuerzo de implementación/tránsito y compatibilidad de consumidores que realmente deben funcionar.

## 5. Crítica específica de decisiones anteriores

- **«Solo descubrir y derivar»:** puede perder negaciones relevantes al decidir el destino; es una hipótesis, no regla final.
- **«Router entiende toda la solicitud»:** lleva a expandir un monolito de interpretación; puede repetir el acoplamiento con controles técnicos.
- **«Todo el cableado actual está mal»:** no probado; conservar guardas de seguridad correctas, aunque la ruta que hoy las invoca sea estructuralmente mala.
- **«Todo desconocido a un explorador genérico»:** un explorador inventado es falso READY; solo se puede usar responsable registrado o investigar un gap legítimo.
- **«El Router bloquea hasta comprobar todo»:** detiene tareas de análisis que no requieren ejecución, viola continuidad segura.
- **«Pasó el test Python, por tanto pasa C2 del Router»:** el log dice `shape_only=true`; acredita el validador, NO destinatarios reales.
- **«Vincular GitHub Actions arregla el checkpoint»:** el defecto de autoría redundante de `programacion.fn_engineering_execution_packet_apply_bounded_checkpoint_test_v1` **ya fue reparado** por PR #2881. Los PR #2879/#2882/#2883 integraron el workflow, vincularon `RUN_TEST` y cerraron **solo RW1-01_C2** con recibo material. Esa reparación del pipeline **no demuestra** la arquitectura futura ni continuidad E2E de ACT-0001.
- **«Arreglar un ejemplo equivale a reparar el Router»:** prohibir casos específicos; la reparación debe ser causal y transversal.

## 6. Evidencia actual de fuente

La línea base del Router vivo y los falsificadores contrastables de A/B/C/D están en [`RW1_02_LIVE_SOURCE_BASELINE_AND_COMPETITION_V1.md`](RW1_02_LIVE_SOURCE_BASELINE_AND_COMPETITION_V1.md).

**Cobertura exacta y evaluación offline:** [`RW1_02_EXACT_CATALOG_COVERAGE_AND_OFFLINE_SCORECARD_V1.md`](RW1_02_EXACT_CATALOG_COVERAGE_AND_OFFLINE_SCORECARD_V1.md) documenta 14 de 22 nombres de tipo sin correspondencia `ACTIVE` exacta (no equivale a 14 funciones ausentes) y la interfaz neutral [`compare_rw102_candidate_traces_v1.py`](../../../sandbox/lf_contract_gate_test/router_wave/compare_rw102_candidate_traces_v1.py), que sin trazas devuelve `NOT_EXECUTED`, jamás elige arquitectura por `shape PASS` y no acredita autoridad mediante cadenas del productor. **No hay trazas A/B/C/D ni tiempos verificados todavía.** Lecturas de Supabase 2026-10-17: función Router de 39.602 caracteres, 35 rutas ACTIVE, 16 tipos con ruta ACTIVE frente a 22 tipos distintos no archivados (conjuntos **no equivalentes**), y cuatro solicitudes de control reproducibles pero sin continuidad material demostrada. Son observaciones diagnósticas, no evaluación de prototipos.

## 6. Secuencia verificable y decisión posterior

1. **RW1-01_C2/C3:** fuente/runner real y crítica independiente completan y congelan corpus y referencias; no alargar C2 con obligación de aprobar el Router actual. El hecho de tener 15 negativos de un verificador no sustituye C3.
2. **RW1-02_C1:** leer esta preinvestigación como hipótesis; registrar al menos tres alternativas y falsificadores, comprobar que existe responsable/capacidad para las derivaciones propuestas.
3. **RW1-02_C2:** ejecutar **las mismas** 30 solicitudes y holdouts adicionales sobre prototipos comparables (sin habilitar producción), con consumidores simulados solo para medir forma y material reales para continuidad; fuente congelada para todos los brazos.
4. **RW1-02_C3:** juez independiente, sin observar identidades de brazo, explica pérdidas/costos/fallos. Seleccionar o rechazar arquitectura solo después de esa evidencia; no porcentajes poblacionales con n pequeño.
5. **RW1-03:** versionar ABI, estrategia de transición, tratamiento de consumidores legacy y regla de seguridad de efectos **después** de elegir arquitectura. Ninguna nueva arquitectura puede forzar apagar el Train.

**Criterio de esta entrega:** es investigación preliminar no validada; no se modifica ACT-0001, no se ejecutan cuatro implementaciones, no se elige ganador, no se marca C1 de RW1-02 y no se altera la lista de dependencias registrada.
