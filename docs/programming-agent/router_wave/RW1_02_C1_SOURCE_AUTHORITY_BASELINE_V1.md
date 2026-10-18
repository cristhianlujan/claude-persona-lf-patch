# RW1-02_C1 — Fuentes, autoridad y baseline neutral para competencia de arquitecturas

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1` · **Unidad:** `RW1-02` · **Checkpoint:** `RW1-02_C1`  
**Naturaleza:** congelación de fuentes y criterios comparativos. **No selecciona arquitectura, no ejecuta Router runtime, no autoriza efectos ni producción.**

## 1. Pregunta de C1

¿Qué fuentes son autoridad para comparar arquitecturas de ACT-0001 y qué medidas deben aplicarse de forma idéntica a todos los candidatos antes de que C2 produzca evidencia?

El comportamiento actual es **baseline diagnóstico**, no oráculo. El RFC #2872 es **propuesta abierta**, no arquitectura aprobada. RW1-01 aporta necesidades/oráculos de contrato, no certificación del Router runtime.

## 2. Fuentes congeladas y alcance probatorio

| ID | Fuente | Identidad observada | Demuestra | No demuestra |
|---|---|---|---|---|
| S01 | `docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md` | blob `4bb64d568c3f005cf454fb223b4a5ed699c34504` | Objetivo RW1-02: comparar al menos tres diseños; dimensiones exigidas; no preselección | Ganador |
| S02 | `RW1_01_C1_NEEDS_SOURCES_AND_BIASES_V1.md` | blob `89aeae9e3116ebee9c2f547c2f41c4f2ba23c69d` | N01–N12 y sesgos B01–B10 independientes de la solución | Que el Router actual satisfaga N01–N12 |
| S03 | `ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md` | blob `28e020ba05721892524bfc7971cd7c0f3a8f9878`; A16Q_C1 `DONE` | Inventario reusable de Router, consumidores, perfiles/adapters y brechas | E2E actual o arquitectura objetivo |
| S04 | `RW1_01_C3_INDEPENDENT_VERDICT_V2.json` | blob `b4c1fab848b2d98a56f12bc5475103bddce623bf` | Contrato/oráculo local RW1-01 superó revisión independiente | Router runtime, producción o GOLDEN |
| S05 | Evento `public.lf_eventos/21263` | `PLAN_SNAPSHOT_DETALLADO`; `acceptance_declared=false` | La ola existe y no autoacepta sus unidades | PASS de RW1-02 |
| S06 | EKB Router | 7 códigos revalidados en C1 | Fallos históricos y prevención reusable | Obligación de conservar el cableado que produjo los fallos |
| S07 | PR #2872 | estado `open`; head `921518bdc0ba5cd3ce462973af51fb5141c90b49` | Hipótesis de diseño y transición a desafiar | Autoridad canónica o decisión de arquitectura |
| S08 | RW1-01 / work item 1127 | C1/C2/C3 `DONE`; work item `DONE` | Dependencia previa satisfecha | Resultado de la competencia RW1-02 |

**Main observado al congelar C1:** `f180b3d3bd2718bfad1ca5d0ecec4971e6f1bdf7`.

## 3. EKB obligatorio reutilizado

1. `LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001`: una negación no puede convertirse en orden positiva.
2. `LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002`: la fidelidad a intención/alcance debe existir antes del primer efecto.
3. `LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002`: multiobjeto/condiciones no pueden perderse ni volverse falso READY.
4. `LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003`: target tipado es candidato de discovery, no autoridad.
5. `LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005`: sujeto, ejecutor y adapter son roles distintos.
6. `LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003`: reconocer pantalla no debe saltarse discovery de responsabilidad.
7. `CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL`: limitación del conector RO no equivale a imposibilidad funcional global.

C1 usa estas entradas como **restricciones y falsificadores históricos**, no como recetas de implementación.

## 4. Arquitecturas a competir en C2

### A — `MIN_ROUTER_SEMANTIC_SPECIALIST`
ACT-0001 hace discovery de sujetos/capacidades/responsabilidades, preserva literal/contexto y deriva a un especialista semántico gobernado. La semántica profunda y la composición quedan fuera del Router; la autoridad de efecto permanece en operación/consumidor.

**Riesgo a falsificar:** crear un “especialista universal” que se vuelva segundo Router o cuello de botella.

### B — `MIN_CLASSIFIER_COMPOSITE_DERIVATION`
ACT-0001 realiza clasificación mínima de modo/rol suficiente para derivar y puede producir una composición de múltiples responsables cuando hay varios objetivos. No decide detalle de implementación ni autoridad de efecto.

**Riesgo a falsificar:** que la clasificación mínima vuelva a ser lexical, pierda negaciones o no pueda componer responsabilidades sin hardcoding.

### C — `BOUNDED_SEMANTIC_ROUTER`
ACT-0001 incorpora una capa semántica acotada para estructurar objetivos, exclusiones, condiciones y ambigüedad de derivación antes del handoff, sin ejecutar ni autorizar efectos.

**Riesgo a falsificar:** sobrecargar ACT-0001, duplicar lógica de especialistas, aumentar latencia/acoplamiento o convertir interpretación probabilística en autoridad.

### D — `CURRENT_HYBRID_BASELINE` (control, no favorito)
Topología vigente lexical/registry/hints y guards existentes, medida únicamente como baseline. No recibe preferencia por compatibilidad ni penalización automática por ser legado.

**Riesgo conocido:** los EKB muestran false READY, mezcla de roles y problemas con negaciones/hints; C2 debe medir, no asumir que todos persisten.

**Regla:** A, B y C son candidatos elegibles; D es baseline de control. C1 no declara ganador ni ranking.

## 5. Matriz neutral de medición para C2

Todos los candidatos deben recibir **el mismo corpus, fuentes y revisión**.

| Dimensión | Medida neutral | Mejor dirección | Prohibición de interpretación |
|---|---|---|---|
| Fidelidad | objetivos/exclusiones/condiciones preservados; false READY / false BLOCK | cero pérdida / cero falsos positivos materiales | No usar “se parece al código actual” como evidencia |
| Continuidad | solicitudes que progresan a responsable seguro sin pregunta innecesaria; trabajo read-only que continúa cuando write está bloqueado | mayor continuidad correcta | No contar write bloqueado como fracaso de derivación |
| Seguridad | efectos no autorizados, hints convertidos en autoridad, exclusiones violadas | cero | No premiar bloquear todo |
| Extensibilidad | activo/tipo/capacidad nueva resuelta sin patch específico; gap declarado cuando no hay responsable | más casos resueltos sin hardcode | No inventar ejecutor |
| Simplicidad | hops, componentes con decisión, contratos nuevos, dependencias tocadas | menor con igual corrección | No reducir guards necesarios |
| Rendimiento | latencia por etapa, llamadas/consultas, recomputaciones, p50/p95 cuando la muestra lo permita | menor | No inferir percentiles con muestra insuficiente |
| Fallos | propagación/captura de error, recuperación segura, circularidad Train | fallos contenidos, sin dead-end | No ocultar 42501 como fallo funcional |
| Compatibilidad | consumidores/receipts/Train que siguen siendo válidos o requieren migración explícita | mayor compatibilidad legítima | No conservar ABI roto por inercia |
| Determinismo | misma entrada+contexto+revisión → misma decisión de autoridad/ruta | idéntico donde sea autoridad | Texto libre no necesita identidad byte-a-byte |

## 6. Corpus mínimo que C2 debe cubrir

Reutilizar N01–N12 de RW1-01 y, como familias mínimas: lectura/inspección; derivación con requisitos incompletos; aclaración material; multiobjeto; simulación; negación; exclusión explícita; activo/tipo nuevo con y sin responsable; perfil/adapter READ_ONLY; DEMO parcial/completo; Train; consumidor legado; hints manipulados; determinismo; stale/currentness; solicitud con trabajo independiente que puede continuar.

C2 debe añadir falsificadores para cada arquitectura sin alterar el oráculo entre brazos.

## 7. Autoridad y fronteras

- **Supabase:** autoridad para estado de work items/checkpoints, EKB y objetos de gobernanza.
- **GitHub main/blob:** autoridad para artefactos y código versionado.
- **PR #2872:** fuente de hipótesis solamente mientras siga abierto/no canónico.
- **ACT-0001:** decide derivación según el contrato que resulte elegido; no recibe autoridad de efecto por C1.
- **Consumidor/operación:** autoridad de efecto se valida independientemente al punto de efecto.
- **Input Governance:** adapter de recepción cuando aplique; no selector universal.
- **Train:** ruta técnica separada; no simular una solicitud humana para fabricar autorización.

## 8. Criterio de cierre de C1

C1 puede cerrar únicamente si se verifica materialmente:

1. RW1-01 está 3/3 `DONE` y su work item está `DONE`.
2. A16Q_C1 se reutiliza como inventario y no se repite.
3. Las 7 entradas EKB existen con causa y prevención.
4. Evento 21263 existe y mantiene `acceptance_declared=false`.
5. Las fuentes Git S01–S04 tienen los blobs congelados indicados.
6. Hay al menos tres candidatos elegibles y un baseline separado.
7. Las métricas son comunes y no contienen ranking/ganador.
8. RFC #2872 se marca explícitamente no canónico.
9. No se ejecutó Router runtime ni se modificó producción.
10. C2 y C3 permanecen PENDING.

**Salida C1:** baseline versionado para que C2 pueda competir arquitecturas sin sesgo de cableado. No constituye ADR final.
