# LF L38 — Auditoría en vivo SELECT-only de B06_OWNER y B08_IDENTITY

**Fecha de observación:** 13 noviembre 2026. **Base temporal:** Supabase mhwmirqcgxxukpctffuv. **Autoridad de criterios:** L28 documento 12 (`12_criterios_cierre_motor_7.md`), G03 y G04 temporales; plantillas originales B06/B08 no emitidas y criterio L21 productivo más exigente. **Ejecutado:** GitHub reads, SQL SELECT readbacks, pruebas deterministas 8/8 solo shape y lectura de logs históricos laboratorio CI. **No ejecutado:** escritor V2 vivo, DML/DDL, RUN nuevo/reanudación, promoción, firma.

## Tablero
| Bloqueo | Criterios de preparación verificados | Cierre G03/G04 | Veredicto |
|---|---:|---|---|
| **B06_OWNER** | **9/12 = 75%** | ABIERTO | 238/238 owners y 155/155 recibos verificados; faltan negativos transversales, freeze exhaustivo RUN y aceptación independiente |
| **B08_IDENTITY** | **4/10 = 40%** | ABIERTO | 12 RUN en IN_PROGRESS, 5 Product Director, **0 elegibles**; 0 decisiones oficiales V2 |

Los porcentajes cuantifican verificaciones enumeradas en los recibos de este lote; **NO son porcentaje de cierre de producción**. G15 Motor continúa NO-GO.

## B06 — reconstrucción forense de preimagen #3806
El CSV **Git blob 3157e4ed321ab6c327b2bc2eb605c5e766b50a89** contiene 238 códigos/IDs únicos con owner y hash original de `to_jsonb(a)-'updated_at'`.
- Estado **antes**: 83 owners `LF_GOVERNANCE`, **155 distintos** (144 activos + 11 archivados), 13 archivados totales.
- Estado **después**: 238/238 canónicos, 0 variantes, 13 archivados.
- Para las 155 filas cambiadas: 155/155 `before_row` conserva owner y archivado original y su SHA concuerda con CSV; 155/155 `after_sha256` coincide con SHA actual; 155/155 cambió únicamente `owner_name` más auditoría, otros campos intactos.
- Para las 83 no modificadas: 83/83 SHA actual coincide con congelado; ninguna de ellas tiene recibo de cambio.
- Recibos: 155 `APPLIED`, únicos, todos del mismo Train y `decision_record_sha256` válido; `decisor='Cristhian Luján'` declarativo y `proponente='LF_GOVERNANCE'` operativamente distinto. **No es firma humana verificada.**
- Real Train #3806: `EXEC-DB-TRAIN-PR3806-20261113071927-R43384804628`, `COMPLETED`; preflight, patch y verify: `PASS_CLEAN`; GitHub Action `43384804628`, HEAD `da0af21a4a16c52fc63abd40f4385422f54b1611`.
- Guard: default owner `LF_GOVERNANCE`, triggers INSERT/UPDATE instalados, índice unique de recibos `(train_execution_id,asset_code)`. Laboratorio CI **run 43385755925, job 131753702972, SUCCESS**, clases PostgreSQL **17.6** y **18** con rollback de 155 y negativos SHA stale, owner SUPER_ADMIN, scope activo/archivado y falta de proponente. Las pruebas exact SQL ajustaron 238 SHA para fixture sintético (NO es apply a base viva).
- **Pendiente por responsables:** QA/Seguridad: replay/idempotencia cruzada y LF/SALY reales; Operaciones/DBA: freeze íntegro de RUN históricos para demostrar no cambio (un SELECT de `updated_by_execution_id` retornó cero otros RUN pero no prueba ausencia absoluta); Dueño/Seguridad/Arquitectura: aceptación G03 real con identidad/firma y segregación de ámbitos. G03 histórico exige owners por familia/proyecto; el owner funcional único temporal no cierra por sí mismo ese requisito.

Recibo punto a punto: `01_b06_recibo_punto_a_punto_preimagen_238.json`. **9 PASS, 3 pendientes**.

## B08 — no hay RUN elegible para un registro real
La implementación inspeccionada es `public.lf_ig_rule_owner_decide_v2(p_parent text,p_rule text,p_source_sha256 text,p_decision jsonb)`; exige:
- RUN `EJECUCION_PERFIL_LF`, `IN_PROGRESS`, Product Director y manifest read-only/no-write/no-promotion con handoff autorizado.
- `input_validate`, `output_validate`, Step70 `PASS_INDEPENDENT_SEMANTIC` sin bloqueos.
- `execute_profile` RAW con `governed_rule_patch`, trabajador, decisión del producto y `proposed_by` distinto del dueño.
- Screen exacta que contenga regla; source SHA canónico; patch SHA exacto; seis campos `codigo_regla`, `propuesta_sha256`, `veredicto`, `decisor`, `fecha`, `frase_literal`.

SQL vivo: **12 RUN IN_PROGRESS**, de los cuales **5** Product Director:
`EXEC-PROFILE-GATE2-40471E6F661A53D7CE7A4A1B` (7/11, screen 001),
`EXEC-PROFILE-GATE2-35D0AD0C26C3577D2E6AF019` (4/11, screen sin seleccionar),
`EXEC-PROFILE-GATE2-6FBA871B254F838684B84663` (7/11, screen 001),
`EXEC-PROFILE-GATE2-FF4E840386E8F075D9B58C52` (4/11),
`EXEC-PROFILE-GATE2-5B9EFC77E2F1FE98A4C80968` (9/11, screen 001).
**0** cumple el juez/patch; **no hay ejecución real elegible**. Tabla V2 decisiones: 0; owner temporal documental LF: 1 con `identity_verified=false`.

**Candidato de prueba propuesto:** `B2B-RULE-AUTH-033`, CANDIDATO, vinculada a **B2B-AUTH-004** (y 005), preimagen fullrow SHA `181389dac198874c07781bce78b9981803a52c9e845ed01926b86bd2f8ff939b`. Patch documental L32 `DOCUMENTARY_ONLY` cambia solo `descripcion`; su **SHA-256 exacto respecto del archivo** es:
`6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769` (recalculado en PostgreSQL). **No es todavía SHA exacto de RAW del RUN** porque no existe RUN elegible; obligatoriamente volver a comparar contra salida real y juez. El origen canónico equivalente a `lf_asset_snapshot_sha_v1` calculado por SQL es `40db98f0c26b104b53484988377c5ca8c5fb8cac8075d25580878fb60297e721`, pero invocar directamente la función por rol RO devuelve `42501`; no sustituir evidencia oficial de writer por una hipótesis.

**Seis campos de decisión — borrador NO pronunciado por el dueño:**
```json
{
 "codigo_regla":"B2B-RULE-AUTH-033",
 "propuesta_sha256":"6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769",
 "veredicto":"RECHAZAR",
 "decisor":"Cristhian Luján",
 "fecha":"<ISO8601_REAL_DENTRO_VENTANA_DEL_RUN>",
 "frase_literal":"Yo, Cristhian Luján, RECHAZO la propuesta documental de B2B-RULE-AUTH-033, SHA-256 6a398f8cdbd59a4a56099f9deb8ec01a3ea95e62ea1864735546db60c5cfb769, como prueba del recibo B08. No autorizo modificar ni promover esta regla."
}
```
**No es todavía input válido del writer**: falta timestamp real, frase efectiva del dueño, RUN/patch original emitido y juez independiente. No se autoriza su llamada.

## Comparación de opciones y rollback
| Opción | Evidencia ejecutada | Riesgo | Recomendación |
|---|---|---|---|
| Solo documento | 8/8 validaciones de forma SQL SELECT, sin escritor | No demuestra recibo real B08 | Usarla ahora, sin afectar base |
| **RECHAZAR primero** | Histórico PG18 `PASS_PG18_OWNER_REJECT_NO_CHILD_NO_RULE`, `PASS_PG18_NO_SELF_APPROVAL_AND_NO_UNAUTHORIZED_CALL`, CI `43385755925` | Persiste recibo inmutable y consume la combinación RUN+regla+kind; requiere **nuevo RUN** si después se desea APROBAR. No toca regla ni promueve | **Preferida cuando haya un RUN elegible y dueño autorice un disparo concreto** |
| APROBAR | Contrato V2 llama `lf_skill_invoke_v1` y `lf_ig_rule_finalize_v2`; evidencia de laboratorio de rama promoción en fixture | Cambia regla real, puede quedar `VIGENTE`, efectos no deseados e incompatibilidad funcional AUTH-033/policy25 | **NO como primera prueba** |

**Rollback:** RECHAZAR no modifica regla: no hay rollback de regla, pero el recibo permanece auditado. Si APROBAR falla durante la transacción, rollback transaccional de ese intento; si hace COMMIT con `VIGENTE_VERIFIED`, NO hay rollback automático y solo procede corrección/compensación gobernada con preimagen, negativos y readback. Un rechazo posterior sobre el mismo RUN no anula una aprobación persistida.

**Riesgo estructural:** `identity_verified=false` incluso después de registrar RECHAZAR. B08 temporal documental y B08 IAM/producción siguen separados.

## Estado del lote
- B06 **75% verificaciones (9/12), G03 NO-GO**.
- B08 **40% verificaciones (4/10), G04 NO-GO**.
- PR #3806 anterior sí desplegó; no confundir sus READBACK con recibo independiente firmado de B06.
- SQL live: únicamente SELECT; no DML/DDL, escritores V2 ni RUN tocados. Documentos GitHub nuevos en rama L38.
