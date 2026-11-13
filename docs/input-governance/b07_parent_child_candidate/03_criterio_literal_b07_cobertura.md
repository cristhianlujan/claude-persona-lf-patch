# B07 — Cobertura y conflicto con el criterio L28 Documento 12

Fuente canónica: [12_criterios_cierre_motor_7.md, §B07_SCHEMA · G11](https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote28-blocker-closure-plan-v1/audits/rule-quality-lote28/12_criterios_cierre_motor_7.md).

> **Exacta:** SQL/catálogo de ciclo LF **4 columnas** y SALY **5** (incluida `lifecycle_state`, sin falsear SALY.`estado` VALIDADO); DDL UP/DOWN versionado, índices/constraints/RLS/consumidores, preimagen SHA por cambio, simulación PG18 y PG17.6 con muestra representativa, rollback tras datos sin pérdida, SELECT real antes/después.

**Sí exige columnas literalmente.** Decisión posterior del dueño en conversación rechaza esas 9 columnas. No se puede declarar cumplida esa frase: **requiere enmienda explícita y firmada**, sin cerrar B07.

| Control del criterio | Cobertura del diseño PADRE/HIJA | Pendiente |
|---|---|---|
| LF4/SALY5 y `lifecycle_state` | **CONFLICTO**: no añade columnas ni `lifecycle_state` | Firma de enmienda del dueño |
| Respetar SALY VALIDADO | Snapshot íntegro y padre intacto | Pruebas y readback de integración |
| DDL UP/DOWN | SQL candidato aislado sin ruta oficial | Contrato de migración aprobado |
| Índices/constraints | FK y únicos, SHA, cadena y triggers parent/latest | Validación en CI y consumidores |
| RLS/consumidores | RLS HIJA habilitado, permisos directos limitados | Matriz de acceso y adaptación lectores |
| Preimagen SHA por cambio | Cadena previous_sha256 + snapshot_sha256 | Hash firmado oficial, pruebas con datos reales |
| PG18 y PG17.6 | Test aislado, datos representativos sintéticos | Log exact-HEAD y reconciliación live |
| Rollback post-datos sin pérdida | DOWN fail-closed con historia, rollback TX UP | Plan de custodia/restauración con datos y prueba |
| SELECT real antes/después | SOLO SELECT preexistente en Supabase | Post-Train readback real (no autorizado aquí) |
| Preservación B04/B12 y escritor oficial | SQL no altera V2, pero su UPDATE quedaría bloqueado por trigger | Integrar finalizador V2 y SALY, pruebas negativas E2E |

**Estado:** el nuevo diseño mejora la trazabilidad futura, pero no reconstruye versiones antiguas desconocidas; sus propiedades son INFERIDAS salvo referencias citadas. Mantener B07 ABIERTO / NO-GO.
