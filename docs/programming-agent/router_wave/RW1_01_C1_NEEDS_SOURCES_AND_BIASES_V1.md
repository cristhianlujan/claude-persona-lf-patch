# RW1-01_C1 — Fuentes, necesidades originales y sesgos arquitectónicos

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1` · **Unidad:** `RW1-01` · **Checkpoint:** `RW1-01_C1` · **Naturaleza:** investigación y readback de fuentes, sin efecto operativo.  
**Versión:** 2026-10-17 · **Estado del documento:** evidencia candidata de C1; **NO** certificado como DONE, ni implica C2/C3 o arquitectura adoptada.

## Pregunta que C1 debe responder

¿Qué necesidades debe satisfacer el Router, con qué restricciones y con qué evidencia de procedencia, **antes** de elegir entre arquitecturas? La topología vigente es una fuente diagnóstica, no fuente normativa. C1 no repite ni actualiza el mapeo ya terminado de A16Q_C1.

## 1. Necesidades originadas en el propietario (no derivadas de los fallos del código)

| Ref | Necesidad verificable | Lo que **NO** debe suponerse |
|---|---|---|
| N01 | Entrada Router First para solicitudes LF, preservando el pedido literal y el contexto relevante. | Que el Router sea ejecutor, ni que cada activo mencionado deba constituir una operación. |
| N02 | Derivar a **responsable competente** con contexto suficiente para seleccionar la ruta, no para completar el trabajo. | Que deba preguntar todos los requisitos de implementación antes de derivar. |
| N03 | Preguntar solo ante ambigüedad material de **derivación** que no pueda resolverse con fuentes/contexto autorizados; no reiterar preguntas ya respondidas. | Límite numérico artificial de preguntas o permiso para inventar decisiones humanas. |
| N04 | Soportar investigación, exploración, asesoría, simulación, DEMO parcial/completa, trabajo sobre módulos/pantallas, cambio acotado y ejecución gobernada. | Que «crear» dentro de «simular crear» autorice escrituras. |
| N05 | Conservar **todos** los objetivos y sujetos; varias tareas pueden demandar varios responsables y coordinación. | Que la primera palabra coincidente elija un único ejecutor y pierda otros objetivos. |
| N06 | Preservar inclusiones, exclusiones, condiciones, negaciones, límites y modos durante el handoff, y respetarlos antes del primer efecto. | Que contar todos los códigos mencionados como destinos deseados sea correcto. |
| N07 | Descubrir responsables, perfiles, skills, operaciones y tipos nuevos con capacidad extensible; no requerir patch por cada término. | Que todo tipo futuro tenga necesariamente ejecutor existente o que debamos inventar uno. |
| N08 | Distinguir sujeto/objetivo del trabajo de perfil ejecutor, operación, adapter auxiliar, evidencia y control técnico. | Que Input Governance o adapter sea selector universal. |
| N09 | No permitir que una derivación o hint de caller por sí mismo autorice efectos: gobernanza independiente al punto de efecto. | Que una respuesta `BLOCKED` para escritura signifique que está prohibido investigar y derivar. |
| N10 | Continuidad segura y autónoma, sin microaprobaciones ni detenciones por fallas de una capacidad no necesaria para el siguiente paso. | Que el sistema esté autorizado para producción o escrituras irreversibles. |
| N11 | Seguir siendo determinista/reproducible donde se emiten decisiones de autoridad, con fuente/revisión actual y recibos enlazables. | Que un modelo o keyword sea fuente de autoridad. |
| N12 | Arquitectura simple y futura: cuestionar propuestas, reutilizar solo lo útil, minimizar acoplamiento, medir costes y evitar nuevas barreras artificiales. | Que «todo el cableado existente está mal» esté probado o que haya que eliminar todos sus guards. |

**Naturaleza de estas fuentes:** requisitos expresados por el propietario en la discusión de ACT-0001, ratificados al ordenar construir la ola. Se documentan como **necesidades**, no como aprobación de una solución particular. La necesidad N12 reclama deliberadamente cuestionar lo propuesto por el propietario y por el diseñador.

## 2. Fuentes técnicas actuales (reutilización, sin inventario nuevo)

| ID | Fuente canónica / referencia | Qué demuestra | Qué no demuestra |
|---|---|---|---|
| S01 | Supabase `programacion.engineering_plan_units`, `engineering_work_checkpoints`: `LF_ROUTER_ARCHITECTURE_WAVE_V1/RW1-01` | C1/C2/C3 declarados y su estado gobernado | Resultado material por sí solo |
| S02 | Evento `public.lf_eventos/21263` `PLAN_SNAPSHOT_DETALLADO` | Plan persistido sin aceptación | Implementación y ejecución de sus unidades |
| S03 | `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A16Q/A16Q_C1` y `docs/programming-agent/ANALYSIS_A16Q_C1_ROUTER_CONSUMER_INVENTORY_V1.md` | Inventario inicial y fronteras de perfiles/consumidores, C1 DONE de **otro** plan | C2 E2E de A16Q, ni C1 DONE de RW1-01 |
| S04 | `docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md` | Secuencia 6 unidades/18 checkpoints y aceptación prevista | Que el Router actual satisfaga esa secuencia |
| S05 | EKB `LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001`, `...PREWRITE-INTENT-GATE-20261015-002` | Pruebas históricas de deriva lexical y autoridad pre-escritura | Obligación de conservar el parser o parche lexical |
| S06 | EKB `LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002`, `...TYPED-TARGET-AUTHORITY-BYPASS-20261017-003` | Hints y texto no prueban alcance ni permiso de efecto | Que deba bloquearse la derivación segura |
| S07 | EKB `LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005`, `...SCREEN-SHORTCIRCUIT-20261016-003` | Sujeto ≠ ejecutor ≠ adapter | Que un perfil predefinido sea la solución correcta para toda pantalla |
| S08 | EKB `CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL` | Una denegación del conector RO no prueba bloqueo funcional de actor autorizado | Permiso implícito para evadir ACL |
| S09 | PR #2867 → #2868 → #2873 → #2874; Train #2870 `39031677974` | Riesgo real de dependencia circular al mezclar validación humana y técnica; Train normal recuperado | Cualquier necesidad nueva de apagar un control |
| S10 | `public.lf_router_resolve_v1` (firma de cinco argumentos) y `lf_router_operation_catalog_match_v1` | Superficies actuales observadas de enrutamiento y elegibilidad técnica | Que el ABI/estructura actual sea arquitectura objetivo |

La fuente EKB se leyó el 2026-10-17 mediante `public.lf_error_knowledge`. Revalidar fuente/revisión exactas antes de un checkpoint terminal. El contenido de GitHub será acreditable tras merge/lectura de bytes actuales. No trasladar el dato histórico 75 BLOCKED / 1 SUCCEEDED de A16Q a un porcentaje actual.

## 3. Observaciones diagnósticas deliberadamente NO normativas

Una exploración previa de **11** solicitudes dirigidas a `lf_router_resolve_v1(text)` produjo **11 `BLOCKED`**, 7 con `semantic_handoff` y 4 sin él. No acredita continuidad de consumidores ni permite concluir que 11 decisiones sean errores; varias son bloqueos válidos de **efectos**.

Ejemplos de familias observadas: investigación sin cambio, DEMO simulada, módulo completo, regla+skill, simular creación, cambio acotado del login, exclusión ACT-0052, investigación del responsable, tipo futuro sin registro, referente ausente y onboarding para varios segmentos. **No usar estas 11 como el corpus único o principal del próximo C2**: selección sesgada por fallos, sin controles positivos equilibrados y sin comparación de alternativas.

## 4. Sesgos, hipótesis y contradicciones a desafiar en C2/C3

1. **B01 — Reparación por cableado:** elegir contrato porque el código/trigger ya lo espera. Antídoto: necesidades/oráculo antes de consulta de implementación.
2. **B02 — Conformismo:** convertir cada idea del propietario en regla operativa. Antídoto: aceptación/modificación/rechazo motivados, alternativa y costo observable.
3. **B03 — Anti-legado absoluto:** desechar guardas correctos suponiendo que todo está mal. Antídoto: conservar invariantes demostrados; rechazar acoplamientos, no la protección.
4. **B04 — Sesgo por solo negativos:** confundir bloqueo de escritura con fracaso de derivación. Antídoto: medir separadamente derivación, progreso seguro y permiso de efecto; incluir positivos.
5. **B05 — Sobrecarga semántica:** imponer un juez semántico dentro del Router sin comparar con selección responsable + especialista. Antídoto: comparar arquitecturas rivales con criterios iguales.
6. **B06 — Capacidad inventada:** dirigir todo lo desconocido a un experto genérico no registrado. Antídoto: verificar responsable real, o declarar gap técnico sin fabricar ejecutor.
7. **B07 — Compatibilidad circular:** preservar una invocación sintética que hace bloquear al Train. Antídoto: distinguir autoridad técnica y humana desde el contrato.
8. **B08 — Prueba por documento:** asumir C1/C2/C3 PASS por plan, README o prueba aislada. Antídoto: evidencia de fuente actual y recibo de la misma unidad.
9. **B09 — Conteo infinito de preguntas:** transformar aclaraciones en ciclo de aprobación. Antídoto: preguntar solo cuando cambia ruta responsable y continuar lo independiente.
10. **B10 — Catálogo rígido:** clasificar tipos de activo como ejecutores a partir de coincidencias léxicas. Antídoto: rol y capacidad separados.

## 5. Delimitación estricta RW1-01

**C1 (presente):** recuperar y ligar fuentes, necesidades y sesgos; readback exacto de `RW1-01_C1`, A16Q_C1 y EKB. **No elige arquitectura**. La documentación sola no autoriza DONE.

**C2 (posterior):** crear matriz testable de capacidades y resultados esperados, muestrear positivos/negativos, holdouts nuevos y modos actuales/futuros, con falsificadores de N01–N12. Selección independiente del comportamiento actual. No introducir nuevos gates por cada caso.

**C3 (posterior):** crítica independiente de sesgo de selección, omisiones y circularidades; declarar contradicciones y limites n; no declarar significancia sin muestra.

**Criterio de C1:** comprobar que todas N01–N12 tienen fuente de necesidad; S01–S10 están clasificados sin elevar diagnósticos a requisitos; el inventario A16Q_C1 se reutiliza y sus límites se preservan; los sesgos B01–B10 están explicitados; fuente Git actual y EKB leídos realmente; registro de checkpoint solo mediante contrato y ejecución canónica. Si hay fuente ausente o desactualizada, no PASS.

## 6. Consultas de readback de C1

```sql
SELECT u.plan_code,u.unit_code,u.work_item_id,u.unit_metadata->>'schema' metadata_schema,
       c.checkpoint_code,c.status
FROM programacion.engineering_plan_units u
JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
WHERE u.plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
  AND u.unit_code='RW1-01' AND c.checkpoint_code='RW1-01_C1';

SELECT c.checkpoint_code,c.status,c.evidence_ref
FROM programacion.engineering_plan_units u
JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1'
  AND u.unit_code='A16Q' AND c.checkpoint_code='A16Q_C1';

SELECT codigo,titulo,causa_raiz,prevencion
FROM public.lf_error_knowledge
WHERE codigo IN (
 'LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001',
 'LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002',
 'LF-ROUTER-ACT0001-UNSTRUCTURED-MUTATION-FALSE-READY-20261017-002',
 'LF-ROUTER-ACT0001-TYPED-TARGET-AUTHORITY-BYPASS-20261017-003',
 'CIERRE_PREMATURO_POR_CONFUNDIR_READ_ONLY_CON_BLOQUEO_GLOBAL'
) ORDER BY codigo;
```

**Responsabilidad:** C1 read-only; fuente documental se materializa en GitHub por su carril; binding de metadata por Migration Train; estado solo mediante checkpoint transition con readback/material assertion conforme al contrato vigente. No ejecutar directamente un DML usando el conector RO.
