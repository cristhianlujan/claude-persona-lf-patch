# TARJETA B07 — PADRE / HIJA
**Sustituye tarjeta de 9 columnas del PR #3813.**
**Decisor declarado:** Cristhian Luján · APROBACION_DOCUMENTAL_CONFIRMADA_EN_CONVERSACION (2026-11-13 08:31 America/Lima, aportado por el usuario); identity_verified=false; sin recibo autónomo verificable. NO autoriza producción.

## El diseño que decide el dueño
**PADRE** conserva la regla actual. **HIJA** conserva versiones completas (número, contenido, hash anterior/actual, decisión, decisor, fecha). No se agregan columnas lifecycle a `lf_ops.reglas` ni `saly.reglas`.

| LF | SALY |
|---|---|
| Padre existente `lf_ops.reglas` + hija nueva `lf_ops.reglas_versiones_b07` | Padre existente `saly.reglas` + hija nueva `saly.reglas_versiones_b07` |
| PK regla `id integer` → FK `rule_id` | PK regla `id bigint` → FK `rule_id` |
| Solo VIGENTE es consumible; hay 166 CANDIDATO legacy | Conservar literalmente sus 14 `VALIDADO`, `vigente` y `decision_id` |

**Salvaguardas propuestas (INFERIDAS):** una versión base por cada regla actual, sin inventar historial anterior; el escritor oficial actualiza padre+hija en una transacción; si no coinciden al COMMIT se bloquea; no editar/borrar versiones; hash viejo y evidencia incompleta bloquean. DOWN no borra historial.

## Cuatro puntos confirmados documentalmente por el dueño — ejecución técnica pendiente
1. **166 reglas LF CANDIDATO:** mantenerlas temporalmente en el padre, NO consumibles ni promocionadas; ingeniería prepara reconciliación posterior. Propuesta: **sí**.
2. **Historial previo:** aceptar que solo la última versión conocida puede recuperarse sin otras fuentes. Propuesta: **sí**.
3. **Enmienda B07:** documento 12 pide literalmente “LF 4 columnas y SALY 5 (incluida lifecycle_state)”. ¿Reemplazar ese requisito por relación PADRE/HIJA sin relajar pruebas, rollback y readback? Propuesta: **sí**.
4. **DOWN con versiones:** mantener bloqueo hasta aprobar custodia/exportación y restauración. Propuesta: **sí**.

**Selección documentada:** APROBAR MODELO PADRE/HIJA Y ENMIENDA DEL CRITERIO. **Sin autorización de despliegue ni identidad verificada.**

**Ajustes:** ______________________________________________________

**Fuente de confirmación:** mensaje del dueño 2026-11-13 08:31 Lima; **recibo oficial del registrador: NO VERIFICADO**.

**B07 permanece ABIERTO** hasta integración del escritor oficial, pruebas completas y operación gobernada.
