# Enmienda B07_SCHEMA · G11 — TEXTO EXACTO PARA CAMBIO GOBERNADO

**Ámbito:** sustituir únicamente el párrafo «Exacta» y el párrafo «Falta» de B07 en `audits/rule-quality-lote28/12_criterios_cierre_motor_7.md` mediante cambio documental oficial. No modificar otros bloqueos, no alterar historia del criterio sin registro.

**Decisión del dueño:** confirmación documental por conversación, 2026-11-13 08:31 Lima (hora declarada por el usuario). `identity_verified=false`. No hay aquí firma criptográfica, actor Auth ni recibo oficial registrado. Registro de aplicación al documento 12 sigue pendiente.

## Texto sustitutorio propuesto — `Exacta`

**Exacta (ENMIENDA B07 PADRE/HIJA APROBADA DOCUMENTALMENTE):** Implementar historia inmutable por versiones con **PADRE `lf_ops.reglas` y HIJA `lf_ops.reglas_versiones_b07`**, y **PADRE `saly.reglas` e HIJA `saly.reglas_versiones_b07`**; **NO agregar las 4 columnas LF ni 5 columnas SALY `lifecycle_*` del criterio anterior**. Cada padre conserva exactamente la imagen actual de su regla y sus columnas existentes; cada hija conserva toda versión futura como `snapshot` íntegro, número de versión, SHA256 calculado, hash previo, fecha, referencia a decisión documental y escritor oficial. La versión inicial debe reflejar la imagen observada en el backfill (`BASELINE_CURRENT_ONLY`) sin inventar versiones, firmas o aprobaciones antiguas.

Solo el **escritor oficial** puede materializar en la **misma transacción** un cambio del padre y un append de la hija; los consumidores leen vigencia efectiva a través de vistas/contratos con RLS y permisos explícitos. Un `COMMIT` donde el padre no coincida con la última hija debe fallar, al igual que SHA anterior obsoleto, evidencia de decisión incompleta, autorevisión, inserción o edición directa y replay no idempotente. El escritor V2 LF mantiene sus checks de fuente, dueño, siete pasos y promoción; el escritor oficial SALY debe definirse y probarse antes de habilitar cambios SALY. El estado LF `CANDIDATO` previo al corte (166 en la fuente verificada) se conserva íntegro, no se promueve ni se expone como efectivo; SALY mantiene literalmente `estado='VALIDADO'`, `vigente` y `decision_id` sin mapearlo a `VIGENTE`.

Proporcionar UP/DOWN versionados, restricciones, índices, RLS/ACL y consumidores, preimagen y SHA por cada cambio, transacción SQL y pruebas negativas en copias PostgreSQL 17.6 y 18.7; ejecutar **backup y restauración real de base con datos confirmados después de aplicar la migración candidata**, comparando SHA padre+hija, integridad y versión del escritor. DOWN no debe destruir historial: puede bloquearse hasta que exista plan aprobado de custodia/restauración. Exigir SELECT real pre/post, evidencia de Merge Train, preservación B04/B12 y comprobación del escritor oficial; la aprobación documental del dueño conserva `identity_verified=false` en el entorno temporal. **Sin estos recibos, B07 permanece ABIERTO / NO-GO**.

## Texto sustitutorio propuesto — `Falta`

**Falta (al registrar esta enmienda):** readback del criterio documental actualizado por ruta oficial; finalizador LF V2 integrado y certificado bajo ruta oficial y escritor SALY nativo (si no existe, mantener cambios SALY BLOQUEADOS); permisos/RLS/consumidores validados; restauración con datos confirmados y comprobación de hashes; cierre de pruebas PG17.6/PG18.7, tres CI R17/PASE/clasificación sobre el HEAD exacto, Train/SELECT real posdespliegue y recibo de aceptación/cierre. La firma documental de conversación no acredita identidad física ni debe cambiar `identity_verified` a `true`.

## Razón de la enmienda

El texto anterior exigía literalmente «LF 4 columnas y SALY 5 (incluida lifecycle_state)». El dueño lo reemplazó por padre/hija; las salvaguardas de seguridad y rollback no se debilitan. Esta hoja es PROPUESTA DE PATCH, no modificación de la fuente original.
