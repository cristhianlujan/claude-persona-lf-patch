---
name: data-placement-router
description: Enruta datos gobernados al esquema y tabla autorizados antes de cualquier escritura en Supabase. Usar cuando una ejecución necesite registrar pantallas, reglas, campos, validaciones, permisos, estados, políticas, errores, decisiones, evidencia, tokens visuales u otros datos de proyecto. Bloquea si no existe un destino explícito.
version: v0.2
estado: CANDIDATO
impacto_automatico: BLOQUEADO_SI_NO_HAY_DESTINO
---

# DATA PLACEMENT ROUTER

## Objetivo

Evitar que agentes o procesos guarden información en tablas, esquemas o estructuras inventadas y evitar cruces entre proyectos o dominios.

## Regla única

Antes de leer o escribir datos gobernados:

1. Identificar `project_code`.
2. Clasificar `data_type`.
3. Resolver el dominio autorizado y `schema.table` usando `adapters/project-data-map.yaml`.
4. Verificar que la tabla y columnas existan realmente.
5. Buscar si el registro equivalente ya existe.
6. Validar los valores permitidos por la tabla, especialmente estados/catálogos.
7. Si existe: `REUTILIZAR | RELACIONAR | ACTUALIZAR/VERSIONAR` según corresponda.
8. Si no existe y el destino está autorizado: crear el registro en esa tabla.
9. Si no existe mapping autorizado: `BLOCKED_NO_DESTINATION`.

## Proyectos con varios esquemas

Un proyecto puede tener más de un esquema autorizado cuando cada esquema tiene una responsabilidad distinta. Esto no habilita cruces libres entre esquemas.

Para `LF_BACKOFFICE`:

- funcional/operativo → `lf_ops`
- diseño y tokens → `lf_design`
- conocimiento transversal explícito → `public` solo mediante los mappings EKB declarados

Antes de generar o modificar una pantalla LF Backoffice se debe consultar `LF_DS_V1` en `lf_design` y reutilizar tokens existentes. Los tokens `VIGENTE` son la referencia preferente; candidatos o pendientes no se convierten en definitivos por inferencia y los valores `DEPRECADO` no se reutilizan.

## Prohibiciones

- No crear tablas, esquemas o catálogos.
- No usar `public` como fallback.
- No cruzar esquemas de proyectos distintos.
- No guardar un tipo de dato en una tabla parecida por conveniencia.
- No inventar estados, códigos, columnas ni tokens visuales.
- No duplicar registros que ya existen.
- No convertir `BLOCKED_NO_DESTINATION` en una propuesta de tabla automática.

## Resultado mínimo

```yaml
project_code: LF_BACKOFFICE | OVERALL | SALY
domain: functional | visual | knowledge
schema: <schema_resuelto>
data_type: <tipo_clasificado>
table: <tabla_resuelta|null>
action: REUSE | RELATE | UPDATE | INSERT | BLOCKED_NO_DESTINATION
reason: <breve>
```

## Alcance

Esta skill solo decide y valida **dónde** leer o almacenar datos gobernados. No diseña pantallas, no genera historias y no crea nuevas estructuras de base de datos.
