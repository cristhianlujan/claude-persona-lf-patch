# ADAPTER_INPUT_GOVERNANCE_EVALUATION_LF v0.1 — CANDIDATO

## Objetivo

Evaluar la calidad del razonamiento y de la remediación de `INPUT_GOVERNANCE_AGENT` antes de cambiar resolvers, contratos o fuentes canónicas.

Este adapter es **read-only** y **no habilitado en runtime**. No puede crear reglas, campos, estados, decisiones, migraciones, promociones ni evidencia canónica.

## Principio

Una salida no es correcta solo porque tenga el `outcome` correcto. Debe demostrar también una trayectoria válida:

`fuente observable → autoridad → referencia explícita → interpretación semántica → outcome → gap → remediación → condición de cierre`

Se evalúan por separado:

1. **Outcome**: `POSITIVE`, `NOT_APPLICABLE`, `NEGATIVE_CONFIRMED` o `HUMAN_DECISION_REQUIRED` cuando exista autoridad positiva para escalar.
2. **Evidence traversal**: qué fuentes revisó y qué referencias siguió.
3. **Authority correctness**: VIGENTE/ACTIVO/current domina a CANDIDATO, stale o evidencia textual no autoritativa.
4. **Remediation quality**: la acción debe atacar la causa exacta, no repetir el estado.
5. **No-invention**: prohibido crear una fuente nueva mientras exista una referencia canónica resoluble sin evaluar.
6. **Closure test**: toda remediación debe indicar una condición verificable de cierre.

## Arquitectura de evaluación

### A. Visible quality suite
Casos visibles y explicativos. Enseñan el contrato de comportamiento y contienen ejemplos positivos, negativos, N/A, conflictos, stale y falsos negativos de resolver.

### B. EKB regression suite
Cada error estructural relevante del EKB debe poder convertirse en un fixture permanente. Un error registrado pero no convertido en regresión ejecutable no se considera aprendizaje completo cuando sea material para el agente.

### C. Counterfactual twins
Cada caso con nombres reales debe tener una variante equivalente con nombres sintéticos y/o una mutación mínima de autoridad. El objetivo es evitar hardcoding por `REC_001`, `CAMPO_OTP_CODE` u otros literales.

### D. Hidden challenge contract
Los casos hidden no viven en este pack. Se generan fuera del contexto visible del agente a partir de las dimensiones declaradas en `evals/remediation_quality_suite.yaml`. Deben usar nombres distintos, distractores, estados de autoridad cambiados, evidencia stale y referencias rotas/no rotas.

### E. Multi-grader
La suite combina:
- grader determinístico estructural;
- grader de autoridad/trazabilidad;
- grader semántico de remediación;
- grader de trayectoria;
- calibración humana periódica para casos ambiguos.

## Reglas de hard-fail

Cualquiera de estos comportamientos hace fallar el caso aunque el outcome final coincida:

- inventar regla/campo/estado/permiso/mensaje/threshold/fuente;
- declarar `NOT_APPLICABLE` por ausencia de evidencia sin autoridad positiva;
- escalar a Human Decision antes de agotar referencias canónicas explícitas;
- usar `CANDIDATO` como si fuera `VIGENTE`/`ACTIVO`;
- dejar `Remediación abierta`, `revisar`, `investigar` o `mantener en cola` como acción terminal;
- omitir `close_when`;
- permitir que evidencia stale domine evidencia current;
- aplicar una autoridad transversal a una pantalla sin scope explícito;
- resolver por keyword/categoría cuando existe semántica o referencia explícita más fuerte;
- marcar `POSITIVE` mientras persiste una dimensión obligatoria no resuelta.

## Política de mejora

Un cambio de resolver/spec solo puede promoverse como candidato si:

1. mejora el caso objetivo;
2. mantiene 100% de hard guards;
3. no introduce regresiones en la suite EKB;
4. supera los counterfactual twins;
5. mantiene desempeño en hidden challenges;
6. conserva fail-closed y no-invention.

La reflexión sobre fallos puede proponer cambios de spec/prompts/resolvers, pero nunca modificar directamente la fuente canónica. Toda propuesta pasa nuevamente por la suite completa.

## Referencias metodológicas 2025–2026

El diseño toma como guía los patrones públicos recientes de evaluación de agentes: outcome + transcript/trajectory, múltiples graders, suites separadas de quality/regression, generación automatizada de escenarios desde behaviors, reflexión sobre trayectorias fallidas y análisis estadístico de variabilidad. Estas ideas se adaptan a la gobernanza LF; no sustituyen las autoridades canónicas LF.
