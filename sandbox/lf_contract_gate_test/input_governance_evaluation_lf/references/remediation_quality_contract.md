# Remediation Quality Contract v0.1

## 1. Resultado terminal

Toda familia evaluada debe terminar en uno de estos estados de evaluación:

- `POSITIVE`
- `NOT_APPLICABLE`
- `NEGATIVE_CONFIRMED`
- `HUMAN_DECISION_REQUIRED` solo cuando exista autoridad positiva y se haya agotado el trabajo interno permitido.

`SOURCE_INCOMPLETE`, `RESEARCH_REQUIRED`, `KEEP_IN_INTERNAL_REMEDIATION_QUEUE` y equivalentes son estados de trabajo, no resultados terminales de evaluación.

## 2. Contrato mínimo de una remediación negativa

Un `NEGATIVE_CONFIRMED` accionable debe contener, semánticamente, todas estas piezas:

```yaml
evaluation_outcome: NEGATIVE_CONFIRMED
evidence_examined:
  - source_ref: <referencia concreta>
    authority_status: <VIGENTE|ACTIVO|CANDIDATO|STALE|ABSENT|...>
    observed_fact: <hecho verificable>
evidence_found:
  - <evidencia positiva parcial o [] si realmente no existe>
exact_gap: <qué dimensión obligatoria falta exactamente>
cause_type: <tipo de causa>
remediation_action:
  - <acción concreta y ejecutable>
do_not_do:
  - <acción prohibida para evitar invención/bypass>
close_when:
  - <condición verificable de cierre>
next_owner: <INTERNAL_RESOLVER|CURATOR|UX_PRODUCT|SECURITY|ENGINEERING|OWNER>
human_decision_required: <true|false>
authority_ref: <obligatorio si human_decision_required=true>
```

### `cause_type` permitido

- `RESOLVER_MISSED_EXPLICIT_REFERENCE`
- `CANONICAL_SOURCE_ABSENT`
- `AUTHORITY_INSUFFICIENT`
- `SOURCE_CONFLICT`
- `STALE_EVIDENCE`
- `APPLICABILITY_AUTHORITY_MISSING`
- `LATER_STAGE_REQUIREMENT`
- `FUNCTIONAL_DEFINITION_MISSING`
- `GOVERNANCE_EVIDENCE_MISSING`
- `HUMAN_AUTHORITY_REQUIRED`

## 3. Contrato POSITIVE

`POSITIVE` exige:

- cadena de evidencia reproducible;
- autoridad suficiente para el scope exacto;
- ausencia de dimensiones obligatorias sin resolver en la etapa evaluada;
- ninguna inferencia basada solo en nombre, keyword o semejanza;
- referencias stale/candidate tratadas como insuficientes salvo autoridad explícita que diga lo contrario.

Formato semántico esperado:

```yaml
evaluation_outcome: POSITIVE
evidence_chain:
  - <pantalla/regla/fuente>
  - <referencia explícita>
  - <entidad canónica resuelta>
authority_basis:
  - <fuente y estado>
resolved_requirements:
  - <dimensión>
unresolved_required: []
close_reason: <por qué está satisfecha la familia>
```

## 4. Contrato NOT_APPLICABLE

`NOT_APPLICABLE` nunca se deduce de `count=0`, ausencia de reglas o ausencia de pantalla visual.

Debe contener:

```yaml
evaluation_outcome: NOT_APPLICABLE
positive_authority_ref: <decisión/regla/contrato explícito>
scope_match: true
reason: <por qué esa familia no aplica a esta pantalla/etapa>
```

Sin `positive_authority_ref` válido → hard fail.

## 5. Contrato Human Decision

`HUMAN_DECISION_REQUIRED` es terminal solo si:

1. las búsquedas/resoluciones internas aplicables están agotadas;
2. no existe fuente canónica suficiente reutilizable;
3. la decisión no puede derivarse de reglas existentes;
4. existe una propiedad verdaderamente discrecional que requiere autoridad humana;
5. se indica la pregunta mínima y las opciones/impacto conocidos;
6. no se pide al humano resolver un defecto del propio resolver.

## 6. Trayectoria obligatoria

Para familias materiales, el grader debe comprobar la trayectoria, no solo la redacción final.

Ejemplo de trayectoria válida:

`REC_001 → REG_CLIENT_RECOVERY_PHONE_CONTROL_001 (VIGENTE) → old_phone_otp_field_code → CAMPO_OTP_CODE (ACTIVO) → validaciones activas`

Ejemplo inválido aunque el outcome final sea correcto:

`texto contiene "OTP" → asumir que existe campo OTP → POSITIVE`

## 7. Remediaciones prohibidas por ser genéricas

Estas frases no son acciones terminales válidas por sí solas:

- `Remediación abierta`
- `Revisar evidencia`
- `Completar la información faltante`
- `Investigar`
- `Mantener en cola`
- `Resolver pendiente`
- `Crear lo faltante`
- `Pedir definición al usuario`

Pueden aparecer únicamente acompañadas por objeto/fuente concreta, operación concreta y `close_when` verificable.

## 8. Regla de agotamiento antes de crear

Antes de proponer creación o Human Decision, el agente debe demostrar que agotó:

1. referencias explícitas de reglas VIGENTES/ACTIVAS;
2. `reuse_rules` y entidades nombradas;
3. contratos/policies/rutas/componentes canónicos explícitamente relacionados;
4. evidencia current de la pantalla;
5. autoridades transversales con scope explícito;
6. contradicciones y stale sources.

No se permite expansión por similitud textual como autoridad.

## 9. Condición de calidad

Una remediación se considera `ACTIONABLE` solo si un segundo agente puede ejecutarla sin tener que volver a descubrir:

- qué falta;
- dónde buscar;
- qué referencia seguir;
- qué no debe inventar;
- quién tiene autoridad si hace falta;
- cómo sabe que terminó.
