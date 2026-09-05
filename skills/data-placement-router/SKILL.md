---
name: data-placement-router
description: Enruta datos gobernados al esquema y tabla autorizados antes de cualquier escritura en Supabase. Usar cuando una ejecución necesite registrar pantallas, reglas, campos, validaciones, permisos, estados, políticas, errores, decisiones, evidencia u otros datos de proyecto. Bloquea si no existe un destino explícito.
version: v0.1
estado: CANDIDATO
impacto_automatico: BLOQUEADO_SI_NO_HAY_DESTINO
---

# DATA PLACEMENT ROUTER

## Objetivo

Evitar que agentes o procesos guarden información en tablas, esquemas o estructuras inventadas.

## Regla única

Antes de escribir en Supabase:

1. Identificar `project_code`.
2. Clasificar `data_type`.
3. Resolver `schema.table` usando `adapters/project-data-map.yaml`.
4. Verificar que la tabla y columnas existan realmente.
5. Buscar si el registro equivalente ya existe.
6. Validar los valores permitidos por la tabla, especialmente estados/catálogos.
7. Si existe: `REUTILIZAR | RELACIONAR | ACTUALIZAR/VERSIONAR` según corresponda.
8. Si no existe y el destino está autorizado: crear el registro en esa tabla.
9. Si no existe mapping autorizado: `BLOCKED_NO_DESTINATION`.

## Prohibiciones

- No crear tablas, esquemas o catálogos.
- No usar `public` como fallback.
- No guardar un tipo de dato en una tabla parecida por conveniencia.
- No inventar estados, códigos ni columnas.
- No duplicar registros que ya existen.
- No convertir `BLOCKED_NO_DESTINATION` en una propuesta de tabla automática.

## Resultado mínimo

```yaml
project_code: LF_BACKOFFICE | OVERALL | SALY
schema: <schema_resuelto>
data_type: <tipo_clasificado>
table: <tabla_resuelta|null>
action: REUSE | RELATE | UPDATE | INSERT | BLOCKED_NO_DESTINATION
reason: <breve>
```

## Alcance

Esta skill solo decide y valida **dónde** almacenar. No diseña pantallas, no genera historias y no crea nuevas estructuras de base de datos.
