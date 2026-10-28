# IG LF — Auditoría de pendientes atómicos del PR #3269 (28-oct-2026)

> **REORDENAMIENTO DE TRABAJO (2026-10-28):** Antes de cualquier reclasificación se deben definir y validar estrategia, glosario, reglas de evaluación, autoridad y conflictos, con ensayos sintéticos. Los inventarios P00/P07 son solo evidencia histórica; **NO_RECLASSIFY** hasta completar y ratificar G0–G4. Contrato: [estrategia, definiciones y reglas v2](./IG_N4_TREMED_CONTRATO_ESTRATEGIA_DEFINICIONES_REGLAS_V2_20261028.md); [protocolo preclasificación](./IG_N4_TREMED_PRECLASS_GATES_Y_CASOS_V2_20261028.md). Los pasos P00–P12 abajo siguen como backlog dependiente, no ejecución autorizada.

**Estado:** auditado parcialmente contra EKB y código vivo; NO es cierre, NO es PASS para despliegue. Desarrollo **sin Router**, sin modificación de Supabase. **No convertir la función SQL de sandbox en migración** hasta cerrar estos puntos.

## Dictamen

El PR #3269 reúne documentación, clasificador de referencia, una proyección SQL transaccional con `ROLLBACK` y consultas de lectura. **No implementa** todavía el ciclo completo de herencia semántica y aprobación de alcance. El SQL candidato retira la rama de herencia `DERIVED_GLOBAL` de una sola vez; hacerlo en producción ahora cortaría relaciones no evaluadas. Esa propuesta es **NO-GO para cutover** hasta preservar, reexpresar o desautorizar individualmente las herencias bajo evidencia.

### Matriz ordenada por dependencia

| ID | Estado actual | Pendiente atómico | Entregable medible / gate |
|---|---|---|---|
| P00 | PARCIAL | Congelar snapshot con HEAD Git, MD5 de funciones, EKB, consumidor, selector, contratos, fecha/epoch y source manifest | Evidencia reproducible 58 pantallas, referencias y baseline de los lectores antes de cambiar semántica |
| P01 | NO HECHO | **Definir naturaleza/clase de cada regla**, incl. prioridad, owner, seguridad, caso de uso, transversabilidad condicionada y exclusiones; no usar frecuencias como decisión | Al menos muestras estratificadas por tipo, positivos/negativos y ficha de cada cambio; arbitraje si clasificación es incierta |
| P02 | NO HECHO | **Contexto opcional por regla**: conservar screen/module/app_shell como envoltorio base; cada selector declara sus atributos indispensables y consulta solo sus fuentes canónicas autorizadas. Nunca exigir sesión, onboarding o pagos a todas las pantallas ni inventar campos a partir de nombres. | Para cada condición: path, fuente, owner, freshness y ensayos MATCH/NO_MATCH/UNKNOWN. Falta de dato afecta exclusivamente a esa regla. Estrategia y casos en [IG_N4_TREMED_ESTRATEGIA_PROFUNDA_BASADA_EN_EVIDENCIA_20261028.md](./IG_N4_TREMED_ESTRATEGIA_PROFUNDA_BASADA_EN_EVIDENCIA_20261028.md) |
| P03 | NO HECHO | **Representar negaciones y excepciones** sin hardcodear categorías. Selector `v1` admite `EXISTS`, `EQ`, `IN`, `all`, `any` y no provee `NOT` ni expresiones de conflicto/precedencia. | Evolución mínima y versionada de matcher *si la evidencia lo exige*, compatibilidad y fail-closed de selectores actuales |
| P04 | NO HECHO | **Resolver precedencia, duplicados y contradicciones reales**: acumulación compatible, regla más específica, veto superior de Seguridad/Legal, excepciones autorizadas, empate | Casos de prueba N-4 y referencia explicable. Ninguna regla de pantalla puede degradar automáticamente una política superior |
| P05 | REFERENCIA SOLAMENTE | **Convertir puntuación 0..6 en decisión explicable**, comparar hipótesis, verificar fuentes por criterio, calibrar casos oro; NO tratar la cifra como confianza estadística | Dataset positivo/negativo, score con evidencia/fecha/autor, tasa de abstención y fallos; veto y alternativas |
| P06 | NO HECHO | **Decisión gerencial trazable**: rol/competencia, solicitud, opciones, motivo, firma/identidad, version SHA, autorización condicionada, caducidad/revisión y veto especializado | Binding verificable de recibo + autorización/estado. `programacion.human_decisions` tiene triggers que exigen `execution_id`, HEAD y recibo; no reutilizar a ciegas |
| P07 | NO HECHO | **Tratamiento sin pérdida de herencia legítima**: inventario y clasificación de 241 reglas que generan 8.852 enlaces (92 marcadas transversales, 149 no marcadas); 92 de las 95 transversales sin selector generan herencia; las 18 `UNRESOLVED` tienen selector y están fuera de esta cohorte | Por cada regla: mantener por selector autorizado, restringir, revisar o retirar por decisión sustentada; comparación antes/después, sin caída arbitraria de cobertura |
| P08 | PARCIAL | **Paridad de consumidores**: contratos Login y genérico, security/design/API, reglas candidatas, vínculos físicos y `fn_t_remed_effective_rules_v1`; prevenir caminos alternativos hacia globales sin selector | Inventario de todos los lectores, decisión de tipo de salida (operativo vs análisis), pruebas de consistencia y versionado de contratos |
| P09 | NO HECHO | **Ciclo de vida completo**: crear/cambiar/derogar una regla o selector, evolución de perfiles/Creadores/Actualizadores cuando corresponda; invalidar cache/source manifest | Transiciones `CANDIDATO → REVIEW → ACTIVE → SUPERSEDED/REVOKED` solo como *concepto*, homologar con estados canónicos antes de DB, auditoría y rollback |
| P10 | NO HECHO | **Gate de promoción** separado de alcance: auditar diferencias de `fn_t_remed_promote_v1`, `v3` y jueces. Un PASS técnico de promoción nunca habilita transversabilidad | Casos negativos y prueba de que promoción no puede saltar un selector `UNRESOLVED` |
| P11 | PARCIAL | **Pruebas funcionales y performance**: 58 pantallas, cohortes de 13×47, nueva pantalla con/sin política, casos descartados/inactivos, contradicción y veto, autorización humana, source-currentness y tiempo | Test SQL rollback realmente ejecutado en DB aislada; Curator y Validator con selección determinista→semántica de familias, sin recorrer las 47 a ciegas; CI exact-head, medir latencia |
| P12 | NO HECHO | **Cierre de integración gobernada posterior**: fuente exacta, ACL/funciones, compatibilidad, recibos owner, PR y Merge Train, autoridad vigente | Solo después de P00–P11 y decisión positiva de integración. No correr Router durante diseño según instrucción del usuario |

## Hallazgos concretos verificados

1. `programacion.fn_input_effective_rule_links_v1` sigue incluyendo `DERIVED_GLOBAL` por `fn_t_remed_global_rules_v1(0.25)`. No hay match N-4 para esa rama; EKB lo prohíbe como autoridad terminal.
2. `programacion.fn_input_rule_target_context_v1` entrega `target.screen`, `target.module`, `target.app_shell`; campos de capacidad de sesión/canal/negocio no se verificaron en esas tablas, así que los ejemplos de sesión autenticada **no se pueden imponer fielmente hoy**.
3. `programacion.fn_input_rule_selector_clause_matches_v1` solo admite `EXISTS`, `EQ`, `IN` y falla cerrado para desconocidos. No se diseñó `NOT` ni precedencia.
4. `programacion.human_decisions` no es una cola gerencial genérica: `fn_guard_human_decision` verifica `ejecuciones.head_sha`, identidad y approval_ref; `fn_guard_human_decision_authority_receipt` exige recibo de procedencia. Integración del nuevo dominio no comprobada.
5. En vivo: 58 pantallas, 578 reglas; 8.852 relaciones `DERIVED_GLOBAL` generadas por 241 reglas (92 transversales marcadas y 149 no marcadas); 488 relaciones `CANDIDATO`. Catálogo: 95 reglas `VIGENTE` marcadas transversales sin selector (92 de ellas producen DERIVED_GLOBAL) y 18 `UNRESOLVED` con selector (ninguna forma parte de DERIVED_GLOBAL).
6. El PR #3269 es **draft**. No hay pruebas en PostgreSQL del SQL candidato, ni aprobación gerencial activa, ni migración. Las ocho aserciones del helper están **escritas**; no contarlas como ocho PASS ejecutados mientras no exista evidencia de ejecución.

## Secuencia de trabajo que evita convertir T-REMED en un monstruo

- **Primero P00-P02 y P07:** recuperar qué se hereda hoy, qué debería heredarse según función y con qué atributos comprobables. Construir matriz de casos con suficientes negativos.
- **Luego P03-P06:** extender solo lo indispensable en N-4 (si necesita nuevas primitivas) y reutilizar el mecanismo de autoridad adecuado, sin un segundo motor o una tabla paralela por defecto.
- **Después P08-P10:** integrar contratos y promoción sin caminos de escape. T-REMED sigue siendo **descubridor/reparador**, N-4 evalúa alcance, la gerencia ratifica cambios de política, el Validator audita.
- **Por último P11-P12:** evidencia de regresión, rendimiento y cutover gradual. Nunca reemplazar de golpe 8.852 relaciones por 5.688 sin demostrar sus herencias válidas.

## Definición de listo (NO-GO hasta completar)

Un caso puede considerarse funcionalmente cerrado cuando su regla tiene: origen y propósito; dueño; hipótesis y score explicables; condición positiva y negativa; evidencias válidas; decisión autenticada de alcance; selector versionado autorizado; prueba positiva y negativa en destino; distinción de reglas candidatas; y verificación de consumidores/receipts/currentness. 

Si hay empate sin autoridad, dato canónico ausente, contradicción o decisión vencida: **HOLD** y conservación del estado gobernado vigente (no escalada de alcance automática). No hay permiso para aplicar el selector propuesto.

**Fuentes:** EKB `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`; Supabase read-only; GitHub PR #3269.
