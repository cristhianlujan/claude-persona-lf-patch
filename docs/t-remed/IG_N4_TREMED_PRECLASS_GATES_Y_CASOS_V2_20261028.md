# LF Input Governance — protocolo de validación del modelo ANTES de reclasificar
**Versión de diseño:** v2 candidato · 2026-10-28 · **Estado:** SPEC ONLY / NO RECLASS / NO SUPABASE WRITES.

> **RESULTADO NUEVO DE ENSAYOS PARCIALES:** La ronda sintética se amplió a **27 vectores**, con **18 PASS/9 FAIL** del matcher vigente y **27/27** de sombra SQL SELECT. Pruebas aisladas de decisiones/conflictos **35/35**, no integración. G3, G4 y G5 **NO están cerrados**. Consultar [informe](./IG_N4_G2_G3_TRABAJO_TECNICO_VALIDACION_20261028.md). No reinterpretar el registro histórico 23-vector de los apartados originales como estado final.

> **EJECUCIÓN PARCIAL G3 (2026-10-28):** Se ejecutaron 23 pruebas SQL de matcher N-4: 18 PASS, 5 FAIL contra el contrato objetivo. **Esto NO completa los 14 escenarios S01–S14** (conflictos, autoridad, consumer operativo, G4). Ver [resultados](./IG_N4_TREMED_G3_RESULTADOS_PRUEBAS_SELECTORES_V21_20261028.md) y [adenda de diseño v2.1](./IG_N4_TREMED_G2_AUDITORIA_Y_AJUSTES_DE_CONTRATO_V21_20261028.md). No iniciar G5.

## 1. Cambio de dependencias

El lote A anterior procedió con inventarios y clasificación estructural antes de ratificar la estrategia. Ese trabajo es evidencia histórica **no resultado de reclasificación**. A partir de este documento, el gate correcto de inicio de análisis del catálogo es:

`G0 STRATEGY_REVIEW → G1 DEFINITIONS_LOCK → G2 CLASSIFICATION_RULES_LOCK → G3 SYNTHETIC_TESTS_PASS → G4 OWNER_METHOD_APPROVAL → G5 REAL_RULES_RECLASSIFICATION`

**No ejecutar G5 ni convertir el SQL de sandbox en migración hasta superar G0–G4.** Las etiquetas `G0..` son etiquetas de este protocolo en la rama dev; no nuevos gates del Router ni estados de Supabase.

## 2. Criterios de cierre por gate

| Gate | Entradas obligatorias | Salida | Verificación negativa |
|---|---|---|---|
| G0 Estrategia | EKB vigente, mandato de preservar cascada, componentes y owners existentes | Objetivo, límites, separados offline/online, reglas sin hardcodear | No aparece un nuevo motor ni una tabla por defecto |
| G1 Definiciones | Glosario de regla, intención, naturaleza, fuerza, scope, policy, contexto, evidencia y autoridad | Definiciones no ambiguas y ejemplos límite | Ningún término como “transversal” equivale a “global” |
| G2 Normas | Contrato H01–H15, excepciones, veto, composición y gestión de conflictos | Tabla de decisión jerárquica ratificada con autor competente | Precedencia no depende de orden SQL ni solo nivel de pantalla |
| G3 Ensayos sintéticos | Casos S01–S14 a continuación con precondiciones controladas | Resultado esperado por caso, rastros, negativas y contraste independiente | Nuevas reglas/pantallas no exigen código/ID añadido al resolvedor |
| G4 Ratificación del método | Revisión Curator/Validator + dueño funcional + competencia legal/seguridad, impacto y evidencia | Decisión de diseño/version autoritativa + recibo existente homologado | Ausencia de aprobación mantiene G5 bloqueado |
| G5 Reclasificación real | Versión G4, inventario solo como universo, fichas por regla | Clasificación con evidencia y decisiones, casos de nueva naturaleza como MODEL_GAP | No se reclasifica en masa ni se altera herencia efectiva durante investigación |

## 3. Ficha mínima de evaluación, sin tabla nueva

Campos de la **ficha conceptual** (no es un nuevo schema DB):

- `source_ref` + `source_sha` + `rule_ref`, `rule_version`, `rule_status`.
- `purpose`, `subject`, `event`, `precondition`, `effect`, `constraint`, `exceptions`, `normativity`.
- `context_requirements`: atributos **solo necesarios para esta regla**, `path`, `owner`, `source_ref`, `freshness`, `reason`.
- `authority`: policy refs, autoridad funcional, veto competente, ámbito permitido, decision ref, fecha/vigencia.
- `alternative_hypotheses`: proponer al menos una alternativa razonable y registrar por qué queda descartada o en HOLD.
- `tests`: casos positivos, negativos, de dato ausente, contradicción y nueva pantalla.
- `composition`: compatibilidad, duplicidad, colisión, sustitución o excepción con referencias.
- `evidence_quality`: procedencia, fuentes primarias, corroboración, desactualización y contradicciones.
- `risk`: daño de aplicar incorrectamente y daño de omitir la regla; criticidad no equivale a alcance.
- `decision`: autorización **ausente** hasta recibir ratificación de actor competente, y reason/handoff si queda pendiente.
- `model_gap`: dimensiones que el contrato v2 no pudo expresar (si existen), con propuesta de evolución.

La categoría funcional es **metadato analítico extensible**, no switch/case de motor. La diferencia entre `FALSE` y `UNKNOWN` debe preservarse en evidencias aunque el matcher v1 de N-4 devuelva booleano.

## 4. Casos sintéticos ANTES de ver catálogo real

Todos estos ejemplos son hipótesis genéricas, no contratos actuales de LF, ni etiquetas que deban codificarse como casos especiales:

| Caso | Entradas controladas | Resultado esperado | Invariante demostrado |
|---|---|---|---|
| S01 | Regla obligatoria de protección de datos con ámbito expresamente autorizado para canales A/B | Puede aplicar a A/B con atributos presentes y autoridad ratificada | Una regla ampliamente reutilizable no debe perderse por salir del shell original |
| S02 | Regla de secuencia de onboarding con evento “OTP incompleto”; destino login sin onboarding | No aplica | Parecido textual y frecuencia no autorizan |
| S03 | Regla autenticación con precondición “sesión autenticada” y destino preauth | No aplica si falsedad probada, HOLD si dato no comprobable | No confundir FALSE/UNKNOWN |
| S04 | Misma regla sobre una pantalla nueva con atributos autorizados | Herencia dinámica sin editar SQL | Cascada efectiva |
| S05 | Pantalla nueva del mismo módulo sin precondición | No hereda | El módulo no basta |
| S06 | Pantalla sin módulo y regla independiente de módulo | Evalúa con otros datos disponibles | No exigir módulos a todas las pantallas |
| S07 | Regla que necesita sesión y destino sin dato de sesión confiable; otra regla visual independiente | HOLD solo de sesión; evaluación visual continúa | Contexto por demanda |
| S08 | Dos reglas con efectos compatibles (privacidad + accesibilidad) | Componer ambas | No priorizar por score |
| S09 | Dos reglas opuestas sobre el mismo efecto, sin precedencia | HOLD del conflicto; no elegir por orden | Conflicto explícito |
| S10 | Regla de pantalla permitiría degradar política superior | VETO hasta decisión especializada, sin debilitamiento | Prioridad de autoridad |
| S11 | Regla CANDIDATO con un policy_id de política vigente | Visible en análisis, NO en contrato operativo ejecutable | Estados separados |
| S12 | Selector UNRESOLVED y condición NOT sobre atributo ausente | No habilitar regla ni convertir NULL en true | Fail-closed |
| S13 | Dos hipótesis iguales en score o una con score alto y evidencia legal contradictoria | Gerencia/competente revisa, score no autoriza | Scoring accesorio |
| S14 | Caso verdadero nuevo, naturaleza o efecto no representable | `MODEL_GAP`: propuesta versionada y tests, sin forzar etiqueta existente | Modelo evolutivo |

**Adicional:** repetir S01–S14 con una regla futura no registrada previamente y un destino creado tras la ratificación; si exige cambiar código de selector para meter un ID especial, G3 falla.

## 5. Reglas de revisión adversarial

Para cada candidato, el revisor debe buscar explícitamente:
- Contradicción entre el texto de la regla, política citada, destino y origen.
- Mismo vocabulario pero **disparadores o sujetos diferentes**.
- Fuente que ya no es vigente o cuyo owner no tiene autoridad sobre la ampliación.
- Regla con recomendación redactada como obligación operativa.
- Regla de gobernanza de agentes indebidamente tratada como comportamiento de pantalla.
- Múltiples reglas compatibles cuya supuesta “competencia” no existe.
- Negación sobre un campo ausente y otro campo sin procedencia.
- Caso de nueva capacidad no expresable con los atributos/operadores actuales.
- Excepciones sin límite, caducidad o aprobador adecuado.
- Impacto sobre consumidores distintos, estados, regla futura y pantalla futura.

**Si se descubre una categoría adicional, no se cambia la muestra retrospectivamente**: generar MODEL_GAP + propuesta de contrato `v2.x` o `v3` según compatibilidad, revisarla y después reanudar con versión fija.

## 6. Separación de autoridad, calidad y resultados

- La puntuación de evidencia 0–6 es solo una señal de priorización de revisión; **no hay umbral auto-APPROVE**. Si el helper Python existente anuncia `PROPOSAL_READY_FOR_GOVERNANCE_REVIEW`, eso no es política publicada.
- Una regla de seguridad con falsa aplicación y una regla visual con falsa aplicación tienen costos diferentes: realizar evaluación bidireccional de daño, sin usar la criticidad para declarar “GLOBAL”.
- Curator prepara alternativas; Validator comprueba de forma independiente; owner funcional/gerencia define cobertura; Seguridad/Legal vetan dentro de su dominio; autoridad técnica gobierna cambios físicos. Nunca un mismo agente declara su propio resultado como revisión independiente.
- Reutilizar el mecanismo humano válido **solo después de verificar su esquema, triggers y propósito**; la existencia de `programacion.human_decisions` y `lf_ops.system_audit_human_decisions` no implica que admitan este workflow.
- Si hay dos decisiones comparables de distinta autoridad y no consta competencia, prevalece HOLD, no última escritura.

## 7. Qué está hecho y qué no

**Hecho:** estrategia y normas H01–H15 definidas en contrato director v2; matriz de ensayos sintéticos S01–S14 y criterios G0–G5 preparados. Documentos versionados en rama de desarrollo, sin Supabase writes.

**No hecho:** ratificación por responsables; ejecución de pruebas S01–S14 contra una implementación; aprobación de clasificación y reclasificación. El SQL candidato que elimina `DERIVED_GLOBAL` en bloque está expresamente **NO-GO**.

## 8. Fuente canónica de esta fase

- Contrato: `docs/t-remed/IG_N4_TREMED_CONTRATO_ESTRATEGIA_DEFINICIONES_REGLAS_V2_20261028.md`.
- Contrato de validación: este documento.
- EKB observado: `IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001`, `INPUT-GOV-CONSUMER-BINDING-001`, `CI-MIGRATION-SOURCE-PARITY-001`.
- Referencias metodológicas: NIST SP 800-162, OMG DMN (hit policy), OPA Policy Testing. Ninguna fuente externa sustituye los contratos LF.
