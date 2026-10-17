# OLA 01 — Arquitectura futura de ACT-0001 (LF)

- **Plan canónico propuesto:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`
- **Workstream:** `WS-LF-ROUTER-ARCHITECTURE-WAVE-V1`
- **Ámbito:** Libertad Financiera ACT-0001, consumidores y operación gobernada; **no** Saly.
- **Autoridad:** `SUPER_ADMIN`; cambios de datos solo vía `ACTUALIZACION_DB_LF → Migration Merge Train`.
- **Estado inicial deseado:** 6 unidades BACKLOG, 18 checkpoints PENDING; no ejecución ni cierre reclamados.
- **Alcance del registro:** planificación, sin escribir código Router, habilitar perfiles, efectuar producción, conceder excepción a Train o declarar C2/C3 aprobados.

## Por qué una ola nueva y no duplicar A16Q

`PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A16Q` tiene C1 DONE y C2/C3 PENDING. A16Q documenta arquitectura y consumidor de **análisis del Agente de Programación**; esta ola cubre el **producto transversal Router** actual y futuro. Reutiliza su inventario, EKB y baseline, registra una relación `RELATED` con A16Q y no requiere cerrar A16Q para iniciar RW1-01. No reabrir C1, no contabilizar su DONE como prueba de esta ola, no retirar ni sustituir A16Q.

## Método

Orden normativo: **necesidades presentes y futuras → arquitecturas rivales y falsificadores → decisión arquitectónica → contrato → implementación mínima → consumidor real → aseguramiento independiente**. Las conexiones actuales son evidencia a evaluar, no el estándar de diseño. No basta con contar `BLOCKED`: comprobar continuidad y seguridad por separado. La elección no presupone que el Router deba tener semántica propia, ni que el especialista resuelva todas las ambigüedades; se decide en RW1-02.

## Unidades, dependencia y checkpoints

| Unidad | Objeto | C1 | C2 | C3 | Depende de |
|---|---|---|---|---|---|
| RW1-01 | Necesidades y aceptación futura | Recuperar necesidades, EKB, A16Q_C1 y fuente vigente; declarar supuestos y sesgos de selección sin repetir el inventario. | Construir una matriz trazable de necesidades y escenarios positivos, negativos, exploratorios, multiobjeto y futuros, con expected behavior independiente del sistema actual. | Crítica independiente de cobertura y sesgos: refutar omisiones y evitar sobreajuste a las once pruebas iniciales. | A16Q RELATED (no gate) |
| RW1-02 | Competencia de arquitecturas | Releer únicamente inventario y restricciones necesarios; identificar tres alternativas reales y sus premisas falsables. | Ejecutar evaluación homogénea de alternativas sobre la matriz RW1-01, incluyendo solicitudes nunca usadas para diseñarlas y coste de nuevas capacidades. | Crítico adversarial independiente selecciona o rechaza arquitectura con falsificadores, omisiones y costes; ninguna aprobación por consenso. | RW1-01 REQUIRES |
| RW1-03 | Contrato y estrategia de transición | Precisar contratos de superficie, consumidores, permisos y EKB estrictamente afectados por la arquitectura ganadora; reutilizar mapeo A16Q. | Especificar ABI, contexto mínimo y handoff íntegro, responsabilidad de aclarar, seguridad pre-efecto, compatibilidad y migración/corte sin doble Router. | Revisión independiente de contrato con falsificadores de ruptura de Train, prompts sintéticos, restricciones negativas, fuentes obsoletas y consumidores legacy. | RW1-02 REQUIRES |
| RW1-04 | Refactor transversal del núcleo ACT-0001 | Congelar head/ledger/source SHA y regresiones; desglosar diffs mínimos necesarios de arquitectura sin cambiarla para acomodar tests. | Aplicar implementación por operaciones canónicas y migraciones exactas; prueba positiva/negativa a nivel contrato y rollback. | Contraste independiente de diseño vs código, comportamiento invariante de seguridad, alcance y no-regresión bajo fuente actual. | RW1-03 REQUIRES |
| RW1-05 | Consumidores y recorrido extremo a extremo | Releer consumidores realmente aplicables y A16Q_C2; comprobar qué contratos y receipts faltan tras el refactor, sin duplicar inventario. | Integrar y ejecutar rutas reales con conservación del texto/hash, scopes positivos/negativos, consumidores atestados y efecto autorizado o sin efecto según modo. | Verificación independiente de no-bypass, doble objeto, ausencia de preguntas redundantes, Train reserva/aplica/cierra y permisos de read-only. | RW1-04 REQUIRES |
| RW1-06 | Validación independiente y decisión de cierre | Congelar versión exacta, corpus independiente/holdouts y umbrales de fallo antes de evaluar, preservando separación del implementador. | Ejecutar corpus funcional, nuevos tipos y modos, preguntas, negativos de autorización, regresiones de consumidores y mediciones de overhead completas. | Juez independiente contrasta resultados, EKB, recibos y desviaciones; PASS/FAIL/GAP explícito sin promoción por declaración. | RW1-05 REQUIRES |

## Aceptación por unidad

### RW1-01: Necesidades y aceptación futura

**Objetivo:** Definir resultados observables de derivación, aclaración, multiobjeto, simulación y extensibilidad sin asumir el cableado actual.

**Salida:** Matriz congelada de necesidades actuales/futuras con oráculos de aceptación, riesgos, negativos y caso desconocido.

**Cierre válido:** Matriz de necesidades completa y adversarial, oráculos versionados, ningún requisito derivado de un bloqueo observado por sí solo.

### RW1-02: Competencia de arquitecturas

**Objetivo:** Comparar críticamente por lo menos tres diseños, entre ellos Router mínimo con especialista semántico, Router con clasificación mínima y derivación compuesta, sin imponer uno de antemano.

**Salida:** ADR comparativa con medidas de simplicidad, continuidad, seguridad, extensibilidad, rendimiento, fallos y compatibilidad de consumidores.

**Cierre válido:** Arquitectura elegida mediante evidencia comparativa y falsificadores, no por conservar código ni por complacer una propuesta previa.

### RW1-03: Contrato y estrategia de transición

**Objetivo:** Congelar separación entre derivación, intención transportada y autorización, junto con interfaces y migración compatible solo cuando la compatibilidad sea legítima.

**Salida:** Contrato versionado de entrada/salida, roles, composición, aclaraciones, autoridad, errores y plan de transición/reversión.

**Cierre válido:** Contrato firmado por pruebas de consistencia, transición sin callejón circular de Train ni permiso de escritura inferido de discovery.

### RW1-04: Refactor transversal del núcleo ACT-0001

**Objetivo:** Implementar únicamente los cambios transversales justificados por RW1-01..03, sin regex por caso, segundo Router, parches laterales o activación no autorizada.

**Salida:** PRs gobernados del contrato/router mínimo más suite reusable; fuente versionada, recibos CI/PASE/Train y readback cuando haya DB.

**Cierre válido:** El código reproduce el contrato objetivo, CI/PASE/Train/readback comprobados donde correspondan, sin claims de C2 E2E ajenos.

### RW1-05: Consumidores y recorrido extremo a extremo

**Objetivo:** Asegurar derivación real a responsables y operación gobernada sin confundir adición de ruta con permisos de efectos.

**Salida:** Trazas reales Router→especialista→operación→evidencia para modos representativos y canarios de continuidad, incluyendo Train.

**Cierre válido:** Consumidores y Train acreditados end-to-end con identificadores/RAW/readback del mismo request; no PASS por simulación o receipt aislado.

### RW1-06: Validación independiente y decisión de cierre

**Objetivo:** Decidir con evidencia si la arquitectura satisface necesidades presentes y futuras, permite avance y no rompe seguridad, sin GOLDEN automático.

**Salida:** Informe adversarial, métricas de continuidad/derivación y seguridad, matriz de hallazgos, condiciones de cierre y disposición gobernada.

**Cierre válido:** Todos los checkpoints acreditados con evidencia real y decisión independiente; si hay defectos, reparación causal transversal y nueva prueba específica, no campañas indefinidas.


## Prevención de regresiones y autoridad

1. Cada C1=fuentes y alcance acreditables; cada C2=artefacto/resultado real según naturaleza; cada C3=crítica independiente y negativos materiales. C2 y C3 no se autovalidan ni heredan PASS del paso previo.
2. Todo checkpoint debe tener `action_spec_v3`, `source_pack_v2`, consumidor y proveedor material actual antes de pasar a READY para ejecución. **El alta de esta ola no implica esa admisión**.
3. Toda mutación futura via PR→CI→PASE→Train/Operation según naturaleza→Post-PASE→readback; no apagado de controles ni nueva tabla/motor de Router.
4. El Router decide derivación; la autoridad de efecto se valida en la operación/consumidor. Cuestionar críticamente si el Router necesita comprensión semántica propia en lugar de fijarlo dogmáticamente.
5. Integrar requerimientos abiertos/relevantes del [RFC #2872](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2872), sin asumir que ese borrador sea arquitectura ya aprobada técnicamente.
6. Incluir casos de solicitud exploratoria, DEMO parcial/completo, multiobjeto, negación, exclusions, nuevos activos, preguntas necesarias/no necesarias y ejecución Train.
7. Medir progresos globales y por unidad usando filas reales. No terminar con checklists que puedan crecer indefinidamente: cada defecto se clasifica como blocker material, gap residual con owner, o descartado con razón.

## Registro y continuidad

La migración crea `programacion.engineering_workstreams`, 6 `engineering_work_items`, 6 `engineering_plan_units`, 18 `engineering_work_checkpoints`, dependencias secuenciales y un evento `PLAN_SNAPSHOT_DETALLADO` con aceptación falsa. Los checkpoints comienzan PENDING y la implementación arranca **solo** después de su propia admisión de fuente/operación. Checkpoint y ejecución se cierran con recibos reales; nunca por el mero merge de la migración.

Reutilizar EKB: `LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002`, `LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002`, `LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003`, `CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL`. Evidencia actual: PRs #2867, #2868, #2870, #2872 y A16Q_C1.

