# PG-01: compatibilidad con los tres canales del Router

Fecha: 24-oct-2026. Estado: VERIFICADO_LOCALMENTE_EN_FUENTE; sin admisión operativa.
PR del receptor: #3135, draft. Revisión independiente pendiente.

## Cambio revisado

La imagen aportada por Paulo define PRODUCTO (definición funcional), PROGRAMACION (ciclo técnico completo) y OPERACIONES (uso cotidiano de capacidades existentes). Perfiles y skills son recursos transversales. No constituyen canales adicionales. Despliegue y mantenimiento técnico pertenecen a Programación; cada efecto conserva su operación y autorización.

Se cotejó con main 5c4c6dd43f7011fbcbc4f064c496f92f4fd95379, que incorpora #3136, #3137, #3139 y #3138.
No se verificó en esta ejecución el despliegue ni el estado de esas funciones en Supabase.
Los 14 paths de main desde 4d399c9ffb20f1d22b69782231e96918a5fdb7bb corresponden al Router, su documentación, clasificación, workflow y migraciones.
No hay cambios upstream en wave1_boundary_contracts ni en el motor material_currentness.

## Efecto sobre el receptor

| Límite | Consecuencia |
|---|---|
| Producto define el QUÉ | PG-01 no inventa definiciones ni sustituye su fuente canónica |
| Programación cubre el ciclo técnico | Mantiene A9 y PROGRAMMING_ENTRY_CONTRACT_V1; clasificar no admite ni ejecuta |
| Operaciones usa capacidades existentes | Una consulta cotidiana no debe forzarse a entrar por PG-01 |
| Perfiles/skills transversales | Ejecutar un recurso no cambia el canal; gestionarlo usa su operación gobernada |
| Despliegue dentro de Programación | Un ACCEPT del receptor no concede permisos de despliegue |
| Reparación estructural | Su alcance es STRUCTURE_ONLY_NO_FUNCTIONAL_TRUTH y vuelve a PRODUCTO para revalidación |

La fuente SQL nueva conserva PROGRAMACION_PRECHECK_DEFINICION, PRODUCTO_PRIMERO y PROGRAMACION_ADMISION_REQUERIDA.
La reparación estructural cita ANALYSIS_IMPLEMENTATION_PACKAGE_V1 y PROGRAMMING_ENTRY_CONTRACT_V1; no habilita escrituras funcionales.
No se agregó al receptor un adaptador Router→A9 ni se interpretó un paso del Router como recibo ACCEPT.
El target_ref del Router es una referencia del negocio; no se equipara automáticamente al context_id de A9.

## Siguiente paso ejecutado

Se integró main por merge local normal en lf/pg01-context-receiver-foundation-v1, preservando la historia.
Padres: eda4b8a1842498c49fd9bda806f058d0a6199e34 y 5c4c6dd43f7011fbcbc4f064c496f92f4fd95379.
Merge local: 2e698e2889e90d8ccc001385ff3158a6ad2c65d4.
Sin conflictos ni cambios en los blobs del receptor.
Las migraciones del Router se conservaron desde main; no son nuevas migraciones propuestas por este PR.

Validación sobre el merge local:
- 76 tests unitarios PG-01 satisfactorios.
- 67 tests unitarios Router V1/V2/política/handoff satisfactorios.
- 111 comprobaciones SQL PG-01 satisfactorias en PostgreSQL 17.6 desechable, sin red.
- Históricos no reejecutados; catálogo técnico/currentness y positivos siguen siendo fixtures donde lo eran.
- No constituye prueba integral del Router SQL vivo, del cableado operativo Router→A9→PG-01 ni de persistencia real.

Los resultados y hashes se conservan en pg01_router_compatibility_local_20261024.json.
No se modificó la migración base PG-01 ni sus contratos o digest d2e347ef….
Los siete campos del recibo y los permisos falsos de planificación/ejecución/admisión se mantienen.

## Checkpoints

| Checkpoint | Estado |
|---|---|
| Compatibilidad fuente / actualización de base | Comprobada localmente |
| 2A.i publicación y CI exact-HEAD | Pendiente; no usar el CI del HEAD publicado anterior |
| PG-01 C4 | Parcial; faltan manifiesto/control, presupuesto aprobado y proveedor admitido |
| PG-01 C7 / C1 compartido | Parcial; falta mapa acordado con A9 y readback semántico |
| PG-01 C6 persistencia | Pendiente de D7 y positivo real PR2 |
| P1 / I0 | Abiertos |

Publicación pendiente de autenticación de Paulo. No usar la cuenta de Cristhian para push.
Sin push, ready-to-merge, merge remoto, apply, llamadas de pago ni escritura en Supabase.
