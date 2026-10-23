# PROFILE_TASK_RUNTIME_BINDING_V1

Contrato/resolver read-only para construir un binding de ejecución de Profile **por task/step**, derivado de las autoridades existentes.

## Por qué existe

El Profile Runtime compartido resuelve hoy paquetes standalone bajo `profiles/<profile_slug>/`. Story Creator, en cambio, conserva sus Profiles, agents, schemas, validators y judges dentro de `skills/creating-integral-user-stories/` y algunos Profiles —por ejemplo Cross Cutting Enricher— sirven a varios steps con jueces/validadores distintos.

Copiar esos perfiles a `profiles/` o crear un Profile por cada juez duplicaría autoridad. Este contrato evita ambas cosas.

## Entrada

```text
step_contract
+ worker_binding resuelto
+ profile_authority (lf_activos + Router + currentness)
+ task_authority (Skill/artifacts/judge/schema/validator actuales)
        |
        v
PROFILE_TASK_RUNTIME_BINDING_V1
```

El resolver no consulta ninguna autoridad. Consume snapshots ya obtenidos por sus dueños y sólo cross-bindea su identidad exacta.

## Salida

Un binding inmutable contiene:

- `profile_code` + `profile_slug`;
- `step_id` + `worker_role`;
- `source_mode` y `source_root`;
- refs de fuente exactos con SHA-256;
- una única `runtime_schema` por `EXACT_REF`;
- un validador determinista exacto + modo de invocación;
- judge independiente exacto;
- contexto permitido y presupuesto;
- authority refs/revisions/digests;
- source revision y binding digest.

## Embedded profile sin duplicación

`source_mode=EMBEDDED_SKILL_PROFILE` permite que el Profile siga siendo artifact del Skill. No se copia a `profiles/`, no se crea un segundo source-of-truth y el runtime no puede inventar un schema agregando todos los schemas del Skill.

## Binding por step

El Profile es identidad/capacidad; el task binding decide el contrato de esa ejecución. Por eso el mismo `PERFIL-CROSS-CUTTING-ENRICHER-LF` puede usar:

```text
OBSERVATIONS_ERRORS       -> J05 + validate_field_coverage
ANALYTICS_OBSERVABILITY   -> J09 + detect_pii_telemetry
```

sin clonar el Profile.

## Fail closed

Bloquea si:

- Router no autoriza downstream;
- Profile o fuentes no están CURRENT;
- role no coincide;
- source revision difiere;
- una fuente escapa del root declarado;
- schema no es un exact ref;
- SHA del schema/validator/judge no coincide;
- judge no es el esperado o no exige independencia;
- faltan authority refs/digests;
- contexto excede o carece de presupuesto válido.

## Boundary

Este PR no modifica `services/profile_runtime_api`, no registra Profiles, no crea runtime binding persistente, no crea registry/tabla/queue, no ejecuta modelos y no activa runtime o producción. La integración opcional de este binding al runtime compartido debe ser una solución/PR posterior.
