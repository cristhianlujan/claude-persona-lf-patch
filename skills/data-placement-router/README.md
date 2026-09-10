# Data Placement Router

Skill de routing de persistencia gobernada.

Resuelve `project_code + data_type` hacia un destino autorizado `schema.table` y bloquea cuando no existe mapping explícito.

No crea tablas, esquemas ni catálogos y no usa `public` como fallback.
