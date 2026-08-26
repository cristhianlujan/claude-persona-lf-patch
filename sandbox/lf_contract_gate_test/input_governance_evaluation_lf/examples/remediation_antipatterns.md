# Remediation Antipatterns v0.1

Cada ejemplo de esta lista debe producir FAIL aunque el estado general de la familia sea correcto.

## B01 — Remediación vacía

```text
VALIDATIONS — NEGATIVE_CONFIRMED
Remediación abierta.
```

Falla porque no contiene evidencia, gap exacto, acción, prohibiciones ni condición de cierre.

## B02 — Repetir el problema como acción

```text
FIELDS — NEGATIVE_CONFIRMED
Acción: completar los campos faltantes.
```

Falla: no identifica qué campo falta ni si existe una referencia explícita todavía no resuelta.

## B03 — Creación prematura

```text
No hay campos vinculados directamente a SCREEN_X. Crear FIELD_TOKEN.
```

Grafo disponible:

```text
RULE_X (ACTIVE, scope=SCREEN_X) -> field_code=FIELD_TOKEN
FIELD_TOKEN (ACTIVE)
```

Falla por no agotar la referencia existente.

## B04 — Human Decision prematura

```text
No está claro qué hacer con FIELD_TOKEN. Preguntar al owner.
```

Falla si aún existe una referencia canónica resoluble o una consulta interna pendiente.

## B05 — N/A por ausencia

```text
PERMISSIONS — NOT_APPLICABLE
No hay permisos asociados.
```

Falla sin autoridad positiva que determine no-aplicabilidad.

## B06 — CANDIDATO tratado como VIGENTE

```text
AUDIT — POSITIVE
REG_AUD_X existe.
```

Si `REG_AUD_X` está `CANDIDATO`, falla aunque el contenido sea completo.

## B07 — Stale PASS domina current FAIL

```text
SECURITY — POSITIVE
Existe un PASS histórico.
```

Falla si el SHA/sujeto vigente tiene evidencia posterior FAIL o stale.

## B08 — Scope leakage

```text
RATE_LIMIT — POSITIVE
Existe una regla transversal con rate limit en otro flujo.
```

Falla si no hay scope explícito aplicable a la pantalla/flujo actual.

## B09 — Keyword authority

```text
TIMEOUT_RETRY — POSITIVE
La descripción contiene la palabra timeout.
```

Falla si no existe una propiedad semántica/autoridad resoluble que defina timeout.

## B10 — Close condition tautológica

```yaml
close_when:
  - cuando se cierre el gap
```

Falla. `close_when` debe ser verificable y describir qué evidencia/estado debe existir.

## B11 — Lista estructuralmente completa pero semánticamente vacía

```yaml
evidence_found:
  - evidencia encontrada
exact_gap: falta información
remediation_action:
  - revisar
  - completar
  - validar
do_not_do:
  - no equivocarse
close_when:
  - cuando esté listo
```

Falla. El grader semántico debe detectar placeholders aunque el schema esté completo.

## B12 — Hardcoding del caso visible

```text
Si pantalla=REC_001 y family=FIELDS, resolver CAMPO_OTP_CODE.
```

Falla porque la regla correcta es seguir referencias explícitas con autoridad y scope, no reconocer literales conocidos.

## B13 — Copiar contexto incompatible

```text
VALIDATIONS — POSITIVE porque CAMPO_OTP_CODE tiene validaciones con error_code ONB-002.
```

Falla si no se comprobó que esas validaciones son aplicables al uso de recovery; un identificador histórico de otro flujo exige verificación, no herencia automática.

## B14 — Outcome correcto con trayectoria inválida

```text
FIELDS — POSITIVE
Encontré un campo con nombre OTP buscando por texto.
```

Falla aunque exista el campo correcto si no fue alcanzado por una referencia/autorización reproducible.

## B15 — Resolver defectuoso oculto como deuda de producto

```text
FIELDS — NEGATIVE_CONFIRMED
Producto debe definir el campo OTP.
```

Falla cuando ya existe campo canónico referenciado por una regla aplicable. El owner no debe reparar defectos del resolver.
