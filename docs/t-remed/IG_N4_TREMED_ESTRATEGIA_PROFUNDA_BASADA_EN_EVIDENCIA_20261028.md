# LF Input Governance — estrategia ejecutable de evaluación semántica, aplicabilidad y cierre P00–P12
**2026-10-28 | REV 1 | Desarrollo / diseño, no autorizado para producción | PR #3269 | NO Router en fase de cambios.**

## 0. Decisión arquitectónica y fundamento verificable

**No existe una obligación de agregar atributos de sesión, pagos, onboarding o similares a todas las pantallas.** El contexto canónico de N-4 es el *envoltorio* base de procedencia del destino, actualmente producido por \`programacion.fn_input_rule_target_context_v1\`: \`target.screen\`, \`target.module\`, \`target.app_shell\` y \`consumer_role\`. Cada regla activa declara únicamente sus condiciones aplicables. Cuando una condición requiere un dato no disponible en ese envoltorio, hay que estudiar y reutilizar su fuente autorizada y resolverla puntualmente, con límite de costo. Si no se puede comprobar, esa regla es \`UNRESOLVED\` / HOLD, sin invalidar a otras.

**Semántica no es autoridad.** Su producto es una *hipótesis de alcance con explicación, contrapropuesta y evidencia*. N-4 resuelve el match determinista de selectores publicados por autoridad. T-REMED detecta y repara brechas y recomienda posible reutilización. No se implementa motor/tabla de decisiones paralela ni se convierte el 25% de uso en permiso.

Referencias de diseño: NIST SP 800-162 (atributos verificados, decisión de política separada de datos/administración); OMG DMN 1.6/1.7 beta (reglas coincidentes/precedencia explícita, no orden accidental); OPA Policy Testing (pruebas tabulares, casos negativos, coverage); Google SRE Canarying Releases (comparación contra control, medición y rollback). **Son referencias metodológicas; NO autorizan una plataforma nueva**.
- https://csrc.nist.gov/pubs/sp/800/162/upd2/final
- https://www.omg.org/spec/DMN
- https://www.openpolicyagent.org/docs/policy-testing
- https://sre.google/workbook/canarying-releases/

## 1. Contra qué se analiza semánticamente — especificación de entradas

Para cada regla \`R\` y destino/consumer \`D\`, formar paquete efímero \`E(R,D,version)\` en esta jerarquía de procedencia:

| Orden | Entrada | Campos / fuentes actuales comprobadas | Verificación |
|---|---|---|---|
| A | Norma/autoridad superior, negativa y positiva | EKB: \`IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001\` y política/decisión vinculada | ¿Se permite la expansión? No aceptar inferencia de globalidad por frecuencia ni categoría |
| B | Semántica propia de R | \`lf_ops.reglas\`: \`titulo\`, \`descripcion\`, \`razon\`, \`origen\`, \`categoria\`, \`valor_config\`, \`estado\`, \`pendiente_decision\` | Separar sujeto, evento, acción, precondiciones, excepciones, fuente y vigencia |
| C | Destino y capacidad comprobable | \`lf_ops.pantallas\`: \`objective\`, \`descripcion\`, \`flujo\`, \`dependencies\`, \`module_id\`; módulo y shell; contratos verdaderos | ¿La condición funcional existe o solo aparece en una etiqueta? |
| D | Precedentes, NO autoridad | \`lf_ops.reglas_pantallas\`, \`fn_t_remed_recommend_v1\`, regla en mismo shell/categoría | Solo para descubrir casos positivos/negativos; frecuencia nunca equivale a permiso |
| E | Capacidad externa/canónica puntual | Fuente de política, seguridad, sesión, API u otra capacidad **solo si R la exige** | Se exige nombre de campo, URI/ID de fuente, dueño, vigencia y prueba de integridad; si falta: UNKNOWN |
| F | Contraste independiente | Otros casos, tests, Curator y Validator con evidencia de signo contrario | Prueba positiva, negativa y caso de dato ausente para cada nuevo selector |

**Secuencia:** filtro determinista por familia/consumer/lifecycle → recuperar los candidatos plausibles (no las 578 reglas ni 47 familias a ciegas) → análisis semántico de hipótesis de alcance **contra A–F** → extracción de condiciones en estructura controlada → validación de procedencia y veto → pruebas de consecuencias → puntuación auxiliar → revisión humana cuando corresponde → publicación gobernada distinta del scoring.

### Esquema de ficha semántica (no nuevo modelo persistente)

\`{rule_ref, source_version_hash, consumer, target_class_hypotheses:[], purpose, trigger, subject, action, required_attributes:[{path, source_ref, freshness, nullable, owner}], positive_cases:[], negative_cases:[], exclusions:[], superior_policies:[], citations:[], contradictory_evidence:[], uncertainty:[], score_breakdown, approval_status:"NOT_AUTHORIZED"}\`.

El esquema es **contrato lógico de trabajo/artefacto**, no tabla SQL por defecto. No usar códigos de negocio hardcodeados en el motor. Para prueba se permiten fixtures con códigos reales claramente etiquetados.

### Ejemplo crítico

\`REG_SES_001\` trata de expiración de *onboarding incompleto*. El título por sí solo podría parecer compatible con Login B2B porque ambos contienen “sesión”, pero:
1. la condición semántica es estar en onboarding incompleto;
2. el login no prueba esa condición;
3. tener 25 vínculos físicos solo indica frecuencia de uso;
4. N-4 debe devolver **NOT_APPLICABLE** cuando la condición falsa esté probada, **UNRESOLVED** cuando no se pueda probar, o **APPLICABLE** solo con selector ratificado que coincida.
No hay aprobación implícita al repetir el caso.

## 2. Dos tipos de evaluación estrictamente distintos

### 2.1 Evaluación en cambios de regla / scope (investigación)

Curator investiga significado y contrasta documentos, propone al menos una hipótesis conservadora más una alternativa y contraejemplos, produce ficha de evidencia. Segundo revisor/Validator busca activamente *falsaciones* (no simplemente que la IA haya explicado algo convincente). La gerencia ratifica la competencia funcional; Seguridad/Legal vetan dentro de su autoridad. Un score puede priorizar una revisión, nunca activar un selector.

### 2.2 Evaluación en runtime de un destino (barata, determinista)

N-4 recibe consumer permitido, selector **ACTIVE** autorizado, contexto base y únicamente campos requeridos por el selector. Evalúa condiciones con salida **MATCH / NO_MATCH / UNKNOWN** en diseño conceptual (hoy v1 retorna booleano). Si algún dato exigido está ausente o carece de fuente, UNKNOWN no equivale a FALSE y *jamás* debe convertirse a TRUE por aplicar \`NOT\`. La publicación/precedencia debe escoger tratamiento de UNKNOWN compatible con el contrato actual; en cómputo efectivo de autorización es fail-closed (no aplica esa regla).

No realizar investigación web, lectura EKB global, valoración semántica LLM ni consulta a gerencia en cada pantalla. Costos de datos: identificar dependencias estáticamente, agrupar por fuente, cachear con invalidación por versión y consultar solo los atributos necesarios. **Antes de introducir carga dinámica adicional, demostrar con caso real que la regla no puede expresarse con datos existentes.**

## 3. Resolución de conflictos sin construir otro motor

Primero identificar conflictos *demostrados*: mismo efecto y distinto parámetro, una regla permite lo que otra prohíbe, distinta prioridad de autoridad, excepción restringida. No sobreingenierizar un operador NOT/ordenación/jerarquía completa si los casos observados se expresan con \`all/any/EQ/IN/EXISTS\`.

| Colisión | Estrategia | Gate |
|---|---|---|
| Distintas reglas compatibles (UI + Seguridad) | **Acumular**; no elegir una por score | Efectos compatibles probados |
| Duplicado exacto | **Deduplicar por identidad/procedencia**, no por parecido de título | Mismo efecto y evidencia |
| Mismo dominio, parámetros distintos | **HOLD** salvo regla de precedencia explícita autorizada | Contradicción detectada por Validator |
| Política superior obligatoria vs regla local | **No rebajar** la superior; local solo puede restringir o aportar comportamiento permitido | Prueba de no debilitamiento |
| Excepción aprobada y acotada | Selector propio con condición y aprobación explícita | Dueño y límite positivo/negativo |
| Dos hipótesis con score igual o cerca | **Revisión humana** de evidencia y consecuencias | Sin desempate por hash/orden |
| Dato requerido ausente | **UNKNOWN/HOLD** de esa regla | Resto de reglas continúa |

**No codificar preferencia “pantalla > módulo > shell” indiscriminada**: la especificidad contextual no autoriza derrotar normas de mayor jerarquía. Tomar concepto de *hit policies* (Unique/Collect/Priority) de DMN como disciplina de clasificación, no adoptar su runtime.

## 4. Plan atómico P00–P12 — propietario, mecanismo, prueba negativa y criterio de cierre

### LOTE A: congelación y evidencia (P00, P01, P02, P07)

| ID | Trabajo preciso y mecanismo | Responsable funcional/técnico | Artefacto y control que demuestra cierre |
|---|---|---|---|
| **P00** | Snapshot real de reglas, selector, relación, consumidores, manifests, HEAD, hashes SQL; categorizar VIGENTE/CANDIDATO/UNRESOLVED/INACTIVE. Comparar al cambiar. | IG/Validator + DB read-only | Matriz base con 58 pantallas/578 reglas, hashes, timestamp y diferencias reproducibles. **NEG:** si HEAD cambia no reutilizar PASS |
| **P01** | T-REMED entrega candidatos; Curator interpreta cada regla contra A–F. Separar semántica de “globalidad”. Crear *golden set* de ejemplos positivos, negativos, falsos amigos lexicales y casos dudosos; segmentar por criticidad y tipo. | Curator + owner de la regla | Ficha por regla con hipótesis A/B y prueba adversarial. **NEG:** “expiración onboarding” no llega a Login por compartir palabra “sesión” |
| **P02** | **Contexto opcional por regla**: leer solo \`required_attributes\` del selector/hipótesis. Auditar si existen ya en screen/module/shell/contratos/políticas; reutilizar fuente canónica, sin columnas globales ni atributos estáticos para las 58 pantallas. Proveniencia, acceso y freshness. | Curator + owner del dato + N-4 | Mapa \`attribute path → source/owner → presente/ausente\`, pruebas MATCH/NO_MATCH/UNKNOWN. **NEG:** falta dato de sesión solo afecta regla de sesión |
| **P07** | Inventario completo y priorizado de **241 reglas** que originan **8.852 enlaces** heredados: 92 marcadas transversales y 149 no; cohortes aparte: 95 vigentes transversales sin selector (92 de la cohorte heredada) y 18 \`UNRESOLVED\` con selector. Usar riesgo semántico e impacto, no número de links como permiso. | Curator/owner + Validator | **241/241** con resolución rastreable: conservar alcance validado, restringir con selector, HOLD por evidencia o retirar con autorización. No aplicar corte de 8.852→0 antes de cobertura clasificada. **NEG:** cero herencias lícitas desaparecen sin decisión |

**Gate A:** P00–P02 completos + inventario P07 etiquetado/canónico. El SQL actual de sandbox que elimina \`DERIVED_GLOBAL\` sigue clasificado **NO-GO**. Si evidencia insuficiente, se mantienen pendientes individuales, no se inventa certeza.

### LOTE B: lenguaje, resolución y gerencia (P03, P04, P05, P06)

| ID | Trabajo preciso y mecanismo | Responsable | Artefacto/gate |
|---|---|---|---|
| **P03** | Inventariar condiciones existentes: \`EQ/IN/EXISTS\`, \`all/any\`. Demostrar con ejemplos qué negativas no se pueden expresar; decidir si basta \`EQ false\` contra dato confiable o si se requiere evolución **versionada** para \`NOT\`/NULL con lógica de tres valores. No introducir NOT automáticamente. | N-4 + Validator | Matriz 100% de condiciones solicitadas por casos del lote A expresables/verificables, y tests de UNKNOWN. **NEG:** campo ausente no satisface negación |
| **P04** | Clasificar efectos: compatibles, duplicados, contradictorios, superior-inferior, excepción legítima. Comparar autorizaciones, no título, frecuencia ni especificidad a ciegas; documentar precedencia por competencia. | Owner, Seguridad/Legal según dominio, Validator | Casos de acumulación, veto, excepción y empate; contradicción irresuelta = HOLD. **NEG:** regla local no reduce seguridad superior |
| **P05** | Evaluar hipótesis contra A–F con rubric 0–2 en semántica, expresabilidad y evidencia. Revisor independiente evalúa un set estratificado (no solo ocho asserts del helper). Calibrar 5/6 y gap 2 contra falsos positivos y abstenciones reales. | Curator + Validator/independiente | Dataset etiquetado, matriz de confusión por categoría de riesgo, ejemplos explicados, hash de fuentes; umbral no se declara producción hasta validación. **NEG:** score 6 sin prueba negativa no autoriza |
| **P06** | Mapear owner de regla, gerencia competente, Seguridad/Legal y recibo de aprobación. **No asumir** \`programacion.human_decisions\`: triggers exigen \`execution_id\`, \`ejecuciones.head_sha\`, \`actor_identity\`, \`approval_ref\`, \`authority_receipt_id\`; evaluar compatibilidad antes de reutilizar. Construir ficha de decisión con opciones, impacto, SHA, caducidad/cambio, firma y veto. | Gerencia/owner + autoridad de decisiones | Decisión verificable vinculada a selector y versión, rechazos/condiciones; gerencia no necesita decidir nuevas pantallas dentro de alcance ya ratificado. **NEG:** aprobación de otro head o rol no autoriza |

**Gate B:** no existe selector ACTIVADO solo por score; toda nueva expansión exige fuente, competencia, decisión autorizada y pruebas de aplicación/no aplicación. Evitar tabla/servicio de gerencia si un registro existente cumple contrato verificado.

### LOTE C: consumidores, lifecycle y promoción (P08, P09, P10)

| ID | Trabajo preciso y mecanismo | Responsable | Artefacto/gate |
|---|---|---|---|
| **P08** | Inventariar lectores \`fn_input_effective_rule_links_v1\`, \`fn_t_remed_effective_rules_v1\` y \`lf_ops.reglas_pantallas\`; clasificar cada contrato como OPERATIVO o ANALÍTICO. Resolver \`CANDIDATO\` solo para análisis; \`VIGENTE\` autorizada para operativo; misma interpretación selector y consumer. | N-4 + owners de contratos | Matriz \`consumer → fuente → estado → authority\`, comparaciones de contratos API/seguridad/diseño/IG. **NEG:** candidato no aporta políticas ejecutables |
| **P09** | Definir lifecycle por evento: crear, editar, publicar, restringir, derogar, sustituir y nuevas pantallas. Invalidar solo selectores/manifest afectado y procesar dependencias. No inventar estado SQL \`REVIEW\` sin cotejar enumeraciones actuales. | Owner + IG + Curator/Validator | Transiciones legales, idempotencia, receipts, diff del selector, rollback. **NEG:** selector obsoleto no sigue activo por cache |
| **P10** | Separar promoción de estado de regla y autorización de *scope*. Auditar \`fn_t_remed_promote_v1\`, \`v3\`, juez de refs y \`fn_t_remed_rule_promotion_verdicts_v1\`; un PASS de refs/uso no equivale a selector ACTIVE. | T-REMED + Validator | Pruebas negativas de promoción sin scope o con UNRESOLVED; diff reversión y seguridad. **NEG:** política referenciada no convierte regla local en global |

**Gate C:** todos los caminos efectivos de consumo pasan una sola semántica de autoridad; análisis sigue mostrando candidatas con etiqueta; motor de T-REMED conserva naturaleza de reparación.

### LOTE D: certificación y publicación futura (P11, P12)

| ID | Trabajo preciso y mecanismo | Responsable | Artefacto/gate |
|---|---|---|---|
| **P11** | Probar función SQL en PostgreSQL aislado con ROLLBACK/readback, ACL y SQL hash; comparación funcional antes/después; evaluar **58 pantallas** y regresión de la cohorte histórica **13×47** según gate, pero en ejecución normal respetar selector determinista→semántico de familias, no procesar todas a ciegas; probar nuevas pantallas, permisos, inactivos, falsos positivos, empate, veto, política de sesión, fallas de fuente, consumo, rendimiento p50/p95 y costo tokens. | Validator + CI/DB | Reporte reproducible de PASS/FAIL por caso, evidencia negativa y objetivos de performance definidos por baseline real. Sin afirmar “8/8” si solo están escritas las aserciones |
| **P12** | Preparar integración **en otra fase**: scope autorizado, fuente exacta Git, versión exacta del ledger, owner de DB/Migration, CI exact-head, merge train, readback, canary/rollback por cohortes. Durante la fase actual **sin Router**. | Owner de integración gobernada | PASS de source parity, auditoría, autorización y post-deployment verification. **No** tocar main/producción desde PR #3269 |

## 5. Gating del pipeline; evita reordenar pasos

\`DETECTAR → FILTRAR_FAMILIA_Y_CANDIDATOS → CARGAR_EVIDENCIA → HIPÓTESIS_SEMÁNTICAS → VALIDAR_ATRIBUTOS → VETO_Y_CONFLICTOS → SCORE_ASESOR → AUTORIDAD_HUMANA_SI_CORRESPONDE → PUBLICAR_SELECTOR_GOBERNADO → MATCH_N4 → CONSUMIDOR → VALIDATOR\`.

- La rama de runtime parte de **PUBLICAR_SELECTOR_GOBERNADO → MATCH_N4 → CONSUMIDOR**, nunca ejecuta LLM/gerencia para cada pantalla.
- Si falla scope/atributo de una regla, HOLD local; no salta a promoverla ni interrumpe una evaluación de otra regla sana.
- Cada paso aporta \`input_hash\`, \`output_hash\`, razón de paso/salto, fuente y estado. El runtime/handoff debe impedir entrar al paso N+1 sin recibo válido del N. **Es diseño para validar**, no afirmación de pipeline ya instalado.
- La selección de familias de IG es independiente de la selección de reglas; usar la secuencia que realmente define el contrato vigente y no asumir que 47 se ejecutan en cada solicitud.

## 6. Protocolos de ensayo que prueban que no está 'en duro'

**Caso 1 — Variación de pantalla:** crear en fixture una pantalla nueva del mismo módulo con atributos válidos: hereda selector contextual; cambiar atributo exigido a false: no hereda; omitir campo: UNKNOWN/HOLD; no editar SQL.

**Caso 2 — Regla nueva:** agregar fixture de regla con selector permitido y contexto existente; hereda sin añadir un código de regla al resolvedor.

**Caso 3 — Dato ajeno:** en simulador de deuda, evaluar solo reglas elegibles de datos personales; la ausencia de información de sesión no debe impedir reglas independientes.

**Caso 4 — Dos políticas en conflicto:** política local menos restrictiva de seguridad superior: veto, aunque score de local sea 6.

**Caso 5 — Empate A/B:** scores 5/5 o 6/5: revisión; no 'orden primero' ni md5 como decisión de negocio.

**Caso 6 — Regla \`CANDIDATO\` con policy_id válido:** disponible para análisis, inexistente como fuente de política operativa.

**Caso 7 — \`UNRESOLVED\` y negación:** atributo NULL no debe contarse como "no tiene sesión"; no activar mediante NOT.

**Caso 8 — Distinta familia:** cambio de regla de diseño no fuerza ejecución de familias ajenas; selección inicial de familias comprobada.

**Caso 9 — Promoción:** PASS de vínculo + 5 pantallas no confiere globalidad ni publica selector.

**Caso 10 — Comparación incremental:** medir costos/latencia/cobertura y diferencias antes/después; cero reglas autorizadas perdidas sin decisión registrada.

## 7. Reglas de ingeniería, entregable y criterio NO-GO

Cada checkpoint tiene un micro-contrato de seis elementos: **entrada congelada → método → artefacto → caso positivo y negativo → dueño del PASS → referencia de evidencia actual**. Sin uno, queda PENDING y el siguiente paso dependiente no corre.

No extender esquema o motor solo por comodidad. Toda nueva primitiva debe tener un caso fallido reproducible con el contrato existente y demostrar que no se resuelve con la semántica ya ofrecida.

**Evidencia actual 2026-10-28:** PR #3269 contiene prototipo SQL con ROLLBACK, clasificador de referencia (8 aserciones definidas sin reporte de ejecución), inventario read-only y documentación. DB vivo N-4: matcher \`EQ\`, \`IN\`, \`EXISTS\`, \`all\`, \`any\`; 14 selectores \`ACTIVE\`, 18 \`UNRESOLVED\`. Hay 241 reglas que generan 8.852 \`DERIVED_GLOBAL\`. Este documento es una estrategia de cierre **NO una ejecución ni aprobación**.
