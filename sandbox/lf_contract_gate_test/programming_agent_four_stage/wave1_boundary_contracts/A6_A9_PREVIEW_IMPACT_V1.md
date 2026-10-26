# Vista previa A6 → A9: impacto y límites
Fecha: 24-oct-2026. Estado: IMPLEMENTADO_LOCALMENTE; SIN APLICAR NI PUBLICAR.
Autorización: Paulo pidió implementar sin aplicar, para revisar el impacto antes de activar.
Base: 8b987d00e24a8b2be5eead22bde944c8af0c8ac8, receptor draft #3135.
Rama local separada: lf/a6-a9-preservation-preview-v1.

## Qué se implementó

analysis_a6_a9_preview_v1.py añade dos funciones puras y optativas:
- validate_a6_payload_v1: diagnostica los campos y tipos del artefacto IMPLEMENTABILITY_SCHEMA_V1, identidades, scopes, referencias, transportes y bloqueadores explícitos. Obtiene los campos/enums del contrato A6 existente.
- assemble_a6_a9_preview_v1: recibe un borrador A9 y un A6 completo con digest esperado independiente, conserva A6 íntegro y delega la matriz a assemble_scope_front_matrix_v1 existente.

La salida es una envoltura A6_A9_ASSEMBLY_PREVIEW_V1 con diagnóstico y candidate_snapshot separado.
CANDIDATE_ASSEMBLED solo indica ensamblado local, no READY operativo. Puede contener scopes NEED_MORE_EVIDENCE/BLOCKED que no se promueven.
La función devuelve RETURN_TO_ANALYSIS y candidate_snapshot=null si no puede ensamblar una entrega coherente.
No se agregó una llamada desde el perfil, Router, resolver, receptor, cron o workflow. No hay endpoint, conexión DB, llamada a modelos ni escritura de persistencia en estas funciones.

## Ejemplos del efecto

| Entrada | Resultado de la vista previa | Efecto sobre el sistema actual |
|---|---|---|
| A6 completo y borrador coherente | Copia candidata; A6 íntegro y matriz derivada de A7 | Ninguno: no está conectada al flujo activo |
| Faltan los cuatro campos observados en v1.0 | Lista de rutas faltantes; sin candidato | No modifica datos ni bloquea otros pedidos |
| A6 contiene un bloqueo que afecta a un scope declarado READY | Devuelve el problema a Análisis | No marca el scope como listo ni borra su bloqueo |
| Scope independiente S2 bloqueado y S1 completo | Puede conservar S1; no contamina por el mero bloqueo de S2 | Probado con fixture; requiere evidencia real antes de admisión |
| A7 tiene relaciones contradictorias | Rechazo mediante el ensamblador/validador existente | No reconstruye procedencia por inferencia |
| Matriz existente válida con metadata adicional | Se conserva íntegra | No se reemplaza solo por diferencias de orden o metadata |
| A6 existente difiere del A6 entregado | Conflicto explícito | No sobrescribe silenciosamente el artefacto anterior |
| Se entrega una envoltura persistida con context_id/sha o extensions | Rechazo de reescritura de contexto | Los históricos permanecen intactos |
| Transporte A6 diferido con resolvedor tipado | Se conserva sin inventar valor resuelto | No demuestra resolución; C7 actual tiene su gate aparte |
| NOT_ADMITTED o admisión operativa false en el borrador | Se conservan literalmente | No se convierten a CURRENT ni a true |

No se alteró el resolver Supabase existente. No se modificaron contratos congelados ni el digest de entrada d2e347ef….
No se eligieron nuevos binding_kind, no se completaron textos ni referencias y no se generó un fingerprint de A6 para ocultar su ausencia.
El fingerprint se comprueba en formato, no en semántica: el contrato no fija aquí una receta universal de su proyección.
El digest esperado liga el artefacto completo; no atestigua su origen ni su autoridad.
A6 existente idéntico se reutiliza. Para una entrega nueva distinta se necesita un borrador/decisión de Análisis y la persistencia append-only autorizada, no modificar un registro previo.

## Qué podría bloquear si después se conectara

Solo podría rechazar la entrega que se le pasa, por carencias o contradicciones. No cambia la disponibilidad de servicios ni los permisos globales.
Un error en el código podría rechazar un borrador válido o aceptar una estructura insuficiente. Por eso aún no está cableado ni admitido y se mantienen las comprobaciones posteriores de PG-01, vigencia y revisión independiente.
Las pruebas locales no demuestran ausencia de errores ni compatibilidad con todos los outputs reales A6.
Esta entrega implementa conservación y diagnóstico/ensamblado: no produce por sí sola la evidencia funcional real que falta a Análisis.

## Verificación local

- 27 tests nuevos satisfactorios de ensamblado, conservación, conflictos, tipos, digests, transporte, bloqueo por scope, independencia, determinismo y no mutación.
- 76 tests unitarios del receptor existentes satisfactorios.
- Test existente de payload/matriz: positivo, ensamblador positivo, 2 negativos del ensamblador y 14 negativos satisfactorios.
- Lectura RO nueva de los tres A6 históricos: 07/09-oct siguen sin requirements, canonical_implementation_bindings, currentness_refs e implementability_fingerprint_sha256; 06-oct no contiene implementability_schema.
- Estos históricos se diagnosticaron sin completarlos, sin ensamblarlos como positivos y sin guardar sus payloads crudos en el repo.
- No se reejecutaron las 111 comprobaciones SQL de la entrega anterior: no hay cambio SQL ni del receptor en este incremento.
- Evidencia resumida: analysis_a6_a9_preview_local_20261024.json.
- Sin calificación operacional o revisión independiente.

## Alcance y reversibilidad

Solo se añaden módulo, tests, este documento y evidencia en wave1_boundary_contracts.
Familia fija prevista PROGRAMMING_AGENT_TESTS; sin nueva migración, manifest, cambios de registry o workflows.
Los archivos están en una rama/worktree local aislada del receptor publicado. El PR #3135 permanece en su HEAD publicado anterior.
Para descartar el candidato basta con no integrarlo: no hay cambios en Supabase que revertir.
Cualquier futura conexión al productor será un cambio explícito separado, revisado y con su operación/gates aplicables.

planning_allowed=false, execution_allowed=false, operational_admission=false y persistence_allowed=false incluso en CANDIDATE_ASSEMBLED.
P1/I0 abiertos. La obtención del positivo A9 admitido, C4/C7, D5/D7 y el proveedor de vigencia siguen pendientes.
