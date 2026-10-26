# PG01_D7_RECEIPT_PERSISTENCE_PROPOSAL_V1

26-oct-2026. Solo diseño para revisión de Claude y decisión D7. Sin código de persistencia, migración ni apply. I0 necesita PERSISTED_PROGRAMMING_CONTEXT_RECEIPT; no basta emitir ACCEPT en memoria.

Ambas opciones conservan schema_version y los siete campos del recibo actual. Scope admitido, target exacto, autoría, operación autorizada, procedencia A9 y referencia de currentness requieren un envelope de persistencia acordado: son diseño propuesto, no campos emitidos por el Router ni campos nuevos del recibo contractual.

| Aspecto | A · Tabla en BD vía Train | B · Artefacto del PR + exact reader |
|---|---|---|
| Escritura | Futura operación gobernada Router→Train con migración revisada y datos append-only; sin DML directo desde receptor | Archivo canónico en commit inmutable del repo, creado por actor autenticado con revisión; sin confiar en el HEAD mutable de un PR |
| Consulta del Router | Futuro lector SQL de recibo por clave exacta context_id/context_sha256/scope/target y digest esperado; solo admite registro correspondiente a operación y autoridad vigentes | Router SQL no puede consultar Git por sí solo. Un consumidor externo autorizado usa ExactArtifactReader y entrega un witness verificable mediante un puente gobernado aún por diseñar |
| Readback | Releer fila independiente, recalcular hash del envelope/recibo y comparar identidad, digests, scope y currentness; ausencia o deriva bloquea | Pin repo/commit/path/SHA256 de bytes. Readback independiente del objeto Git; cotejar receipt y envelope contra expectativas admitidas, nunca un booleano supplied por caller |
| Idempotencia | Clave canónica de binding: recibo completo + contexto/scope/target + procedencia de la operación; repetir devuelve mismo registro. Conflicto de contenido bloquea; cambios de autoridad crean nueva versión enlazada, no sobrescriben BLOCK con ACCEPT | Mismo binding y bytes produce mismo artefacto/referencia; un cambio exige nueva versión y pin explícito. Nunca resolver latest ni sustituir una revisión por otra |
| Autoría | Identidad del ejecutor de Train y operación autorizada guardadas fuera de los siete campos; permisos mínimos y auditoría. El autor del snapshot no se autoacredita como consumidor independiente | Actor del commit y evidencia de revisión/OIDC admitida se vinculan en envelope. El nombre del autor Git por sí solo no es autoridad; CI verde tampoco |
| Riesgo | Introduce esquema, lector, ACL, retención y escritura gobernada; hay que acordar autorización, revocación y concurrentes antes de implementar | Acopla disponibilidad de Git y puente externo; riesgo TOCTOU, pins ausentes, actor no admitido, bloqueo de red. Un PR abierto mutable no satisface persistencia exacta por sí solo |

## Brechas que comparten

La ruta PROGRAMACION actual declara el precheck pero no ejecuta la compuerta de persistencia. Ninguna opción está ya conectada al Router. Falta decidir quién es lector independiente y fuente de la expectativa admitida; D7 no debe convertir datos aportados por el receptor en su propia autorización.

Para B, la política debe admitir expresamente el artefacto Git como persistencia válida. Si se requiere un witness consultable por SQL en BD, seguirá haciendo falta una escritura gobernada y su diseño: B no garantiza cero escrituras. No usar un enlace PR ni un flag de CI como sustituto.

Propuesta a revisar: preferir A si el Router SQL seguirá siendo la compuerta decisora; B sirve como evidencia revisable inmediata y solo podría ser persistencia operativa tras admitir el puente exacto. La decisión queda abierta. Claude revisa antes de código; implementación posterior requiere especificación de envelope, lector, claves y autoridad, además del positivo C1/PR2. No se solicita ni ejecuta apply.
