# Story Pack canonico

Cada historia produce diecisiete secciones. La ausencia de una seccion
aplicable es falla, no omision.

```text
A. Identidad y trazabilidad      J. Auditoria
B. Nucleo funcional              K. Tokens y mensajes
C. Contrato de interaccion       L. Analytics
D. Contrato de campos            M. Observabilidad
E. Validaciones                  N. Responsive y accesibilidad
F. Observaciones                 O. Casos de prueba
G. Errores                       P. Dependencias, riesgos y decisiones
H. Seguridad y privacidad        Q. Jueces y evidencia
I. Estados e integridad
```

## A. Identidad

```text
story_code, title, epic_code, module_code, screen_code,
functional_unit_code, source_decision_id, source_version, status, priority
```

## B. Nucleo funcional

```text
actor, need, benefit, preconditions, trigger, main_flow,
alternative_flows, postconditions, acceptance_criteria, out_of_scope
```

Cada criterio de aceptacion se expresa como `given` / `when` / `then` con
`criterion_code`. Texto libre no es criterio.

## I. Estados e integridad

Declara estado inicial, transiciones permitidas, transiciones prohibidas,
efectos sobre recursos persistidos y politica de concurrencia.

## P. Dependencias, riesgos y decisiones

Toda pregunta no resuelta por la fuente se registra como `PENDING_DECISION`
con el dato minimo faltante. Prohibido inferir la respuesta y marcarla
CONFIRMED.

## Q. Jueces y evidencia

Lista de jueces ejecutados, resultado, `compliance_bit`, `failed_assertions`
y referencias de evidencia. Sin esta seccion el Story Pack esta incompleto.

## Familias de prueba

```text
FUNCTIONAL VALIDATION OBSERVATION ERROR PERMISSION TENANT SECURITY STATE
IDEMPOTENCY CONCURRENCY AUDIT ANALYTICS OBSERVABILITY RESPONSIVE
ACCESSIBILITY PERFORMANCE
```
