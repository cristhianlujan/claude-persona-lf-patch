# SALY sources and authority (candidate, read-only)
| Fuente | Alcance | Confianza |
|---|---|---|
| EKB Input Governance LF V1.4 | Orden ACT-0001→Perfil→RUN→IG→juez→registro→cierre | Fuente operativa |
| Decisión del dueño «Si me designo», 2026-11-13 12:53 Lima | Owner documental SALY + permiso para crear perfil propio | Afirmación de chat sin Auth |
| `saly.proyecto` SALY-001 | Proyecto activo | SELECT en Supabase |
| `saly.reglas`, `saly.decisiones` | Reglas y decisiones SALY | SELECT, no write |
| `lf_operation_registry` | Operación SALY ausente antes de alta | SELECT |
| `lf_ig_project_owner_v2` | Owner SALY ausente antes de alta | SELECT |
| `CREACION_PERFIL_LF` | Única ruta oficial de creación de perfil | Catálogo/Router |
| #3818 B07 | Writer/historia candidata, **sin Train** | R17 PG17/18 aislado únicamente |

No equiparar la decisión conversacional con verificación legal de identidad, firma digital o rol productivo.
